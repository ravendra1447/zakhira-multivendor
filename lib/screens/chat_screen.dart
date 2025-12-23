import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path_provider/path_provider.dart';

// Import the necessary models and services
import '../config.dart';
import '../models/chat_model.dart';
import '../services/chat_service.dart';
import '../services/local_auth_service.dart';
import '../services/contact_service.dart';
import 'new_chat_page.dart';
import 'media_viewer_screen.dart';
import 'multi_image_picker_screen.dart';
import 'message_info_screen.dart' hide OrientationAwareImage;

// Helper function to format date headers
String formatDateHeader(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final messageDate = DateTime(date.year, date.month, date.day);
  final difference = today.difference(messageDate).inDays;

  if (difference == 0) {
    return "Today";
  } else if (difference == 1) {
    return "Yesterday";
  } else if (difference < 7) {
    return DateFormat('EEEE, MMM d').format(date);
  } else {
    return DateFormat('dd/MM/yyyy').format(date);
  }
}

class OrientationAwareImage extends StatefulWidget {
  final ImageProvider provider;
  final String? thumbBase64;
  final bool forcePortraitFitHeight;
  final VoidCallback? onImageLoaded; // ✅ Callback when image loads
  const OrientationAwareImage({Key? key, required this.provider, this.thumbBase64, this.forcePortraitFitHeight = false, this.onImageLoaded}) : super(key: key);
  @override
  State<OrientationAwareImage> createState() => _OrientationAwareImageState();
}

class _OrientationAwareImageState extends State<OrientationAwareImage> {
  BoxFit _fit = BoxFit.cover;
  Alignment _align = Alignment.center;
  bool _resolved = false;
  @override
  void initState() {
    super.initState();
    final stream = widget.provider.resolve(const ImageConfiguration());
    ImageStreamListener? listener;
    listener = ImageStreamListener((info, _) {
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      BoxFit f;
      if (w > h) {
        f = BoxFit.fitHeight;
      } else if (h > w) {
        f = widget.forcePortraitFitHeight ? BoxFit.fitHeight : BoxFit.fitWidth;
      } else {
        f = BoxFit.contain;
      }
      if (mounted) {
        setState(() {
          _fit = f;
          _align = Alignment.center;
          _resolved = true;
        });
        // ✅ Notify parent that image is loaded (auto-hide download button)
        widget.onImageLoaded?.call();
      }
      stream.removeListener(listener!);
    }, onError: (error, stack) {
      stream.removeListener(listener!);
    });
    stream.addListener(listener);
  }
  @override
  Widget build(BuildContext context) {
    Widget? thumb;
    final t = widget.thumbBase64;
    if (!_resolved && t != null && t.isNotEmpty) {
      try {
        final clean = t.contains(',') ? t.split(',').last.trim() : t.trim();
        final bytes = base64Decode(clean);
        thumb = Image.memory(bytes, fit: BoxFit.contain);
      } catch (_) {}
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            if (thumb != null) Positioned.fill(child: FittedBox(fit: BoxFit.contain, child: SizedBox(width: constraints.maxWidth, height: constraints.maxHeight, child: thumb))),
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: Image(image: widget.provider),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class ChatScreen extends StatefulWidget {
  final int chatId;
  final int otherUserId;
  final String otherUserName;

  const ChatScreen({
    Key? key,
    required this.chatId,
    required this.otherUserId,
    required this.otherUserName,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final FocusNode _focusNode = FocusNode();

  Set<String> selectedMessageIds = {};
  late ScrollController _scrollController;

  File? _imageFile;
  final _messageBox = Hive.box<Message>('messages');
  final _authBox = Hive.box('authBox');
  final _scrollBox = Hive.box('chatScroll');

  bool _isTyping = false;
  bool _isOtherUserTyping = false;
  bool _isSending = false;
  bool _isLoadingMore = false;
  Timer? _typingTimer;
  String _userStatus = "offline";
  int _lastReadMessageId = 0;

  String _resolvedTitle = "";
  String? _otherUserPhone;

  StreamSubscription? _typingSubscription;
  StreamSubscription? _statusSubscription;
  StreamSubscription? _newMessageSubscription;
  StreamSubscription? _uploadProgressSubscription;
  StreamSubscription? _messageDeliveredSubscription;
  StreamSubscription? _thumbnailReadySubscription;
  StreamSubscription? _allThumbnailsReadySubscription;

  bool _isKeyboardOpen = false;
  bool _isFirstLoad = true;
  bool _shouldScrollToBottom = true;
  bool _hasInitialScrollDone = false;

  // ✅ REPLY FUNCTIONALITY
  Message? _replyingToMessage;
  final GlobalKey _replyPreviewKey = GlobalKey();

  // ✅ SWIPE TO REPLY VARIABLES
  double _swipeOffset = 0.0;
  bool _isSwiping = false;
  Message? _swipeMessage;

  // ✅ FLOATING SCROLL BUTTON
  bool _showScrollToBottom = false;

  // ✅ SELECTION MODE
  bool _selectionMode = false;

  // ✅ OPTIMIZED SCROLLING VARIABLES
  bool _isAtBottom = true;
  double _scrollThreshold = 100.0;

  // ✅ PERFORMANCE OPTIMIZATION - MESSAGE CACHING
  List<Message> _cachedMessages = [];
  bool _needsRefresh = true;
  Timer? _updateTimer;
  
  // ✅ CRITICAL: ValueNotifier to trigger UI rebuild when collage is ready
  // Step: Last image aayi → version.value++ → ValueListenableBuilder rebuild → Collage turant draw
  final ValueNotifier<int> _collageVersionNotifier = ValueNotifier<int>(0);

  // ✅ CRITICAL: In-memory temp messages for INSTANT display (WhatsApp style)
  // This ensures temp messages appear instantly before Hive sync completes
  final Map<String, Message> _pendingTempMessages = {};

  // ✅ DUPLICATE PROTECTION
  final Set<String> _processedMessageIds = {};

  // ✅ UPLOAD PROGRESS TRACKING
  final Map<String, double> _uploadProgress = {};

  // ✅ FIXED: PERSISTENT LOADING STATES
  final Map<String, int> _imageLoadStages = {};
  final Map<String, Timer> _loadTimers = {};
  final Set<String> _fullyLoadedMessages = {};
  
  // ✅ DOWNLOAD STATE TRACKING (WhatsApp style)
  final Set<String> _downloadingMessages = {}; // Messages currently downloading
  final Map<String, double> _downloadProgress = {}; // Download progress 0.0-100.0
  final Set<String> _downloadedMessages = {}; // Messages that are downloaded locally
  final Set<String> _loadedImages = {}; // Images that are fully loaded/cached (auto-hide download button)

  // ✅ LOAD MORE MESSAGES
  DateTime _oldestMessageTime = DateTime.now();
  bool _hasMoreMessages = true;

  // ✅ COLLAGE STATE MANAGEMENT - Fixed Slot System
  // Track which groups have been built (collage created once)
  final Set<String> _builtGroups = {};
  // Fixed slots: groupId -> List of image URLs/null by index
  final Map<String, List<String?>> _collageMap = {};
  // Track if layout is frozen for a group
  final Map<String, bool> _collageLayoutFrozen = {};
  // Track total images expected for each group
  final Map<String, int> _collageTotalImages = {};
  // ✅ SOLUTION #1: Track which groups have been RENDERED (prevent duplicate rendering)
  final Set<String> _renderedGroups = {};
  // ✅ SOLUTION #2: Track which anchor messages have been rendered
  final Set<String> _renderedAnchorMessages = {};
  // ✅ Collage widget cache keyed by anchorId to reuse already built collages
  final Map<String, Widget> _collageWidgetCache = {};
  // ✅ Track filled slots count when caching collage widgets (for cache invalidation)
  final Map<String, int> _cachedFilledSlotsCount = {};
  // ✅ Track which groups already ran one-time slot sync inside build
  final Set<String> _slotsSyncedForGroup = {};
  // ✅ Track which groups need slot sync (receiver side)
  final Map<String, bool> _slotsNeedSync = {};
  // ✅ Track cached slot signature to detect changes
  final Map<String, String> _slotSignature = {};
  // ✅ Track recently received messages on receiver side (for individual display)
  final Set<String> _recentlyReceivedMessages = {};
  final Map<String, Timer> _recentMessageTimers = {};
  // ✅ Track groups that need immediate bundle rebuild (force rebuild even if cache exists)
  final Set<String> _forceBundleRebuild = {};

  // ✅ DEBUG: Print collage map for debugging
  void debugCollageMap(String groupId) {
    if (!_collageMap.containsKey(groupId)) {
      print("❌ [DEBUG] collageMap me groupId $groupId nahi mila");
      return;
    }
    final slotList = _collageMap[groupId]!;
    final totalImages = _collageTotalImages[groupId] ?? slotList.length;
    final filledCount = slotList.where((url) => url != null && url.isNotEmpty).length;

    print("🔍 [DEBUG COLLAGE MAP] GROUP: $groupId");
    print("🟦 Total Slots: ${slotList.length}");
    print("📊 Total Images Expected: $totalImages");
    print("✅ Filled Slots: $filledCount");
    print("📋 Slot Details:");
    for (int i = 0; i < slotList.length; i++) {
      final url = slotList[i];
      if (url != null && url.isNotEmpty) {
        final preview = url.length > 50 ? url.substring(0, 50) + "..." : url;
        print("   ✅ Slot[$i] = $preview");
      } else {
        print("   ⬜ Slot[$i] = null (empty)");
      }
    }
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  }

  // ✅ Helper function to determine if collage needs sync
  bool shouldSyncCollage({
    required bool slotsCountChanged,
    required bool slotSignatureChanged,
    required bool tempIdConverted,
    required int filledCount,
    required int totalImages,
  }) {
    final missingSlots = filledCount < totalImages;
    return slotsCountChanged ||
        slotSignatureChanged ||
        tempIdConverted ||
        missingSlots;
  }

  // ✅ DEBUG: Print detailed collage status with thumbnail info
  void debugCollageStatus(Message msg) {
    final gid = msg.groupId ?? "NO_GID";

    print("\n\n===================== 🧩 COLLAGE DEBUG START =====================");
    print("📩 MessageID: ${msg.messageId}");
    print("📌 groupId: $gid");
    print("🖼 MEDIA INFO:");
    print("→ Full Image URL: ${msg.messageContent}");
    print("→ Thumbnail Base64: ${msg.thumbnailBase64 != null && msg.thumbnailBase64!.isNotEmpty ? 'present (${msg.thumbnailBase64!.length} chars)' : 'null/empty'}");
    print("→ Low Quality URL: ${msg.lowQualityUrl ?? 'null'}");
    print("→ High Quality URL: ${msg.highQualityUrl ?? 'null'}");
    print("→ Image Load Stage: ${msg.imageLoadStage}");
    print("→ Image Index: ${msg.imageIndex}");
    print("→ Total Images: ${msg.totalImages}");
    print("-------------------------------------------------------------");

    // ✅ Get all messages in this group for thumbnail info
    final allGroupMessages = _messageBox.values
        .where((m) => m.groupId == gid && m.chatId == widget.chatId)
        .toList();
    allGroupMessages.addAll(_pendingTempMessages.values
        .where((m) => m.groupId == gid && m.chatId == widget.chatId));

    print("📥 GROUP MESSAGES STATUS:");
    print("→ Total Messages in Group: ${allGroupMessages.length}");
    print("→ Message IDs: ${allGroupMessages.map((m) => '${m.messageId}(idx=${m.imageIndex})').join(', ')}");
    print("-------------------------------------------------------------");

    print("🧊 FROZEN COLLAGE STATUS:");
    print("→ Frozen: ${_collageLayoutFrozen[gid] ?? false}");
    print("→ Slots Present: ${_collageMap.containsKey(gid)}");

    if (_collageMap.containsKey(gid)) {
      final slotList = _collageMap[gid]!;
      final totalImages = _collageTotalImages[gid] ?? slotList.length;
      final filledCount = slotList.where((url) => url != null && url.isNotEmpty).length;

      print("→ Slot Count: ${slotList.length}");
      print("→ Total Images Expected: $totalImages");
      print("→ Filled Slots Count: $filledCount");
      print("→ Slot Details with Thumbnails:");

      for (int i = 0; i < slotList.length; i++) {
        final url = slotList[i];
        final msgForSlot = allGroupMessages.firstWhereOrNull(
              (m) => m.imageIndex == i,
        );

        if (url != null && url.isNotEmpty) {
          final hasThumbnail = msgForSlot?.thumbnailBase64 != null && msgForSlot!.thumbnailBase64!.isNotEmpty;
          print("   ✅ Slot[$i] => position:$i,");
          print("              url:${url.length > 50 ? url.substring(0, 50) + '...' : url},");
          print("              thumbnail:${hasThumbnail ? 'present (${msgForSlot.thumbnailBase64!.length} chars)' : 'null/empty'},");
          print("              messageId:${msgForSlot?.messageId ?? 'not_found'}");
        } else {
          print("   ⬜ Slot[$i] => position:$i, url:null, thumbnail:null");
        }
      }
    }

    print("-------------------------------------------------------------");
    print("📊 FILLED SLOTS COUNT: ${_getCachedFilledSlotsCount(gid)}");
    print("-------------------------------------------------------------");

    // ✅ Check isCollageMessage
    //final isCollage = _isCollageMessage(msg);
    //print("🎨 isCollageMessage(): $isCollage");

    // ✅ RECEIVER SIDE CHECK
    final userId = LocalAuthService.getUserId();
    final bool isMe = msg.senderId == userId;
    print("👤 Sender/Receiver: ${isMe ? 'SENDER' : 'RECEIVER'}");
    print("===================== 🧩 COLLAGE DEBUG END =====================\n\n");
  }
  // ✅ Track rendered anchors in fallback/cluster flows
  final Set<String> _clusterRenderedAnchors = {};
  // ✅ CLUSTER CACHE: Prevent reprocessing the same fallback cluster repeatedly
  final Set<String> _clusterCache = {};
  // ✅ STEP 3: Cluster debounce to prevent duplicate builds from socket hits
  final Map<String, int> _clusterStamp = {};

  // ✅ PERMANENT FIX: Use Hive to store loaded status
  bool get _areMessagesLoaded {
    return _authBox.get('messages_loaded_${widget.chatId}', defaultValue: false) ?? false;
  }

  set _areMessagesLoaded(bool value) {
    _authBox.put('messages_loaded_${widget.chatId}', value);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // ✅ OPTIMIZED SCROLL CONTROLLER
    _scrollController = ScrollController(
      keepScrollOffset: true,
    );

    _initializeChat();

    // ✅ RESTORE SCROLL POSITION
    _restoreScrollPosition();
  }

  void _initializeChat() {
    ChatService.initSocket();
    ChatService.ensureConnected();

    _lastReadMessageId = int.tryParse(_authBox.get('lastReadMessageId_${widget.chatId}', defaultValue: '0').toString()) ?? 0;

    // ✅ OPTIMIZED SCROLL LISTENER
    _scrollController.addListener(() {
      _updateScrollToBottomPreference();
      _updateLastReadMessageId();
      _updateFloatingButtonVisibility();

      // ✅ LOAD MORE MESSAGES WHEN NEAR TOP - DISABLED: Don't load after 4 messages
      // User requested: "4 messages ke bad loading na karo"
      // if (_scrollController.offset <= _scrollController.position.minScrollExtent + 200 &&
      //     _hasMoreMessages &&
      //     !_isLoadingMore) {
      //   _loadMoreMessages();
      // }
    });

    // ✅ IMMEDIATE SCROLL TO BOTTOM ON INIT
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && _shouldScrollToBottom) {
        _scrollToBottomSmooth();
      }
    });

    Future.delayed(const Duration(milliseconds: 50), () async {
      ChatService.joinRoom(widget.chatId);

      if (!_areMessagesLoaded) {
        await _fetchMessages();
      } else {
        print("✅ Using previously loaded messages for chat ${widget.chatId}");
        // ✅ Initialize fixed slots from existing messages
        _initializeFixedSlotsFromExistingMessages();
        if (mounted) setState(() {});
      }

      await _resolveHeader();

      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToBottomSmooth();
          _isFirstLoad = false;
        }
      });
      _hasInitialScrollDone = true;
    });

    // ✅ OPTIMIZED NEW MESSAGE LISTENER - Prevent fluctuation
    _newMessageSubscription = ChatService.onNewMessage.listen((msg) async {
      if (mounted && msg.chatId == widget.chatId) {
        // ✅ CRITICAL FIX: Fetch message from Hive to get correct groupId, imageIndex, totalImages
        // The stream message might not have these fields set yet
        final hiveMsg = _messageBox.get(msg.messageId);
        final Message messageToUse = hiveMsg ?? msg;
        
        // ✅ DEBUG: Log ALL media messages to check if they have groupId
        if (messageToUse.messageType == 'media' || messageToUse.messageType == 'encrypted_media') {
          print("📱 [ONNEWMESSAGE] Media message received: messageId=${messageToUse.messageId}");
          print("   - groupId: ${messageToUse.groupId}");
          print("   - imageIndex: ${messageToUse.imageIndex}");
          print("   - totalImages: ${messageToUse.totalImages}");
          print("   - messageContent: ${messageToUse.messageContent.length > 50 ? messageToUse.messageContent.substring(0, 50) + "..." : messageToUse.messageContent}");

          if ((messageToUse.groupId ?? '').isEmpty) {
            print("⚠️ [ONNEWMESSAGE WARNING] Media message WITHOUT groupId!");
            print("   - This message will NOT be grouped into a collage");
            print("   - messageId=${messageToUse.messageId}, senderId=${messageToUse.senderId}");
            print("   - Hive message exists: ${hiveMsg != null}");
            if (hiveMsg != null) {
              print("   - Hive message groupId: ${hiveMsg.groupId}, imageIndex: ${hiveMsg.imageIndex}, totalImages: ${hiveMsg.totalImages}");
            }
          }
        }

        if (_processedMessageIds.contains(msg.messageId)) {
          return;
        }

        _processedMessageIds.add(msg.messageId);
        Future.delayed(const Duration(seconds: 30), () {
          _processedMessageIds.remove(msg.messageId);
        });

        // ✅ CRITICAL: Initialize fixed slots for temp messages with groupId
        // Use messageToUse (from Hive if available) to get correct groupId fields
        if ((messageToUse.groupId ?? '').isNotEmpty &&
            messageToUse.imageIndex != null &&
            messageToUse.totalImages != null &&
            messageToUse.totalImages! > 0) {
          final gid = messageToUse.groupId!;

          // ✅ INDEXING FIX: Validate and fix imageIndex for temp messages
          int? validImageIndex = messageToUse.imageIndex;
          if (validImageIndex != null) {
            if (validImageIndex < 0) {
              print("⚠️ [TEMP INDEX FIX] Invalid imageIndex: $validImageIndex (negative), setting to 0");
              validImageIndex = 0;
            } else if (validImageIndex >= messageToUse.totalImages!) {
              print("⚠️ [TEMP INDEX FIX] Invalid imageIndex: $validImageIndex (>= totalImages=${messageToUse.totalImages}), clamping to ${messageToUse.totalImages! - 1}");
              validImageIndex = messageToUse.totalImages! - 1;
            }
          }

          if (!_collageMap.containsKey(gid)) {
            print("🧩 [TEMP] Creating fixed slots for group $gid with ${messageToUse.totalImages} images");
            _collageMap[gid] = List.filled(messageToUse.totalImages!, null);
            // ✅ FIX: Don't freeze immediately - only freeze when 4 slots are full
            _collageLayoutFrozen[gid] = false;
            _collageTotalImages[gid] = messageToUse.totalImages!;
          }

          // ✅ Place temp message in fixed slot with validated index
          final slotList = _collageMap[gid]!;
          if (validImageIndex != null && validImageIndex >= 0 && validImageIndex < slotList.length) {
            if (slotList[validImageIndex] == null || slotList[validImageIndex]!.isEmpty) {
              slotList[validImageIndex] = messageToUse.messageContent;
              print("✅ [TEMP] Image placed in slot $validImageIndex for group $gid (original index was ${messageToUse.imageIndex})");

              // ✅ Update message with corrected index if different
              if (messageToUse.imageIndex != validImageIndex) {
                print("🔄 [TEMP INDEX FIX] Correcting imageIndex from ${messageToUse.imageIndex} to $validImageIndex for message ${messageToUse.messageId}");
                // Note: Message object might be immutable, but slot is placed correctly
              }

              // ✅ CRITICAL: Check if 2+ images have arrived, trigger immediate bundle creation
              final filledSlots = slotList.where((url) => url != null && url.isNotEmpty).length;
              final totalImages = messageToUse.totalImages ?? slotList.length;
              if (filledSlots >= 2 && totalImages >= 2) {
                final isAllImages = filledSlots == totalImages;
                print("✅ [TEMP BUNDLE] ${isAllImages ? 'All' : '$filledSlots'} $totalImages images received for group $gid - triggering immediate bundle creation");
                
                // ✅ CRITICAL FIX: Clear "recent" markers for all messages in this group to allow bundle to show
                final allGroupMsgs = _messageBox.values
                    .where((m) => m.groupId == gid && m.chatId == widget.chatId)
                    .toList();
                allGroupMsgs.addAll(_pendingTempMessages.values
                    .where((m) => m.groupId == gid && m.chatId == widget.chatId));
                
                for (final m in allGroupMsgs) {
                  final msgIdStr = m.messageId.toString();
                  _recentlyReceivedMessages.remove(msgIdStr);
                  _recentMessageTimers[msgIdStr]?.cancel();
                  _recentMessageTimers.remove(msgIdStr);
                }
                print("🧹 [TEMP ALL IMAGES] Cleared recent markers for ${allGroupMsgs.length} messages in group $gid");
                
                // ✅ Clear all rendering flags and cache to force fresh bundle creation
                final String groupAnchorKey = 'group_${gid}_anchor';
                _renderedGroups.remove(gid);
                _renderedAnchorMessages.remove(groupAnchorKey);
                _builtGroups.remove(gid);
                _slotsSyncedForGroup.remove(gid);
                
                // ✅ CRITICAL: Mark group for forced rebuild (even if cache exists later)
                _forceBundleRebuild.add(gid);
                
                for (final m in allGroupMsgs) {
                  if ((m.imageIndex ?? 0) == 0) {
                    final anchorKey = m.messageId.toString();
                    _collageWidgetCache.remove(anchorKey);
                    _cachedFilledSlotsCount.remove(anchorKey);
                    _renderedAnchorMessages.remove(anchorKey);
                  }
                }
                
                _reinitializeSlotsForGroup(gid, widget.chatId);
                
                // ✅ CRITICAL: Clear message list cache to force full rebuild
                _cachedMessages.clear();
                _needsRefresh = true;
                
                // ✅ CRITICAL: Force rebuild message list immediately to include new messages
                // This ensures bundle check sees all messages including temp ones
                final currentMessages = _getOptimizedMessages();
                print("🔄 [BUNDLE REBUILD] Forced message list rebuild - found ${currentMessages.length} messages");
                
                // ✅ STEP: Last image aayi → version.value++ 🔥 → ValueListenableBuilder rebuild → Collage turant draw
                _collageVersionNotifier.value = _collageVersionNotifier.value + 1;
                print("🔥 [COLLAGE VERSION] Incremented collage version to ${_collageVersionNotifier.value} for group $gid (filledSlots=$filledSlots/$totalImages)");
                
                // ✅ INSTANT UI REBUILD: Direct setState to force immediate UI update (SYNCHRONOUS)
                if (mounted) {
                  // ✅ CRITICAL: Use SchedulerBinding to ensure setState happens after current frame
                  SchedulerBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _needsRefresh = true;
                        _cachedMessages.clear(); // Clear cache again to force rebuild
                      });
                      print("🔄 [BUNDLE REBUILD] Triggered setState in postFrame callback (synchronous)");
                      
                      // ✅ Also trigger in next frame as backup
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _needsRefresh = true;
                          });
                          print("🔄 [BUNDLE REBUILD] Triggered setState in second postFrame callback (backup)");
                        }
                      });
                    }
                  });
                  
                  // ✅ Also trigger immediate setState for instant update
                  setState(() {
                    _needsRefresh = true;
                    _cachedMessages.clear();
                  });
                  print("🔄 [BUNDLE REBUILD] Triggered immediate setState for instant UI update");
                }
                
                // ✅ CRITICAL FIX: Force Hive box update by touching extraData to trigger ValueListenableBuilder
                Future.microtask(() async {
                  if (mounted) {
                    final anchorMsg = allGroupMsgs.firstWhereOrNull((m) => (m.imageIndex ?? 0) == 0);
                    if (anchorMsg != null) {
                      final updatedMsg = _messageBox.get(anchorMsg.messageId);
                      if (updatedMsg != null) {
                        // ✅ Force update by touching extraData field (triggers HiveObject change detection)
                        final currentExtraData = updatedMsg.extraData ?? <String, dynamic>{};
                        final uniqueKey = '_bundle_refresh_${DateTime.now().millisecondsSinceEpoch}';
                        updatedMsg.extraData = {...currentExtraData, uniqueKey: DateTime.now().millisecondsSinceEpoch};
                        await updatedMsg.save();
                        print("✅ [TEMP BUNDLE] Triggered Hive box update for anchor ${anchorMsg.messageId} to force UI rebuild");
                      }
                    }
                  }
                });
                print("✅ [TEMP ALL IMAGES] Bundle creation triggered immediately for group $gid");
              }
            } else {
              print("⚠️ [TEMP] Slot $validImageIndex already filled for group $gid - duplicate detected");
              // Don't add duplicate temp message
              return;
            }
          } else {
            print("❌ [TEMP INDEX ERROR] Invalid imageIndex: $validImageIndex for group $gid (slotList.length=${slotList.length}, totalImages=${messageToUse.totalImages})");
            return;
          }
        }

        final existingMessage = _messageBox.values.firstWhereOrNull(
              (existingMsg) => existingMsg.messageId == messageToUse.messageId && existingMsg.chatId == widget.chatId,
        );

        if (existingMessage == null) {
          // ✅ FIX: Only scroll if at bottom (prevent fluctuation/jumping)
          if (_shouldScrollToBottom) {
            // ✅ CRITICAL: Prevent jumping at start - delay scroll slightly
            Future.microtask(() {
              if (mounted && _shouldScrollToBottom) {
                _scrollToBottomSmooth();
              }
            });
          }

          // ✅ Only haptic feedback for non-temp messages (prevent flickering)
          if (!messageToUse.messageId.toString().startsWith('temp_')) {
            HapticFeedback.selectionClick();
          }

          // ✅ FIX: Resolve header without blocking UI
          unawaited(_resolveHeader());

          if ((messageToUse.messageType == 'media' || messageToUse.messageType == 'encrypted_media') &&
              !_fullyLoadedMessages.contains(messageToUse.messageId)) {
            _startProgressiveLoading(messageToUse);
          }
        }

        // ✅ CRITICAL FIX: Instant refresh for temp messages (WhatsApp style)
        final isTemp = messageToUse.messageId.toString().startsWith('temp_');

        // ✅ FIX: Check if real message already exists to prevent duplication
        if (!isTemp) {
          // Check if this real message already exists in Hive
          final existingMsg = _messageBox.get(messageToUse.messageId);
          if (existingMsg != null) {
            // Message already exists, just update it if needed
            if (messageToUse.thumbnailBase64 != null && messageToUse.thumbnailBase64!.isNotEmpty &&
                (existingMsg.thumbnailBase64 == null || existingMsg.thumbnailBase64!.isEmpty)) {
              existingMsg.thumbnailBase64 = messageToUse.thumbnailBase64;
              await _messageBox.put(messageToUse.messageId, existingMsg);
            }
            // Clean up any matching temp messages
            _pendingTempMessages.removeWhere((tempId, tempMsg) {
              if (tempMsg.chatId == msg.chatId &&
                  tempMsg.messageType == msg.messageType &&
                  tempMsg.timestamp.difference(msg.timestamp).inSeconds.abs() < 10) {
                print("🧹 Cleaned up pending temp message: $tempId (replaced by ${msg.messageId})");
                return true;
              }
              return false;
            });
            _needsRefresh = true;
            if (mounted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {});
              });
            }
            return; // Don't process duplicate
          }

          // Check if this real message might be replacing a pending temp message
          _pendingTempMessages.removeWhere((tempId, tempMsg) {
            // If real message matches temp message (by content, type, timestamp), remove temp
            if (tempMsg.chatId == msg.chatId &&
                tempMsg.messageType == msg.messageType &&
                tempMsg.timestamp.difference(msg.timestamp).inSeconds.abs() < 10) {
              // Also check groupId match for media messages
              if (msg.groupId != null && msg.groupId!.isNotEmpty) {
                if (tempMsg.groupId == msg.groupId && tempMsg.imageIndex == msg.imageIndex) {
                  print("🧹 Cleaned up pending temp message: $tempId (replaced by ${msg.messageId})");
                  return true;
                }
              } else {
                print("🧹 Cleaned up pending temp message: $tempId (replaced by ${msg.messageId})");
                return true;
              }
            }
            return false;
          });
        }

        _needsRefresh = true;

        if (mounted) {
          if (isTemp) {
            // ✅ CRITICAL: Store in-memory for instant display (before Hive sync)
            _pendingTempMessages[msg.messageId] = msg;

            // ✅ NEW: Mark sender messages as recently sent (for individual display)
            final userId = LocalAuthService.getUserId();
            final bool isMe = msg.senderId == userId;
            if (isMe && (msg.groupId ?? '').isNotEmpty) {
              final msgIdStr = msg.messageId.toString();
              _recentlyReceivedMessages.add(msgIdStr); // Use same set for both sender and receiver
              // Cancel existing timer if any
              _recentMessageTimers[msgIdStr]?.cancel();
              // Set timer to remove from recent set after 10 seconds
              _recentMessageTimers[msgIdStr] = Timer(const Duration(seconds: 10), () {
                _recentlyReceivedMessages.remove(msgIdStr);
                _recentMessageTimers.remove(msgIdStr);
                print("⏰ [RECENT] Removed sender message $msgIdStr from recently sent set");
              });
              print("✅ [RECENT] Marked sender message $msgIdStr as recently sent (will show individually)");
            }

            // ✅ CRITICAL FIX: Batch setState calls to prevent flickering
            // Use debounce to batch multiple updates together
            _debounceSetState();
            print("⚡ INSTANT UI refresh for temp message: ${msg.messageId}");
          } else {
            // ✅ Batch refresh for non-temp messages (prevent fluctuation)
            _debounceSetState();
          }
        }
      }
    });

    // ✅ OTHER LISTENERS
    _uploadProgressSubscription = ChatService.onUploadProgress.listen((progressData) {
      final tempId = progressData['tempId'];
      final progress = progressData['progress'];

      if (mounted && tempId != null) {
        setState(() {
          if (progress >= 0 && progress < 100) {
            // ✅ FIX: Only track progress while uploading
            _uploadProgress[tempId] = progress;
          } else {
            // ✅ FIX: Remove from progress when complete (>= 100) or failed (< 0)
            _uploadProgress.remove(tempId);
            // ✅ FIX: Clean up temp messages when upload is complete/removed
            _needsRefresh = true;
          }
        });
      }
    });

    _messageDeliveredSubscription = ChatService.onMessageDelivered.listen((messageId) {
      if (mounted) {
        print("✅ Message delivered update: $messageId");
        _needsRefresh = true;
      }
    });

    // ✅ CRITICAL FIX: THUMBNAIL READY LISTENER - Instant UI refresh (WhatsApp style)
    _thumbnailReadySubscription = ChatService.onThumbnailReady.listen((thumbnailData) {
      if (mounted) {
        final tempId = thumbnailData['tempId']?.toString();
        final message = thumbnailData['message'] as Message?;
        final thumbnailBase64 = thumbnailData['thumbnailBase64'];

        // ✅ CRITICAL: Update UI for temp messages (even without thumbnail initially)
        if (message != null && message.chatId == widget.chatId) {
          // ✅ CRITICAL: Update in-memory pending messages
          if (tempId != null && _pendingTempMessages.containsKey(tempId)) {
            _pendingTempMessages[tempId] = message;
          }

          if (thumbnailBase64 != null && thumbnailBase64.toString().isNotEmpty) {
            print("🖼️ Thumbnail ready for message: $tempId");
          } else {
            print("⚡ Temp message notification (no thumbnail yet): $tempId");
          }
          // ✅ CRITICAL FIX: Use debounced setState to prevent flickering
          _needsRefresh = true;
          _debounceSetState();
        }
      }
    });

    // ✅ ALL THUMBNAILS READY LISTENER - Trigger immediate bundle creation
    _allThumbnailsReadySubscription = ChatService.onAllThumbnailsReady.listen((data) {
      if (mounted) {
        final groupId = data['group_id']?.toString();
        final chatId = data['chat_id']?.toString();
        final totalImages = data['total_images'] as int?;

        if (groupId != null && chatId != null && totalImages != null && int.tryParse(chatId) == widget.chatId) {
          print("🖼️ [ALL THUMBNAILS READY] All thumbnails ready for group $groupId, total images: $totalImages");
          print("🔄 [ALL THUMBNAILS READY] Triggering immediate bundle creation...");

          // ✅ CRITICAL FIX: Clear "recent" markers for all messages in this group to allow bundle to show
          final allGroupMsgs = _messageBox.values
              .where((m) => m.groupId == groupId && m.chatId == widget.chatId)
              .toList();
          allGroupMsgs.addAll(_pendingTempMessages.values
              .where((m) => m.groupId == groupId && m.chatId == widget.chatId));
          
          for (final m in allGroupMsgs) {
            final msgIdStr = m.messageId.toString();
            _recentlyReceivedMessages.remove(msgIdStr);
            _recentMessageTimers[msgIdStr]?.cancel();
            _recentMessageTimers.remove(msgIdStr);
          }
          print("🧹 [ALL THUMBNAILS READY] Cleared recent markers for ${allGroupMsgs.length} messages in group $groupId");

          // ✅ Clear all rendering flags and cache to force fresh bundle creation
          final String groupAnchorKey = 'group_${groupId}_anchor';
          _renderedGroups.remove(groupId);
          _renderedAnchorMessages.remove(groupAnchorKey);
          _builtGroups.remove(groupId);
          _slotsSyncedForGroup.remove(groupId);
          
          // ✅ CRITICAL: Mark group for forced rebuild (even if cache exists later)
          _forceBundleRebuild.add(groupId);
          
          for (final m in allGroupMsgs) {
            if ((m.imageIndex ?? 0) == 0) {
              final anchorKey = m.messageId.toString();
              _collageWidgetCache.remove(anchorKey);
              _cachedFilledSlotsCount.remove(anchorKey);
              _renderedAnchorMessages.remove(anchorKey);
            }
          }

          // ✅ Trigger immediate bundle creation by re-initializing slots
          _reinitializeSlotsForGroup(groupId, widget.chatId);

          // ✅ CRITICAL: Clear message list cache to force full rebuild
          _cachedMessages.clear();
          _needsRefresh = true;

          // ✅ INSTANT UI REBUILD: Direct setState to force immediate UI update
          if (mounted) {
            setState(() {
              _needsRefresh = true;
            });
            print("🔄 [BUNDLE REBUILD] Triggered direct setState for instant UI update");
          }

          // ✅ CRITICAL FIX: Force Hive box update by touching extraData to trigger ValueListenableBuilder
          final anchorMsg = allGroupMsgs.firstWhereOrNull((m) => (m.imageIndex ?? 0) == 0);
          if (anchorMsg != null) {
            final updatedMsg = _messageBox.get(anchorMsg.messageId);
            if (updatedMsg != null) {
              // ✅ Force update by touching extraData field (triggers HiveObject change detection)
              final currentExtraData = updatedMsg.extraData ?? <String, dynamic>{};
              updatedMsg.extraData = {...currentExtraData, '_bundle_refresh': DateTime.now().millisecondsSinceEpoch};
              updatedMsg.save();
              print("✅ [THUMBNAILS BUNDLE] Triggered Hive box update for anchor ${anchorMsg.messageId} to force UI rebuild");
            }
          }
          print("✅ [ALL THUMBNAILS READY] Bundle creation triggered immediately for group $groupId");
        }
      }
    });

    _typingSubscription = ChatService.onTypingStatus.listen((typingInfo) {
      if (mounted && typingInfo['chatId'] == widget.chatId && typingInfo['userId'] != LocalAuthService.getUserId()) {
        setState(() {
          _isOtherUserTyping = typingInfo['isTyping'] ?? false;
        });
      }
    });

    _statusSubscription = ChatService.onUserStatus.listen((statusInfo) {
      if (mounted && statusInfo['userId'] == widget.otherUserId.toString()) {
        setState(() {
          _userStatus = statusInfo['status'] ?? "offline";
        });
      }
    });

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        setState(() {
          _isKeyboardOpen = true;
        });
        // Auto-scroll when keyboard opens
        if (_shouldScrollToBottom) {
          _scrollToBottomSmooth();
        }
      } else {
        setState(() {
          _isKeyboardOpen = false;
        });
      }
    });
  }

  // ✅ OPTIMIZED: GET MESSAGES WITH CACHING
  List<Message> _getOptimizedMessages() {
    // ✅ CRITICAL: Bypass cache if any group is marked for forced rebuild
    final bool hasForcedRebuild = _forceBundleRebuild.isNotEmpty;
    if (hasForcedRebuild) {
      print("🔄 [FORCE REBUILD] Bypassing message cache - groups in forced rebuild: ${_forceBundleRebuild.toList()}");
      _needsRefresh = true; // Force refresh
      _cachedMessages.clear(); // Clear cache to force rebuild
    }
    
    if (!_needsRefresh && _cachedMessages.isNotEmpty) {
      // ✅ CRITICAL: Still include pending temp messages for instant display
      final pendingToAdd = _pendingTempMessages.values
          .where((msg) => msg.chatId == widget.chatId)
          .where((msg) => !_cachedMessages.any((m) => m.messageId == msg.messageId))
          .where((msg) {
        final isTemp = msg.messageId.toString().startsWith('temp_');
        if (isTemp) {
          return msg.messageType == 'media' || msg.messageType == 'encrypted_media';
        }
        return false;
      })
          .toList();

      if (pendingToAdd.isNotEmpty) {
        // ✅ FIX: Filter out non-anchor messages from pending temp messages
        final filteredPending = <Message>[];
        final processedGroups = <String>{};
        final allMessages = [..._cachedMessages, ...pendingToAdd];

        for (final msg in pendingToAdd) {
          if ((msg.groupId ?? '').isEmpty) {
            filteredPending.add(msg);
          } else {
            final gid = msg.groupId!;
            if (!processedGroups.contains(gid)) {
              // Find anchor for this group from all messages
              final allInGroup = allMessages.where((m) => m.groupId == gid).toList();
              if (allInGroup.isNotEmpty) {
                final anchorIndex = allInGroup
                    .where((m) => m.imageIndex != null && m.imageIndex! >= 0)
                    .map((m) => m.imageIndex!)
                    .fold(9999, (a, b) => a < b ? a : b);
                final actualAnchorIndex = anchorIndex == 9999 ? 0 : anchorIndex;

                if ((msg.imageIndex ?? 0) == actualAnchorIndex) {
                  filteredPending.add(msg);
                  processedGroups.add(gid);
                }
              }
            }
          }
        }

        final combined = [..._cachedMessages, ...filteredPending];
        // ✅ CRITICAL FIX: Sort by imageIndex for grouped messages, timestamp otherwise
        // Same sorting logic as main sorting to maintain consistent order
        combined.sort((a, b) {
          // ✅ If both messages belong to same group, sort by imageIndex
          if (a.groupId != null && a.groupId == b.groupId &&
              a.imageIndex != null && b.imageIndex != null) {
            return a.imageIndex!.compareTo(b.imageIndex!);
          }

          // ✅ If both have imageIndex but different groups, sort by timestamp (groups maintain their internal order)
          // ✅ Fallback to timestamp sorting for non-grouped messages or different groups
          return a.timestamp.compareTo(b.timestamp);
        });
        return combined;
      }
      return _cachedMessages;
    }

    // ✅ CRITICAL: Combine Hive messages with in-memory pending temp messages
    final hiveMessages = _messageBox.values
        .where((msg) => msg.chatId == widget.chatId)
        .toList();

    // ✅ Add pending temp messages that aren't in Hive yet (for instant display)
    final pendingMessages = _pendingTempMessages.values
        .where((msg) => msg.chatId == widget.chatId)
        .where((msg) => !hiveMessages.any((m) => m.messageId == msg.messageId))
        .toList();

    final allMessages = [...hiveMessages, ...pendingMessages];

    final messages = allMessages.where((msg) {
      // ✅ CRITICAL FIX: Show temp messages INSTANTLY (WhatsApp style - even without thumbnails)
      final isTemp = msg.messageId.toString().startsWith('temp_');
      if (isTemp) {
        // ✅ CRITICAL: Show temp media messages IMMEDIATELY (even without thumbnail)
        // ✅ Thumbnails will load in background and update UI
        if (msg.messageType == 'media' || msg.messageType == 'encrypted_media') {
          return true; // ✅ Show INSTANTLY - WhatsApp style (no thumbnail wait)
        }
        // Hide all temp text messages completely
        return false;
      }

      // Show all non-temp messages
      return true;
    })
        .toList();

    // ✅ CRITICAL FIX: Sort by imageIndex for grouped messages, timestamp otherwise
    // This ensures sender and receiver show images in SAME order
    // Images in same group should be sorted by imageIndex, then by timestamp for different groups
    messages.sort((a, b) {
      // ✅ If both messages belong to same group, sort by imageIndex
      if (a.groupId != null && a.groupId == b.groupId &&
          a.imageIndex != null && b.imageIndex != null) {
        return a.imageIndex!.compareTo(b.imageIndex!);
      }

      // ✅ CRITICAL: For different groups or mixed (grouped vs non-grouped), sort by timestamp
      // This ensures messages appear in chronological order (newest at bottom)
      // Groups maintain internal order via imageIndex, but groups themselves are ordered by timestamp
      return a.timestamp.compareTo(b.timestamp);
    });

    // ✅ FIX: Deduplication - Remove duplicate messages by messageId
    // ✅ CRITICAL: Also clean up pending temp messages that are now in Hive
    final Map<String, Message> uniqueMessages = {};
    for (final m in messages) {
      final msgId = m.messageId.toString();
      // ✅ CRITICAL: If message is in Hive (real ID), remove from pending (already synced)
      if (!m.messageId.toString().startsWith('temp_')) {
        _pendingTempMessages.removeWhere((key, value) =>
        value.chatId == m.chatId &&
            value.messageType == m.messageType &&
            value.timestamp.difference(m.timestamp).inSeconds.abs() < 5
        );
      } else if (_pendingTempMessages.containsKey(msgId)) {
        // ✅ If temp message is in Hive, prefer Hive version if it has more data
        final pending = _pendingTempMessages[msgId]!;
        if ((m.thumbnailBase64 != null && m.thumbnailBase64!.isNotEmpty) ||
            (m.mediaUrls != null && m.mediaUrls!.isNotEmpty)) {
          // Use Hive version if it has data - remove from pending
          _pendingTempMessages.remove(msgId);
        } else {
          // Use pending version if Hive version has no data yet
          // Skip Hive version, will add pending version later
          continue;
        }
      }

      if (!uniqueMessages.containsKey(msgId)) {
        uniqueMessages[msgId] = m;
      } else {
        // ✅ FIX: Keep the one with more data (thumbnail, etc.)
        final existing = uniqueMessages[msgId]!;
        if ((m.thumbnailBase64 != null && m.thumbnailBase64!.isNotEmpty) &&
            (existing.thumbnailBase64 == null || existing.thumbnailBase64!.isEmpty)) {
          uniqueMessages[msgId] = m;
        }
      }
    }

    // ✅ CRITICAL: Add back pending temp messages that aren't in Hive yet (for instant display)
    for (final entry in _pendingTempMessages.entries) {
      if (!uniqueMessages.containsKey(entry.key)) {
        uniqueMessages[entry.key] = entry.value;
      }
    }

    final deduplicatedMessages = uniqueMessages.values.toList();

    // ✅ CRITICAL: DEDUPE GROUPED MEDIA: show only anchor (smallest imageIndex present)
    // ✅ This ensures consistent anchor detection across all functions
    final Map<String, int> groupAnchors = {};
    for (final m in deduplicatedMessages) {
      final gid = m.groupId;
      if (gid != null && gid.isNotEmpty) {
        // ✅ CRITICAL FIX: Only consider messages with valid imageIndex for anchor detection
        if (m.imageIndex != null && m.imageIndex! >= 0) {
          final idx = m.imageIndex!;
          if (!groupAnchors.containsKey(gid) || idx < groupAnchors[gid]!) {
            groupAnchors[gid] = idx;
          }
        } else {
          // ✅ If imageIndex is null, use 0 as default (first message)
          if (!groupAnchors.containsKey(gid)) {
            groupAnchors[gid] = 0;
          }
        }
      }
    }

    if (groupAnchors.isNotEmpty) {
      try {
        final anchorsLog = groupAnchors.entries.map((e) => '${e.key}:${e.value}').join(', ');
        print('🧩 [ANCHOR DETECTION] Group anchors computed: $anchorsLog');
        // ✅ DEBUG: Log all messages in each group to verify anchor detection
        for (final entry in groupAnchors.entries) {
          final gid = entry.key;
          final anchorIdx = entry.value;
          final groupMsgs = deduplicatedMessages.where((m) => m.groupId == gid).toList();
          print('🧩 [ANCHOR DEBUG] Group $gid: anchor=$anchorIdx, messages=${groupMsgs.map((m) => '${m.messageId}(idx=${m.imageIndex})').join(', ')}');
          
          // ✅ DEBUG: Check if anchor message exists in the list
          final anchorMsg = groupMsgs.firstWhereOrNull((m) => (m.imageIndex ?? 0) == anchorIdx);
          if (anchorMsg != null) {
            print('✅ [ANCHOR DEBUG] Anchor message found: ${anchorMsg.messageId}');
          } else {
            print('⚠️ [ANCHOR DEBUG] Anchor message NOT found for group $gid (anchor=$anchorIdx)');
          }
        }
      } catch (_) {}
    }

    // ✅ CRITICAL: DON'T pre-mark anchors here - let them be marked during actual rendering
    // ✅ Pre-marking causes issues where anchor is marked but collage never renders
    // ✅ The filtering below will ensure only anchor messages are in the list

    final filtered = <Message>[];
    // ✅ CRITICAL: Track processed groupIds to prevent showing multiple collages
    final processedGroups = <String>{};
    // ✅ CRITICAL: Track processed cluster anchors to prevent duplicates
    final processedClusterAnchors = <String>{};

    for (final m in deduplicatedMessages) {
      final gid = m.groupId;
      if (gid == null || gid.isEmpty) {
        // ✅ FIX: Check if message is part of fallback cluster
        //final cluster = _getContiguousMediaCluster(m);
        // if (cluster.length >= 2) {
        //   // ✅ FIX: Only show anchor message from cluster
        //   cluster.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        //   final Message anchor = cluster.first;
        //   if (m.messageId != anchor.messageId) {
        //     // Hide non-anchor messages from cluster
        //     print('🚫 [FILTER] Hiding non-anchor cluster message ${m.messageId} (anchor=${anchor.messageId})');
        //     continue; // Skip this message
        //   }
        //
        //   // ✅ CRITICAL: Use cluster-level key to prevent duplicate cluster anchors
        //   final List<String> clusterIds = cluster.map((msg) => msg.messageId.toString()).toList()..sort();
        //   final String clusterKey = 'cluster_${clusterIds.join('_')}';
        //
        //   if (processedClusterAnchors.contains(clusterKey)) {
        //     print('🚫 [FILTER] Cluster $clusterKey already processed, hiding ${m.messageId}');
        //     continue; // Skip duplicate cluster
        //   }
        //   processedClusterAnchors.add(clusterKey);
        //   print('✅ [FILTER] Added cluster anchor ${m.messageId} for cluster $clusterKey');
        // }
        filtered.add(m);
      } else {
        // ✅ FIX: Get all messages in this group to check count
        final List<Message> groupMessages = [];
        groupMessages.addAll(deduplicatedMessages.where((msg) => msg.groupId == gid && msg.chatId == widget.chatId));

        // ✅ FIX: Check if this is sender side (isMe) or receiver side
        final userId = LocalAuthService.getUserId();
        final bool isMe = m.senderId == userId;

        // ✅ RECEIVER SIDE COLLAGE FIX: Show collage if 2+ images received
        if (!isMe) {
          // ✅ RECEIVER SIDE: Check slots to determine if collage should be shown
          final groupMsgs = deduplicatedMessages.where((msg) => msg.groupId == gid && msg.chatId == widget.chatId).toList();

          // ✅ CRITICAL: Check filled slots from _collageMap, not just message count
          // ✅ Also sync slots from messages to get accurate count
          int filledSlots = 0;
          if (_collageMap.containsKey(gid)) {
            final slotList = _collageMap[gid]!;
            // ✅ Sync slots from actual messages to get accurate count
            final updatedSlotList = List<String?>.from(slotList);
            for (final msg in groupMsgs) {
              if (msg.imageIndex != null && msg.imageIndex! >= 0 && msg.imageIndex! < updatedSlotList.length) {
                final url = msg.messageContent;
                if (url.isNotEmpty && (updatedSlotList[msg.imageIndex!] == null || updatedSlotList[msg.imageIndex!]!.isEmpty)) {
                  updatedSlotList[msg.imageIndex!] = url;
                }
              }
            }
            filledSlots = updatedSlotList.where((url) => url != null && url.isNotEmpty).length;
          } else {
            // No slots yet - use message count as fallback
            filledSlots = groupMsgs.length;
          }

          print('🔍 [FILTER DEBUG] Receiver side - group $gid: groupMsgs=${groupMsgs.length}, filledSlots=$filledSlots, imageIndex=${m.imageIndex}');

          // ✅ CRITICAL FIX: If 2+ images arrived, ALWAYS show anchor (bundle)
          if (filledSlots >= 2 || groupMsgs.length >= 2) {
            // ✅ RECEIVER SIDE: Show only anchor message (collage) if 2+ images
            final anchor = groupAnchors[gid] ?? 0;
            print('🔍 [FILTER DEBUG] Receiver - anchor=$anchor, current imageIndex=${m.imageIndex}, match=${(m.imageIndex ?? 0) == anchor}');

            if ((m.imageIndex ?? 0) == anchor) {
              if (!processedGroups.contains(gid)) {
                filtered.add(m);
                processedGroups.add(gid);
                print('✅ [FILTER] Receiver: Added anchor message ${m.messageId} for group $gid (collage, imageIndex=${m.imageIndex}, filledSlots=$filledSlots)');
                print('✅ [FILTER] Receiver: Message ${m.messageId} WILL BE DISPLAYED in UI');
              } else {
                print('🚫 [FILTER] Receiver: Group $gid already processed, hiding ${m.messageId}');
                print('⚠️ [FILTER] Receiver: Message ${m.messageId} will NOT be displayed (duplicate group)');
              }
            } else {
              print('🚫 [FILTER] Receiver: Hiding non-anchor message ${m.messageId} for group $gid (showing collage, anchor=$anchor)');
              print('⚠️ [FILTER] Receiver: Message ${m.messageId} will NOT be displayed (not anchor)');
            }
          } else {
            // Less than 2 images - show all individually
            filtered.add(m);
            print('✅ [FILTER] Receiver: Added message ${m.messageId} for group $gid (single image, imageIndex=${m.imageIndex}, filledSlots=$filledSlots)');
          }
        } else {
          // Sender side: Check if group already processed - STRICT CHECK
          if (processedGroups.contains(gid)) {
            print('🚫 [FILTER] Group $gid already processed, hiding ${m.messageId}');
            continue; // Skip - group already has an anchor
          }
          // ✅ SENDER SIDE PERSISTENCE FIX: Show collage if 2+ images (not just 4+)
          // This ensures collage persists after app restart
          if (groupMessages.length >= 2) {
            // ✅ SENDER SIDE: Show only anchor message (collage) if 2+ images
            final anchor = groupAnchors[gid] ?? 0;
            if ((m.imageIndex ?? 0) == anchor) {
              filtered.add(m);
              processedGroups.add(gid);
              print('✅ [FILTER] Sender: Added anchor message ${m.messageId} for group $gid (collage, anchor=$anchor)');
            } else {
              print('🚫 [FILTER] Sender: Hiding non-anchor message ${m.messageId} (idx=${m.imageIndex}, anchor=$anchor)');
              continue; // Skip this message completely
            }
          } else {
            // Single message in group (not enough for collage yet) - ALWAYS show on sender side
            filtered.add(m);
            print('✅ [FILTER] Added single message ${m.messageId} for group $gid (waiting for more)');
          }
        }
      }
    }

    // ✅ JUMPING FIX: Save scroll position before updating cache
    double? savedScrollPosition;
    if (_scrollController.hasClients) {
      savedScrollPosition = _scrollController.offset;
    }

    // ✅ DEBUG: Log final filtered messages to verify anchor messages are included
    if (groupAnchors.isNotEmpty) {
      for (final entry in groupAnchors.entries) {
        final gid = entry.key;
        final anchorIdx = entry.value;
        final anchorInFiltered = filtered.any((m) => m.groupId == gid && (m.imageIndex ?? 0) == anchorIdx);
        print('🔍 [FILTER RESULT] Group $gid: anchor=$anchorIdx, anchorInFiltered=$anchorInFiltered, filteredCount=${filtered.length}');
        if (!anchorInFiltered) {
          print('⚠️ [FILTER WARNING] Anchor message NOT in filtered list for group $gid!');
          final groupMsgsInFiltered = filtered.where((m) => m.groupId == gid).toList();
          print('⚠️ [FILTER WARNING] Group messages in filtered: ${groupMsgsInFiltered.map((m) => '${m.messageId}(idx=${m.imageIndex})').join(', ')}');
        }
      }
    }

    _cachedMessages = filtered;
    _needsRefresh = false;

    // ✅ JUMPING FIX: Don't restore scroll position here - let Flutter handle it automatically
    // Restoring manually causes jumping issues
    return filtered;
  }

  // ✅ IMPLEMENTED: FRAME-SYNCED AUTO-SCROLL
  void _scrollToBottomSmooth() {
    if (!_scrollController.hasClients) return;

    // ✅ Use multiple callbacks to ensure scroll happens after layout
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _shouldScrollToBottom) {
        try {
          final maxScroll = _scrollController.position.maxScrollExtent;
          if (maxScroll > 0) {
            _scrollController.animateTo(
              maxScroll,
              duration: const Duration(milliseconds: 150), // ✅ FIX: Faster scroll animation
              curve: Curves.easeOut,
            );
          }
        } catch (e) {
          print("Scroll error in _scrollToBottomSmooth: $e");
        }
      }
    });
  }

  // ✅ FIXED: SCROLL TO BOTTOM - CORRECT IMPLEMENTATION
  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        try {
          final maxScroll = _scrollController.position.maxScrollExtent;
          _scrollController.jumpTo(maxScroll);
        } catch (e) {
          print("Scroll error: $e");
        }
      }
    });
  }

  // ✅ IMPLEMENTED: SCROLL POSITION CACHE
  void _saveScrollPosition() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.offset;
    _scrollBox.put('chat_${widget.chatId}', pos);
  }

  void _restoreScrollPosition() {
    final pos = _scrollBox.get('chat_${widget.chatId}', defaultValue: 0.0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && pos > 0) {
        _scrollController.jumpTo(pos.toDouble());
      }
    });
  }

  // ✅ IMPLEMENTED: SMART SCROLL LOCK - NEW MESSAGE TOAST
  void _showNewMessageToast() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('New message'),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'Scroll',
          onPressed: _scrollToBottom,
        ),
      ),
    );
  }

  void _updateScrollToBottomPreference() {
    if (!_scrollController.hasClients) return;

    final double currentOffset = _scrollController.offset;
    final double maxOffset = _scrollController.position.maxScrollExtent;

    setState(() {
      _isAtBottom = (maxOffset - currentOffset) <= _scrollThreshold;
      _shouldScrollToBottom = _isAtBottom;
    });

    // ✅ AUTO-SAVE SCROLL POSITION
    _saveScrollPosition();
  }

  // ✅ FLOATING BUTTON VISIBILITY
  void _updateFloatingButtonVisibility() {
    if (!_scrollController.hasClients) return;

    final double currentOffset = _scrollController.offset;
    final double maxOffset = _scrollController.position.maxScrollExtent;

    setState(() {
      _showScrollToBottom = (maxOffset - currentOffset) > 400;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTyping();
    _focusNode.unfocus();
    _focusNode.dispose();
    _typingTimer?.cancel();
    _typingSubscription?.cancel();
    _statusSubscription?.cancel();
    _newMessageSubscription?.cancel();
    _uploadProgressSubscription?.cancel();
    _messageDeliveredSubscription?.cancel();
    _thumbnailReadySubscription?.cancel();
    _allThumbnailsReadySubscription?.cancel();
    _updateTimer?.cancel();
    _collageVersionNotifier.dispose();

    // ✅ CLEANUP LOADING TIMERS
    _loadTimers.forEach((key, timer) => timer.cancel());
    _loadTimers.clear();

    // ✅ SAVE SCROLL POSITION ON DISPOSE
    _saveScrollPosition();

    _scrollController.dispose();
    _processedMessageIds.clear();
    _uploadProgress.clear();
    _imageLoadStages.clear();
    _fullyLoadedMessages.clear();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final bottomInset = WidgetsBinding.instance.window.viewInsets.bottom;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (bottomInset > 0.0 && _focusNode.hasFocus && _shouldScrollToBottom) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  // ✅ FIX: Handle app lifecycle changes to clear recent messages and trigger bundle creation
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // ✅ When app resumes, clear recent messages to show bundles
      print("🔄 [LIFECYCLE] App resumed - clearing recent messages to show bundles");
      _recentlyReceivedMessages.clear();
      _recentMessageTimers.values.forEach((timer) => timer.cancel());
      _recentMessageTimers.clear();
      
      // ✅ Clear cache and force rebuild to show bundles
      _cachedMessages.clear();
      _needsRefresh = true;
      
      // ✅ Trigger UI rebuild
      if (mounted) {
        setState(() {
          _needsRefresh = true;
        });
        print("✅ [LIFECYCLE] Triggered UI rebuild after app resume");
      }
    }
  }

  // ✅ OPTIMIZED JUMP TO BOTTOM
  void _jumpToBottom() {
    if (!_scrollController.hasClients) return;

    // ✅ Use multiple callbacks to ensure scroll happens after layout
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _shouldScrollToBottom) {
        try {
          // ✅ Wait for next frame to ensure layout is complete
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients && _shouldScrollToBottom) {
              try {
                final maxScroll = _scrollController.position.maxScrollExtent;
                if (maxScroll > 0) {
                  _scrollController.jumpTo(maxScroll);
                }
              } catch (e) {
                print("Scroll error in _jumpToBottom: $e");
              }
            }
          });
        } catch (e) {
          print("Scroll error in _jumpToBottom (outer): $e");
        }
      }
    });
  }

  void _toggleKeyboard() {
    if (_focusNode.hasFocus) {
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
    }
  }

  void _updateLastReadMessageId() {
    if (!_scrollController.hasClients) return;

    final messages = _getOptimizedMessages();
    if (messages.isEmpty) return;

    final firstVisibleIndex = (_scrollController.position.maxScrollExtent - _scrollController.offset) ~/ (60);

    if (firstVisibleIndex >= 0 && firstVisibleIndex < messages.length) {
      final lastReadMsg = messages[messages.length - 1 - firstVisibleIndex];
      final int lastReadMsgId = int.tryParse(lastReadMsg.messageId.toString()) ?? 0;

      if (lastReadMsgId > _lastReadMessageId) {
        setState(() {
          _lastReadMessageId = lastReadMsgId;
        });
        _authBox.put('lastReadMessageId_${widget.chatId}', _lastReadMessageId.toString());
      }
    }
  }

  // ✅ FIXED: PERSISTENT PROGRESSIVE LOADING FUNCTIONS
  void _startProgressiveLoading(Message msg) {
    final messageId = msg.messageId;

    if (_fullyLoadedMessages.contains(messageId)) {
      _imageLoadStages[messageId] = 3;
      return;
    }

    if (_imageLoadStages.containsKey(messageId)) {
      return;
    }

    print("🚀 Starting WhatsApp-style loading: $messageId");

    _imageLoadStages[messageId] = 1;

    _loadTimers[messageId] = Timer(const Duration(milliseconds: 800), () {
      if (_imageLoadStages[messageId] == 2 && mounted) {
        _loadHighQualityImage(msg);
      }
    });

    if (mounted) setState(() {});
  }

  void _markLowQualityLoaded(Message msg) {
    final messageId = msg.messageId;
    _imageLoadStages[messageId] = 2;
    if (mounted) setState(() {});
  }

  void _loadHighQualityImage(Message msg) {
    final messageId = msg.messageId;
    if (_imageLoadStages[messageId] == 3) return;

    _imageLoadStages[messageId] = 3;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fullyLoadedMessages.add(messageId);
        setState(() {});
      }
    });

    if (mounted) setState(() {});
  }

  // ✅ SWIPE TO REPLY FUNCTIONALITY
  void _handleSwipeStart(DragStartDetails details, Message message) {
    if (_selectionMode) return; // Don't allow swipe in selection mode
    _swipeMessage = message;
    _isSwiping = true;
  }

  void _handleSwipeUpdate(DragUpdateDetails details) {
    if (!_isSwiping || _selectionMode) return;

    _swipeOffset += details.delta.dx;

    // Limit swipe to right only and max 100px
    if (_swipeOffset > 0) {
      _swipeOffset = _swipeOffset.clamp(0.0, 100.0);
    } else {
      _swipeOffset = 0.0;
    }

    setState(() {});
  }

  void _handleSwipeEnd(DragEndDetails details) {
    if (!_isSwiping || _selectionMode) return;

    // If swiped more than 60px, trigger reply
    if (_swipeOffset > 60) {
      _startReply(_swipeMessage!);
      HapticFeedback.lightImpact();
    }

    // Reset swipe state
    _swipeOffset = 0.0;
    _isSwiping = false;
    _swipeMessage = null;
    setState(() {});
  }

  // ✅ FLOATING SCROLL TO BOTTOM BUTTON - FIXED
  Widget _buildFloatingScrollButton() {
    if (!_showScrollToBottom || !_scrollController.hasClients) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: 100,
      right: 16,
      child: FloatingActionButton(
        backgroundColor: const Color(0xFF075E54),
        mini: true,
        onPressed: () {
          _scrollToBottom(); // ✅ FIXED: Use correct function
          HapticFeedback.lightImpact();
        },
        child: const Icon(Icons.arrow_downward, color: Colors.white, size: 20),
      ),
    );
  }

  // ✅ SELECTION MODE FUNCTIONS
  void _enterSelectionMode(String messageId) {
    setState(() {
      _selectionMode = true;
      selectedMessageIds.add(messageId);
    });
  }

  void _toggleSelection(String messageId) {
    setState(() {
      if (selectedMessageIds.contains(messageId)) {
        selectedMessageIds.remove(messageId);
        if (selectedMessageIds.isEmpty) _selectionMode = false;
      } else {
        selectedMessageIds.add(messageId);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
      selectedMessageIds.clear();
    });
  }

  // ✅ SELECTION BOTTOM BAR (WHATSAPP STYLE) - UPDATED WITH COPY
  Widget _buildSelectionBottomBar() {
    if (!_selectionMode) return const SizedBox.shrink();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // Delete Button
            _buildSelectionActionButton(
              icon: Icons.delete_outline,
              label: 'Delete',
              color: Colors.red,
              onTap: _deleteSelectedMessages,
            ),

            // Forward Button
            _buildSelectionActionButton(
              icon: Icons.forward,
              label: 'Forward',
              color: Colors.green,
              onTap: _forwardSelectedMessages,
            ),

            // ✅ COPY BUTTON - ADDED
            if (_hasTextMessagesSelected())
              _buildSelectionActionButton(
                icon: Icons.copy,
                label: 'Copy',
                color: Colors.blue,
                onTap: _copySelectedMessages,
              ),

            // Selected Count
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                "${selectedMessageIds.length}",
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),

            // Close Button
            _buildSelectionActionButton(
              icon: Icons.close,
              label: 'Close',
              color: Colors.grey,
              onTap: _clearSelection,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ✅ CHECK IF ANY TEXT MESSAGES ARE SELECTED
  bool _hasTextMessagesSelected() {
    for (final messageId in selectedMessageIds) {
      final message = _messageBox.values.firstWhereOrNull((m) => m.messageId == messageId);
      if (message != null && message.messageType == 'text') {
        return true;
      }
    }
    return false;
  }

  // ✅ COPY SELECTED MESSAGES FUNCTION
  void _copySelectedMessages() {
    final textMessages = selectedMessageIds
        .map((id) => _messageBox.values.firstWhereOrNull((m) => m.messageId == id))
        .where((msg) => msg != null && msg.messageType == 'text')
        .map((msg) => msg!.messageContent)
        .toList();

    if (textMessages.isNotEmpty) {
      final textToCopy = textMessages.join('\n\n');
      Clipboard.setData(ClipboardData(text: textToCopy));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Copied ${textMessages.length} message${textMessages.length > 1 ? 's' : ''}"),
          duration: const Duration(seconds: 2),
        ),
      );

      _clearSelection();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No text messages selected to copy"),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ✅ COPY SINGLE MESSAGE FUNCTION
  void _copySingleMessage(String messageId) {
    final message = _messageBox.values.firstWhereOrNull((m) => m.messageId == messageId);
    if (message != null && message.messageType == 'text') {
      Clipboard.setData(ClipboardData(text: message.messageContent));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Message copied"),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Cannot copy media messages"),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _resolveHeader() async {
    try {
      String? phone = _authBox.get('otherUserPhone');
      if (phone == null || phone.toString().trim().isEmpty) {
        final msgs = _getOptimizedMessages();

        for (final m in msgs.reversed) {
          if (m.senderId == widget.otherUserId && (m.senderPhoneNumber?.isNotEmpty ?? false)) {
            phone = m.senderPhoneNumber!;
            break;
          }
          if (m.receiverId == widget.otherUserId && (m.receiverPhoneNumber?.isNotEmpty ?? false)) {
            phone = m.receiverPhoneNumber!;
            break;
          }
        }
      }

      String title;
      if (phone != null && phone.isNotEmpty) {
        final localName = await ContactService.getContactNameByPhoneNumber(phone);
        if (localName != null && localName.isNotEmpty) {
          title = localName;
        } else {
          title = phone;
        }
      } else if (widget.otherUserName.isNotEmpty) {
        title = widget.otherUserName;
      } else {
        title = "User ${widget.otherUserId}";
      }

      if (!mounted) return;
      setState(() {
        _otherUserPhone = phone;
        _resolvedTitle = title;
      });
    } catch (e) {
      print("Error in resolveHeader: $e");
    }
  }

  // ✅ OPTIMIZED LOAD MORE MESSAGES
  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) return;

    setState(() => _isLoadingMore = true);

    try {
      // Save current scroll position before loading more
      final currentScroll = _scrollController.offset;
      final messages = _getOptimizedMessages();

      if (messages.isNotEmpty) {
        _oldestMessageTime = messages.first.timestamp;

        // Simulate loading more messages
        await Future.delayed(const Duration(milliseconds: 500));

        // Restore scroll position after loading
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(currentScroll + 100);
          }
        });
      }
    } catch (e) {
      print("Error loading more messages: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  // ✅ FIXED: _fetchMessages with STRONG duplicate prevention
  Future<void> _fetchMessages() async {
    try {
      print("🔄 Loading last 50 messages from server for chat ${widget.chatId}");

      final url = Uri.parse("${Config.baseNodeApiUrl}/messages/combined/${widget.chatId}");

      final res = await http.get(url);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);

        if (data["success"] == true && data["messages"] != null) {
          int newMessagesCount = 0;
          int duplicateCount = 0;

          final messages = List.from(data["messages"]);

          for (var msg in messages) {
            final messageId = msg["message_id"]?.toString();
            final tempId = msg["temp_id"]?.toString();
            final idToProcess = messageId ?? tempId;

            if (idToProcess == null) continue;

            final existingMessage = _messageBox.values.firstWhereOrNull(
                  (existingMsg) => existingMsg.messageId == idToProcess,
            );

            if (existingMessage == null) {
              await _handleIncomingData(msg);
              newMessagesCount++;
            } else {
              duplicateCount++;
            }
          }

          print("✅ Loaded $newMessagesCount new messages, skipped $duplicateCount duplicates");

        } else {
          print("❌ Server response indicates failure: ${data['message']}");
        }
      } else {
        print("❌ Server error: ${res.statusCode}");
      }

      setState(() {
        _areMessagesLoaded = true;
        _needsRefresh = true;
      });

      // ✅ Initialize fixed slots from loaded messages
      _initializeFixedSlotsFromExistingMessages();

    } catch (e) {
      print("❌ Fetch messages error: $e");
      setState(() {
        _areMessagesLoaded = true;
        _needsRefresh = true;
      });
    }
  }

  // ✅ Initialize fixed slots from existing messages (for app restart)
  Future<void> _initializeFixedSlotsFromExistingMessages() async {
    print("🔄 Initializing fixed slots from existing messages...");

    // ✅ CRITICAL: Clear everything on initialization to allow fresh rendering
    // ✅ But we'll mark anchors during initialization to prevent duplicates
    _renderedGroups.clear();
    _renderedAnchorMessages.clear();
    _collageWidgetCache.clear();
    _cachedFilledSlotsCount.clear(); // Also clear cached counts
    _slotsSyncedForGroup.clear();
    _slotsNeedSync.clear();
    _slotSignature.clear();
    _clusterRenderedAnchors.clear();
    _clusterCache.clear();
    _clusterStamp.clear(); // ✅ Clear cluster debounce stamps

    // ✅ BACK NAVIGATION FIX: Clear recently received messages when coming back
    // This ensures that when user comes back, collage is shown instead of individual images
    _recentlyReceivedMessages.clear();
    _recentMessageTimers.values.forEach((timer) => timer.cancel());
    _recentMessageTimers.clear();
    print("🧹 Cleared rendered groups, anchors, widget cache, slot syncs, slot need sync, slot signatures, cluster anchors, cluster cache, cluster stamps, and recent messages for fresh initialization");

    // Group messages by groupId (from both Hive and pending temp messages)
    final Map<String, List<Message>> groupMap = {};

    // ✅ DEBUG: Count messages in chat
    int totalMessagesInChat = 0;
    int messagesWithGroupId = 0;
    int messagesWithImageIndex = 0;
    int messagesWithTotalImages = 0;

    // ✅ Add messages from Hive
    for (final msg in _messageBox.values) {
      if (msg.chatId == widget.chatId) {
        totalMessagesInChat++;

        // ✅ INDEXING FIX: Check for groupId even if it's empty string or null
        final hasGroupId = (msg.groupId ?? '').isNotEmpty;
        if (hasGroupId) {
          messagesWithGroupId++;
          final hasImageIndex = msg.imageIndex != null && msg.imageIndex! >= 0;
          if (hasImageIndex) {
            messagesWithImageIndex++;
            final hasTotalImages = msg.totalImages != null && msg.totalImages! > 0;
            if (hasTotalImages) {
              messagesWithTotalImages++;
              final gid = msg.groupId!;
              if (!groupMap.containsKey(gid)) {
                groupMap[gid] = [];
              }
              groupMap[gid]!.add(msg);
              print("📱 [INIT DEBUG] Found grouped message: groupId=$gid, imageIndex=${msg.imageIndex}, totalImages=${msg.totalImages}, messageId=${msg.messageId}");
            } else {
              print("⚠️ [INIT DEBUG] Message has groupId but no totalImages: groupId=${msg.groupId}, imageIndex=${msg.imageIndex}, messageId=${msg.messageId}");
            }
          } else {
            print("⚠️ [INIT DEBUG] Message has groupId but no imageIndex: groupId=${msg.groupId}, messageId=${msg.messageId}");
          }
        }

        // ✅ DEBUG: Log messages that should have groupId but don't
        if (!hasGroupId && (msg.messageType == 'media' || msg.messageType == 'encrypted_media')) {
          // Check if this might be a grouped message that lost its groupId
          print("📱 [INIT DEBUG] Media message without groupId: messageId=${msg.messageId}, messageType=${msg.messageType}");
          print("   - timestamp: ${msg.timestamp}");
          print("   - senderId: ${msg.senderId}");
          print("   - messageContent length: ${msg.messageContent.length}");
        }
      }
    }

    print("📊 [INIT DEBUG] Chat ${widget.chatId}: totalMessages=$totalMessagesInChat, withGroupId=$messagesWithGroupId, withImageIndex=$messagesWithImageIndex, withTotalImages=$messagesWithTotalImages, groupsFound=${groupMap.length}");

    // ✅ APP RESTART FIX: Check if we have messages with groupId but they're not in groupMap
    // This can happen if messages have groupId but slots weren't initialized properly
    if (messagesWithGroupId > 0 && groupMap.isEmpty) {
      print("⚠️ [INIT WARNING] Found $messagesWithGroupId messages with groupId but groupMap is empty - re-grouping messages");

      // Re-group messages that have groupId
      for (final msg in _messageBox.values) {
        if (msg.chatId == widget.chatId && (msg.groupId ?? '').isNotEmpty) {
          final gid = msg.groupId!;
          if (!groupMap.containsKey(gid)) {
            groupMap[gid] = [];
          }
          if (!groupMap[gid]!.any((m) => m.messageId == msg.messageId)) {
            groupMap[gid]!.add(msg);
            print("🔄 [INIT RE-GROUP] Added message ${msg.messageId} to group $gid (imageIndex=${msg.imageIndex}, totalImages=${msg.totalImages})");
          }
        }
      }

      print("📊 [INIT RE-GROUP] After re-grouping: groupsFound=${groupMap.length}");
    }

    // ✅ FALLBACK GROUPING: If no groups found but we have media messages, try to group by timestamp proximity
    // ✅ CRITICAL: Always run fallback grouping if groupMap is empty, regardless of messagesWithGroupId
    // This ensures that even if messages lost their groupId, they can be re-grouped
    if (groupMap.isEmpty) {
      print("⚠️ [FALLBACK GROUPING] No groups found (messagesWithGroupId=$messagesWithGroupId) - attempting fallback grouping by timestamp proximity");

      // Group media messages by sender and timestamp proximity (within 5 seconds)
      final Map<String, List<Message>> fallbackGroups = {};
      final mediaMessages = _messageBox.values
          .where((msg) => msg.chatId == widget.chatId &&
          (msg.messageType == 'media' || msg.messageType == 'encrypted_media'))
          .toList();

      mediaMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      String? currentGroupId;
      DateTime? lastMessageTime;
      int groupCounter = 0;

      for (final msg in mediaMessages) {
        if (lastMessageTime == null ||
            msg.timestamp.difference(lastMessageTime!).inSeconds > 5) {
          // New group
          groupCounter++;
          currentGroupId = 'fallback_${widget.chatId}_${msg.senderId}_${groupCounter}';
          fallbackGroups[currentGroupId] = [];
        }

        if (currentGroupId != null) {
          fallbackGroups[currentGroupId]!.add(msg);
          lastMessageTime = msg.timestamp;

          // ✅ Update message with fallback groupId (if not already set)
          if ((msg.groupId ?? '').isEmpty) {
            msg.groupId = currentGroupId;
            msg.imageIndex = fallbackGroups[currentGroupId]!.length - 1;
            // ✅ CRITICAL: Don't set totalImages here - will set after all messages are added
            print("🔄 [FALLBACK] Updated message ${msg.messageId} with fallback groupId=$currentGroupId, imageIndex=${msg.imageIndex}");
          }
        }
      }

      // ✅ CRITICAL FIX: Update totalImages for ALL messages in each group AFTER grouping is complete
      for (final entry in fallbackGroups.entries) {
        final groupId = entry.key;
        final groupMessages = entry.value;
        final totalCount = groupMessages.length;

        print("🔄 [FALLBACK] Processing group $groupId with $totalCount messages");

        // ✅ CRITICAL FIX: Update imageIndex and totalImages for ALL messages AFTER grouping is complete
        // ✅ APP RESTART FIX: Save messages synchronously to ensure persistence
        for (int i = 0; i < groupMessages.length; i++) {
          final msg = groupMessages[i];
          msg.imageIndex = i; // ✅ Ensure imageIndex is correct (0, 1, 2, ...)
          msg.totalImages = totalCount; // ✅ Set to FINAL count, not current count

          // ✅ CRITICAL: Save synchronously to ensure messages are persisted before app restart
          // This ensures that when app restarts, messages have groupId/imageIndex/totalImages
          await ChatService.saveMessageLocal(msg);
          print("🔄 [FALLBACK] Updated message ${msg.messageId}: groupId=$groupId, imageIndex=$i, totalImages=$totalCount");
        }

        // ✅ Initialize slots for this fallback group with CORRECT totalCount
        if (!_collageMap.containsKey(groupId)) {
          _collageMap[groupId] = List.filled(totalCount, null);
          _collageLayoutFrozen[groupId] = false;
          _collageTotalImages[groupId] = totalCount;
          print("🧩 [FALLBACK] Initialized slots for group $groupId with $totalCount images");
        } else {
          // ✅ If slots exist but wrong size, resize them
          final existingSlots = _collageMap[groupId]!;
          if (existingSlots.length != totalCount) {
            print("⚠️ [FALLBACK] Resizing slots for group $groupId from ${existingSlots.length} to $totalCount");
            final oldSlots = List<String?>.from(existingSlots);
            _collageMap[groupId] = List.filled(totalCount, null);
            // Copy old slots to new slots
            for (int i = 0; i < oldSlots.length && i < totalCount; i++) {
              if (oldSlots[i] != null && oldSlots[i]!.isNotEmpty) {
                _collageMap[groupId]![i] = oldSlots[i];
              }
            }
            _collageTotalImages[groupId] = totalCount;
          }
        }

        // ✅ Fill slots with messages
        final slotList = _collageMap[groupId]!;
        for (final msg in groupMessages) {
          if (msg.imageIndex != null &&
              msg.imageIndex! >= 0 &&
              msg.imageIndex! < slotList.length &&
              msg.messageContent.isNotEmpty) {
            slotList[msg.imageIndex!] = msg.messageContent;
            print("✅ [FALLBACK] Filled slot ${msg.imageIndex} for group $groupId from message ${msg.messageId}");
          } else {
            print("⚠️ [FALLBACK] Skipped slot fill for message ${msg.messageId}: imageIndex=${msg.imageIndex}, slotList.length=${slotList.length}, messageContent.isEmpty=${msg.messageContent.isEmpty}");
          }
        }

        final filledSlots = slotList.where((url) => url != null && url.isNotEmpty).length;

        // ✅ Add fallback groups to groupMap
        if (groupMessages.length >= 2) {
          groupMap[groupId] = groupMessages;
          print("✅ [FALLBACK] Created fallback group $groupId with ${groupMessages.length} messages, totalImages=$totalCount");
        }
      }

      print("📊 [FALLBACK] Created ${fallbackGroups.length} fallback groups from ${mediaMessages.length} media messages");
    }

    // ✅ Add messages from pending temp messages
    for (final msg in _pendingTempMessages.values) {
      if (msg.chatId == widget.chatId &&
          (msg.groupId ?? '').isNotEmpty &&
          msg.imageIndex != null &&
          msg.totalImages != null) {
        final gid = msg.groupId!;
        if (!groupMap.containsKey(gid)) {
          groupMap[gid] = [];
        }
        // ✅ Only add if not already in map (avoid duplicates)
        final exists = groupMap[gid]!.any((m) =>
        m.messageId == msg.messageId ||
            (m.imageIndex == msg.imageIndex && m.groupId == msg.groupId)
        );
        if (!exists) {
          groupMap[gid]!.add(msg);
        }
      }
    }

    // Create fixed slots for each group
    for (final entry in groupMap.entries) {
      final groupId = entry.key;
      final messages = entry.value;

      if (messages.isEmpty) continue;

      // ✅ Get totalImages from message with totalImages set, or calculate from unique imageIndexes
      int? totalImages;
      final messagesWithTotal = messages.where((m) => m.totalImages != null).toList();
      if (messagesWithTotal.isNotEmpty) {
        totalImages = messagesWithTotal.first.totalImages;
      } else {
        // Calculate from max imageIndex + 1
        final maxIndex = messages
            .where((m) => m.imageIndex != null && m.imageIndex! >= 0)
            .map((m) => m.imageIndex!)
            .fold(-1, (a, b) => a > b ? a : b);
        totalImages = maxIndex >= 0 ? maxIndex + 1 : messages.length;
      }

      if (totalImages == null || totalImages <= 0) continue;

      // Create fixed slots if not already created
      if (!_collageMap.containsKey(groupId)) {
        print("🧩 Initializing fixed slots for group $groupId with $totalImages images");
        _collageMap[groupId] = List.filled(totalImages, null);
        // ✅ FIX: Don't freeze immediately - only freeze when 4 slots are full
        _collageLayoutFrozen[groupId] = false;
        _collageTotalImages[groupId] = totalImages;
      }

      // Fill slots with existing messages (prioritize non-temp messages)
      final slotList = _collageMap[groupId]!;
      int slotsFilled = 0;

      // ✅ CRITICAL FIX: Sort messages by imageIndex to ensure correct order with stable sort
      // ✅ APP RESTART FIX: Use messageId as secondary key to ensure consistent ordering
      final sortedMessages = List<Message>.from(messages);
      sortedMessages.sort((a, b) {
        final aIdx = a.imageIndex ?? 9999;
        final bIdx = b.imageIndex ?? 9999;
        final indexCompare = aIdx.compareTo(bIdx);
        // ✅ CRITICAL: If imageIndex is same, use messageId for stable sorting (ensures same order on app restart)
        if (indexCompare != 0) {
          return indexCompare;
        }
        // ✅ Secondary sort by messageId to ensure consistent order even if imageIndex is duplicate
        return a.messageId.toString().compareTo(b.messageId.toString());
      });

      for (final msg in sortedMessages) {
        // ✅ INDEXING FIX: Validate imageIndex before placing
        int? validIndex = msg.imageIndex;
        if (validIndex == null || validIndex < 0 || validIndex >= slotList.length) {
          if (validIndex != null && totalImages != null) {
            if (validIndex < 0) {
              validIndex = 0;
            } else if (validIndex >= totalImages) {
              validIndex = totalImages - 1;
            }
            print("⚠️ [INIT INDEX FIX] Corrected imageIndex from ${msg.imageIndex} to $validIndex for message ${msg.messageId}");
          } else {
            print("⚠️ [INIT] Skipping message ${msg.messageId} - invalid imageIndex: ${msg.imageIndex}");
            continue;
          }
        }

        if (validIndex >= 0 && validIndex < slotList.length) {
          final url = msg.messageContent;
          if (url.isNotEmpty) {
            // ✅ If slot is empty, fill it
            // ✅ If slot has temp message and this is real message, replace it
            // ✅ If slot has real message and this is temp, keep real message
            final isTemp = msg.messageId.toString().startsWith('temp_');
            if (slotList[validIndex] == null || slotList[validIndex]!.isEmpty) {
              slotList[validIndex] = url;
              slotsFilled++;
              print("✅ [INIT] Restored slot $validIndex for group $groupId (${isTemp ? 'temp' : 'real'}) - messageId=${msg.messageId}");
            } else if (!isTemp) {
              // Real message replaces temp in slot
              slotList[validIndex] = url;
              if (slotList[validIndex] != url) slotsFilled++;
              print("✅ [INIT] Updated slot $validIndex for group $groupId with real message - messageId=${msg.messageId}");
            }
          }
        }
      }

      // ✅ CRITICAL: After filling slots, ensure collage can be rendered when user comes back
      final filledSlots = slotList.where((url) => url != null && url.isNotEmpty).length;
      if (filledSlots >= 2) {
        // ✅ Mark slot signature so collage knows slots are ready
        _slotSignature[groupId] = slotList.join("|");

        // ✅ APP RESTART FIX: Clear rendered flags to allow collage rendering after restart
        _renderedGroups.remove(groupId);
        final String groupAnchorKey = 'group_${groupId}_anchor';
        _renderedAnchorMessages.remove(groupAnchorKey);
        _builtGroups.remove(groupId);
        _slotsSyncedForGroup.remove(groupId); // Don't mark as synced - let it sync during rendering

        // ✅ Clear cache to force fresh collage build after restart
        final anchorMessages = messages.where((m) => (m.imageIndex ?? 0) == 0).toList();
        for (final anchorMsg in anchorMessages) {
          final anchorKey = anchorMsg.messageId.toString();
          _collageWidgetCache.remove(anchorKey);
          _cachedFilledSlotsCount.remove(anchorKey);
        }

        print("✅ [INIT] Group $groupId initialized with $filledSlots/$totalImages slots filled - collage ready to render on back/restart");
        print("📊 [INIT] Slot status: ${slotList.asMap().entries.map((e) => 'Slot[${e.key}]:${e.value != null && e.value!.isNotEmpty ? "✓" : "✗"}').join(', ')}");
        print("🔄 [INIT] Cleared rendered flags and cache for group $groupId to allow fresh collage render");
      } else {
        print("✅ [INIT] Group $groupId initialized with $filledSlots/$totalImages slots filled - waiting for more images");
      }

      // ✅ CRITICAL: DON'T mark anchor during initialization - let it be marked during actual rendering
      // ✅ Marking during initialization causes issues where anchor is marked but collage never renders
      // ✅ The filtering in _getOptimizedMessages() will ensure only anchor messages are shown
      print("✅ [INIT] Group $groupId initialized with ${messages.length} messages, $slotsFilled slots filled - anchor will be marked during rendering");
    }

    print("✅ Fixed slots initialized for ${groupMap.length} groups");

    // ✅ CRITICAL: Force UI refresh after initialization to render collages
    if (mounted) {
      setState(() {
        _needsRefresh = true;
      });
      print("🔄 [INIT] Forced UI refresh after slot initialization");
    }
  }

  // ✅ CRITICAL FIX: Re-initialize slots for a specific group when new images arrive
  // This ensures all images show immediately in real-time, same as when navigating back
  void _reinitializeSlotsForGroup(String groupId, int chatId) {
    print("🔄 [RE-INIT] Re-initializing slots for group $groupId (real-time update)");

    // Get ALL messages for this group from both Hive and pending temp messages
    final List<Message> groupMessages = [];

    // Add from Hive
    groupMessages.addAll(_messageBox.values.where((m) =>
    m.chatId == chatId &&
        m.groupId == groupId &&
        m.imageIndex != null &&
        m.totalImages != null
    ));

    // Add from pending temp messages
    groupMessages.addAll(_pendingTempMessages.values.where((m) =>
    m.chatId == chatId &&
        m.groupId == groupId &&
        m.imageIndex != null &&
        m.totalImages != null
    ));

    if (groupMessages.isEmpty) {
      print("⚠️ [RE-INIT] No messages found for group $groupId");
      return;
    }

    print("🔄 [RE-INIT] Found ${groupMessages.length} messages for group $groupId");

    // Get totalImages from message with totalImages set, or calculate
    int? totalImages;
    final messagesWithTotal = groupMessages.where((m) => m.totalImages != null).toList();
    if (messagesWithTotal.isNotEmpty) {
      totalImages = messagesWithTotal.first.totalImages;
    } else {
      final maxIndex = groupMessages
          .where((m) => m.imageIndex != null && m.imageIndex! >= 0)
          .map((m) => m.imageIndex!)
          .fold(-1, (a, b) => a > b ? a : b);
      totalImages = maxIndex >= 0 ? maxIndex + 1 : groupMessages.length;
    }

    if (totalImages == null || totalImages <= 0) {
      print("⚠️ [RE-INIT] Invalid totalImages for group $groupId");
      return;
    }

    // Create or ensure slots exist
    if (!_collageMap.containsKey(groupId)) {
      print("🧩 [RE-INIT] Creating fixed slots for group $groupId with $totalImages images");
      _collageMap[groupId] = List.filled(totalImages, null);
      // ✅ FIX: Don't freeze immediately - only freeze when 4 slots are full
      _collageLayoutFrozen[groupId] = false;
      _collageTotalImages[groupId] = totalImages;
    }

    // ✅ CRITICAL: Clear ALL caches and flags FIRST before filling slots
    final String groupAnchorKey = 'group_${groupId}_anchor';

    // Clear ALL tracking flags to allow fresh rebuild
    _renderedGroups.remove(groupId);
    _renderedAnchorMessages.remove(groupAnchorKey);
    _slotsSyncedForGroup.remove(groupId);
    _builtGroups.remove(groupId);

    // Get all messages in group to clear cache for all anchors
    final allMessagesInGroup = _messageBox.values
        .where((m) => m.chatId == chatId && m.groupId == groupId)
        .toList();
    allMessagesInGroup.addAll(_pendingTempMessages.values
        .where((m) => m.chatId == chatId && m.groupId == groupId));

    // Clear cache for ALL anchor messages
    for (final m in allMessagesInGroup) {
      if ((m.imageIndex ?? 0) == 0) {
        final anchorKey = m.messageId.toString();
        _collageWidgetCache.remove(anchorKey);
        _cachedFilledSlotsCount.remove(anchorKey); // Also clear cached count
        _renderedAnchorMessages.remove(anchorKey);
        print("🗑️ [RE-INIT] Cleared cache for anchor $anchorKey");
      }
    }

    // Fill slots with ALL messages (prioritize non-temp messages)
    final slotList = _collageMap[groupId]!;
    int previousFilledCount = slotList.where((url) => url != null).length;

    // ✅ CRITICAL FIX: Sort messages: real messages first, then temp messages, then by imageIndex for consistency
    // ✅ APP RESTART FIX: Use stable sort with imageIndex and messageId to ensure consistent ordering
    groupMessages.sort((a, b) {
      final aIsTemp = a.messageId.toString().startsWith('temp_');
      final bIsTemp = b.messageId.toString().startsWith('temp_');
      if (aIsTemp && !bIsTemp) return 1; // Real messages first
      if (!aIsTemp && bIsTemp) return -1;
      // ✅ If both are same type (both temp or both real), sort by imageIndex
      final aIdx = a.imageIndex ?? 9999;
      final bIdx = b.imageIndex ?? 9999;
      final indexCompare = aIdx.compareTo(bIdx);
      if (indexCompare != 0) {
        return indexCompare;
      }
      // ✅ Secondary sort by messageId to ensure consistent order even if imageIndex is duplicate
      return a.messageId.toString().compareTo(b.messageId.toString());
    });

    for (final msg in groupMessages) {
      if (msg.imageIndex != null &&
          msg.imageIndex! >= 0 &&
          msg.imageIndex! < slotList.length) {
        final url = msg.messageContent;
        if (url.isNotEmpty) {
          final isTemp = msg.messageId.toString().startsWith('temp_');
          // ✅ Always update slot if it's empty or if this is a real message
          if (slotList[msg.imageIndex!] == null || !isTemp) {
            slotList[msg.imageIndex!] = url;
            print("✅ [RE-INIT] Filled slot ${msg.imageIndex} for group $groupId (${isTemp ? 'temp' : 'real'})");
          }
        }
      }
    }

    final filledSlots = slotList.where((url) => url != null).length;
    print("✅ [RE-INIT] Group $groupId re-initialized: $filledSlots/$totalImages slots filled (was $previousFilledCount)");
    print("✅ [RE-INIT] Slot status: ${slotList.asMap().entries.map((e) => '${e.key}:${e.value != null ? "filled" : "empty"}').join(', ')}");

    // ✅ CRITICAL: Always force UI rebuild when slots are re-initialized (new images arrived)
    print("🔄 [RE-INIT] Forcing UI rebuild for group $groupId ($filledSlots/$totalImages slots filled, was $previousFilledCount)");

    // Clear message cache to force rebuild of message list
    _cachedMessages.clear();
    _needsRefresh = true;

    // ✅ CRITICAL: Force immediate setState (don't wait for callbacks)
    if (mounted) {
      setState(() {
        _needsRefresh = true;
        _cachedMessages.clear(); // ✅ Clear cache to force fresh message list
      });
      print("🔄 [RE-INIT] Triggered immediate setState for group $groupId");
    }

    // ✅ Also trigger post-frame callback as backup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _needsRefresh = true;
        });
        print("🔄 [RE-INIT] Triggered setState (postFrame backup) for group $groupId");
      }
    });
  }

  Future<void> _handleIncomingData(dynamic data) async {
    try {
      final messageId = data["message_id"]?.toString();
      final tempId = data["temp_id"]?.toString();
      final idToProcess = messageId ?? tempId;

      if (idToProcess == null) {
        return;
      }

      String messageText = data["message_text"]?.toString() ?? "";
      String messageType = data["message_type"]?.toString() ?? "text";

      bool hasMedia = (data["media_url"] != null && data["media_url"].toString().isNotEmpty) ||
          (data["low_quality_url"] != null && data["low_quality_url"].toString().isNotEmpty) ||
          (data["high_quality_url"] != null && data["high_quality_url"].toString().isNotEmpty);

      if (hasMedia) {
        messageType = "media";
        messageText = "media";
      }

      String? mediaUrl = data["media_url"]?.toString();
      //String? lowQualityUrl = data["low_quality_url"]?.toString();
      //String? highQualityUrl = data["high_quality_url"]?.toString();
      //String? blurHash = data["blur_hash"]?.toString();
      String? thumbnailBase64 = data["thumbnail_data"]?.toString() ??
          data["thumbnail"]?.toString() ??
          data["thumbnail_base64"]?.toString();

      // ✅ CLEAN THUMBNAIL BASE64 - Remove data URI prefix if present
      if (thumbnailBase64 != null && thumbnailBase64.isNotEmpty) {
        // Remove "data:image/jpeg;base64," or similar prefixes
        if (thumbnailBase64.contains(',')) {
          thumbnailBase64 = thumbnailBase64.split(',').last;
        }
        thumbnailBase64 = thumbnailBase64.trim();
        print("🖼️ Thumbnail received: ${thumbnailBase64.length} chars");
      } else {
        print("⚠️ No thumbnail data in server response");
      }

      String? replyToMessageId = data["reply_to_message_id"]?.toString();
      bool isForwarded = data["is_forwarded"] == true || data["is_forwarded"] == 1;
      String? forwardedFrom = data["forwarded_from"]?.toString();

      mediaUrl = _convertToFullUrl(mediaUrl);
      //lowQualityUrl = _convertToFullUrl(lowQualityUrl);
      //highQualityUrl = _convertToFullUrl(highQualityUrl);

      // ✅ FIX: Check for duplicate grouped messages on receiver side
      final String? groupId = data["group_id"]?.toString();
      final int? imageIndexRaw = data["image_index"] != null ? int.tryParse(data["image_index"].toString()) : null;
      final int? totalImages = data["total_images"] != null ? int.tryParse(data["total_images"].toString()) : null;

      // ✅ INDEXING FIX: Ensure imageIndex is valid (0-based indexing)
      int? imageIndex = imageIndexRaw;
      if (imageIndexRaw != null && totalImages != null) {
        // ✅ Validate imageIndex is within valid range (0 to totalImages-1)
        if (imageIndexRaw < 0) {
          print("⚠️ [INDEX FIX] Invalid imageIndex: $imageIndexRaw (negative), setting to 0");
          imageIndex = 0;
        } else if (imageIndexRaw >= totalImages) {
          print("⚠️ [INDEX FIX] Invalid imageIndex: $imageIndexRaw (>= totalImages=$totalImages), clamping to ${totalImages - 1}");
          imageIndex = totalImages - 1;
        }
      }

      // ✅ DEBUG: Log group data with validation - ALWAYS log for media messages
      if (messageType == 'media' || hasMedia) {
        print("📱 [SOCKET DATA] Media message received: messageId=$idToProcess");
        print("   - group_id from socket: ${data["group_id"]} (type: ${data["group_id"]?.runtimeType})");
        print("   - image_index from socket: ${data["image_index"]} (type: ${data["image_index"]?.runtimeType})");
        print("   - total_images from socket: ${data["total_images"]} (type: ${data["total_images"]?.runtimeType})");
        print("   - Extracted: groupId=$groupId, imageIndex=$imageIndex, totalImages=$totalImages");
      }

      if (groupId != null && groupId.isNotEmpty) {
        print("🧩 RECEIVED GROUP MESSAGE: groupId=$groupId, imageIndex=$imageIndex (raw=$imageIndexRaw), totalImages=$totalImages, messageId=$idToProcess");
        if (imageIndexRaw != imageIndex) {
          print("⚠️ [INDEX FIX] imageIndex corrected from $imageIndexRaw to $imageIndex");
        }
      } else if (messageType == 'media' || hasMedia) {
        print("⚠️ [SOCKET WARNING] Media message received WITHOUT groupId/imageIndex/totalImages!");
        print("   - This message will NOT be grouped into a collage");
        print("   - messageId=$idToProcess, messageType=$messageType");
      }

      // ✅ CRITICAL: Check for duplicate by messageId first
      final existingMsg = _messageBox.values.firstWhereOrNull(
            (m) => m.messageId == idToProcess,
      );

      if (existingMsg != null) {
        print("⚠️ Duplicate message blocked on receiver: messageId=$idToProcess");
        return; // Skip duplicate
      }

      // ✅ FIXED SLOT SYSTEM: Handle group images with index-based placement
      if (groupId != null && groupId.isNotEmpty && imageIndex != null && totalImages != null && totalImages > 0) {
        final chatIdForGroup = int.tryParse(data["chat_id"]?.toString() ?? "0") ?? 0;
        final senderIdForGroup = int.tryParse(data["sender_id"]?.toString() ?? "0") ?? 0;
        final userId = LocalAuthService.getUserId();
        final bool isMe = senderIdForGroup == userId;

        // ✅ STEP 1: Create fixed slots when first image arrives
        if (!_collageMap.containsKey(groupId)) {
          print("🧩 Creating fixed slots for group $groupId with $totalImages images");
          _collageMap[groupId] = List.filled(totalImages, null);
          // ✅ FIX: Don't freeze immediately - only freeze when 4 slots are full
          _collageLayoutFrozen[groupId] = false;
          _collageTotalImages[groupId] = totalImages;
        }

        // ✅ STEP 2: Check for duplicate by groupId + imageIndex + chatId (including temp messages)
        // ✅ CRITICAL: Check both Hive messages AND pending temp messages
        final existingGroupedMsg = _messageBox.values.firstWhereOrNull(
              (m) => m.groupId == groupId &&
              m.imageIndex == imageIndex &&
              m.chatId == chatIdForGroup,
        );

        // ✅ CRITICAL: Also check pending temp messages
        final existingTempMsg = _pendingTempMessages.values.firstWhereOrNull(
              (m) => m.groupId == groupId &&
              m.imageIndex == imageIndex &&
              m.chatId == chatIdForGroup,
        );

        if (existingGroupedMsg != null) {
          print("⚠️ Duplicate grouped message blocked: groupId=$groupId, imageIndex=$imageIndex, messageId=$idToProcess, existingId=${existingGroupedMsg.messageId}");

          // ✅ If this is a real message replacing a temp message, update the temp message
          if (existingGroupedMsg.messageId.toString().startsWith('temp_') && !idToProcess.toString().startsWith('temp_')) {
            final oldTempId = existingGroupedMsg.messageId;
            print("🔄 Updating temp message $oldTempId with real messageId $idToProcess");
            existingGroupedMsg.messageId = idToProcess;
            if (mediaUrl != null) existingGroupedMsg.messageContent = mediaUrl;
            if (thumbnailBase64 != null && thumbnailBase64.isNotEmpty) {
              existingGroupedMsg.thumbnailBase64 = thumbnailBase64;
            }
            await ChatService.saveMessageLocal(existingGroupedMsg);
            _pendingTempMessages.remove(oldTempId);

            // ✅ Force slot update immediately after temp → final ID conversion
            if (_collageMap.containsKey(groupId)) {
              final slotList = _collageMap[groupId]!;
              if (existingGroupedMsg.imageIndex != null &&
                  existingGroupedMsg.imageIndex! >= 0 &&
                  existingGroupedMsg.imageIndex! < slotList.length) {
                final newUrl = mediaUrl ?? existingGroupedMsg.messageContent;
                if (newUrl.isNotEmpty && slotList[existingGroupedMsg.imageIndex!] != newUrl) {
                  slotList[existingGroupedMsg.imageIndex!] = newUrl;
                  print('🔄 [TEMP CONVERSION] Force updated slot ${existingGroupedMsg.imageIndex} in group $groupId with new URL');

                  // ✅ Refresh slot signature after temp replace
                  final String signatureNow = slotList.join("|");
                  _slotSignature[groupId] = signatureNow;
                  print('🔄 [TEMP CONVERSION] Refreshed slot signature for group $groupId');

                  // ✅ Invalidate cache, otherwise old cached collage keeps showing
                  final anchorKey = existingGroupedMsg.messageId.toString();
                  _collageWidgetCache.remove(anchorKey);
                  _collageWidgetCache.remove(oldTempId.toString());
                  _cachedFilledSlotsCount.remove(anchorKey);
                  _cachedFilledSlotsCount.remove(oldTempId.toString());
                  print('🔄 [TEMP CONVERSION] Invalidated cache for anchor: $anchorKey and old temp: $oldTempId');

                  // ✅ Force re-sync
                  _slotsSyncedForGroup.remove(groupId);
                  _slotsNeedSync[groupId] = true;
                }
              }
            }

            // ✅ STEP 2 FIX: If old temp was anchor and rendered, update rendered set
            // ✅ Use groupId as key instead of messageId to prevent duplicate anchors
            final String groupAnchorKey = 'group_${groupId}_anchor';
            if (_renderedAnchorMessages.contains(groupAnchorKey)) {
              print("🔄 Anchor already rendered for group $groupId - keeping existing anchor");
            } else {
              _renderedAnchorMessages.add(groupAnchorKey);
              print("✅ Marked group $groupId anchor as rendered");
            }

            // ✅ Also update messageId-based tracking for cache
            if (_renderedAnchorMessages.contains(oldTempId.toString())) {
              _renderedAnchorMessages.remove(oldTempId.toString());
            }
            _renderedAnchorMessages.add(idToProcess.toString());
            print("🔄 Updated rendered anchor from $oldTempId to $idToProcess (Hive update)");

            _needsRefresh = true;
            if (mounted) setState(() {});
            return; // Don't create new message, just updated existing
          }

          return; // Skip duplicate
        }

        if (existingTempMsg != null && !idToProcess.toString().startsWith('temp_')) {
          print("🔄 Found temp message for same groupId+imageIndex, updating it with real messageId");
          // Update temp message with real messageId
          final oldTempId = existingTempMsg.messageId;
          existingTempMsg.messageId = idToProcess;
          if (mediaUrl != null) existingTempMsg.messageContent = mediaUrl;
          if (thumbnailBase64 != null && thumbnailBase64.isNotEmpty) {
            existingTempMsg.thumbnailBase64 = thumbnailBase64;
          }
          _pendingTempMessages.remove(oldTempId);
          _pendingTempMessages[idToProcess] = existingTempMsg;

          // ✅ Force slot update immediately after temp → final ID conversion
          if (_collageMap.containsKey(groupId)) {
            final slotList = _collageMap[groupId]!;
            if (existingTempMsg.imageIndex != null &&
                existingTempMsg.imageIndex! >= 0 &&
                existingTempMsg.imageIndex! < slotList.length) {
              final newUrl = mediaUrl ?? existingTempMsg.messageContent;
              if (newUrl.isNotEmpty && slotList[existingTempMsg.imageIndex!] != newUrl) {
                slotList[existingTempMsg.imageIndex!] = newUrl;
                print('🔄 [TEMP CONVERSION] Force updated slot ${existingTempMsg.imageIndex} in group $groupId with new URL');

                // ✅ Refresh slot signature after temp replace
                final String signatureNow = slotList.join("|");
                _slotSignature[groupId] = signatureNow;
                print('🔄 [TEMP CONVERSION] Refreshed slot signature for group $groupId');

                // ✅ Invalidate cache, otherwise old cached collage keeps showing
                final anchorKey = idToProcess.toString();
                _collageWidgetCache.remove(anchorKey);
                _collageWidgetCache.remove(oldTempId.toString());
                _cachedFilledSlotsCount.remove(anchorKey);
                _cachedFilledSlotsCount.remove(oldTempId.toString());
                print('🔄 [TEMP CONVERSION] Invalidated cache for anchor: $anchorKey and old temp: $oldTempId');

                // ✅ Force re-sync
                _slotsSyncedForGroup.remove(groupId);
                _slotsNeedSync[groupId] = true;
              }
            }
          }

          // ✅ STEP 2 FIX: If old temp was anchor and rendered, update rendered set
          // ✅ Use groupId as key instead of messageId to prevent duplicate anchors
          final String groupAnchorKey = 'group_${groupId}_anchor';
          if (_renderedAnchorMessages.contains(groupAnchorKey)) {
            print("⛔ Duplicate anchor attempt blocked for group $groupId");
            return; // ✅ BLOCK - anchor already exists for this group
          } else {
            _renderedAnchorMessages.add(groupAnchorKey);
            print("✅ Marked group $groupId anchor as rendered");
          }

          // ✅ Also update messageId-based tracking for cache
          if (_renderedAnchorMessages.contains(oldTempId.toString())) {
            _renderedAnchorMessages.remove(oldTempId.toString());
          }
          _renderedAnchorMessages.add(idToProcess.toString());
          print("🔄 Updated rendered anchor from $oldTempId to $idToProcess");

          // ✅ Update fixed slot
          final slotList = _collageMap[groupId]!;
          if (imageIndex >= 0 && imageIndex < slotList.length) {
            slotList[imageIndex] = mediaUrl ?? messageText;
          }
          // Continue to save the updated message
        }

        // ✅ STEP 3: Place image in fixed slot by index (NO DUPLICATE POSSIBLE)
        final slotList = _collageMap[groupId]!;

        // ✅ INDEXING FIX: Double-check imageIndex is valid before placing
        if (imageIndex == null || imageIndex < 0 || imageIndex >= slotList.length) {
          print("❌ [INDEX ERROR] Invalid imageIndex: $imageIndex for group $groupId (slotList.length=${slotList.length}, totalImages=$totalImages)");
          print("   - messageId: $idToProcess");
          print("   - groupId: $groupId");
          if (imageIndex != null && imageIndex >= 0 && totalImages != null) {
            // Try to clamp to valid range
            final clampedIndex = imageIndex >= totalImages ? totalImages - 1 : imageIndex;
            if (clampedIndex >= 0 && clampedIndex < slotList.length) {
              print("   - Attempting to clamp to valid index: $clampedIndex");
              imageIndex = clampedIndex;
            } else {
              print("   - Cannot clamp, blocking message");
              return; // Block invalid index
            }
          } else {
            return; // Block if imageIndex is null or invalid
          }
        }

        if (imageIndex >= 0 && imageIndex < slotList.length) {
          // ✅ CRITICAL: Check if slot is already filled - if yes, it's a duplicate
          if (slotList[imageIndex] != null && slotList[imageIndex]!.isNotEmpty) {
            print("⚠️ [FIXED SLOT] Slot $imageIndex already filled for group $groupId - DUPLICATE BLOCKED");
            print("   - Existing slot URL: ${slotList[imageIndex]!.substring(0, slotList[imageIndex]!.length > 50 ? 50 : slotList[imageIndex]!.length)}...");
            print("   - New message URL: ${(mediaUrl ?? messageText).substring(0, (mediaUrl ?? messageText).length > 50 ? 50 : (mediaUrl ?? messageText).length)}...");
            print("   - New messageId: $idToProcess");

            // ✅ Check if existing message exists in Hive or pending
            final slotFilledMsg = _messageBox.values.firstWhereOrNull(
                  (m) => m.groupId == groupId &&
                  m.imageIndex == imageIndex &&
                  m.chatId == chatIdForGroup,
            ) ?? _pendingTempMessages.values.firstWhereOrNull(
                  (m) => m.groupId == groupId &&
                  m.imageIndex == imageIndex &&
                  m.chatId == chatIdForGroup,
            );

            if (slotFilledMsg != null) {
              print("⚠️ [FIXED SLOT] Message already exists for slot $imageIndex - BLOCKING DUPLICATE");
              print("   - Existing messageId: ${slotFilledMsg.messageId}");
              return; // ✅ BLOCK DUPLICATE - slot already has a message
            }

            // ✅ STEP 1 FIX: If slot is filled but no message exists, DON'T replace - it might be from another source
            // ✅ Just block the duplicate instead of replacing
            print("⚠️ [FIXED SLOT] Slot $imageIndex already filled but no message found in Hive - BLOCKING to prevent replacement");
            print("   - Existing slot URL: ${slotList[imageIndex]!.substring(0, slotList[imageIndex]!.length > 50 ? 50 : slotList[imageIndex]!.length)}...");
            print("   - New message URL: ${(mediaUrl ?? messageText).substring(0, (mediaUrl ?? messageText).length > 50 ? 50 : (mediaUrl ?? messageText).length)}...");
            return; // ✅ BLOCK - don't replace filled slot
          } else {
            // Slot is empty, fill it
            slotList[imageIndex] = mediaUrl ?? messageText;
            print("✅ [FIXED SLOT] Image placed in slot $imageIndex for group $groupId (totalSlots=${slotList.length}, totalImages=$totalImages)");

            // ✅ CRITICAL: Clear cache immediately when new slot is filled (receiver side)
            final userId = LocalAuthService.getUserId();
            final bool isMe = int.tryParse(data["sender_id"]?.toString() ?? "0") == userId;
            if (!isMe) {
              // Receiver side: Clear cache for all messages in this group to force rebuild
              final allGroupMsgs = _messageBox.values
                  .where((m) => m.groupId == groupId && m.chatId == chatIdForGroup)
                  .toList();
              allGroupMsgs.addAll(_pendingTempMessages.values
                  .where((m) => m.groupId == groupId && m.chatId == chatIdForGroup));

              for (final m in allGroupMsgs) {
                final anchorKey = m.messageId.toString();
                _collageWidgetCache.remove(anchorKey);
                _cachedFilledSlotsCount.remove(anchorKey);
              }

              final String groupAnchorKey = 'group_${groupId}_anchor';
              _renderedGroups.remove(groupId);
              _renderedAnchorMessages.remove(groupAnchorKey);
              _builtGroups.remove(groupId);
              _slotsSyncedForGroup.remove(groupId);

              print("🗑️ [FIXED SLOT] Cleared cache for group $groupId after slot $imageIndex filled");
            }
          }
        }

        // ✅ DEBUG: Count how many slots are filled and log slot status
        final filledSlots = slotList.where((url) => url != null && url.isNotEmpty).length;
        print("🧩 Group $groupId: $filledSlots/$totalImages slots filled");
        print("📊 [SLOT STATUS] Group $groupId slots: ${slotList.asMap().entries.map((e) => 'Slot[${e.key}]:${e.value != null && e.value!.isNotEmpty ? "✓" : "✗"}').join(', ')}");

        // ✅ CRITICAL: If 2+ images have arrived, trigger immediate bundle creation
        if (filledSlots >= 2 && totalImages >= 2) {
          final isAllImages = filledSlots == totalImages;
          print("✅ [BUNDLE CREATION] ${isAllImages ? 'All' : '$filledSlots'} $totalImages images received for group $groupId - triggering immediate bundle creation");
          
          // ✅ CRITICAL FIX: Clear "recent" markers for all messages in this group to allow bundle to show
          final allGroupMsgs = _messageBox.values
              .where((m) => m.groupId == groupId && m.chatId == chatIdForGroup)
              .toList();
          allGroupMsgs.addAll(_pendingTempMessages.values
              .where((m) => m.groupId == groupId && m.chatId == chatIdForGroup));
          
          for (final m in allGroupMsgs) {
            final msgIdStr = m.messageId.toString();
            _recentlyReceivedMessages.remove(msgIdStr);
            _recentMessageTimers[msgIdStr]?.cancel();
            _recentMessageTimers.remove(msgIdStr);
          }
          print("🧹 [ALL IMAGES ARRIVED] Cleared recent markers for ${allGroupMsgs.length} messages in group $groupId");
          
          // ✅ Clear all rendering flags and cache to force fresh bundle creation
          final String groupAnchorKey = 'group_${groupId}_anchor';
          _renderedGroups.remove(groupId);
          _renderedAnchorMessages.remove(groupAnchorKey);
          _builtGroups.remove(groupId);
          _slotsSyncedForGroup.remove(groupId);
          
          // ✅ CRITICAL: Mark group for forced rebuild (even if cache exists later)
          _forceBundleRebuild.add(groupId);
          
          for (final m in allGroupMsgs) {
            if ((m.imageIndex ?? 0) == 0) {
              final anchorKey = m.messageId.toString();
              _collageWidgetCache.remove(anchorKey);
              _cachedFilledSlotsCount.remove(anchorKey);
              _renderedAnchorMessages.remove(anchorKey);
            }
          }
          
          // Trigger immediate bundle creation
          _reinitializeSlotsForGroup(groupId, chatIdForGroup);
          
          // ✅ CRITICAL: Clear message list cache to force full rebuild
          _cachedMessages.clear();
          _needsRefresh = true;
          
          // ✅ STEP: Last image aayi → version.value++ 🔥 → ValueListenableBuilder rebuild → Collage turant draw
          _collageVersionNotifier.value = _collageVersionNotifier.value + 1;
          print("🔥 [COLLAGE VERSION] Incremented collage version to ${_collageVersionNotifier.value} for group $groupId (filledSlots=$filledSlots/$totalImages)");

          // ✅ INSTANT UI REBUILD: Direct setState to force immediate UI update
          if (mounted) {
            setState(() {
              _needsRefresh = true;
            });
            print("🔄 [BUNDLE REBUILD] Triggered direct setState for instant UI update");
          }

          // ✅ CRITICAL FIX: Force Hive box update by touching extraData to trigger ValueListenableBuilder
          final anchorMsg = allGroupMsgs.firstWhereOrNull((m) => (m.imageIndex ?? 0) == 0);
          if (anchorMsg != null) {
            final updatedMsg = _messageBox.get(anchorMsg.messageId);
            if (updatedMsg != null) {
              // ✅ Force update by touching extraData field (triggers HiveObject change detection)
              final currentExtraData = updatedMsg.extraData ?? <String, dynamic>{};
              updatedMsg.extraData = {...currentExtraData, '_bundle_refresh': DateTime.now().millisecondsSinceEpoch};
              updatedMsg.save();
              print("✅ [BUNDLE] Triggered Hive box update for anchor ${anchorMsg.messageId} to force UI rebuild");
            }
          }
          print("✅ [ALL IMAGES ARRIVED] Bundle creation triggered immediately for group $groupId");
        }
      }

      final msg = Message(
        messageId: idToProcess,
        chatId: int.tryParse(data["chat_id"]?.toString() ?? "0") ?? 0,
        senderId: int.tryParse(data["sender_id"]?.toString() ?? "0") ?? 0,
        receiverId: int.tryParse(data["receiver_id"]?.toString() ?? "0") ?? 0,
        messageContent: mediaUrl ?? messageText,
        messageType: messageType,
        isRead: int.tryParse(data["is_read"]?.toString() ?? "0") ?? 0,
        isDelivered: int.tryParse(data["is_delivered"]?.toString() ?? "0") ?? 0,
        timestamp: DateTime.tryParse(data["timestamp"]?.toString() ?? "") ?? DateTime.now(),
        senderName: data["sender_name"]?.toString(),
        receiverName: data["receiver_name"]?.toString(),
        senderPhoneNumber: data["sender_phone"]?.toString(),
        receiverPhoneNumber: data["receiver_phone"]?.toString(),
        //lowQualityUrl: lowQualityUrl,
        //highQualityUrl: highQualityUrl,
        //blurHash: blurHash,
        thumbnailBase64: thumbnailBase64,
        replyToMessageId: replyToMessageId,
        isForwarded: isForwarded,
        forwardedFrom: forwardedFrom,
        groupId: groupId,
        imageIndex: imageIndex,
        totalImages: data["total_images"] != null ? int.tryParse(data["total_images"].toString()) : null,
      );

      // ✅ CRITICAL: Final duplicate check using fixed slots BEFORE saving
      // ✅ FIX: Only block if message with SAME messageId already exists (not just same slot)
      if (groupId != null && groupId.isNotEmpty && imageIndex != null && _collageMap.containsKey(groupId)) {
        final slotList = _collageMap[groupId]!;

        // ✅ INDEXING FIX: Validate imageIndex before checking slot
        if (imageIndex < 0 || imageIndex >= slotList.length) {
          print("❌ [INDEX ERROR] Final check - Invalid imageIndex: $imageIndex for group $groupId (slotList.length=${slotList.length})");
          print("   - messageId: ${msg.messageId}");
          print("   - totalImages: $totalImages");
          return; // Block invalid index
        }

        if (imageIndex >= 0 && imageIndex < slotList.length && slotList[imageIndex] != null && slotList[imageIndex]!.isNotEmpty) {
          // ✅ Check if message with SAME messageId already exists (strongest check)
          final existingByMessageId = _messageBox.values.firstWhereOrNull(
                (m) => m.messageId == msg.messageId,
          ) ?? _pendingTempMessages.values.firstWhereOrNull(
                (m) => m.messageId == msg.messageId,
          );

          if (existingByMessageId != null) {
            print("⚠️ [FINAL CHECK] Duplicate blocked by messageId: ${msg.messageId}");
            return; // ✅ BLOCK DUPLICATE - same messageId
          }

          // ✅ Also check if message with same groupId+imageIndex+chatId+senderId exists
          final existingForSlot = _messageBox.values.firstWhereOrNull(
                (m) => m.groupId == groupId &&
                m.imageIndex == imageIndex &&
                m.chatId == msg.chatId &&
                m.senderId == msg.senderId &&
                m.messageId != msg.messageId, // ✅ Different messageId
          ) ?? _pendingTempMessages.values.firstWhereOrNull(
                (m) => m.groupId == groupId &&
                m.imageIndex == imageIndex &&
                m.chatId == msg.chatId &&
                m.senderId == msg.senderId &&
                m.messageId != msg.messageId, // ✅ Different messageId
          );

          if (existingForSlot != null) {
            print("⚠️ [FINAL CHECK] Duplicate blocked by fixed slot: groupId=$groupId, imageIndex=$imageIndex");
            print("   - Existing messageId: ${existingForSlot.messageId}");
            print("   - New messageId: ${msg.messageId}");
            return; // ✅ BLOCK DUPLICATE - same slot with different messageId
          }
        }
      }

      // ✅ DEBUG: Log message before saving - ALWAYS log for media messages
      if (messageType == 'media' || hasMedia) {
        print("💾 [SAVE DEBUG] Saving media message: messageId=${msg.messageId}");
        print("   - groupId from data: $groupId");
        print("   - imageIndex from data: $imageIndex");
        print("   - totalImages from data: $totalImages");
        print("   - msg.groupId: ${msg.groupId}");
        print("   - msg.imageIndex: ${msg.imageIndex}");
        print("   - msg.totalImages: ${msg.totalImages}");
      }

      if (groupId != null && groupId.isNotEmpty) {
        print("💾 [SAVE DEBUG] Saving message with group data: messageId=${msg.messageId}, groupId=$groupId, imageIndex=${msg.imageIndex}, totalImages=${msg.totalImages}");
      }

      await ChatService.saveMessageLocal(msg);

      // ✅ VERIFY: Check if message was saved correctly with groupId - ALWAYS check for media
      final savedMsg = _messageBox.get(msg.messageId);
      if (savedMsg != null) {
        if (messageType == 'media' || hasMedia) {
          print("💾 [SAVE VERIFY] Checking saved media message: messageId=${savedMsg.messageId}");
          print("   - savedMsg.groupId: ${savedMsg.groupId}");
          print("   - savedMsg.imageIndex: ${savedMsg.imageIndex}");
          print("   - savedMsg.totalImages: ${savedMsg.totalImages}");
        }

        if (groupId != null && groupId.isNotEmpty) {
          if (savedMsg.groupId != groupId || savedMsg.imageIndex != imageIndex || savedMsg.totalImages != msg.totalImages) {
            print("⚠️ [SAVE ERROR] Message saved incorrectly! Expected: groupId=$groupId, imageIndex=$imageIndex, totalImages=${msg.totalImages}");
            print("   Actual: groupId=${savedMsg.groupId}, imageIndex=${savedMsg.imageIndex}, totalImages=${savedMsg.totalImages}");
          } else {
            print("✅ [SAVE VERIFY] Message saved correctly with group data");
          }
        } else if (messageType == 'media' || hasMedia) {
          print("⚠️ [SAVE WARNING] Media message saved WITHOUT groupId/imageIndex/totalImages!");
        }
      }

      // ✅ NEW: Mark sender messages as recently sent when saved locally (for individual display)
      final userId = LocalAuthService.getUserId();
      final bool isMe = msg.senderId == userId;
      final bool isReceiver = !isMe;

      // ✅ RECEIVER SIDE: Mark receiver messages as recently received (ONLY if not all images received)
      if (isReceiver && (msg.groupId ?? '').isNotEmpty && msg.imageIndex != null && msg.totalImages != null) {
        final gid = msg.groupId!;
        
        // ✅ Check if 2+ images have arrived for this group
        if (_collageMap.containsKey(gid)) {
          final slotList = _collageMap[gid]!;
          final filledSlots = slotList.where((url) => url != null && url.isNotEmpty).length;
          
          // ✅ FIX: Create bundle when 2+ images arrive (not just when all arrive)
          if (filledSlots >= 2 && msg.totalImages! >= 2) {
            final isAllImages = filledSlots == msg.totalImages;
            // 2+ images received - clear recent markers for entire group to show bundle
            final allGroupMsgs = _messageBox.values
                .where((m) => m.groupId == gid && m.chatId == msg.chatId)
                .toList();
            allGroupMsgs.addAll(_pendingTempMessages.values
                .where((m) => m.groupId == gid && m.chatId == msg.chatId));
            
            for (final m in allGroupMsgs) {
              final msgIdStr2 = m.messageId.toString();
              _recentlyReceivedMessages.remove(msgIdStr2);
              _recentMessageTimers[msgIdStr2]?.cancel();
              _recentMessageTimers.remove(msgIdStr2);
            }
            print("🧹 [SAVE] Cleared recent markers for group $gid (${isAllImages ? 'all' : '$filledSlots'} $filledSlots images received) - bundle will show");
            
            // ✅ CRITICAL: Trigger immediate bundle creation
            _forceBundleRebuild.add(gid);
            _renderedGroups.remove(gid);
            _builtGroups.remove(gid);
            _slotsSyncedForGroup.remove(gid);
            
            // ✅ Clear collage cache to force fresh rebuild
            final String groupAnchorKey = 'group_${gid}_anchor';
            _renderedAnchorMessages.remove(groupAnchorKey);
            final allGroupMsgsForCache = _messageBox.values
                .where((m) => m.groupId == gid && m.chatId == msg.chatId)
                .toList();
            for (final m in allGroupMsgsForCache) {
              if ((m.imageIndex ?? 0) == 0) {
                final anchorKey = m.messageId.toString();
                _collageWidgetCache.remove(anchorKey);
                _cachedFilledSlotsCount.remove(anchorKey);
                _renderedAnchorMessages.remove(anchorKey);
              }
            }
            
            _cachedMessages.clear();
            
            // ✅ STEP: Last image aayi → version.value++ 🔥 → ValueListenableBuilder rebuild → Collage turant draw
            _collageVersionNotifier.value = _collageVersionNotifier.value + 1;
            print("🔥 [COLLAGE VERSION] Incremented collage version to ${_collageVersionNotifier.value} for group $gid (filledSlots=$filledSlots/${msg.totalImages})");
            
            // ✅ INSTANT UI REBUILD: Direct setState to force immediate UI update (SYNCHRONOUS)
            if (mounted) {
              setState(() {
                _needsRefresh = true;
              });
              print("🔄 [SAVE BUNDLE] Triggered direct setState for instant UI update (synchronous)");
              
              // ✅ Also trigger in next frame as backup
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _needsRefresh = true;
                  });
                  print("🔄 [SAVE BUNDLE] Triggered setState in postFrame callback (backup)");
                }
              });
            }
          } else if (filledSlots < 2) {
            // Less than 2 images - mark as recent (show individually)
        final msgIdStr = msg.messageId.toString();
        _recentlyReceivedMessages.add(msgIdStr);
        // Cancel existing timer if any
        _recentMessageTimers[msgIdStr]?.cancel();
        // Set timer to remove from recent set after 10 seconds
        _recentMessageTimers[msgIdStr] = Timer(const Duration(seconds: 10), () {
          _recentlyReceivedMessages.remove(msgIdStr);
          _recentMessageTimers.remove(msgIdStr);
          print("⏰ [RECENT] Removed receiver message $msgIdStr from recently received set");
        });
            print("✅ [RECENT] Marked receiver message $msgIdStr as recently received (groupId=$gid, imageIndex=${msg.imageIndex}, waiting for more: $filledSlots/${msg.totalImages})");
          }
        } else {
          // Group not initialized yet - mark as recent
          final msgIdStr = msg.messageId.toString();
          _recentlyReceivedMessages.add(msgIdStr);
          _recentMessageTimers[msgIdStr]?.cancel();
          _recentMessageTimers[msgIdStr] = Timer(const Duration(seconds: 10), () {
            _recentlyReceivedMessages.remove(msgIdStr);
            _recentMessageTimers.remove(msgIdStr);
          });
          print("✅ [RECENT] Marked receiver message $msgIdStr as recently received (group not initialized yet)");
        }
      }

      if (isMe && (msg.groupId ?? '').isNotEmpty) {
        final msgIdStr = msg.messageId.toString();
        _recentlyReceivedMessages.add(msgIdStr); // Use same set for both sender and receiver
        // Cancel existing timer if any
        _recentMessageTimers[msgIdStr]?.cancel();
        // Set timer to remove from recent set after 10 seconds
        _recentMessageTimers[msgIdStr] = Timer(const Duration(seconds: 10), () {
          _recentlyReceivedMessages.remove(msgIdStr);
          _recentMessageTimers.remove(msgIdStr);
          print("⏰ [RECENT] Removed sender message $msgIdStr from recently sent set");
        });
        print("✅ [RECENT] Marked sender message $msgIdStr as recently sent (will show individually)");
      }

      if (messageType == 'media' && mounted && !_fullyLoadedMessages.contains(msg.messageId)) {
        _startProgressiveLoading(msg);
      }

      // ✅ FIX: On receiver side, if message has groupId, immediately check if grouping is needed
      if (groupId != null && groupId.isNotEmpty && isReceiver) {
        print("🔄 [RECEIVER INCOMING] New image arrived for group $groupId, imageIndex=$imageIndex, totalImages=$totalImages, messageId=$idToProcess");

        // ✅ RECEIVER SIDE: Ensure slots are initialized and filled
        if (!_collageMap.containsKey(groupId)) {
          print("🧩 [RECEIVER INIT] Initializing slots for group $groupId on receiver side");
          _collageMap[groupId] = List.filled(totalImages ?? 1, null);
          _collageLayoutFrozen[groupId] = false;
          _collageTotalImages[groupId] = totalImages ?? 1;
        }

        // ✅ RECEIVER SIDE: Fill slot immediately
        final slotList = _collageMap[groupId]!;
        if (imageIndex != null && imageIndex >= 0 && imageIndex < slotList.length) {
          slotList[imageIndex] = mediaUrl ?? messageText;
          print("✅ [RECEIVER INIT] Filled slot $imageIndex for group $groupId on receiver side");

          // ✅ CRITICAL: Check if 2+ images have arrived, trigger immediate bundle creation
          final filledSlots = slotList.where((url) => url != null && url.isNotEmpty).length;
          final totalImagesCount = totalImages ?? slotList.length;
          
          // ✅ FIX: Create bundle immediately when 2+ images arrive (not just when all arrive)
          if (filledSlots >= 2 && totalImagesCount >= 2) {
            final isAllImages = filledSlots == totalImagesCount;
            print("✅ [RECEIVER BUNDLE] ${isAllImages ? 'All' : '$filledSlots'} $totalImagesCount images received for group $groupId - triggering immediate bundle creation");
            
            // ✅ CRITICAL FIX: Clear "recent" markers for all messages in this group to allow bundle to show
            final allGroupMsgs = _messageBox.values
                .where((m) => m.groupId == groupId && m.chatId == msg.chatId)
                .toList();
            allGroupMsgs.addAll(_pendingTempMessages.values
                .where((m) => m.groupId == groupId && m.chatId == msg.chatId));
            
            for (final m in allGroupMsgs) {
              final msgIdStr = m.messageId.toString();
              _recentlyReceivedMessages.remove(msgIdStr);
              _recentMessageTimers[msgIdStr]?.cancel();
              _recentMessageTimers.remove(msgIdStr);
            }
            print("🧹 [RECEIVER ALL IMAGES] Cleared recent markers for ${allGroupMsgs.length} messages in group $groupId");
            
            // ✅ Clear all rendering flags and cache to force fresh bundle creation
            final String groupAnchorKey = 'group_${groupId}_anchor';
            _renderedGroups.remove(groupId);
            _renderedAnchorMessages.remove(groupAnchorKey);
            _builtGroups.remove(groupId);
            _slotsSyncedForGroup.remove(groupId);
            
            // ✅ CRITICAL: Mark group for forced rebuild (even if cache exists later)
            _forceBundleRebuild.add(groupId);
            print("🔄 [FORCE REBUILD] Added group $groupId to _forceBundleRebuild set. Current set: ${_forceBundleRebuild.toList()}");
            
            for (final m in allGroupMsgs) {
              if ((m.imageIndex ?? 0) == 0) {
                final anchorKey = m.messageId.toString();
                _collageWidgetCache.remove(anchorKey);
                _cachedFilledSlotsCount.remove(anchorKey);
                _renderedAnchorMessages.remove(anchorKey);
              }
            }
            
            // Trigger immediate bundle creation
            _reinitializeSlotsForGroup(groupId, msg.chatId);
            
            // ✅ CRITICAL: Clear message list cache to force full rebuild
            _cachedMessages.clear();
            _needsRefresh = true;
            
            // ✅ CRITICAL: Force rebuild message list immediately to include new messages
            // This ensures bundle check sees all messages including temp ones
            final currentMessages = _getOptimizedMessages();
            print("🔄 [RECEIVER BUNDLE REBUILD] Forced message list rebuild - found ${currentMessages.length} messages");

            // ✅ CRITICAL: Increment collage version BEFORE setState to trigger ValueListenableBuilder
            _collageVersionNotifier.value = _collageVersionNotifier.value + 1;
            print("🔥 [COLLAGE VERSION] Incremented collage version to ${_collageVersionNotifier.value} for group $groupId (filledSlots=$filledSlots/$totalImagesCount)");

            // ✅ INSTANT UI REBUILD: Direct setState to force immediate UI update (SYNCHRONOUS)
            if (mounted) {
              // ✅ CRITICAL: Use SchedulerBinding to ensure setState happens after current frame
              SchedulerBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _needsRefresh = true;
                    _cachedMessages.clear(); // Clear cache again to force rebuild
                  });
                  print("🔄 [RECEIVER BUNDLE REBUILD] Triggered setState in postFrame callback (synchronous)");
                  
                  // ✅ Also trigger in next frame as backup
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _needsRefresh = true;
                      });
                      print("🔄 [RECEIVER BUNDLE REBUILD] Triggered setState in second postFrame callback (backup)");
                    }
                  });
                }
              });
              
              // ✅ Also trigger immediate setState for instant update
              setState(() {
                _needsRefresh = true;
                _cachedMessages.clear();
              });
              print("🔄 [RECEIVER BUNDLE REBUILD] Triggered immediate setState for instant UI update");
            }

            // ✅ CRITICAL FIX: Force Hive box update by touching ALL group messages to trigger ValueListenableBuilder
            // Update multiple messages to ensure ValueListenableBuilder rebuilds
            Future.microtask(() async {
              if (mounted) {
                for (final groupMsg in allGroupMsgs) {
                  final updatedMsg = _messageBox.get(groupMsg.messageId);
                  if (updatedMsg != null) {
                    // ✅ Force update by touching extraData field (triggers HiveObject change detection)
                    final currentExtraData = updatedMsg.extraData ?? <String, dynamic>{};
                    final uniqueKey = '_bundle_refresh_${DateTime.now().millisecondsSinceEpoch}';
                    updatedMsg.extraData = {...currentExtraData, uniqueKey: DateTime.now().millisecondsSinceEpoch};
                    await updatedMsg.save();
                  }
                }
                print("✅ [RECEIVER BUNDLE] Triggered Hive box update for ${allGroupMsgs.length} messages in group $groupId to force UI rebuild");
              }
            });
            print("✅ [RECEIVER ALL IMAGES] Bundle creation triggered immediately for group $groupId (filledSlots=$filledSlots, totalImages=$totalImagesCount)");
            return; // Early return - bundle created, no need to continue
          } else {
            // ✅ NEW: Mark this message as recently received (for individual display) ONLY if not all images received
        final msgIdStr = msg.messageId.toString();
        _recentlyReceivedMessages.add(msgIdStr);
        // Cancel existing timer if any
        _recentMessageTimers[msgIdStr]?.cancel();
        // Set timer to remove from recent set after 10 seconds
        _recentMessageTimers[msgIdStr] = Timer(const Duration(seconds: 10), () {
          _recentlyReceivedMessages.remove(msgIdStr);
          _recentMessageTimers.remove(msgIdStr);
          print("⏰ [RECENT] Removed message $msgIdStr from recently received set");
        });
            print("✅ [RECENT] Marked message $msgIdStr as recently received (will show individually until all images arrive: $filledSlots/$totalImagesCount)");

        // ✅ CRITICAL FIX: Re-initialize slots for this group (same as when navigating back)
        // This ensures ALL images show immediately in real-time, not just 2
        _reinitializeSlotsForGroup(groupId, msg.chatId);

        // ✅ CRITICAL: Also clear cache immediately to force rebuild
            final String groupAnchorKey2 = 'group_${groupId}_anchor';
        _renderedGroups.remove(groupId);
            _renderedAnchorMessages.remove(groupAnchorKey2);
        _builtGroups.remove(groupId);

        // Clear cache for all anchor messages in this group
            final allGroupMsgs2 = _messageBox.values
                .where((m) => m.groupId == groupId && m.chatId == msg.chatId)
                .toList();
            allGroupMsgs2.addAll(_pendingTempMessages.values
                .where((m) => m.groupId == groupId && m.chatId == msg.chatId));

            for (final m in allGroupMsgs2) {
              if ((m.imageIndex ?? 0) == 0) {
                final anchorKey = m.messageId.toString();
                _collageWidgetCache.remove(anchorKey);
                _cachedFilledSlotsCount.remove(anchorKey);
                _renderedAnchorMessages.remove(anchorKey);
              }
            }

            // ✅ Force UI refresh on receiver side (but don't create bundle yet)
            if (mounted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _needsRefresh = true;
                  });
                  print("🔄 [RECEIVER INIT] Triggered UI refresh for group $groupId (waiting for more images: $filledSlots/$totalImagesCount)");
                }
              });
            }
          }
        }

        // Ensure we have the group messages list in this scope before iterating
        final allGroupMsgs = _messageBox.values
            .where((m) => m.groupId == groupId && m.chatId == msg.chatId)
            .toList();
        allGroupMsgs.addAll(_pendingTempMessages.values
            .where((m) => m.groupId == groupId && m.chatId == msg.chatId));

        for (final m in allGroupMsgs) {
          if ((m.imageIndex ?? 0) == 0) {
            final anchorKey = m.messageId.toString();
            _collageWidgetCache.remove(anchorKey);
            _cachedFilledSlotsCount.remove(anchorKey); // Also clear cached count
            _renderedAnchorMessages.remove(m.messageId.toString());
          }
        }

        print("🗑️ [INCOMING] Cleared all caches for group $groupId to force rebuild");

        // ✅ CRITICAL: Clear message cache to force complete rebuild
        _cachedMessages.clear();
        _needsRefresh = true;

        // ✅ CRITICAL: Force immediate setState to rebuild collage with all images
        // Don't wait for callbacks - rebuild immediately
        if (mounted) {
          setState(() {
            _needsRefresh = true;
          });
          print("🔄 [INCOMING] Triggered immediate setState for group $groupId");
        }

        // ✅ Also trigger post-frame callback as backup to ensure rebuild
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _needsRefresh = true;
            });
            print("🔄 [INCOMING] Triggered setState (postFrame backup) for group $groupId");
          }
        });
      }

      _needsRefresh = true;

    } catch (e) {
      print("❌ Error handling incoming data: $e");
    }
  }

  String? _convertToFullUrl(String? url) {
    if (url == null || url.isEmpty) return null;

    if (url.startsWith('/uploads/')) {
      final fileName = url.split('/').last;
      return '${Config.baseNodeApiUrl}/media/file/$fileName?quality=high';
    } else if (!url.startsWith('http')) {
      return '${Config.baseNodeApiUrl}$url';
    }

    return url;
  }

  void _clearTemporaryMessages() {
    try {
      final temporaryMessages = _messageBox.values.where((msg) =>
      msg.chatId == widget.chatId &&
          msg.messageId.toString().startsWith('temp_')
      ).toList();

      for (var tempMsg in temporaryMessages) {
        _messageBox.delete(tempMsg.messageId);
      }

      if (temporaryMessages.isNotEmpty) {
        print("🧹 Cleared ${temporaryMessages.length} temporary messages for chat ${widget.chatId}");
        _needsRefresh = true;
      }
    } catch (e) {
      print("❌ Error clearing temporary messages: $e");
    }
  }

  void _startTyping() {
    if (!_isTyping) {
      setState(() => _isTyping = true);
      ChatService.startTyping(widget.chatId);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 700), _stopTyping);
  }

  void _stopTyping() {
    if (_isTyping) {
      setState(() => _isTyping = false);
      ChatService.stopTyping(widget.chatId);
    }
    _typingTimer?.cancel();
  }

  // ✅ CRITICAL FIX: Debounce setState to prevent flickering from multiple rapid updates
  // ✅ JUMPING FIX: Don't manually restore scroll - let Flutter handle it
  void _debounceSetState() {
    _updateTimer?.cancel();

    _updateTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        setState(() {
          _needsRefresh = true;
        });
      }
    });
  }

  // ✅ REPLY FUNCTIONALITY
  void _startReply(Message message) {
    setState(() {
      _replyingToMessage = message;
    });
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyingToMessage = null;
    });
  }

  // ✅ BUILD REPLY PREVIEW
  Widget _buildReplyPreview() {
    if (_replyingToMessage == null) return const SizedBox.shrink();

    final replyMsg = _replyingToMessage!;
    final isMe = replyMsg.senderId == LocalAuthService.getUserId();
    final senderName = isMe ? "You" : (replyMsg.senderName ?? "User");

    return Container(
      key: _replyPreviewKey,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Replying to $senderName",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getReplyPreviewText(replyMsg),
                  style: const TextStyle(fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: _cancelReply,
          ),
        ],
      ),
    );
  }

  String _getReplyPreviewText(Message msg) {
    if (msg.messageType == 'media' || msg.messageType == 'encrypted_media') {
      return '📷 Media';
    }
    return msg.messageContent;
  }

  void _openImageFullScreen(Message message) {
    final bool isLocalFile = message.messageId.toString().startsWith('temp_') ||
        (message.messageContent.startsWith('/') && File(message.messageContent).existsSync());

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => MediaViewerScreen(
          mediaUrl: message.messageContent,
          messageId: message.messageId,
          isLocalFile: isLocalFile,
          chatId: widget.chatId,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // ✅ Bottom to top slide transition
          const begin = Offset(0.0, 1.0); // Start from bottom
          const end = Offset.zero; // End at top
          const curve = Curves.easeInOut;

          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  Future<void> _openMultiPicker() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MultiImagePickerScreen(
          chatId: widget.chatId,
          receiverId: widget.otherUserId,
        ),
      ),
    );

    if (result == null) return;
    if (result is List<File>) {
      if (result.length == 1) {
        setState(() {
          _imageFile = result[0];
          _focusNode.unfocus();
        });
        await _sendMessage();
      } else {
        final paths = result.map((f) => f.path).toList();
        // ✅ CRITICAL: Close keyboard immediately after selecting multiple images (WhatsApp style)
        _focusNode.unfocus();

        // ✅ CRITICAL: Clear built groups when sending new media group so collage rebuilds
        // This fixes the issue where collage doesn't rebuild when sending multiple images again
        _builtGroups.clear();
        _collageWidgetCache.clear();
        _cachedFilledSlotsCount.clear();
        print("🧹 Cleared built groups and cache before sending new media group");

        await ChatService.sendMediaGroup(
          chatId: widget.chatId,
          receiverId: widget.otherUserId,
          mediaPaths: paths,
          senderName: _authBox.get('userName'),
          receiverName: _resolvedTitle.isNotEmpty ? _resolvedTitle : widget.otherUserName,
          senderPhoneNumber: _authBox.get('userPhone'),
          receiverPhoneNumber: _otherUserPhone ?? _authBox.get('otherUserPhone'),
          replyToMessageId: _replyingToMessage?.messageId,
        );
        setState(() {
          _replyingToMessage = null;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1080,
        maxHeight: 1920,
      );

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
          _focusNode.unfocus();
        });

        _sendMessage();
      }
    } catch (e) {
      print("Error picking image: $e");
    }
  }

  // ✅ FIX: Add camera picker function
  Future<void> _pickImageFromCamera() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 75,
        maxWidth: 1080,
        maxHeight: 1920,
      );

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
          _focusNode.unfocus();
        });

        _sendMessage();
      }
    } catch (e) {
      print("Error picking image from camera: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to capture image')),
      );
    }
  }

  Future<void> _sendMessage() async {
    if (_isSending) {
      return;
    }

    String text = _controller.text.trim();
    if (text.isEmpty && _imageFile == null) return;

    _stopTyping();

    // ✅ FIX: Prevent chat fluctuation when sending text
    final textBeforeSend = text;

    setState(() {
      _isSending = true;
      _shouldScrollToBottom = true;
    });

    // ✅ FIX: Clear text immediately to prevent UI fluctuation
    if (_imageFile == null) {
      _controller.clear();
    }

    try {
      if (_imageFile != null) {
        _jumpToBottom();

        await ChatService.sendMediaMessage(
          chatId: widget.chatId,
          receiverId: widget.otherUserId,
          mediaPath: _imageFile!.path,
          senderName: _authBox.get('userName'),
          receiverName: _resolvedTitle.isNotEmpty ? _resolvedTitle : widget.otherUserName,
          senderPhoneNumber: _authBox.get('userPhone'),
          receiverPhoneNumber: _otherUserPhone ?? _authBox.get('otherUserPhone'),
          replyToMessageId: _replyingToMessage?.messageId,
        );

        // ✅ CRITICAL: Close keyboard immediately after sending image (WhatsApp style)
        _focusNode.unfocus();

        setState(() {
          _imageFile = null;
          _replyingToMessage = null;
        });
      } else {
        await ChatService.sendMessage(
          chatId: widget.chatId,
          receiverId: widget.otherUserId,
          messageContent: textBeforeSend, // ✅ FIX: Use saved text
          messageType: 'text',
          senderName: _authBox.get('userName'),
          receiverName: _resolvedTitle.isNotEmpty ? _resolvedTitle : widget.otherUserName,
          senderPhoneNumber: _authBox.get('userPhone'),
          receiverPhoneNumber: _otherUserPhone ?? _authBox.get('otherUserPhone'),
          replyToMessageId: _replyingToMessage?.messageId,
        );

        // ✅ FIX: Controller already cleared above to prevent fluctuation
        setState(() {
          _replyingToMessage = null;
        });
      }

      _resolveHeader();
      _needsRefresh = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpToBottom();
      });

    } catch (e) {
      print("Error sending message: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  // ✅ UPDATED MESSAGE BUBBLE WITH SWIPE TO REPLY & SELECTION - SAME SIZE MAINTAINED
  Widget _buildMessageBubble(Message msg, {Key? key}) {
    // ✅ DEBUG: Log when building message bubble
    final hasGroupId = (msg.groupId ?? '').isNotEmpty;
    if (hasGroupId) {
      print('🔍 [BUILD BUBBLE] Building bubble for message ${msg.messageId}, groupId=${msg.groupId}, imageIndex=${msg.imageIndex}');
    }
    final String msgId = msg.messageId.toString();
    final bool isSelected = selectedMessageIds.contains(msgId);
    final userId = LocalAuthService.getUserId();
    final bool isMe = msg.senderId == userId;

    // ✅ FIX: Hide non-anchor messages in grouped media (prevent dots and duplication)
    // ✅ CRITICAL: This check happens BEFORE any rendering, so non-anchor messages never appear
    if (hasGroupId) {
      final String gid = msg.groupId!;
      // Get all messages with this groupId
      final List<Message> allGroupMessages = [];
      allGroupMessages.addAll(_messageBox.values.where((m) => m.groupId == gid && m.chatId == widget.chatId));
      allGroupMessages.addAll(_pendingTempMessages.values.where((m) => m.groupId == gid && m.chatId == widget.chatId));

      if (allGroupMessages.length >= 2) {
        // ✅ FIX: Only group if we have 2+ messages (collage)
        // Find minimum imageIndex (anchor)
        final int anchorIndex = allGroupMessages
            .where((m) => m.imageIndex != null && m.imageIndex! >= 0)
            .map((m) => m.imageIndex!)
            .fold(9999, (a, b) => a < b ? a : b);
        final int actualAnchorIndex = anchorIndex == 9999 ? 0 : anchorIndex;

        // ✅ FIX: On receiver side, show ALL images (no filtering) UNLESS all images received
        // ✅ RECEIVER SIDE FIX: When all images received, only show anchor (collage), hide rest
        if (!isMe) {
          // Check if all images are received by checking fixed slots
          final bool allImagesReceived = false;
          if (_collageMap.containsKey(gid)) {
            final slotList = _collageMap[gid]!;
            final totalImages = _collageTotalImages[gid] ?? slotList.length;
            final filledSlots = slotList.where((url) => url != null && url.isNotEmpty).length;
            final bool allReceived = filledSlots == totalImages && totalImages >= 2;

            if (allReceived) {
              // All images received - only show anchor message (collage), hide rest
              if ((msg.imageIndex ?? 0) != actualAnchorIndex) {
                print('🚫 [RECEIVER COLLAGE] Hiding non-anchor message ${msg.messageId} - all images received, showing collage only');
                return const SizedBox.shrink();
              }
              print('✅ [RECEIVER COLLAGE] Showing anchor message ${msg.messageId} - all images received ($filledSlots/$totalImages), will show collage');
            } else {
              // Still receiving - show all messages individually
              print('✅ [BUBBLE] Receiver: Showing message ${msg.messageId} for group $gid (imageIndex=${msg.imageIndex}) - still receiving');
            }
          } else {
            // No fixed slots yet - show all messages
            print('✅ [BUBBLE] Receiver: Showing message ${msg.messageId} for group $gid (imageIndex=${msg.imageIndex}) - no slots yet');
          }

          print('📱 [RECEIVER BUBBLE] Receiver side check - group $gid, messageId=${msg.messageId}, imageIndex=${msg.imageIndex}, anchorIndex=$actualAnchorIndex');
          print('📱 [RECEIVER BUBBLE] All group messages: ${allGroupMessages.map((m) => '${m.messageId}(idx=${m.imageIndex})').join(', ')}');
          // Continue to normal rendering
        } else {
          // Sender side: check if should show individually
          final bool shouldShowIndividually = _shouldShowIndividually(msg);
          final isTemp = msg.messageId.toString().startsWith('temp_');

          // ✅ CRITICAL: Always show temp messages individually for instant display
          if (isTemp) {
            print('✅ [BUBBLE] Temp message ${msg.messageId} - showing individually (sender side)');
            // Continue to normal rendering - show individually
          } else if (!shouldShowIndividually) {
            // Grouping mode: hide non-anchor messages
            if ((msg.imageIndex ?? 0) != actualAnchorIndex) {
              print('🚫 CRITICAL: Hiding non-anchor message on sender (grouped): msgId=${msg.messageId}, idx=${msg.imageIndex}, anchor=$actualAnchorIndex, group=$gid');
              return const SizedBox.shrink(); // Completely hide - no widget, no selection, nothing
            }
          }
          // If shouldShowIndividually is true, show all messages (while sending)
        }

        // ✅ If this is anchor message with 2+ images, show collage
        if ((msg.imageIndex ?? 0) == actualAnchorIndex) {
          // ✅ CRITICAL: Check group-level anchor key to prevent duplicates
          final String groupAnchorKey = 'group_${gid}_anchor';

          // ✅ RECEIVER SIDE LOG: Log anchor check
          print('📱 [RECEIVER BUBBLE] Anchor check - messageId=${msg.messageId}, imageIndex=${msg.imageIndex}, actualAnchorIndex=$actualAnchorIndex, isMe=$isMe, isReceiver=${!isMe}');
          print('📱 [RECEIVER BUBBLE] groupAnchorKey=$groupAnchorKey');

          // ✅ Check cache first - if cached, allow render
          final String anchorKey = msg.messageId.toString();
          print('📱 [RECEIVER BUBBLE] anchorKey=$anchorKey, checking cache...');
          print('📱 [RECEIVER BUBBLE] Cache contains anchorKey? ${_collageWidgetCache.containsKey(anchorKey)}');
          print('📱 [RECEIVER BUBBLE] Rendered groups: $_renderedGroups');
          print('📱 [RECEIVER BUBBLE] Rendered anchors: ${_renderedAnchorMessages.toList()}');

          if (_collageWidgetCache.containsKey(anchorKey)) {
            print('✅ [BUBBLE CHECK] Group $gid anchor ${msg.messageId} has cached collage - allowing render');
            print('📱 [RECEIVER BUBBLE] Cache found - allowing render');
            // Continue to render
          } else if (_renderedGroups.contains(gid) || _renderedAnchorMessages.contains(groupAnchorKey)) {
            // ✅ If already rendered but no cache, it might be from initialization - allow rebuild
            print('⚠️ [BUBBLE CHECK] Group $gid anchor ${msg.messageId} marked but no cache - allowing rebuild');
            print('📱 [RECEIVER BUBBLE] Already rendered but no cache - allowing rebuild');
            // Continue to render - will be handled in _buildMediaMessage
          } else {
            // ✅ Not rendered yet - mark it
            _renderedGroups.add(gid);
            _renderedAnchorMessages.add(groupAnchorKey);
            print('✅ [ALLOWING RENDER] Group $gid, anchor ${msg.messageId}, count=${allGroupMessages.length} (bubble check)');
            print('📱 [RECEIVER BUBBLE] Not rendered yet - marking group $gid and anchor $groupAnchorKey');
            print('📱 [RECEIVER BUBBLE] After marking - renderedGroups: $_renderedGroups');
            print('📱 [RECEIVER BUBBLE] After marking - renderedAnchors: ${_renderedAnchorMessages.toList()}');
          }
        } else {
          print('📱 [RECEIVER BUBBLE] NOT anchor - messageId=${msg.messageId}, imageIndex=${msg.imageIndex}, actualAnchorIndex=$actualAnchorIndex');
        }
      } else if (allGroupMessages.length == 1) {
        // ✅ Show single image if only 1 image in group (not enough for collage)
        print('🧩 Showing single image ${msg.messageId} (only 1 image in group, waiting for more)');
        // Continue to normal rendering below
      }
    }

    // ✅ FIX: Also check fallback cluster for messages without groupId
    final bool isMediaMessage = msg.messageType == 'media' ||
        msg.messageType == 'encrypted_media' ||
        (msg.lowQualityUrl != null && msg.lowQualityUrl!.isNotEmpty) ||
        (msg.highQualityUrl != null && msg.highQualityUrl!.isNotEmpty);
    
    // ✅ DEBUG: Log media message check
    //final hasGroupId = (msg.groupId ?? '').isNotEmpty;
    if (hasGroupId) {
      print('🔍 [BUILD BUBBLE] Message ${msg.messageId}: hasGroupId=$hasGroupId, isMediaMessage=$isMediaMessage, messageType=${msg.messageType}');
    }

    if (isMediaMessage && !hasGroupId) {
      //final cluster = _getContiguousMediaCluster(msg);
      // if (cluster.length >= 2) {
      //   cluster.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      //   final Message anchor = cluster.first;
      //   if (msg.messageId != anchor.messageId) {
      //     // ✅ FIX: Hide non-anchor messages from fallback cluster
      //     print('🚫 CRITICAL: Hiding non-anchor message from fallback cluster: msgId=${msg.messageId}, anchor=${anchor.messageId}');
      //     return const SizedBox.shrink(); // Completely hide
      //   }
      // }
    }

    // ✅ CRITICAL: Show temp media messages instantly with loading indicator (WhatsApp style)
    final isTemp = msg.messageId.toString().startsWith('temp_');
    if (isTemp) {
      if (msg.messageType == 'media' || msg.messageType == 'encrypted_media') {
        // ✅ FIX: If message has groupId, it's part of a group - never show bubble
        // ✅ Show individually without bubble while sending, or as collage after all sent
        // final bool isTempCollage = _isCollageMessage(msg);

        if (hasGroupId) {
          // ✅ Render grouped images without bubble (individual or collage)
          return GestureDetector(
            onHorizontalDragStart: (details) => _handleSwipeStart(details, msg),
            onHorizontalDragUpdate: _handleSwipeUpdate,
            onHorizontalDragEnd: _handleSwipeEnd,
            behavior: HitTestBehavior.opaque,
            child: Transform.translate(
              offset: Offset(_swipeMessage?.messageId == msg.messageId ? _swipeOffset : 0.0, 0),
              child: RepaintBoundary(
                key: key,
                child: Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _buildMediaMessage(msg, msg.messageContent, Colors.black),
                        ),
                        // ✅ SELECTION CHECKBOX for grouped images
                        if (_selectionMode && isSelected)
                          Positioned(
                            top: 8,
                            left: isMe ? null : 4,
                            right: isMe ? 4 : null,
                            child: GestureDetector(
                              onTap: () => _toggleSelection(msgId),
                              child: Container(
                                width: 20,
                                height: 20,

                                decoration: BoxDecoration(
                                  color: isSelected ? Colors.green : Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? Colors.green : Colors.grey,
                                    width: 2,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        } else {
          // ✅ Show temp single media messages (not part of group) with bubble
          return _buildMediaMessageBubble(msg, isMe: isMe, isSelected: isSelected);
        }
      }
      // Hide all temp text messages completely
      return const SizedBox.shrink();
    }

    // final bool isMediaMessage = msg.messageType == 'media' ||
    //     msg.messageType == 'encrypted_media' ||
    //     (msg.lowQualityUrl != null && msg.lowQualityUrl!.isNotEmpty) ||
    //     (msg.highQualityUrl != null && msg.highQualityUrl!.isNotEmpty);

    if ((isMe && msg.isDeletedSender == 1) || (!isMe && msg.isDeletedReceiver == 1)) {
      return const SizedBox.shrink();
    }

    // ✅ FIX: If message has groupId, it's part of a group - never show bubble
    // ✅ Show individually without bubble or as collage
    //final bool isCollage = isMediaMessage && _isCollageMessage(msg);

    // ✅ FIX: Grouped images should never show bubbles - only show as collage or individually without bubble
    if (hasGroupId && isMediaMessage) {
      print('🔍 [BUILD BUBBLE PATH] Message ${msg.messageId} has groupId and isMediaMessage - entering bundle path');
      // ✅ Check if should show individually (while sending) or as collage (after all sent)
      final bool shouldShowIndividually = _shouldShowIndividually(msg);
      print('🔍 [BUILD BUBBLE PATH] shouldShowIndividually=$shouldShowIndividually for message ${msg.messageId}');

      if (shouldShowIndividually) {
        // ✅ Show individually without bubble while sending
        return GestureDetector(
          onHorizontalDragStart: (details) => _handleSwipeStart(details, msg),
          onHorizontalDragUpdate: _handleSwipeUpdate,
          onHorizontalDragEnd: _handleSwipeEnd,
          behavior: HitTestBehavior.opaque,
          child: Transform.translate(
            offset: Offset(_swipeMessage?.messageId == msg.messageId ? _swipeOffset : 0.0, 0),
            child: RepaintBoundary(
              key: key,
              child: Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  child: ValueListenableBuilder<int>(
                    valueListenable: _collageVersionNotifier,
                    builder: (context, version, child) {
                      // ✅ Recalculate filled slots on every rebuild (real-time updates)
                      final String gid2 = msg.groupId ?? '';
                      int filledSlots2 = 0;
                      int totalImages2 = msg.totalImages ?? 1;
                      if (gid2.isNotEmpty && _collageMap.containsKey(gid2)) {
                        final slotList = _collageMap[gid2]!;
                        filledSlots2 = slotList.where((url) => url != null && url.isNotEmpty).length;
                        totalImages2 = _collageTotalImages[gid2] ?? msg.totalImages ?? 1;
                      } else if (msg.totalImages != null && msg.totalImages! > 1) {
                        totalImages2 = msg.totalImages!;
                        filledSlots2 = 1; // At least this one image
                      }
                      
                      final bool showCountingBadge2 = totalImages2 > 1 && filledSlots2 < totalImages2;
                      
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _buildMediaMessage(msg, msg.messageContent, Colors.black),
                          ),
                          // ✅ COUNTING BADGE: Show "1/3", "2/3" etc. when multiple images expected (updates in real-time)
                          if (showCountingBadge2)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$filledSlots2/$totalImages2',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          // ✅ SELECTION CHECKBOX for grouped images
                          if (_selectionMode && isSelected)
                            Positioned(
                              top: 8,
                              left: isMe ? null : 4,
                              right: isMe ? (showCountingBadge2 ? 50 : 4) : null, // Adjust position if badge is shown
                              child: GestureDetector(
                                onTap: () => _toggleSelection(msgId),
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.green : Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? Colors.green : Colors.grey,
                                      width: 2,
                                    ),
                                  ),
                                  child: isSelected
                                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                                      : null,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      }
      // ✅ Otherwise show as collage (after all sent) - no bubble
      // ✅ For grouped images, always show without bubble (either individually or as collage)
      print('🔍 [BUILD BUBBLE PATH] Showing as bundle (shouldShowIndividually=false) for message ${msg.messageId}');
      final bundleWidget = GestureDetector(
        onHorizontalDragStart: (details) => _handleSwipeStart(details, msg),
        onHorizontalDragUpdate: _handleSwipeUpdate,
        onHorizontalDragEnd: _handleSwipeEnd,
        behavior: HitTestBehavior.opaque,
        child: Transform.translate(
          offset: Offset(_swipeMessage?.messageId == msg.messageId ? _swipeOffset : 0.0, 0),
          child: RepaintBoundary(
            key: key,
            child: Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.70,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildMediaMessage(msg, msg.messageContent, Colors.black),
                ),
              ),
            ),
          ),
        ),
      );
      print('✅ [BUILD BUBBLE PATH] Returning bundle widget for message ${msg.messageId}');
      return bundleWidget;
    } else {
      print('🔍 [BUILD BUBBLE PATH] Message ${msg.messageId} - hasGroupId=$hasGroupId, isMediaMessage=$isMediaMessage - NOT entering bundle path');
    }

    // if (isCollage) {
    //   // ✅ FIX: Get group messages to check count
    //   final String gid = msg.groupId ?? '';
    //   final List<Message> groupMessages = [];
    //   groupMessages.addAll(_messageBox.values.where((m) => m.groupId == gid && m.chatId == widget.chatId));
    //   groupMessages.addAll(_pendingTempMessages.values.where((m) => m.groupId == gid && m.chatId == widget.chatId));
    //
    //   // ✅ FIX: Remove duplicates
    //   final uniqueGroupMessages = <String, Message>{};
    //   for (final m in groupMessages) {
    //     if (!uniqueGroupMessages.containsKey(m.messageId)) {
    //       uniqueGroupMessages[m.messageId] = m;
    //     }
    //   }
    //   final finalGroupMessages = uniqueGroupMessages.values.toList();
    //
    //   // ✅ FIX: Render collage without bubble - use ClipRRect with borderRadius
    //   return GestureDetector(
    //     onHorizontalDragStart: (details) => _handleSwipeStart(details, msg),
    //     onHorizontalDragUpdate: _handleSwipeUpdate,
    //     onHorizontalDragEnd: _handleSwipeEnd,
    //     behavior: HitTestBehavior.opaque,
    //     child: Transform.translate(
    //       offset: Offset(_swipeMessage?.messageId == msg.messageId ? _swipeOffset : 0.0, 0),
    //       child: RepaintBoundary(
    //         key: key,
    //         child: Align(
    //           alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
    //           child: Container(
    //             margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
    //             constraints: BoxConstraints(
    //               maxWidth: MediaQuery.of(context).size.width * 0.70,
    //             ),
    //             child: Stack(
    //               children: [
    //                 ClipRRect(
    //                   borderRadius: BorderRadius.circular(12),
    //                   child: _buildMediaMessage(msg, msg.messageContent, Colors.black),
    //                 ),
    //                 // ✅ SELECTION CHECKBOX for collage
    //                 if (_selectionMode && isSelected)
    //                   Positioned(
    //                     top: 8,
    //                     left: isMe ? null : 4,
    //                     right: isMe ? 4 : null,
    //                     child: GestureDetector(
    //                       onTap: () => _toggleSelection(msgId),
    //                       child: Container(
    //                         width: 20,
    //                         height: 20,
    //                         decoration: BoxDecoration(
    //                           color: isSelected ? Colors.green : Colors.white,
    //                           shape: BoxShape.circle,
    //                           border: Border.all(
    //                             color: isSelected ? Colors.green : Colors.grey,
    //                             width: 2,
    //                           ),
    //                         ),
    //                         child: isSelected
    //                             ? const Icon(Icons.check, size: 14, color: Colors.white)
    //                             : null,
    //                       ),
    //                     ),
    //                   ),
    //               ],
    //             ),
    //           ),
    //         ),
    //       ),
    //     ),
    //   );
    // }

    final color = isMe ? const Color(0xFFDCF8C6) : Colors.white;
    final textColor = Colors.black;

    final bool contentDeleted = !isMe && msg.isDeletedSender == 1;
    final String content = contentDeleted ? '❌ This message was deleted' : msg.messageContent;

    final borderRadius = BorderRadius.only(
      topLeft: isMe ? const Radius.circular(16) : const Radius.circular(2),
      topRight: isMe ? const Radius.circular(2) : const Radius.circular(16),
      bottomLeft: const Radius.circular(16),
      bottomRight: const Radius.circular(16),
    );

    // ✅ SWIPE TO REPLY GESTURE DETECTOR
    return GestureDetector(
      onHorizontalDragStart: (details) => _handleSwipeStart(details, msg),
      onHorizontalDragUpdate: _handleSwipeUpdate,
      onHorizontalDragEnd: _handleSwipeEnd,
      behavior: HitTestBehavior.opaque,
      child: Transform.translate(
        offset: Offset(_swipeMessage?.messageId == msg.messageId ? _swipeOffset : 0.0, 0),
        child: RepaintBoundary(
          key: key,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_selectionMode) {
                _toggleSelection(msgId);
              } else if (_focusNode.hasFocus) {
                _focusNode.unfocus();
              } else if (isMediaMessage) {
                _openImageFullScreen(msg);
              }
            },
            onLongPress: () {
              if (_selectionMode) {
                _toggleSelection(msgId);
              } else {
                _enterSelectionMode(msgId);
              }
            },
            child: Container(
              decoration: BoxDecoration(
                border: isSelected ? Border.all(color: Colors.green, width: 2) : null,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      padding: (msg.messageType == 'text' && !isMediaMessage) || contentDeleted
                          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
                          : const EdgeInsets.all(6),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: borderRadius,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            spreadRadius: 1,
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ✅ REPLY PREVIEW IN MESSAGE
                          if (msg.replyToMessageId != null && msg.replyToMessageId!.isNotEmpty)
                            _buildReplyInMessage(msg),

                          if (contentDeleted)
                            Text(
                                content,
                                style: TextStyle(color: Colors.red[800], fontSize: 14, fontStyle: FontStyle.italic)
                            )

                          else if (msg.messageType == 'text' && !isMediaMessage)
                            Text(content, style: TextStyle(color: textColor, fontSize: 16))

                          else if (isMediaMessage)
                              _buildMediaMessage(msg, msg.messageContent, textColor)

                            else
                              Text(
                                content.isNotEmpty ? content : "📎 Attachment",
                                style: TextStyle(color: textColor, fontSize: 16),
                              ),

                          if (msg.messageType == 'text' && !contentDeleted && !isMediaMessage) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatTime(msg.timestamp),
                                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                                ),
                                if (isMe) const SizedBox(width: 4),
                                if (isMe)
                                  _buildMessageTicks(msg),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // ✅ SELECTION CHECKBOX (visible only when message selected)
                  if (_selectionMode && isSelected)
                    Positioned(
                      top: 8,
                      left: isMe ? null : 4,
                      right: isMe ? 4 : null,
                      child: GestureDetector(
                        onTap: () => _toggleSelection(msgId),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.green : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.green : Colors.grey,
                              width: 2,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, size: 14, color: Colors.white)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ✅ BUILD REPLY IN MESSAGE
  Widget _buildReplyInMessage(Message msg) {
    final repliedMessage = _messageBox.values.firstWhereOrNull(
          (m) => m.messageId == msg.replyToMessageId,
    );

    if (repliedMessage == null) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: const Text(
          "Original message not found",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      );
    }

    final isMeReply = repliedMessage.senderId == LocalAuthService.getUserId();
    final senderName = isMeReply ? "You" : (repliedMessage.senderName ?? "User");

    return GestureDetector(
      onTap: () {
        // Scroll to the original message
        _scrollToOriginalMessage(repliedMessage);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              senderName,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _getReplyPreviewText(repliedMessage),
              style: const TextStyle(fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToOriginalMessage(Message originalMsg) {
    final messages = _getOptimizedMessages();
    final index = messages.indexWhere((msg) => msg.messageId == originalMsg.messageId);

    if (index != -1) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent * (index / messages.length),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  // ✅ UPDATED: SHOW MESSAGE OPTIONS WITH COPY
  void _showMessageOptions(Message msg) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ✅ INFO OPTION FOR MEDIA MESSAGES (WhatsApp style) - ADDED
            if (msg.messageType == 'media' || msg.messageType == 'encrypted_media')
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Info'),
                onTap: () {
                  Navigator.pop(context); // Close bottom sheet
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MessageInfoScreen(
                        message: msg,
                        otherUserName: widget.otherUserName,
                      ),
                    ),
                  );
                },
              ),
            // ✅ COPY OPTION - ADDED
            if (msg.messageType == 'text')
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.pop(context);
                  _copySingleMessage(msg.messageId);
                },
              ),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                _startReply(msg);
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward),
              title: const Text('Forward'),
              onTap: () {
                Navigator.pop(context);
                _forwardSingleMessage(msg.messageId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirmation(msg.messageId);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ✅ MEDIA MESSAGE BUBBLE WITH PERSISTENT LOADING - SAME SIZE MAINTAINED
  Widget _buildMediaMessageBubble(Message msg, {required bool isMe, required bool isSelected}) {
    // ✅ FIX: If message has groupId, it's part of a group - NEVER show bubble
    // ✅ Show without bubble (individually or as collage)
    final bool hasGroupId = (msg.groupId ?? '').isNotEmpty;
    //final bool isCollage = _isCollageMessage(msg);

    // ✅ RECEIVER SIDE LOG: Log bubble building check
    //print('📱 [RECEIVER BUBBLE] Building bubble - messageId=${msg.messageId}, hasGroupId=$hasGroupId, isCollage=$isCollage, isMe=$isMe, isReceiver=${!isMe}');
    print('📱 [RECEIVER BUBBLE] groupId=${msg.groupId}, imageIndex=${msg.imageIndex}');

    // ✅ FIX: On receiver side, if it's not a collage message, show individually (skip collage path)
    // if (!isMe && hasGroupId && !isCollage) {
    //   // Receiver side non-anchor message: show individually with bubble
    //   print('📱 [RECEIVER BUBBLE] Receiver side - showing individually with bubble (hasGroupId=true, isCollage=false)');
    //   final color = Colors.white;
    //   return GestureDetector(
    //     onHorizontalDragStart: (details) => _handleSwipeStart(details, msg),
    //     onHorizontalDragUpdate: _handleSwipeUpdate,
    //     onHorizontalDragEnd: _handleSwipeEnd,
    //     behavior: HitTestBehavior.opaque,
    //     child: Transform.translate(
    //       offset: Offset(_swipeMessage?.messageId == msg.messageId ? _swipeOffset : 0.0, 0),
    //       child: Align(
    //         alignment: Alignment.centerLeft,
    //         child: Container(
    //           margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
    //           constraints: BoxConstraints(
    //             maxWidth: MediaQuery.of(context).size.width * 0.70,
    //           ),
    //           padding: const EdgeInsets.all(8),
    //           decoration: BoxDecoration(
    //             color: color,
    //             borderRadius: BorderRadius.circular(12),
    //             border: Border.all(color: Colors.grey.withOpacity(0.3), width: 1),
    //           ),
    //           child: _buildMediaMessage(msg, msg.messageContent, Colors.black),
    //         ),
    //       ),
    //     ),
    //   );
    // }

    // if (hasGroupId || isCollage) {
    //   // ✅ Render grouped images without bubble (always, for both sender and receiver)
    //   final String gid = msg.groupId ?? '';
    //   print('📱 [RECEIVER BUBBLE] Grouped path - gid=$gid, isMe=$isMe, isReceiver=${!isMe}, isCollage=$isCollage');
    //
    //   final List<Message> groupMessages = [];
    //   groupMessages.addAll(_messageBox.values.where((m) => m.groupId == gid && m.chatId == widget.chatId));
    //   groupMessages.addAll(_pendingTempMessages.values.where((m) => m.groupId == gid && m.chatId == widget.chatId));
    //
    //   final uniqueGroupMessages = <String, Message>{};
    //   for (final m in groupMessages) {
    //     if (!uniqueGroupMessages.containsKey(m.messageId)) {
    //       uniqueGroupMessages[m.messageId] = m;
    //     }
    //   }
    //   final finalGroupMessages = uniqueGroupMessages.values.toList();
    //
    //   print('📱 [RECEIVER BUBBLE] Group messages count: ${finalGroupMessages.length}, current messageId=${msg.messageId}');
    //   print('📱 [RECEIVER BUBBLE] Group messageIds: ${finalGroupMessages.map((m) => '${m.messageId}(idx=${m.imageIndex})').join(', ')}');
    //
    //   return GestureDetector(
    //     onHorizontalDragStart: (details) => _handleSwipeStart(details, msg),
    //     onHorizontalDragUpdate: _handleSwipeUpdate,
    //     onHorizontalDragEnd: _handleSwipeEnd,
    //     behavior: HitTestBehavior.opaque,
    //     child: Transform.translate(
    //       offset: Offset(_swipeMessage?.messageId == msg.messageId ? _swipeOffset : 0.0, 0),
    //       child: Align(
    //         alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
    //         child: Container(
    //           margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
    //           constraints: BoxConstraints(
    //             maxWidth: MediaQuery.of(context).size.width * 0.70,
    //           ),
    //           child: ClipRRect(
    //             borderRadius: BorderRadius.circular(12),
    //             child: _buildMediaMessage(msg, msg.messageContent, Colors.black),
    //           ),
    //         ),
    //       ),
    //     ),
    //   );
    // }

    final color = isMe ? const Color(0xFFDCF8C6) : Colors.white;

    return GestureDetector(
      onHorizontalDragStart: (details) => _handleSwipeStart(details, msg),
      onHorizontalDragUpdate: _handleSwipeUpdate,
      onHorizontalDragEnd: _handleSwipeEnd,
      behavior: HitTestBehavior.opaque,
      child: Transform.translate(
        offset: Offset(_swipeMessage?.messageId == msg.messageId ? _swipeOffset : 0.0, 0),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_selectionMode) {
              _toggleSelection(msg.messageId);
            } else if (_focusNode.hasFocus) {
              _focusNode.unfocus();
            } else {
              _openImageFullScreen(msg);
            }
          },
          onLongPress: () {
            if (_selectionMode) {
              _toggleSelection(msg.messageId);
            } else {
              // ✅ FIX: For media messages, show options (including Info) - WhatsApp style
              if (msg.messageType == 'media' || msg.messageType == 'encrypted_media') {
                _showMessageOptions(msg);
              } else {
                _enterSelectionMode(msg.messageId);
              }
            }
          },
          child: Container(
            decoration: BoxDecoration(
              border: isSelected ? Border.all(color: Colors.green, width: 2) : null,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    // ✅ FIX: Reduce padding for grouped images (cleaner WhatsApp style)
                    padding: (msg.groupId != null && msg.groupId!.isNotEmpty)
                        ? const EdgeInsets.all(2)  // Minimal padding for grouped images
                        : const EdgeInsets.all(6),  // Normal padding for single images
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.70, // ✅ FIX: Adjusted width
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.only(
                        topLeft: isMe ? const Radius.circular(16) : const Radius.circular(2),
                        topRight: isMe ? const Radius.circular(2) : const Radius.circular(16),
                        bottomLeft: const Radius.circular(16),
                        bottomRight: const Radius.circular(16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ✅ REPLY PREVIEW IN MEDIA MESSAGE
                        if (msg.replyToMessageId != null && msg.replyToMessageId!.isNotEmpty)
                          _buildReplyInMessage(msg),

                        Stack(
                          children: [
                            _buildMediaMessage(msg, msg.messageContent, Colors.black),
                            // ✅ COUNTING BADGE: Show "1/3", "2/3" etc. when multiple images expected
                            if (msg.groupId != null && msg.groupId!.isNotEmpty && msg.totalImages != null && msg.totalImages! > 1)
                              Builder(
                                builder: (context) {
                                  final String gid = msg.groupId!;
                                  int filledSlots = 0;
                                  int totalImages = msg.totalImages!;
                                  if (_collageMap.containsKey(gid)) {
                                    final slotList = _collageMap[gid]!;
                                    filledSlots = slotList.where((url) => url != null && url.isNotEmpty).length;
                                    totalImages = _collageTotalImages[gid] ?? msg.totalImages ?? 1;
                                  } else {
                                    filledSlots = 1; // At least this one image
                                  }
                                  
                                  final bool showCountingBadge = totalImages > 1 && filledSlots < totalImages;
                                  
                                  if (!showCountingBadge) return const SizedBox.shrink();
                                  
                                  return Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.7),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '$filledSlots/$totalImages',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // ✅ SELECTION CHECKBOX FOR MEDIA MESSAGES (only when selected)
                if (_selectionMode && isSelected)
                  Positioned(
                    top: 8,
                    left: isMe ? null : 4,
                    right: isMe ? 4 : null,
                    child: GestureDetector(
                      onTap: () => _toggleSelection(msg.messageId),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.green : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.green : Colors.grey,
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, size: 14, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ✅ Helper function to check if message should be shown as individual (not grouped yet)
  bool _shouldShowIndividually(Message msg) {
    // ✅ FIX: If no groupId, can't be grouped - show individually
    if (msg.groupId == null || msg.groupId!.isEmpty) {
      print('🔍 [SHOW INDIVIDUAL CHECK] Message ${msg.messageId} has no groupId - returning false');
      return false;
    }

    final String gid = msg.groupId!;
    final List<Message> groupMessages = [];
    groupMessages.addAll(_messageBox.values.where((m) => m.groupId == gid && m.chatId == widget.chatId));
    groupMessages.addAll(_pendingTempMessages.values.where((m) => m.groupId == gid && m.chatId == widget.chatId));

    if (groupMessages.length < 2) {
      print('🔍 [SHOW INDIVIDUAL CHECK] Group $gid has less than 2 messages (${groupMessages.length}) - returning false');
      return false;
    }

    // ✅ CRITICAL FIX: Check filled slots FIRST - if 2+ images arrived, ALWAYS show bundle
    // This check must happen BEFORE any other logic
    // ✅ ONSCREEN FIX: Always sync slots from actual messages to get accurate count
    int actualFilledSlots = 0;
    if (_collageMap.containsKey(gid)) {
      final slotList = _collageMap[gid]!;
      // ✅ CRITICAL: Sync slots from messages to get accurate count (same logic as _buildMediaMessage)
      final updatedSlotList = List<String?>.from(slotList);
      
      // ✅ ONSCREEN FIX: Always update slots from all messages to ensure accurate count
      for (final m in groupMessages) {
        if (m.imageIndex != null && m.imageIndex! >= 0 && m.imageIndex! < updatedSlotList.length) {
          final url = m.messageContent;
          if (url.isNotEmpty) {
            // ✅ Always update slot if empty OR if this is a real message (replaces temp)
            final isTemp = m.messageId.toString().startsWith('temp_');
            if (updatedSlotList[m.imageIndex!] == null || updatedSlotList[m.imageIndex!]!.isEmpty || !isTemp) {
              updatedSlotList[m.imageIndex!] = url;
            }
          }
        }
      }
      actualFilledSlots = updatedSlotList.where((url) => url != null && url.isNotEmpty).length;
      
      // ✅ ONSCREEN FIX: Update actual slotList in _collageMap to keep it in sync
      // This ensures that slots are always up-to-date when checking
      bool slotsChanged = false;
      for (int i = 0; i < updatedSlotList.length && i < slotList.length; i++) {
        if (updatedSlotList[i] != slotList[i]) {
          slotList[i] = updatedSlotList[i];
          slotsChanged = true;
        }
      }
      if (slotsChanged) {
        print('🔄 [SHOW INDIVIDUAL SYNC] Updated slots for group $gid - actualFilledSlots=$actualFilledSlots');
      }
    } else {
      // No slots yet - use message count as fallback
      actualFilledSlots = groupMessages.length;
    }

    print('🔍 [SHOW INDIVIDUAL CHECK] Group $gid: actualFilledSlots=$actualFilledSlots, groupMessages=${groupMessages.length}');

    // ✅ CRITICAL: If 2+ images arrived, ALWAYS show bundle (return false immediately)
    if (actualFilledSlots >= 2) {
      print('✅ [SHOW BUNDLE] Group $gid has $actualFilledSlots filled slots - ALWAYS showing bundle (not individually)');
      return false; // ✅ Always show bundle if 2+ images arrived - skip all other checks
    }

    // ✅ FIX: Check if this is sender side (isMe) or receiver side
    final userId = LocalAuthService.getUserId();
    final bool isMe = msg.senderId == userId;

    // ✅ FIX: On receiver side, ALWAYS group immediately (never show individually)
    // ✅ Only on sender side, show individually while sending (within 2 seconds)
    if (!isMe) {
      print('✅ [SHOW BUNDLE] Receiver side - always showing bundle');
      return false; // Receiver side: always group
    }

    // ✅ CRITICAL: Always show temp messages individually for instant display
    // ✅ BUT: Only if less than 2 images have arrived (checked above)
    final isTemp = msg.messageId.toString().startsWith('temp_');
    if (isTemp) {
      print('✅ [SHOW INDIVIDUALLY] Temp message ${msg.messageId} - showing individually (less than 2 images)');
      return true; // ✅ Show temp messages individually only if less than 2 images
    }

    // ✅ Sender side: Show individually if messages are recent (within 5 seconds)
    // ✅ BUT: Only if less than 2 images have arrived (checked above)
    final now = DateTime.now();
    final recentMessages = groupMessages.where((m) {
      final diff = now.difference(m.timestamp).inSeconds;
      return diff < 5; // Recent (within 5 seconds) - show individually while sending
    }).length;

    // ✅ If all messages are recent (within 5 seconds), show individually on sender side
    // ✅ BUT: Only if less than 2 images have arrived (checked above)
    final shouldShow = recentMessages == groupMessages.length;
    if (shouldShow) {
      print('✅ [SHOW INDIVIDUALLY] Recent messages in group $gid - showing individually (less than 2 images)');
    }
    return shouldShow;
  }

  // ✅ Helper function to check if message is part of a collage
  // ✅ Helper function to get cached filled slots count for a group
  int _getCachedFilledSlotsCount(String groupId) {
    if (!_collageMap.containsKey(groupId)) return -1;
    final slotList = _collageMap[groupId]!;
    // ✅ FIX: Count only non-null AND non-empty URLs
    return slotList.where((url) => url != null && url.isNotEmpty).length;
  }

  // ✅ Helper function to get cached filled slots count for a group
  // int _getCachedFilledSlotsCount(String groupId) {
  //   if (!_collageMap.containsKey(groupId)) return -1;
  //   final slotList = _collageMap[groupId]!;
  //   return slotList.where((url) => url != null).length;
  // }

  // ✅ Generate key for message bubble that includes filled slots count for grouped messages
  // This ensures that when slots are updated, the widget rebuilds
  Key _getMessageKey(Message msg) {
    if ((msg.groupId ?? '').isNotEmpty) {
      final groupId = msg.groupId!;
      final filledSlots = _getCachedFilledSlotsCount(groupId);
      // Include filled slots count in key so widget rebuilds when slots change
      return ValueKey('${msg.messageId}_slots_$filledSlots');
    }
    return ValueKey(msg.messageId);
  }

  // bool _isCollageMessage(Message msg) {
  //   // Check if message has groupId
  //   if ((msg.groupId ?? '').isNotEmpty) {
  //     final String gid = msg.groupId!;
  //
  //     // ✅ FIXED SLOT SYSTEM: Check if we have fixed slots and at least 2 filled
  //     if (_collageMap.containsKey(gid)) {
  //       final slotList = _collageMap[gid]!;
  //       final filledSlots = slotList.where((url) => url != null).length;
  //
  //       // ✅ Show collage only after 2 images are received
  //       if (filledSlots >= 2) {
  //         // ✅ FIX: Don't show as collage if should show individually (progressive grouping)
  //         if (_shouldShowIndividually(msg)) {
  //           return false;
  //         }
  //
  //         // Only return true if this is the anchor message (index 0)
  //         return (msg.imageIndex ?? 0) == 0;
  //       }
  //       return false; // Not enough images yet
  //     }
  //
  //     // ✅ FALLBACK: Old system for groups without fixed slots
  //     final List<Message> groupMessages = [];
  //     groupMessages.addAll(_messageBox.values.where((m) => m.groupId == gid && m.chatId == widget.chatId));
  //     groupMessages.addAll(_pendingTempMessages.values.where((m) => m.groupId == gid && m.chatId == widget.chatId));
  //
  //     // ✅ FIX: Simple check - if groupMessages.length >= 2, it's a collage
  //     bool isCollage = groupMessages.length >= 2;
  //
  //     if (isCollage) {
  //       // ✅ FIX: Don't show as collage if should show individually (progressive grouping)
  //       if (_shouldShowIndividually(msg)) {
  //         return false;
  //       }
  //
  //       // Only return true if this is the anchor message
  //       final int anchorIndex = groupMessages
  //           .where((m) => m.imageIndex != null && m.imageIndex! >= 0)
  //           .map((m) => m.imageIndex!)
  //           .fold(9999, (a, b) => a < b ? a : b);
  //       final int actualAnchorIndex = anchorIndex == 9999 ? 0 : anchorIndex;
  //       return (msg.imageIndex ?? 0) == actualAnchorIndex;
  //     }
  //   }
  //
  //   // Check if message is part of a cluster (fallback)
  //   final cluster = _getContiguousMediaCluster(msg);
  //   if (cluster.length >= 2) {
  //     cluster.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  //     return msg.messageId == cluster.first.messageId;
  //   }
  //
  //   return false;
  // }

  Widget _buildMediaMessage(Message msg, String mediaUrl, Color textColor) {
    // ✅ DEBUG: Log entry to _buildMediaMessage
    final hasGroupId = (msg.groupId ?? '').isNotEmpty;
    if (hasGroupId) {
      print('🔍 [BUILD MEDIA] _buildMediaMessage called for message ${msg.messageId}, groupId=${msg.groupId}, imageIndex=${msg.imageIndex}');
    }
    if ((msg.groupId ?? '').isNotEmpty) {
      final String gid = msg.groupId!;

      // ✅ FIXED SLOT SYSTEM: Use fixed slots if available
      // ✅ FALLBACK: If slots don't exist, initialize them on-demand
      // ✅ ON-DEMAND INITIALIZATION: If slots don't exist but message has groupId, initialize them
      if (!_collageMap.containsKey(gid)) {
        if (msg.imageIndex != null && msg.totalImages != null && msg.totalImages! > 0) {
          print("🧩 [ON-DEMAND INIT] Initializing fixed slots for group $gid from _buildMediaMessage");
          print("   - imageIndex=${msg.imageIndex}, totalImages=${msg.totalImages}, messageId=${msg.messageId}");

          // Initialize slots
          _collageMap[gid] = List.filled(msg.totalImages!, null);
          _collageLayoutFrozen[gid] = false;
          _collageTotalImages[gid] = msg.totalImages!;

          // Try to fill slots from all messages in this group
          final allGroupMsgs = _messageBox.values
              .where((m) => m.groupId == gid && m.chatId == widget.chatId)
              .toList();
          allGroupMsgs.addAll(_pendingTempMessages.values
              .where((m) => m.groupId == gid && m.chatId == widget.chatId));

          final slotList = _collageMap[gid]!;
          for (final groupMsg in allGroupMsgs) {
            if (groupMsg.imageIndex != null &&
                groupMsg.imageIndex! >= 0 &&
                groupMsg.imageIndex! < slotList.length &&
                groupMsg.messageContent.isNotEmpty) {
              if (slotList[groupMsg.imageIndex!] == null || slotList[groupMsg.imageIndex!]!.isEmpty) {
                slotList[groupMsg.imageIndex!] = groupMsg.messageContent;
                print("✅ [ON-DEMAND INIT] Filled slot ${groupMsg.imageIndex} for group $gid from message ${groupMsg.messageId}");
              }
            }
          }

          final filledSlots = slotList.where((url) => url != null && url.isNotEmpty).length;
          print("✅ [ON-DEMAND INIT] Group $gid initialized with $filledSlots/${msg.totalImages} slots filled");
        } else {
          print("⚠️ [ON-DEMAND INIT] Cannot initialize slots - missing imageIndex or totalImages: imageIndex=${msg.imageIndex}, totalImages=${msg.totalImages}");
        }
      }

      if (!_collageMap.containsKey(gid) && msg.imageIndex != null && msg.totalImages != null) {
        print("⚠️ [ON-DEMAND INIT] Slots not found for group $gid - initializing on-demand");
        _collageMap[gid] = List.filled(msg.totalImages!, null);
        _collageLayoutFrozen[gid] = false;
        _collageTotalImages[gid] = msg.totalImages!;

        // Try to fill slots from existing messages
        final allGroupMsgs = _messageBox.values
            .where((m) => m.groupId == gid && m.chatId == widget.chatId)
            .toList();
        allGroupMsgs.addAll(_pendingTempMessages.values
            .where((m) => m.groupId == gid && m.chatId == widget.chatId));

        final slotList = _collageMap[gid]!;
        for (final m in allGroupMsgs) {
          if (m.imageIndex != null && m.imageIndex! >= 0 && m.imageIndex! < slotList.length) {
            final url = m.messageContent;
            if (url.isNotEmpty) {
              slotList[m.imageIndex!] = url;
              print("✅ [ON-DEMAND INIT] Filled slot ${m.imageIndex} for group $gid");
            }
          }
        }
        print("✅ [ON-DEMAND INIT] Initialized slots for group $gid with ${allGroupMsgs.length} messages");
      }

      if (_collageMap.containsKey(gid)) {
        final slotList = _collageMap[gid]!;
        final totalImages = _collageTotalImages[gid] ?? slotList.length;
        final filledSlots = slotList.where((url) => url != null).length;

        // ✅ DEBUG: Disable freeze logic - always false
        final bool isFrozen = false; // _collageLayoutFrozen[gid] == true && filledSlots == 4;

        // Sender anchor: show collage immediately even with 1 image
        final userIdSender = LocalAuthService.getUserId();
        final bool isMeSender = msg.senderId == userIdSender;
        final bool isSenderAnchorEarly = isMeSender && (msg.imageIndex ?? -1) == 0;
        if (isSenderAnchorEarly && filledSlots >= 1) {
          final String anchorKeyEarly2 = msg.messageId.toString();
          final Widget collageEarly2 = _buildCollageFromFixedSlots(gid, slotList, totalImages, msg);
          if (filledSlots == totalImages) {
            _collageWidgetCache[anchorKeyEarly2] = collageEarly2;
            _cachedFilledSlotsCount[anchorKeyEarly2] = filledSlots;
          } else {
            _collageWidgetCache.remove(anchorKeyEarly2);
            _cachedFilledSlotsCount.remove(anchorKeyEarly2);
          }
          return collageEarly2;
        }

        // ✅ CRITICAL FIX: Always re-sync slots from actual messages to show all images immediately
        // This ensures that when new images arrive, they are immediately visible in the collage
        final allGroupMsgs = _messageBox.values
            .where((m) => m.groupId == gid && m.chatId == widget.chatId)
            .toList();
        allGroupMsgs.addAll(_pendingTempMessages.values
            .where((m) => m.groupId == gid && m.chatId == widget.chatId));

        // ✅ CRITICAL: Sort messages - real messages first, then temp messages
        allGroupMsgs.sort((a, b) {
          final aIsTemp = a.messageId.toString().startsWith('temp_');
          final bIsTemp = b.messageId.toString().startsWith('temp_');
          if (aIsTemp && !bIsTemp) return 1; // Real messages first
          if (!aIsTemp && bIsTemp) return -1;
          return 0;
        });

        bool slotsUpdated = false;
        bool slotSignatureChanged = false;
        int previousFilledCount = slotList.where((url) => url != null && url.isNotEmpty).length;
        String? replacedTempId; // Track if temp message was converted to real (accessible in collage section)
        // Track if temp message was converted to real

        // ✅ CRITICAL FIX: Check if slotList size matches actual message count, resize if needed
        final actualMessageCount = allGroupMsgs.length;
        final currentSlotSize = slotList.length;

        if (actualMessageCount > currentSlotSize) {
          print("⚠️ [RECEIVER SYNC] Resizing slots for group $gid: $currentSlotSize -> $actualMessageCount");
          final oldSlots = List<String?>.from(slotList);
          _collageMap[gid] = List.filled(actualMessageCount, null);
          _collageTotalImages[gid] = actualMessageCount;

          // Copy old slots to new slots
          for (int i = 0; i < oldSlots.length && i < actualMessageCount; i++) {
            if (oldSlots[i] != null && oldSlots[i]!.isNotEmpty) {
              _collageMap[gid]![i] = oldSlots[i];
            }
          }

          // ✅ Update totalImages for all messages (save async but don't await in widget build)
          for (final m in allGroupMsgs) {
            if (m.totalImages != actualMessageCount) {
              m.totalImages = actualMessageCount;
              // ✅ Don't await - save in background to keep widget building synchronous
              ChatService.saveMessageLocal(m).then((_) {
                print("🔄 [RECEIVER SYNC] Updated message ${m.messageId} totalImages=$actualMessageCount");
              });
            }
          }

          slotsUpdated = true;
          print("✅ [RECEIVER SYNC] Resized slots for group $gid: $currentSlotSize -> $actualMessageCount");
        }

        // ✅ Get updated slotList after potential resize
        final updatedSlotList = _collageMap[gid]!;

        // ✅ RECEIVER SIDE LOG: Log before sync
        final userId = LocalAuthService.getUserId();
        final bool isMe = msg.senderId == userId;
        print('📱 [RECEIVER SYNC] Before sync - group $gid, isMe=$isMe, isReceiver=${!isMe}, previousFilledCount=$previousFilledCount');
        print('📱 [RECEIVER SYNC] All group messages: ${allGroupMsgs.map((m) => '${m.messageId}(idx=${m.imageIndex})').join(', ')}');
        print('📱 [RECEIVER SYNC] Slot list before sync: ${updatedSlotList.asMap().entries.map((e) => 'Slot[${e.key}]:${e.value != null && e.value!.isNotEmpty ? "filled" : "empty"}').join(', ')}');

        // ✅ Track temp message conversions for immediate slot update
        String? convertedTempIdOld;
        String? convertedTempIdNew;

        for (final m in allGroupMsgs) {
          if (m.imageIndex != null && m.imageIndex! >= 0 && m.imageIndex! < updatedSlotList.length) {
            final url = m.messageContent;
            if (url.isNotEmpty) {
              final isTemp = m.messageId.toString().startsWith('temp_');
              final previousSlotUrl = updatedSlotList[m.imageIndex!];

              // ✅ Skip if slot URL already matches message URL
              if (previousSlotUrl == url) {
                print('📱 [RECEIVER SYNC] Slot ${m.imageIndex} skipped - URL already matches: ${url.length > 50 ? url.substring(0, 50) + "..." : url}');
                continue;
              }

              // ✅ Check if this is temp message conversion (temp → final ID)
              final wasTemp = previousSlotUrl != null &&
                  (previousSlotUrl.contains('temp_') ||
                      allGroupMsgs.any((msg) => msg.messageId.toString().startsWith('temp_') &&
                          msg.imageIndex == m.imageIndex &&
                          msg.messageContent == previousSlotUrl));

              // ✅ Always update slot if it's empty OR if this is a real message (replaces temp)
              if (updatedSlotList[m.imageIndex!] == null || !isTemp) {
                // ✅ Track temp message conversion
                if (wasTemp && !isTemp) {
                  // Find the old temp messageId
                  final oldTempMsg = allGroupMsgs.firstWhereOrNull(
                          (msg) => msg.messageId.toString().startsWith('temp_') &&
                          msg.imageIndex == m.imageIndex &&
                          msg.messageContent == previousSlotUrl
                  );
                  if (oldTempMsg != null) {
                    convertedTempIdOld = oldTempMsg.messageId.toString();
                    convertedTempIdNew = m.messageId.toString();
                    replacedTempId = m.messageId.toString();
                    print('🔄 [TEMP CONVERSION] Temp message converted: $convertedTempIdOld → $convertedTempIdNew');

                    // ✅ Force slot update immediately after conversion
                    updatedSlotList[m.imageIndex!] = url;
                    slotsUpdated = true;
                    print('🔄 [TEMP CONVERSION] Force updated slot ${m.imageIndex} with new URL after temp conversion');
                  }
                } else {
                  updatedSlotList[m.imageIndex!] = url;
                  slotsUpdated = true;
                  print("🔄 [SYNC] Updated slot ${m.imageIndex} from message ${m.messageId} (${isTemp ? 'temp' : 'real'})");
                }
                print('📱 [RECEIVER SYNC] Slot ${m.imageIndex} updated - url=${url.length > 50 ? url.substring(0, 50) + "..." : url}');
              } else {
                print('📱 [RECEIVER SYNC] Slot ${m.imageIndex} skipped - already has ${isTemp ? 'temp' : 'real'} message');
              }
            } else {
              print('📱 [RECEIVER SYNC] Slot ${m.imageIndex} skipped - messageContent is empty for ${m.messageId}');
            }
          } else {
            print('📱 [RECEIVER SYNC] Message ${m.messageId} skipped - imageIndex=${m.imageIndex}, updatedSlotList.length=${updatedSlotList.length}');
          }
        }

        // ✅ After temp conversion, force slot signature refresh and cache invalidation
        if (convertedTempIdOld != null && convertedTempIdNew != null) {
          print('🔄 [TEMP CONVERSION] Processing conversion: $convertedTempIdOld → $convertedTempIdNew');

          // ✅ Force slot signature refresh
          final String signatureNow = updatedSlotList.join("|");
          _slotSignature[gid] = signatureNow;
          slotSignatureChanged = true;
          slotsUpdated = true;
          print('🔄 [TEMP CONVERSION] Refreshed slot signature for group $gid');

          // ✅ Invalidate cache for all anchor messages in this group
          final anchorMessages = _messageBox.values
              .where((m) => m.groupId == gid && m.chatId == widget.chatId && (m.imageIndex ?? 0) == 0)
              .toList();
          for (final anchorMsg in anchorMessages) {
            final anchorKey = anchorMsg.messageId.toString();
            _collageWidgetCache.remove(anchorKey);
            _cachedFilledSlotsCount.remove(anchorKey);
            print('🔄 [TEMP CONVERSION] Invalidated cache for anchor: $anchorKey');
          }

          // ✅ Also clear by old temp ID if it was anchor
          _collageWidgetCache.remove(convertedTempIdOld);
          _cachedFilledSlotsCount.remove(convertedTempIdOld);
          print('🔄 [TEMP CONVERSION] Invalidated cache for old temp ID: $convertedTempIdOld');
        }

        int currentFilledCount = updatedSlotList.where((url) => url != null && url.isNotEmpty).length;

        // ✅ Check if slot signature changed (detects any slot changes) - Use join("|") for accurate comparison
        // Note: signatureNow already set above if temp conversion happened
        String signatureNow;
        String? cachedSignature;
        if (convertedTempIdOld == null) {
          signatureNow = updatedSlotList.join("|");
          cachedSignature = _slotSignature[gid];

          if (_slotSignature[gid] != signatureNow) {
            slotSignatureChanged = true;
            _slotSignature[gid] = signatureNow;
          }
        } else {
          // signatureNow already set in temp conversion block above
          signatureNow = updatedSlotList.join("|");
          cachedSignature = _slotSignature[gid];
        }

        // ✅ RECEIVER SIDE LOG: Log after sync
        print('📱 [RECEIVER SYNC] After sync - currentFilledCount=$currentFilledCount, previousFilledCount=$previousFilledCount, slotsUpdated=$slotsUpdated');
        print('📱 [RECEIVER SYNC] Slot signature changed: $slotSignatureChanged (cached: ${cachedSignature != null ? "exists" : "null"}, current: ${signatureNow.length > 50 ? signatureNow.substring(0, 50) + "..." : signatureNow})');
        print('📱 [RECEIVER SYNC] Slot list after sync: ${updatedSlotList.asMap().entries.map((e) => 'Slot[${e.key}]:${e.value != null && e.value!.isNotEmpty ? "filled" : "empty"}').join(', ')}');

        if (currentFilledCount != previousFilledCount || slotSignatureChanged) {
          slotsUpdated = true;
          print("🔄 [SYNC] Filled slots changed: $previousFilledCount -> $currentFilledCount OR slot signature changed");

          // ✅ Mark that slots need sync
          _slotsNeedSync[gid] = true;

          // ✅ Force re-sync
          _slotsSyncedForGroup.remove(gid);

          // ✅ DEBUG: Disable freeze logic - always set to false
          _collageLayoutFrozen[gid] = false;
          print("🔓 [DEBUG] Layout unfrozen for group $gid (freeze disabled for debug)");
        }

        // ✅ If slots were updated, clear ALL caches and flags to force complete rebuild
        // ✅ RECEIVER SIDE FIX: Always clear cache on receiver side when slots change to show all images
        final bool isReceiver = !isMe;
        if (slotsUpdated || slotSignatureChanged || (isReceiver && currentFilledCount != previousFilledCount)) {
          final String groupAnchorKey = 'group_${gid}_anchor';
          _renderedGroups.remove(gid); // Clear rendered groups flag
          _renderedAnchorMessages.remove(groupAnchorKey);
          _builtGroups.remove(gid);
          _slotsSyncedForGroup.remove(gid); // FORCE re-sync

          // Clear collage cache for all anchor messages
          final anchorMessages = _messageBox.values
              .where((m) => m.groupId == gid && m.chatId == widget.chatId && (m.imageIndex ?? 0) == 0)
              .toList();
          for (final anchorMsg in anchorMessages) {
            final anchorKey = anchorMsg.messageId.toString();
            _collageWidgetCache.remove(anchorKey);
            _cachedFilledSlotsCount.remove(anchorKey); // Also clear cached count
            _renderedAnchorMessages.remove(anchorMsg.messageId.toString());
          }

          if (isReceiver) {
            print("📱 [RECEIVER SYNC] Cleared ALL caches on receiver side for group $gid - currentFilledCount=$currentFilledCount, forcing rebuild to show all images");
          } else {
            print("🔄 [SYNC] Cleared ALL caches and flags after slot update for group $gid - forcing rebuild");
          }

          // ✅ CRITICAL: Use post-frame callback to avoid setState during build
          // ✅ Cannot call setState during build phase - use post-frame callback instead
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _needsRefresh = true;
                _slotsNeedSync[gid] = true; // Mark that slots need sync
              });
              if (isReceiver) {
                print("📱 [RECEIVER SYNC] Triggered postFrame setState on receiver side for group $gid to show all $currentFilledCount images");
              } else {
                print("🔄 [SYNC] Triggered postFrame setState after slot update for group $gid");
              }
            }
          });
        }

        // ✅ CRITICAL FIX: Recalculate filledSlots AFTER sync to get accurate count
        // Use updatedSlotList (synced slots) instead of original slotList
        final int filledSlotsAfterSync = updatedSlotList.where((url) => url != null && url.isNotEmpty).length;
        // Use the synced count if available, otherwise use original
        final int actualFilledSlots = slotsUpdated ? filledSlotsAfterSync : filledSlots;
        
        print('🔍 [DEBUG] Group $gid: filledSlots=$filledSlots (before sync), filledSlotsAfterSync=$filledSlotsAfterSync (after sync), actualFilledSlots=$actualFilledSlots (using), totalImages=$totalImages, imageIndex=${msg.imageIndex}, messageId=${msg.messageId}');
        print('🔍 [DEBUG] Slot list (before sync): ${slotList.map((url) => url != null ? "filled" : "empty").toList()}');
        print('🔍 [DEBUG] Slot list (after sync): ${updatedSlotList.map((url) => url != null ? "filled" : "empty").toList()}');
        print('🔍 [DEBUG] Rendered groups: $_renderedGroups');
        print('🔍 [DEBUG] Rendered anchors: ${_renderedAnchorMessages.take(5).toList()}');
        print('🔍 [DEBUG] Is anchor? ${(msg.imageIndex ?? 0) == 0}');

        // ✅ Show collage only after 2 images are received (use actualFilledSlots after sync)
        if (actualFilledSlots >= 2) {
          // ✅ Check if sender or receiver side
          final userId = LocalAuthService.getUserId();
          final bool isMe = msg.senderId == userId;
          final bool isReceiver = !isMe;

          // ✅ FIX: Remove anchor check - only hide if imageIndex is null
          if (msg.imageIndex == null) {
            print('🚫 [MEDIA] Hiding message ${msg.messageId} - imageIndex is null');
            return const SizedBox.shrink();
          }

          // ✅ CRITICAL FIX: If 2+ images have arrived, ALWAYS show bundle (ignore recent status)
          // This ensures bundle is created immediately when 2+ images arrive
          // Get all messages in this group
          final allGroupMsgs = _messageBox.values
              .where((m) => m.groupId == gid && m.chatId == widget.chatId)
              .toList();
          allGroupMsgs.addAll(_pendingTempMessages.values
              .where((m) => m.groupId == gid && m.chatId == widget.chatId));

          // ✅ CRITICAL: If 2+ images arrived, clear recent messages IMMEDIATELY to show bundle
          if (actualFilledSlots >= 2) {
            for (final m in allGroupMsgs) {
              final msgIdStr = m.messageId.toString();
              _recentlyReceivedMessages.remove(msgIdStr);
              _recentMessageTimers[msgIdStr]?.cancel();
              _recentMessageTimers.remove(msgIdStr);
            }
            print("🧹 [BUNDLE FORCE] Cleared recent markers for ${allGroupMsgs.length} messages in group $gid (actualFilledSlots=$actualFilledSlots >= 2) - forcing bundle display");
          }

          // Check if ALL messages in group are recently sent/received (only for display logic)
          final allRecent = allGroupMsgs.every((m) => _recentlyReceivedMessages.contains(m.messageId.toString()));

          print('📱 [INDIVIDUAL CHECK] Group $gid - allRecent=$allRecent, groupSize=${allGroupMsgs.length}, isMe=$isMe, isReceiver=$isReceiver, actualFilledSlots=$actualFilledSlots, totalImages=$totalImages');
          print('📱 [INDIVIDUAL CHECK] Recent set size: ${_recentlyReceivedMessages.length}');
          print('📱 [INDIVIDUAL CHECK] Group message IDs: ${allGroupMsgs.map((m) => m.messageId.toString()).toList()}');

          // ✅ CRITICAL FIX: If 2+ images arrived, ALWAYS show bundle (ignore recent status completely)
          // Only show individually if less than 2 images OR if explicitly marked as recent AND less than 2 images
          bool shouldShowBundle = actualFilledSlots >= 2;
          
          if (!shouldShowBundle && allRecent && allGroupMsgs.length >= 2) {
            // Less than 2 images but all recent - show individually
            print('✅ [INDIVIDUAL] Showing message ${msg.messageId} individually (less than 2 images and all recent) - isMe=$isMe');
            // Skip collage rendering - continue to normal single image rendering below
            // Fall through to the else branch that shows individual images
          } else if (shouldShowBundle) {
            // 2+ images - ALWAYS show bundle
            print('📱 [COLLAGE] Showing as bundle (actualFilledSlots=$actualFilledSlots >= 2) - isMe=$isMe');
            // Continue to collage rendering logic below
          } else {
            // Not all recent or less than 2 images - show as collage if possible
            print('📱 [COLLAGE] Showing as collage (not all recent or groupSize < 2) - isMe=$isMe');
            // Continue to collage rendering logic below
          }

          // ✅ Show collage for any message with valid imageIndex
          // ✅ CRITICAL FIX: If 2+ images arrived, ALWAYS show bundle (ignore recent status)
          if (msg.imageIndex != null && msg.imageIndex! >= 0) {
            // ✅ CRITICAL: If 2+ images arrived, ALWAYS show bundle (don't skip)
            bool shouldSkipCollage = false;

            // ✅ CRITICAL FIX: If 2+ images arrived, NEVER skip collage
            if (actualFilledSlots >= 2) {
              shouldSkipCollage = false;
              print('📱 [BUNDLE FORCE] $actualFilledSlots/$totalImages images received - FORCING bundle creation (ignoring recent status)');
            } else if (allRecent && allGroupMsgs.length >= 2) {
              // Less than 2 images and all recent - show individually
              shouldSkipCollage = true;
              print('✅ [INDIVIDUAL] Skipping collage - showing individually for message ${msg.messageId} (less than 2 images and all recent) - isMe=$isMe');
            } else {
              print('📱 [COLLAGE] Not all recent or less than 2 images - showing as collage (allRecent=$allRecent, groupSize=${allGroupMsgs.length}, actualFilledSlots=$actualFilledSlots) - isMe=$isMe');
            }

            // ✅ CRITICAL: Skip collage rendering ONLY if less than 2 images AND all recent
            if (!shouldSkipCollage) {
              // Continue with collage rendering
              // ✅ CRITICAL: Always render if we have 2+ filled slots and valid imageIndex
              print('✅ [RENDERING COLLAGE] Group $gid, message ${msg.messageId}, actualFilledSlots=$actualFilledSlots/$totalImages, imageIndex=${msg.imageIndex}');
              print('✅ [RENDERING COLLAGE] Slot URLs: ${updatedSlotList.map((url) => url != null ? "has_url" : "null").toList()}');
              print('📱 [COLLAGE] About to render collage - isMe=$isMe, isReceiver=$isReceiver');

              final String anchorKey = msg.messageId.toString();
              final String groupAnchorKey = 'group_${gid}_anchor';

              // ✅ CRITICAL FIX: Always rebuild if slots were updated OR cache doesn't exist
              // Re-initialization clears cache, so if cache doesn't exist, we need to rebuild
              var hasCache = _collageWidgetCache.containsKey(anchorKey);

              // ✅ CRITICAL FIX: Check if filled slots count changed since last cache
              // Compare with the count stored when widget was cached, not current count
              final cachedFilledSlots = _cachedFilledSlotsCount[anchorKey];
              final slotsCountChanged = cachedFilledSlots != null && cachedFilledSlots != actualFilledSlots;

              // ✅ CRITICAL: Check if slots need sync using improved logic
              // Use join("|") for accurate signature comparison
              final String signatureNow = slotList.join("|");
              final bool slotSignatureChanged = _slotSignature[gid] != signatureNow;

              // ✅ Check if temp message was converted (need to track this in sync section)
              // We'll check if any temp messages were replaced during sync
              final bool tempIdConverted = replacedTempId != null;

              // ✅ CRITICAL FIX: Check if forced rebuild is needed BEFORE lock check
              final bool needsForceRebuild = _forceBundleRebuild.contains(gid);
              
              // ✅ CRITICAL FIX: If group is locked AND all images received, sync = false (UNLESS forced rebuild)
              final bool isGroupLocked = _slotsSyncedForGroup.contains(gid);
              final bool allImagesReceived = actualFilledSlots == totalImages;

              // ✅ FIX: Use only these 5 conditions (do NOT use !_slotsSyncedForGroup.contains(gid))
              // 1. slotSignatureChanged
              // 2. slotsCountChanged
              // 3. slotsUpdated
              // 4. tempIdConverted (replacedTempId != null)
              // 5. earlySlotsNeedSync (only if not locked AND more images expected)
              final bool earlySlotsNeedSync = !isGroupLocked && filledSlots < totalImages;

              // ✅ If forced rebuild is needed, ALWAYS sync (ignore lock)
              // ✅ If locked AND all images received → sync = false (no update needed)
              final bool slotsNeedSync;
              if (needsForceRebuild) {
                slotsNeedSync = true;
                print('🔄 [FORCE REBUILD] Group $gid marked for forced rebuild - ignoring lock, sync=true');
              } else if (isGroupLocked && allImagesReceived) {
                slotsNeedSync = false;
                print('🔒 [LOCKED] Group $gid is locked and complete - sync=false (no update needed)');
              } else {
                // ✅ Check only the 5 conditions
                slotsNeedSync = slotSignatureChanged ||
                    slotsCountChanged ||
                    slotsUpdated ||
                    tempIdConverted ||
                    earlySlotsNeedSync;
              }

              // ✅ ALWAYS rebuild if:
              // 1. Slots were updated in this call
              // 2. Filled slots count changed (new images arrived)
              // 3. Cache doesn't exist
              // 4. Slots need sync (new images arrived but not synced yet)
              // 5. Filled slots count is less than total images (more images expected)
              final hasMoreImagesExpected = actualFilledSlots < totalImages;

              // ✅ CRITICAL: If filled slots changed or don't match cache, always clear cache and rebuild
              if (hasCache && (slotsCountChanged || (cachedFilledSlots != null && cachedFilledSlots != actualFilledSlots))) {
                print('🔄 [CACHE INVALID] Cache invalid - filledSlots changed: cached=$cachedFilledSlots, current=$actualFilledSlots');
                _collageWidgetCache.remove(anchorKey);
                _cachedFilledSlotsCount.remove(anchorKey);
                hasCache = false; // Mark as no cache so it rebuilds
              }

              // ✅ CRITICAL FIX: Receiver side should NEVER return cached if actualFilledSlots < totalImages
              // Even if locked, if cache was built with incomplete data, rebuild it
              final bool isReceiver2 = !isMe;
              final bool cacheIsIncomplete = cachedFilledSlots != null && cachedFilledSlots < actualFilledSlots;
              final bool cacheHasWrongCount = cachedFilledSlots != null && cachedFilledSlots != actualFilledSlots;

              // ✅ Note: needsForceRebuild already declared above

                // ✅ RECEIVER SIDE FIX: Always rebuild if cache is incomplete or has wrong count
                // ✅ CRITICAL: On receiver side, NEVER return cached immediately after all images arrive - force fresh rebuild
                // This ensures bundle shows immediately when all images arrive
                if (hasCache && !cacheIsIncomplete && !cacheHasWrongCount && !slotsUpdated && !slotsCountChanged && !slotsNeedSync && actualFilledSlots == totalImages && cachedFilledSlots == actualFilledSlots && !needsForceRebuild) {
                // ✅ RECEIVER SIDE FIX: Don't return cached immediately - force rebuild for instant visibility
                // Only return cached if NOT receiver side OR if we're sure UI has already been updated
                if (!isReceiver2) {
                  print('♻️ [CACHE] Returning cached collage for anchor $anchorKey (actualFilledSlots=$actualFilledSlots/$totalImages, cached=$cachedFilledSlots) - sender side');
                  return _collageWidgetCache[anchorKey]!;
                } else {
                  // ✅ Receiver side: Force rebuild to ensure immediate visibility
                  print('🔄 [RECEIVER FORCE REBUILD] Clearing cache on receiver side to force immediate bundle visibility (actualFilledSlots=$actualFilledSlots/$totalImages)');
                  _collageWidgetCache.remove(anchorKey);
                  _cachedFilledSlotsCount.remove(anchorKey);
                  _slotsSyncedForGroup.remove(gid); // Remove lock to allow fresh rebuild
                  hasCache = false;
                }
              } else if (needsForceRebuild) {
                // ✅ CRITICAL: Force rebuild even if cache exists
                print('🔄 [FORCE REBUILD] Group $gid marked for forced rebuild - clearing cache and forcing fresh build');
                _collageWidgetCache.remove(anchorKey);
                _cachedFilledSlotsCount.remove(anchorKey);
                _slotsSyncedForGroup.remove(gid);
                hasCache = false;
                // Don't remove from _forceBundleRebuild yet - let it rebuild first
              }

              // ✅ Always clear cache if incomplete, wrong count, or receiver side needs rebuild
              if (cacheIsIncomplete || cacheHasWrongCount || slotsNeedSync || (isReceiver2 && actualFilledSlots < totalImages) || slotsCountChanged) {
                print('🔄 [CACHE CLEAR] Clearing cache - cacheIsIncomplete=$cacheIsIncomplete, cacheHasWrongCount=$cacheHasWrongCount, slotsNeedSync=$slotsNeedSync, isReceiver=$isReceiver2, actualFilledSlots=$actualFilledSlots, totalImages=$totalImages, slotsCountChanged=$slotsCountChanged');
                _collageWidgetCache.remove(anchorKey);
                _cachedFilledSlotsCount.remove(anchorKey);
                hasCache = false;
              }

              // ✅ Need to rebuild - slots were updated OR cache doesn't exist OR slots count changed OR slots need sync OR more images expected
              print('🔄 [REBUILD] Rebuilding collage for group $gid anchor $anchorKey (slotsUpdated=$slotsUpdated, actualFilledSlots=$actualFilledSlots/$totalImages, cached=$cachedFilledSlots, countChanged=$slotsCountChanged, needSync=$slotsNeedSync, moreExpected=$hasMoreImagesExpected, hasCache=$hasCache)');

              // Clear all flags and cache to allow fresh rebuild
              _renderedGroups.remove(gid);
              _renderedAnchorMessages.remove(groupAnchorKey);
              _renderedAnchorMessages.remove(anchorKey);
              _builtGroups.remove(gid);
              _collageWidgetCache.remove(anchorKey);
              _cachedFilledSlotsCount.remove(anchorKey); // Also clear cached count

              // Mark as rendered to prevent duplicates, but allow this build
              _renderedGroups.add(gid);
              _renderedAnchorMessages.add(groupAnchorKey);
              _renderedAnchorMessages.add(anchorKey);

              // ✅ Create collage ONCE per group
              if (!_builtGroups.contains(gid)) {
                _builtGroups.add(gid);
                print('🧩 Creating collage for group $gid with $actualFilledSlots/$totalImages images');
              }

              // ✅ Build collage from fixed slots (use updatedSlotList after sync)
              try {
                final collageWidget = _buildCollageFromFixedSlots(gid, updatedSlotList, totalImages, msg);
                print('✅ [SUCCESS] Collage widget built for group $gid with $actualFilledSlots/$totalImages images');

                // ✅ Update signature after building (but don't lock yet - wait for all images)
                _slotsNeedSync[gid] = false;
                _slotSignature[gid] = updatedSlotList.join("|");

                // ✅ CRITICAL: Only cache if all images have arrived (actualFilledSlots == totalImages)
                // This prevents caching incomplete collages that need to be rebuilt when more images arrive
                final bool isReceiver3 = !isMe;

                // ✅ CRITICAL: Verify that ALL slots are actually filled before caching (use updatedSlotList)
                final int actualFilledCount = updatedSlotList.where((url) => url != null && url.isNotEmpty).length;
                final bool allSlotsVerified = actualFilledCount == totalImages && actualFilledCount == actualFilledSlots;

                // ✅ CRITICAL: Check if forced rebuild is needed BEFORE caching
                final bool needsForceRebuild = _forceBundleRebuild.contains(gid);
                print("🔍 [CACHE CHECK] Group $gid - needsForceRebuild=$needsForceRebuild, _forceBundleRebuild contains: ${_forceBundleRebuild.toList()}");
                
                if (actualFilledSlots == totalImages && allSlotsVerified && !needsForceRebuild) {
                  // All images received AND verified AND NOT forced rebuild - safe to cache
                  _collageWidgetCache[anchorKey] = collageWidget;
                  _cachedFilledSlotsCount[anchorKey] = actualFilledSlots;
                  print('✅ [CACHE] Cached collage for group $gid (all $actualFilledSlots images received and verified, actualFilled=$actualFilledCount)');

                  // ✅ Lock mechanism: When collage successfully renders with all images, mark as synced
                  // Only lock when NOT in forced rebuild set
                  if (!_slotsSyncedForGroup.contains(gid)) {
                    print("🟢 [SYNC COMPLETE] Locking slots for group $gid (actualFilledSlots=$actualFilledSlots == totalImages=$totalImages)");
                    _slotsSyncedForGroup.add(gid);
                    print("🟢 [SYNC COMPLETE] Group $gid locked - slots synced, collage complete");
                  }
                } else if (needsForceRebuild) {
                  // ✅ DON'T cache if forced rebuild - allow UI to rebuild every time
                  print('🔄 [FORCE REBUILD] NOT caching collage for group $gid - forced rebuild active, will rebuild on next render to ensure instant UI update');
                  // Clear any existing cache to force rebuild
                  _collageWidgetCache.remove(anchorKey);
                  _cachedFilledSlotsCount.remove(anchorKey);
                  // ✅ CRITICAL FIX: Cannot call setState during build - use post-frame callback
                  // Keep _forceBundleRebuild set until AFTER setState is called to ensure rebuild happens
                  print("🔄 [FORCE REBUILD] About to trigger setState for group $gid. Current set: ${_forceBundleRebuild.toList()}");
                  // ✅ CRITICAL: Use post-frame callback to avoid setState during build
                  if (mounted && _forceBundleRebuild.contains(gid)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _needsRefresh = true;
                          _cachedMessages.clear();
                        });
                        print("🔄 [FORCE REBUILD] Triggered setState (postFrame) for group $gid to force UI rebuild");
                        
                        // ✅ Also trigger in next frame as backup to ensure UI updates
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            setState(() {
                              _needsRefresh = true;
                            });
                            print("🔄 [FORCE REBUILD] Triggered setState (postFrame backup) for group $gid");
                          }
                          // Remove after setState is triggered
                          if (_forceBundleRebuild.contains(gid)) {
                            _forceBundleRebuild.remove(gid);
                            print("✅ [FORCE REBUILD] Group $gid removed from forced rebuild set after UI rebuild triggered");
                          }
                        });
                      }
                    });
                  }
                  // ✅ CRITICAL: Still return the widget even if forced rebuild
                  print('✅ [RETURN COLLAGE FORCE] Returning collage widget for group $gid (forced rebuild), anchor $anchorKey, actualFilledSlots=$actualFilledSlots/$totalImages');
                  return collageWidget;
                } else {
                  // More images expected OR verification failed - don't cache, force rebuild on next call
                  print('⚠️ [CACHE] NOT caching collage for group $gid (actualFilledSlots=$actualFilledSlots/$totalImages, actualFilled=$actualFilledCount, verified=$allSlotsVerified) - incomplete or unverified');
                  // Clear any existing cache to force rebuild
                  _collageWidgetCache.remove(anchorKey);
                  _cachedFilledSlotsCount.remove(anchorKey);
                }

                print('✅ [RETURN COLLAGE] Returning collage widget for group $gid, anchor $anchorKey, actualFilledSlots=$actualFilledSlots/$totalImages');
                return collageWidget;
              } catch (e, st) {
                print('❌ [ERROR] Failed to build collage for group $gid: $e\n$st');
                // ✅ Only remove from rendered sets if build failed (allow retry)
                _renderedAnchorMessages.remove(anchorKey);
                _renderedGroups.remove(gid);
                _collageWidgetCache.remove(anchorKey);
                _cachedFilledSlotsCount.remove(anchorKey); // Also clear cached count
                // Fall through to normal rendering
              }
            }
          } else {
            print('📱 [RECEIVER COLLAGE CHECK] Slot list status: ${slotList.asMap().entries.map((e) => 'Slot[${e.key}]:${e.value != null && e.value!.isNotEmpty ? "filled(${e.value!.length > 30 ? e.value!.substring(0, 30) + "..." : e.value})" : "empty"}').join(', ')}');
            print('📱 [RECEIVER COLLAGE CHECK] Lock status: locked=${_slotsSyncedForGroup.contains(gid)}, needSync=${_slotsNeedSync[gid] ?? false}');

            // ✅ FIX: Remove anchor check - only hide if imageIndex is null
            if (msg.imageIndex == null) {
              print('🚫 [MEDIA] Hiding message ${msg.messageId} - imageIndex is null');
              return const SizedBox.shrink();
            }

            // ✅ CRITICAL FIX: Recalculate filledSlots from actual slotList (sync might not have happened yet)
            // Sync slots from messages to get accurate count
            final allGroupMsgsForSync = _messageBox.values
                .where((m) => m.groupId == gid && m.chatId == widget.chatId)
                .toList();
            allGroupMsgsForSync.addAll(_pendingTempMessages.values
                .where((m) => m.groupId == gid && m.chatId == widget.chatId));
            
            // Update slots from messages
            final updatedSlotListElse = List<String?>.from(slotList);
            for (final m in allGroupMsgsForSync) {
              if (m.imageIndex != null && m.imageIndex! >= 0 && m.imageIndex! < updatedSlotListElse.length) {
                final url = m.messageContent;
                if (url.isNotEmpty && (updatedSlotListElse[m.imageIndex!] == null || updatedSlotListElse[m.imageIndex!]!.isEmpty)) {
                  updatedSlotListElse[m.imageIndex!] = url;
                }
              }
            }
            
            // ✅ CRITICAL: Recalculate filledSlots from synced slots
            final int actualFilledSlotsElse = updatedSlotListElse.where((url) => url != null && url.isNotEmpty).length;
            print('📱 [RECEIVER ELSE] Recalculated filledSlots: original=$filledSlots, after sync=$actualFilledSlotsElse, totalImages=$totalImages');

            // ✅ CRITICAL FIX: If 2+ images have arrived, ALWAYS show bundle (ignore recent status)
            // Get all messages in this group
            final allGroupMsgs = _messageBox.values
                .where((m) => m.groupId == gid && m.chatId == widget.chatId)
                .toList();
            allGroupMsgs.addAll(_pendingTempMessages.values
                .where((m) => m.groupId == gid && m.chatId == widget.chatId));

            // ✅ CRITICAL: If 2+ images arrived, clear recent messages IMMEDIATELY to show bundle
            if (actualFilledSlotsElse >= 2) {
              for (final m in allGroupMsgs) {
                final msgIdStr = m.messageId.toString();
                _recentlyReceivedMessages.remove(msgIdStr);
                _recentMessageTimers[msgIdStr]?.cancel();
                _recentMessageTimers.remove(msgIdStr);
              }
              print("🧹 [RECEIVER BUNDLE FORCE] Cleared recent markers for ${allGroupMsgs.length} messages in group $gid (actualFilledSlotsElse=$actualFilledSlotsElse >= 2) - forcing bundle display");
            }

            // Check if ALL messages in group are recently received (only for display logic)
            final allRecent = allGroupMsgs.every((m) => _recentlyReceivedMessages.contains(m.messageId.toString()));

            print('📱 [RECEIVER INDIVIDUAL CHECK] Group $gid - allRecent=$allRecent, groupSize=${allGroupMsgs.length}, recentMessages=${_recentlyReceivedMessages.length}');
            print('📱 [RECEIVER INDIVIDUAL CHECK] Recent set: ${_recentlyReceivedMessages.take(5).toList()}');
            print('📱 [RECEIVER INDIVIDUAL CHECK] Group message IDs: ${allGroupMsgs.map((m) => m.messageId.toString()).toList()}');

            // ✅ CRITICAL FIX: If 2+ images arrived, ALWAYS show bundle (ignore recent status completely)
            // Only show individually if less than 2 images OR if explicitly marked as recent AND less than 2 images
            bool shouldShowBundle = actualFilledSlotsElse >= 2;
            
            if (!shouldShowBundle && allRecent && allGroupMsgs.length >= 2) {
              // Less than 2 images but all recent - show individually
              print('✅ [RECEIVER INDIVIDUAL] Showing message ${msg.messageId} individually (less than 2 images and all recent)');
              // Skip collage rendering - continue to normal single image rendering below
              // Fall through to the else branch that shows individual images
            } else if (shouldShowBundle) {
              // 2+ images - ALWAYS show bundle
              print('📱 [RECEIVER COLLAGE] Showing as bundle (actualFilledSlotsElse=$actualFilledSlotsElse >= 2)');
              // Continue to collage rendering logic below
            } else {
              // Not all recent or less than 2 images - show as collage if possible
              print('📱 [RECEIVER COLLAGE] Showing as collage (not all recent or groupSize < 2)');
              // Continue to collage rendering logic below
            }

            // ✅ Show collage for any message with valid imageIndex
            // ✅ CRITICAL FIX: If 2+ images arrived, ALWAYS show bundle (ignore recent status)
            if (msg.imageIndex != null && msg.imageIndex! >= 0) {
              // ✅ CRITICAL: If 2+ images arrived, ALWAYS show bundle (don't skip)
              bool shouldSkipCollage = false;

              // ✅ CRITICAL FIX: If 2+ images arrived, NEVER skip collage (use actualFilledSlotsElse)
              if (actualFilledSlotsElse >= 2) {
                shouldSkipCollage = false;
                print('📱 [RECEIVER BUNDLE FORCE] $actualFilledSlotsElse/$totalImages images received - FORCING bundle creation (ignoring recent status)');
              } else if (allRecent && allGroupMsgs.length >= 2) {
                // Less than 2 images and all recent - show individually
                shouldSkipCollage = true;
                print('✅ [RECEIVER INDIVIDUAL] Skipping collage - showing individually for message ${msg.messageId} (less than 2 images and all recent)');
              } else {
                print('📱 [RECEIVER COLLAGE] Not all recent or less than 2 images - showing as collage (allRecent=$allRecent, groupSize=${allGroupMsgs.length}, filledSlots=$filledSlots)');
              }

              // ✅ CRITICAL: Skip collage rendering ONLY if less than 2 images AND all recent
              if (!shouldSkipCollage) {
                // Continue with collage rendering
                // ✅ CRITICAL: Always render if we have 2+ filled slots and valid imageIndex
                print('✅ [RENDERING COLLAGE] Group $gid, message ${msg.messageId}, actualFilledSlotsElse=$actualFilledSlotsElse/$totalImages, imageIndex=${msg.imageIndex}');
                print('✅ [RENDERING COLLAGE] Slot URLs: ${updatedSlotListElse.map((url) => url != null ? "has_url" : "null").toList()}');
                print('📱 [RECEIVER COLLAGE] About to render collage - isMe=$isMe, isReceiver=${!isMe}');

                final String anchorKey = msg.messageId.toString();
                final String groupAnchorKey = 'group_${gid}_anchor';

                // ✅ RECEIVER SIDE LOG: Log anchor keys
                print('📱 [RECEIVER COLLAGE] anchorKey=$anchorKey, groupAnchorKey=$groupAnchorKey');

                // ✅ CRITICAL FIX: Always rebuild if slots were updated OR cache doesn't exist
                // Re-initialization clears cache, so if cache doesn't exist, we need to rebuild
                var hasCache = _collageWidgetCache.containsKey(anchorKey);

                // ✅ RECEIVER SIDE LOG: Log cache check
                print('📱 [RECEIVER COLLAGE] Cache check - hasCache=$hasCache, anchorKey=$anchorKey');
                print('📱 [RECEIVER COLLAGE] All cached keys: ${_collageWidgetCache.keys.toList()}');
                print('📱 [RECEIVER COLLAGE] Rendered groups: $_renderedGroups');
                print('📱 [RECEIVER COLLAGE] Rendered anchors: ${_renderedAnchorMessages.toList()}');

                // ✅ CRITICAL FIX: Check if filled slots count changed since last cache
                // Compare with the count stored when widget was cached, not current count
                final cachedFilledSlots = _cachedFilledSlotsCount[anchorKey];
                final slotsCountChanged = cachedFilledSlots != null && cachedFilledSlots != actualFilledSlotsElse;

                // ✅ RECEIVER SIDE LOG: Log cache details
                print('📱 [RECEIVER COLLAGE] cachedFilledSlots=$cachedFilledSlots, actualFilledSlotsElse=$actualFilledSlotsElse, slotsCountChanged=$slotsCountChanged');

                // ✅ CRITICAL: Check if slots need sync using improved logic
                // Use join("|") for accurate signature comparison (use updatedSlotListElse)
                final String signatureNow = updatedSlotListElse.join("|");
                final bool slotSignatureChanged = _slotSignature[gid] != signatureNow;

                // ✅ Check if temp message was converted (need to track this in sync section)
                // We'll check if any temp messages were replaced during sync
                final bool tempIdConverted = replacedTempId != null;

                // ✅ CRITICAL FIX: If group is locked AND all images received, sync = false
                final bool isGroupLocked = _slotsSyncedForGroup.contains(gid);
                final bool allImagesReceived = actualFilledSlotsElse == totalImages;

                // ✅ FIX: Use only these 5 conditions (do NOT use !_slotsSyncedForGroup.contains(gid))
                // 1. slotSignatureChanged
                // 2. slotsCountChanged
                // 3. slotsUpdated
                // 4. tempIdConverted (replacedTempId != null)
                // 5. earlySlotsNeedSync (only if not locked AND more images expected)
                final bool earlySlotsNeedSync = !isGroupLocked && actualFilledSlotsElse < totalImages;

                // ✅ If locked AND all images received → sync = false (no update needed)
                final bool slotsNeedSync;
                if (isGroupLocked && allImagesReceived) {
                  slotsNeedSync = false;
                  print('🔒 [LOCKED] Group $gid is locked and complete - sync=false (no update needed)');
                } else {
                  // ✅ Check only the 5 conditions
                  slotsNeedSync = slotSignatureChanged ||
                      slotsCountChanged ||
                      slotsUpdated ||
                      tempIdConverted ||
                      earlySlotsNeedSync;
                }

                // ✅ RECEIVER SIDE LOG: Log sync status
                print('📱 [RECEIVER COLLAGE] slotsNeedSync=$slotsNeedSync, isLocked=$isGroupLocked, allImagesReceived=$allImagesReceived');
                print('📱 [RECEIVER COLLAGE] Conditions - slotSignatureChanged=$slotSignatureChanged, slotsCountChanged=$slotsCountChanged, slotsUpdated=$slotsUpdated, tempIdConverted=$tempIdConverted, earlySlotsNeedSync=$earlySlotsNeedSync');
                print('📱 [RECEIVER COLLAGE] filledSlots=$filledSlots, totalImages=$totalImages, replacedTempId=$replacedTempId');
                print('📱 [RECEIVER COLLAGE] Lock status - _slotsSyncedForGroup.contains($gid)=$isGroupLocked, all locked groups=${_slotsSyncedForGroup.toList()}');
                print('📱 [RECEIVER COLLAGE] Signature check - cached: ${_slotSignature[gid] != null ? "exists" : "null"}, current: ${signatureNow.length > 50 ? signatureNow.substring(0, 50) + "..." : signatureNow}');
                print('📱 [RECEIVER COLLAGE] replacedTempId=$replacedTempId');

                // ✅ ALWAYS rebuild if:
                // 1. Slots were updated in this call
                // 2. Filled slots count changed (new images arrived)
                // 3. Cache doesn't exist
                // 4. Slots need sync (new images arrived but not synced yet)
                // 5. Filled slots count is less than total images (more images expected)
                final hasMoreImagesExpected = actualFilledSlotsElse < totalImages;

                // ✅ CRITICAL: If filled slots changed or don't match cache, always clear cache and rebuild
                if (hasCache && (slotsCountChanged || (cachedFilledSlots != null && cachedFilledSlots != filledSlots))) {
                  print('🔄 [CACHE INVALID] Cache invalid - filledSlots changed: cached=$cachedFilledSlots, current=$filledSlots');
                  _collageWidgetCache.remove(anchorKey);
                  _cachedFilledSlotsCount.remove(anchorKey);
                  hasCache = false; // Mark as no cache so it rebuilds
                }

                // ✅ CRITICAL FIX: Receiver side should NEVER return cached if filledSlots < totalImages
                // Even if locked, if cache was built with incomplete data, rebuild it
                final bool isReceiver2 = !isMe;
                final bool cacheIsIncomplete = cachedFilledSlots != null && cachedFilledSlots < filledSlots;
                final bool cacheHasWrongCount = cachedFilledSlots != null && cachedFilledSlots != filledSlots;

                // ✅ CRITICAL: Check if this group is marked for forced rebuild
                final bool needsForceRebuild2 = _forceBundleRebuild.contains(gid);

                // ✅ RECEIVER SIDE FIX: Always rebuild if cache is incomplete or has wrong count
                // ✅ CRITICAL: On receiver side, NEVER return cached immediately after all images arrive - force fresh rebuild
                // This ensures bundle shows immediately when all images arrive
                if (hasCache && !cacheIsIncomplete && !cacheHasWrongCount && !slotsUpdated && !slotsCountChanged && !slotsNeedSync && filledSlots == totalImages && cachedFilledSlots == filledSlots && !needsForceRebuild2) {
                  // ✅ RECEIVER SIDE FIX: Don't return cached immediately - force rebuild for instant visibility
                  // Only return cached if NOT receiver side OR if we're sure UI has already been updated
                  if (!isReceiver2) {
                    print('♻️ [CACHE] Returning cached collage for anchor $anchorKey (actualFilledSlots=$actualFilledSlots/$totalImages, cached=$cachedFilledSlots) - sender side');
                    return _collageWidgetCache[anchorKey]!;
                  } else {
                    // ✅ Receiver side: Force rebuild to ensure immediate visibility
                    print('🔄 [RECEIVER FORCE REBUILD] Clearing cache on receiver side to force immediate bundle visibility (actualFilledSlots=$actualFilledSlots/$totalImages)');
                    _collageWidgetCache.remove(anchorKey);
                    _cachedFilledSlotsCount.remove(anchorKey);
                    _slotsSyncedForGroup.remove(gid); // Remove lock to allow fresh rebuild
                    hasCache = false;
                  }
                } else if (needsForceRebuild2) {
                  // ✅ CRITICAL: Force rebuild even if cache exists
                  print('🔄 [FORCE REBUILD] Group $gid marked for forced rebuild - clearing cache and forcing fresh build');
                  _collageWidgetCache.remove(anchorKey);
                  _cachedFilledSlotsCount.remove(anchorKey);
                  _slotsSyncedForGroup.remove(gid);
                  hasCache = false;
                  // Don't remove from _forceBundleRebuild yet - let it rebuild first
                }

                // ✅ Always clear cache if incomplete, wrong count, or receiver side needs rebuild
                if (cacheIsIncomplete || cacheHasWrongCount || slotsNeedSync || (isReceiver2 && actualFilledSlots < totalImages) || slotsCountChanged) {
                  print('🔄 [CACHE CLEAR] Clearing cache - cacheIsIncomplete=$cacheIsIncomplete, cacheHasWrongCount=$cacheHasWrongCount, slotsNeedSync=$slotsNeedSync, isReceiver=$isReceiver2, actualFilledSlots=$actualFilledSlots, totalImages=$totalImages, slotsCountChanged=$slotsCountChanged');
                  _collageWidgetCache.remove(anchorKey);
                  _cachedFilledSlotsCount.remove(anchorKey);
                  hasCache = false;
                }

                // ✅ Need to rebuild - slots were updated OR cache doesn't exist OR slots count changed OR slots need sync OR more images expected
                print('🔄 [REBUILD] Rebuilding collage for group $gid anchor $anchorKey (slotsUpdated=$slotsUpdated, filledSlots=$filledSlots/$totalImages, cached=$cachedFilledSlots, countChanged=$slotsCountChanged, needSync=$slotsNeedSync, moreExpected=$hasMoreImagesExpected, hasCache=$hasCache)');

                // Clear all flags and cache to allow fresh rebuild
                _renderedGroups.remove(gid);
                _renderedAnchorMessages.remove(groupAnchorKey);
                _renderedAnchorMessages.remove(anchorKey);
                _builtGroups.remove(gid);
                _collageWidgetCache.remove(anchorKey);
                _cachedFilledSlotsCount.remove(anchorKey); // Also clear cached count

                // ✅ RECEIVER SIDE LOG: Log before marking as rendered
                print('📱 [RECEIVER COLLAGE] BEFORE marking - renderedGroups: $_renderedGroups');
                print('📱 [RECEIVER COLLAGE] BEFORE marking - renderedAnchors: ${_renderedAnchorMessages.toList()}');
                print('📱 [RECEIVER COLLAGE] BEFORE marking - builtGroups: $_builtGroups');

                // Mark as rendered to prevent duplicates, but allow this build
                _renderedGroups.add(gid);
                _renderedAnchorMessages.add(groupAnchorKey);
                _renderedAnchorMessages.add(anchorKey);

                // ✅ RECEIVER SIDE LOG: Log after marking as rendered
                print('📱 [RECEIVER COLLAGE] AFTER marking - renderedGroups: $_renderedGroups');
                print('📱 [RECEIVER COLLAGE] AFTER marking - renderedAnchors: ${_renderedAnchorMessages.toList()}');
                print('📱 [RECEIVER COLLAGE] AFTER marking - builtGroups: $_builtGroups');
                print('📱 [RECEIVER COLLAGE] Marked group $gid with anchorKey=$anchorKey and groupAnchorKey=$groupAnchorKey');

                // ✅ Create collage ONCE per group
                if (!_builtGroups.contains(gid)) {
                  _builtGroups.add(gid);
                  print('🧩 Creating collage for group $gid with $actualFilledSlotsElse/$totalImages images');
                }

                // ✅ Build collage from fixed slots (use updatedSlotListElse after sync)
                try {
                  // ✅ RECEIVER SIDE LOG: Before building collage
                  print('📱 [RECEIVER COLLAGE] About to build collage - group $gid, anchorKey=$anchorKey, messageId=${msg.messageId}');
                  print('📱 [RECEIVER COLLAGE] Current renderedGroups before build: $_renderedGroups');
                  print('📱 [RECEIVER COLLAGE] Current renderedAnchors before build: ${_renderedAnchorMessages.toList()}');

                  final collageWidget = _buildCollageFromFixedSlots(gid, updatedSlotListElse, totalImages, msg);
                  print('✅ [SUCCESS] Collage widget built for group $gid with $actualFilledSlotsElse/$totalImages images');
                  print('📱 [RECEIVER COLLAGE] Collage widget built successfully - group $gid, anchorKey=$anchorKey');

                  // ✅ Update signature after building (but don't lock yet - wait for all images)
                  _slotsNeedSync[gid] = false;
                  _slotSignature[gid] = updatedSlotListElse.join("|");
                  print('📱 [RECEIVER COLLAGE] Updated signature for group $gid (actualFilledSlotsElse=$actualFilledSlotsElse/$totalImages)');

                  // ✅ CRITICAL: Only cache if all images have arrived (actualFilledSlotsElse == totalImages)
                  // This prevents caching incomplete collages that need to be rebuilt when more images arrive
                  // ✅ RECEIVER SIDE FIX: On receiver side, be more strict - only cache when all images received AND verified
                  final bool isReceiver3 = !isMe;

                  // ✅ CRITICAL: Verify that ALL slots are actually filled before caching (use updatedSlotListElse)
                  final int actualFilledCount = updatedSlotListElse.where((url) => url != null && url.isNotEmpty).length;
                  final bool allSlotsVerified = actualFilledCount == totalImages && actualFilledCount == actualFilledSlotsElse;

                  if (actualFilledSlotsElse == totalImages && allSlotsVerified) {
                    // All images received AND verified - safe to cache
                    _collageWidgetCache[anchorKey] = collageWidget;
                    _cachedFilledSlotsCount[anchorKey] = actualFilledSlotsElse;
                    print('✅ [CACHE] Cached collage for group $gid (all $actualFilledSlotsElse images received and verified, actualFilled=$actualFilledCount)');
                    if (isReceiver3) {
                      print('📱 [RECEIVER COLLAGE] Cached complete collage on receiver side - all $actualFilledSlotsElse/$totalImages images verified');
                    }

                    // ✅ Remove force rebuild flag after successful build
                    _forceBundleRebuild.remove(gid);
                    print('✅ [FORCE REBUILD] Removed force rebuild flag for group $gid after successful build');

                    // ✅ Lock mechanism: When collage successfully renders with all images, mark as synced
                    // Only lock when all images are received (actualFilledSlotsElse == totalImages)
                    if (!_slotsSyncedForGroup.contains(gid)) {
                      print("🟢 [SYNC COMPLETE] Locking slots for group $gid (actualFilledSlotsElse=$actualFilledSlotsElse == totalImages=$totalImages)");
                      _slotsSyncedForGroup.add(gid);
                      print("🟢 [SYNC COMPLETE] Group $gid locked - slots synced, collage complete");
                    } else {
                      print("🟢 [SYNC COMPLETE] Group $gid already locked");
                    }
                  } else {
                    // More images expected OR verification failed - don't cache, force rebuild on next call
                    print('⚠️ [CACHE] NOT caching collage for group $gid (actualFilledSlotsElse=$actualFilledSlotsElse/$totalImages, actualFilled=$actualFilledCount, verified=$allSlotsVerified) - incomplete or unverified');
                    if (isReceiver3) {
                      print('📱 [RECEIVER COLLAGE] NOT caching incomplete/unverified collage on receiver side - waiting for all $totalImages images (currently $actualFilledSlotsElse, actual=$actualFilledCount)');
                    }
                    // Clear any existing cache to force rebuild
                    _collageWidgetCache.remove(anchorKey);
                    _cachedFilledSlotsCount.remove(anchorKey);
                  }

                  print('✅ [RETURN COLLAGE ELSE] Returning collage widget for group $gid, anchor $anchorKey, actualFilledSlotsElse=$actualFilledSlotsElse/$totalImages');
                  return collageWidget;
                } catch (e, st) {
                  print('❌ [ERROR] Failed to build collage for group $gid: $e\n$st');
                  // ✅ Only remove from rendered sets if build failed (allow retry)
                  _renderedAnchorMessages.remove(anchorKey);
                  _renderedGroups.remove(gid);
                  _collageWidgetCache.remove(anchorKey);
                  _cachedFilledSlotsCount.remove(anchorKey); // Also clear cached count
                  // Fall through to normal rendering
                }
              }
            } else {
              // ✅ On receiver side, show all messages individually (no filtering)
              // ✅ RECEIVER SIDE FIX: But if all images received on receiver side, try to show collage
              final userId = LocalAuthService.getUserId();
              final bool isMe = msg.senderId == userId;
              final bool isReceiver2 = !isMe;

              print('📱 [RECEIVER COLLAGE] Else branch - filledSlots=$filledSlots, totalImages=$totalImages, isMe=$isMe, isReceiver=$isReceiver2, imageIndex=${msg.imageIndex}');

              // ✅ RECEIVER SIDE FIX: If 2+ images received on receiver side, try to render collage even if imageIndex check failed
              // This ensures collage shows when user comes back
              if (isReceiver2 && filledSlots >= 2) {
                print('📱 [RECEIVER COLLAGE] $filledSlots/$totalImages images received in else branch - attempting to render collage');
                // Try to render collage - this handles the case where imageIndex might be null but we still want collage
                // Continue to collage rendering logic by checking if we can build from slots
                final actualFilled = slotList.where((url) => url != null && url.isNotEmpty).length;
                if (actualFilled >= 2) {
                  print('📱 [RECEIVER COLLAGE] Enough filled slots ($actualFilled) - will attempt collage render');
                  // Don't return here - let it fall through to check collage rendering
                  // Actually, we need to go back and render collage
                  // For now, continue to individual rendering but log the issue
                }
              }

              if (!isMe) {
                // Receiver side: Show all messages individually, not just anchor
                // BUT: If 2+ images received, we should show collage instead
                if (isReceiver2 && filledSlots >= 2) {
                  print('⚠️ [RECEIVER COLLAGE] Warning: Should show collage but falling through to individual (imageIndex=${msg.imageIndex}, filledSlots=$filledSlots)');
                }
                print('✅ [MEDIA] Receiver: Showing non-anchor message ${msg.messageId} individually (imageIndex=${msg.imageIndex})');
                print('📱 [RECEIVER COLLAGE] Receiver side - showing individually, NOT collage path');
                // Continue to normal single image rendering below
              } else {
                // Sender side: Hide non-anchor messages when we have 2+ images (collage mode)
                print('🧩 Hiding non-anchor message ${msg.messageId}: filledSlots=$filledSlots, imageIndex=${msg.imageIndex}');
                return const SizedBox.shrink();
              }
            }
          }
        } else if (filledSlots == 1) {
          // ✅ Show single image if only 1 image received (not enough for collage yet)
          // ✅ FIX: Remove anchor check - show if imageIndex is not null
          if (msg.imageIndex == null) {
            print('🚫 [MEDIA] Hiding message ${msg.messageId} - imageIndex is null');
            return const SizedBox.shrink();
          }
          print('🧩 Showing single image ${msg.messageId} (waiting for more images for collage)');
          // Continue to normal single image rendering below
        } else {
          // ✅ On receiver side, show all messages individually (no filtering)
          final userId = LocalAuthService.getUserId();
          final bool isMe = msg.senderId == userId;
          print('📱 [RECEIVER COLLAGE] Final else branch - filledSlots=$filledSlots, isMe=$isMe, isReceiver=${!isMe}, imageIndex=${msg.imageIndex}');
          if (!isMe) {
            // Receiver side: Show all messages individually, not just anchor
            print('✅ [MEDIA] Receiver: Showing message ${msg.messageId} individually (imageIndex=${msg.imageIndex}, filledSlots=$filledSlots)');
            print('📱 [RECEIVER COLLAGE] Receiver side - showing individually (filledSlots < 2), NOT collage path');
            // Continue to normal single image rendering below
          } else {
            // Sender side: Hide if not anchor (index 0) when we have less than 2 images
            print('🧩 Hiding message ${msg.messageId}: filledSlots=$filledSlots, imageIndex=${msg.imageIndex}');
            return const SizedBox.shrink();
          }
        }
      }

      // ✅ FALLBACK: Old system for groups without fixed slots
      // ✅ RECEIVER SIDE LOG: Fallback path
      final userId = LocalAuthService.getUserId();
      final bool isMe = msg.senderId == userId;
      print('📱 [RECEIVER FALLBACK] Fallback collage path - group $gid, messageId=${msg.messageId}, isMe=$isMe, isReceiver=${!isMe}');

      // ✅ FIX: Get ALL messages (including pending temp ones) for the group
      final List<Message> groupMessages = [];
      // Add from Hive
      groupMessages.addAll(_messageBox.values.where((m) => m.groupId == gid && m.chatId == widget.chatId));
      // Add from pending temp messages
      groupMessages.addAll(_pendingTempMessages.values.where((m) => m.groupId == gid && m.chatId == widget.chatId));

      // Remove duplicates by messageId
      final uniqueGroupMessages = <String, Message>{};
      for (final m in groupMessages) {
        if (!uniqueGroupMessages.containsKey(m.messageId)) {
          uniqueGroupMessages[m.messageId] = m;
        } else {
          // Keep the one with thumbnail if available
          final existing = uniqueGroupMessages[m.messageId]!;
          if (m.thumbnailBase64 != null && m.thumbnailBase64!.isNotEmpty &&
              (existing.thumbnailBase64 == null || existing.thumbnailBase64!.isEmpty)) {
            uniqueGroupMessages[m.messageId] = m;
          }
        }
      }
      final finalGroupMessages = uniqueGroupMessages.values.toList();

      print('🧩 BuildMedia: msg=${msg.messageId} gid=$gid count=${finalGroupMessages.length} idx=${msg.imageIndex}');
      print('📱 [RECEIVER FALLBACK] Group messages: ${finalGroupMessages.map((m) => '${m.messageId}(idx=${m.imageIndex})').join(', ')}');
      if (finalGroupMessages.isNotEmpty) {
        // ✅ FIX: Sort by imageIndex to maintain sender's sequence (same logic as _buildCollageForMessages)
        finalGroupMessages.sort((a, b) {
          final aIndex = a.imageIndex ?? -1;
          final bIndex = b.imageIndex ?? -1;

          // If both have imageIndex, sort by imageIndex
          if (aIndex >= 0 && bIndex >= 0) {
            return aIndex.compareTo(bIndex);
          }

          // If only one has imageIndex, prioritize it
          if (aIndex >= 0) return -1;
          if (bIndex >= 0) return 1;

          // If neither has imageIndex, sort by timestamp (fallback)
          return a.timestamp.compareTo(b.timestamp);
        });
        try {
          final idxs = finalGroupMessages.map((m) => m.imageIndex?.toString() ?? 'null').join(',');
          print('🧩 Group ${gid} indices after sort: [$idxs]');
        } catch (_) {}
        final int anchorIndex = finalGroupMessages.map((m) => m.imageIndex ?? 9999).reduce((a, b) => a < b ? a : b);
        final int actualAnchorIndex = anchorIndex == 9999 ? 0 : anchorIndex;
        print('🧩 Group ${gid} anchorIndex=$actualAnchorIndex currentIdx=${msg.imageIndex ?? 0}');
        print('📱 [RECEIVER FALLBACK] anchorIndex=$actualAnchorIndex, current message imageIndex=${msg.imageIndex}, isMe=$isMe, isReceiver=${!isMe}');

        // if (finalGroupMessages.length >= 2 && (msg.imageIndex ?? 0) == actualAnchorIndex) {
        //   // Find the actual anchor message
        //   final anchorMsg = finalGroupMessages.firstWhere(
        //         (m) => (m.imageIndex ?? 0) == actualAnchorIndex,
        //     orElse: () => finalGroupMessages.first,
        //   );
        //
        //   // ✅ CRITICAL: Always render if we have 2+ messages and this is anchor
        //   // ✅ Duplicate prevention will be handled by widget tree
        //   print('✅ [ALLOWING RENDER] Group $gid, anchor ${anchorMsg.messageId}, count=${finalGroupMessages.length} (fallback)');
        //   print('📱 [RECEIVER FALLBACK] About to render fallback collage - group $gid, anchorMsg=${anchorMsg.messageId}, isMe=$isMe, isReceiver=${!isMe}');
        //
        //   print('✅ [RENDERING COLLAGE] Group $gid, anchor ${anchorMsg.messageId}, count=${finalGroupMessages.length} (fallback)');
        //
        //   // ✅ CRITICAL: Use group-level anchor key to ensure only ONE collage per group
        //   final String groupAnchorKey = 'group_${gid}_anchor';
        //   final String anchorKey = anchorMsg.messageId.toString();
        //   final String clusterAnchorKey = 'gid_${gid}_anchor_${anchorMsg.messageId}';
        //
        //   print('📱 [RECEIVER FALLBACK] Keys - groupAnchorKey=$groupAnchorKey, anchorKey=$anchorKey, clusterAnchorKey=$clusterAnchorKey');
        //
        //   // ✅ CRITICAL: Cache is source of truth - if cached, always return it
        //   print('📱 [RECEIVER FALLBACK] Checking cache - anchorKey=$anchorKey, hasCache=${_collageWidgetCache.containsKey(anchorKey)}');
        //   print('📱 [RECEIVER FALLBACK] All cached keys: ${_collageWidgetCache.keys.toList()}');
        //   print('📱 [RECEIVER FALLBACK] Rendered groups: $_renderedGroups');
        //   print('📱 [RECEIVER FALLBACK] Rendered anchors: ${_renderedAnchorMessages.toList()}');
        //
        //   if (_collageWidgetCache.containsKey(anchorKey)) {
        //     print('♻️ [CACHE] Returning cached fallback collage for anchor $anchorKey');
        //     print('📱 [RECEIVER FALLBACK] Returning cached collage');
        //     return _collageWidgetCache[anchorKey]!;
        //   }
        //
        //   // ✅ CRITICAL: Check group-level anchor first to prevent multiple collages
        //   // ✅ But if cache exists, allow render (might be from initialization)
        //   if (_collageWidgetCache.containsKey(anchorKey)) {
        //     // Cache exists - allow render
        //     print('✅ [FALLBACK] Group $gid anchor $anchorKey has cached collage - allowing render');
        //     print('📱 [RECEIVER FALLBACK] Cache exists - allowing render');
        //   } else if (_renderedGroups.contains(gid) || _renderedAnchorMessages.contains(groupAnchorKey)) {
        //     // ✅ If already rendered but no cache, it might be from initialization - allow rebuild
        //     print('⚠️ [FALLBACK] Group $gid anchor $anchorKey marked but no cache - allowing rebuild');
        //     print('📱 [RECEIVER FALLBACK] Already rendered but no cache - allowing rebuild');
        //     // Continue to build - will create cache
        //   } else {
        //     // ✅ Not rendered yet - mark it
        //     _renderedGroups.add(gid);
        //     _renderedAnchorMessages.add(groupAnchorKey);
        //     print('🔒 [GUARD] Marked (fallback) group $gid anchor ${anchorMsg.messageId} as rendered BEFORE build');
        //     print('📱 [RECEIVER FALLBACK] Not rendered yet - marking group $gid and anchor $groupAnchorKey');
        //   }
        //
        //   // ✅ Mark as rendered BEFORE building
        //   print('📱 [RECEIVER FALLBACK] BEFORE marking - renderedGroups: $_renderedGroups');
        //   print('📱 [RECEIVER FALLBACK] BEFORE marking - renderedAnchors: ${_renderedAnchorMessages.toList()}');
        //
        //   _renderedGroups.add(gid);
        //   _renderedAnchorMessages.add(groupAnchorKey);
        //   _renderedAnchorMessages.add(anchorKey);
        //   _clusterRenderedAnchors.add(clusterAnchorKey);
        //   print('🔒 [GUARD] Marked (fallback) group $gid anchor ${anchorMsg.messageId} as rendered BEFORE build');
        //   print('📱 [RECEIVER FALLBACK] AFTER marking - renderedGroups: $_renderedGroups');
        //   print('📱 [RECEIVER FALLBACK] AFTER marking - renderedAnchors: ${_renderedAnchorMessages.toList()}');
        //
        //   try {
        //     print('📱 [RECEIVER FALLBACK] About to build fallback collage - group $gid, anchorMsg=${anchorMsg.messageId}');
        //     final collageWidget = _buildCollageForMessages(finalGroupMessages, anchorMsg);
        //
        //     // ✅ CRITICAL: Cache the widget BEFORE returning
        //     _collageWidgetCache[anchorKey] = collageWidget;
        //     print('✅ [RENDERED] Cached fallback collage for anchor ${anchorMsg.messageId}');
        //     print('📱 [RECEIVER FALLBACK] Fallback collage built and cached - group $gid, anchorKey=$anchorKey');
        //
        //     return collageWidget;
        //   } catch (e, st) {
        //     print('❌ [ERROR] _buildCollageForMessages failed (fallback) for $gid: $e\n$st');
        //     // ✅ Only remove from rendered sets if build failed (allow retry)
        //     _renderedAnchorMessages.remove(anchorKey);
        //     _renderedGroups.remove(gid);
        //     _clusterRenderedAnchors.remove(clusterAnchorKey);
        //     _collageWidgetCache.remove(anchorKey);
        //     _cachedFilledSlotsCount.remove(anchorKey); // Also clear cached count
        //   }
        // } else {
        //   // ✅ On receiver side, show all messages individually (no filtering)
        //   final userId = LocalAuthService.getUserId();
        //   final bool isMe = msg.senderId == userId;
        //   if (!isMe) {
        //     // Receiver side: Show all messages individually, not just anchor
        //     print('✅ [FALLBACK] Receiver: Showing non-anchor message ${msg.messageId} individually (imageIndex=${msg.imageIndex})');
        //     // Continue to normal single image rendering below
        //   } else {
        //     // Sender side: Hide non-anchor messages - no rendering at all
        //     print('🧩 Non-anchor message ${msg.messageId} hidden for group $gid');
        //     return const SizedBox.shrink();
        //   }
        // }
      }
    } else {
      // ✅ CONTIGUOUS MEDIA CLUSTER (non-group messages)
      //final cluster = _getContiguousMediaCluster(msg);
      //print('🧩 Fallback cluster for ${msg.messageId}: size=${cluster.length}');

      // if (cluster.length >= 2) {
      //   // ✅ CRITICAL: Sort cluster by timestamp to get consistent anchor
      //   cluster.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      //   final Message anchor = cluster.first;
      //
      //   // ✅ CRITICAL: Use cluster-level key (based on all message IDs) to ensure same cluster = same anchor
      //   // ✅ messageId is String, so we'll use string IDs directly for the cluster key
      //   final List<String> clusterIds = cluster.map((m) => m.messageId.toString()).toList()..sort();
      //   final String clusterKey = 'cluster_${clusterIds.join('_')}';
      //
      //   print('🧩 Fallback anchor=${anchor.messageId} for msg=${msg.messageId}, clusterKey=$clusterKey');
      //
      //   // ✅ CRITICAL: Check if this is anchor FIRST
      //   if (msg.messageId == anchor.messageId) {
      //     // ✅ This is the anchor - check if cluster already processed
      //     if (_clusterCache.contains(clusterKey)) {
      //       print('♻️ [CLUSTER CACHE] Cluster $clusterKey already processed - returning cached anchor');
      //       final String anchorKey = anchor.messageId.toString();
      //       if (_collageWidgetCache.containsKey(anchorKey)) {
      //         return _collageWidgetCache[anchorKey]!;
      //       }
      //       // If cache missing but cluster processed, rebuild
      //     } else {
      //       // ✅ Mark cluster as processed BEFORE building
      //       _clusterCache.add(clusterKey);
      //       print('✅ [CLUSTER PROCESSED] Marked cluster $clusterKey as processed');
      //     }
      //
      //     // ✅ This is the anchor - always allow rendering
      //     print('✅ [ALLOWING RENDER] Cluster anchor ${anchor.messageId}, count=${cluster.length} (cluster)');
      //
      //     final String anchorKey = anchor.messageId.toString();
      //     final String clusterAnchorKey = 'cluster_anchor_${anchor.messageId}';
      //
      //     // ✅ CRITICAL: Cache is source of truth - if cached, always return it
      //     if (_collageWidgetCache.containsKey(anchorKey)) {
      //       print('♻️ [CACHE] Returning cached cluster collage for anchor $anchorKey');
      //       return _collageWidgetCache[anchorKey]!;
      //     }
      //
      //     // ✅ CRITICAL: Check if cluster anchor already rendered to prevent duplicates
      //     if (_clusterRenderedAnchors.contains(clusterAnchorKey) || _renderedAnchorMessages.contains(anchorKey)) {
      //       print('⚠️ [DUPLICATE PREVENTION] Cluster anchor $anchorKey already rendered - hiding duplicate');
      //       return const SizedBox.shrink();
      //     }
      //
      //     // ✅ Mark as rendered BEFORE building
      //     _renderedAnchorMessages.add(anchorKey);
      //     _clusterRenderedAnchors.add(clusterAnchorKey);
      //     print('🔒 [GUARD] Marked cluster anchor ${anchor.messageId} as rendered BEFORE build');
      //
      //     try {
      //       final collageWidget = _buildCollageForMessages(cluster, anchor);
      //
      //       // ✅ CRITICAL: Cache the widget BEFORE returning
      //       _collageWidgetCache[anchorKey] = collageWidget;
      //       print('✅ [RENDERED] Cached cluster collage for anchor ${anchor.messageId}');
      //
      //       return collageWidget;
      //     } catch (e, st) {
      //       print('❌ [ERROR] _buildCollageForMessages failed (cluster) for ${anchor.messageId}: $e');
      //       print('❌ [STACK TRACE]: $st');
      //       // ✅ Only remove from rendered sets if build failed (allow retry)
      //       _renderedAnchorMessages.remove(anchorKey);
      //       _clusterRenderedAnchors.remove(clusterAnchorKey);
      //       _collageWidgetCache.remove(anchorKey);
      //       _cachedFilledSlotsCount.remove(anchorKey); // Also clear cached count
      //       _clusterCache.remove(clusterKey); // Remove from cluster cache on error
      //       // Fall through to single image rendering
      //     }
      //   } else {
      //     // ✅ This is NOT the anchor - hide immediately
      //     print('🚫 Hiding non-anchor cluster message ${msg.messageId} (anchor is ${anchor.messageId})');
      //     return const SizedBox.shrink();
      //   }
      // }
    }
    final userId = LocalAuthService.getUserId();
    final bool isMe = msg.senderId == userId;
    final tempId = msg.messageId.toString();
    final uploadProgress = _uploadProgress[tempId];
    final isUploading = uploadProgress != null && uploadProgress < 100;



    return GestureDetector(
      // ✅ FIX: Only click on image itself, not surrounding space
      behavior: HitTestBehavior.opaque,
      onTap: () => _openImageFullScreen(msg),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.70,
        ),
        child: Stack(
          children: [
            // ✅ FIX: ClipRRect with InkWell for proper click area (only image area)
            // ✅ FIX: Add border for receiver side like WhatsApp
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: !isMe ? Border.all(color: Colors.grey.withOpacity(0.3), width: 1) : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () => _openImageFullScreen(msg),
                  child: SingleImageBubble(
                    msg: msg,
                    mediaUrl: mediaUrl,
                    isMe: isMe,
                    onImageLoaded: () {
                      // ✅ Mark image as loaded (auto-hide download button like WhatsApp)
                      // ✅ FIX: Debounce to prevent flickering
                      final messageId = msg.messageId.toString();
                      if (!_loadedImages.contains(messageId)) {
                        _loadedImages.add(messageId);
                        // ✅ Use postFrameCallback to prevent flickering
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            setState(() {});
                          }
                        });
                        print("✅ [IMAGE LOADED] Image loaded for message $messageId - hiding download button");
                      }
                    },
                  ),
                ),
              ),
            ),

            // ✅ CRITICAL: WhatsApp-style loading indicator when uploading
            if (isMe && isUploading && uploadProgress != null)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          strokeWidth: 2,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${uploadProgress.toInt()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ✅ RECEIVER SIDE: Download button and loading indicator (WhatsApp style)
            if (!isMe && mediaUrl.startsWith('http')) 
              _buildDownloadControls(msg, mediaUrl),

            Positioned(
              bottom: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(msg.timestamp),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    if (isMe) const SizedBox(width: 4),
                    if (isMe)
                      _buildMessageTicks(msg, isUploading: isUploading),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  // ✅ STEP 3: Cluster debounce function to prevent duplicate builds
  bool _allowCluster(String groupId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_clusterStamp.containsKey(groupId) &&
        now - _clusterStamp[groupId]! < 120) {
      return false; // ✅ BLOCK duplicate cluster build
    }
    _clusterStamp[groupId] = now;
    return true;
  }

  // List<Message> _getContiguousMediaCluster(Message msg, {int windowSeconds = 20}) {
  //   final all = _messageBox.values
  //       .where((m) => m.chatId == widget.chatId)
  //       .toList()
  //     ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  //   final int idx = all.indexWhere((m) => m.messageId == msg.messageId);
  //   if (idx == -1) return [msg];
  //   final cluster = <Message>[msg];
  //   // expand backward
  //   int i = idx - 1;
  //   while (i >= 0) {
  //     final m = all[i];
  //     if (m.senderId != msg.senderId) break;
  //     if (m.messageType != 'media' && m.messageType != 'encrypted_media') break;
  //     final diff = msg.timestamp.difference(m.timestamp).inSeconds.abs();
  //     if (diff > windowSeconds) break;
  //     cluster.add(m);
  //     i--;
  //   }
  //   // expand forward
  //   i = idx + 1;
  //   while (i < all.length) {
  //     final m = all[i];
  //     if (m.senderId != msg.senderId) break;
  //     if (m.messageType != 'media' && m.messageType != 'encrypted_media') break;
  //     final diff = m.timestamp.difference(msg.timestamp).inSeconds.abs();
  //     if (diff > windowSeconds) break;
  //     cluster.add(m);
  //     i++;
  //   }
  //   // ensure uniqueness
  //   final ids = <String>{};
  //   final unique = <Message>[];
  //   for (final m in cluster) {
  //     final id = m.messageId.toString();
  //     if (!ids.contains(id)) {
  //       ids.add(id);
  //       unique.add(m);
  //     }
  //   }
  //   try {
  //     final logIds = unique.map((m) => m.messageId.toString()).join(',');
  //     print('🧩 Cluster unique ids for ${msg.messageId}: [$logIds]');
  //   } catch (_) {}
  //   return unique;
  // }

  Widget _buildMediaGroupCollage(Message firstMsg) {
    final List<Message> groupMessages = _messageBox.values
        .where((m) => m.groupId == firstMsg.groupId)
        .toList();

    // ✅ CRITICAL FIX: Sort by imageIndex to maintain sender's sequence with stable sort
    // ✅ APP RESTART FIX: Use messageId as secondary key to ensure consistent ordering
    groupMessages.sort((a, b) {
      final aIndex = a.imageIndex ?? -1;
      final bIndex = b.imageIndex ?? -1;

      // If both have imageIndex, sort by imageIndex first
      if (aIndex >= 0 && bIndex >= 0) {
        final indexCompare = aIndex.compareTo(bIndex);
        // ✅ CRITICAL: If imageIndex is same, use messageId for stable sorting (ensures same order on app restart)
        if (indexCompare != 0) {
          return indexCompare;
        }
        // ✅ Secondary sort by messageId to ensure consistent order even if imageIndex is duplicate
        return a.messageId.toString().compareTo(b.messageId.toString());
      }

      // If only one has imageIndex, prioritize it
      if (aIndex >= 0) return -1;
      if (bIndex >= 0) return 1;

      // If neither has imageIndex, sort by timestamp, then messageId for consistency
      final timestampCompare = a.timestamp.compareTo(b.timestamp);
      if (timestampCompare != 0) {
        return timestampCompare;
      }
      // ✅ Secondary sort by messageId for absolute consistency
      return a.messageId.toString().compareTo(b.messageId.toString());
    });

    return _buildCollageForMessages(groupMessages, firstMsg);
  }

  // ✅ NEW: Build collage from fixed slots with transparent tiles
  Widget _buildCollageFromFixedSlots(String groupId, List<String?> slotList, int totalImages, Message anchorMsg) {
    // ✅ DEBUG: Print collage map before building
    debugCollageMap(groupId);
    // ✅ DEBUG: Print detailed collage status with thumbnail info
    debugCollageStatus(anchorMsg);

    // ✅ CRITICAL FIX: Get messages for thumbnails - map by imageIndex with stable sort
    // ✅ APP RESTART FIX: Sort messages before mapping to ensure consistent order
    final Map<int, Message> indexToMessage = {};
    final allGroupMessages = _messageBox.values
        .where((m) => m.groupId == groupId && m.chatId == widget.chatId)
        .toList();
    allGroupMessages.addAll(_pendingTempMessages.values
        .where((m) => m.groupId == groupId && m.chatId == widget.chatId));

    // ✅ CRITICAL FIX: Sort messages by imageIndex with stable sort before mapping
    // ✅ APP RESTART FIX: Use messageId as secondary key to ensure consistent order
    allGroupMessages.sort((a, b) {
      final aIndex = a.imageIndex ?? 9999;
      final bIndex = b.imageIndex ?? 9999;
      final indexCompare = aIndex.compareTo(bIndex);
      // ✅ CRITICAL: If imageIndex is same, use messageId for stable sorting
      if (indexCompare != 0) {
        return indexCompare;
      }
      // ✅ Secondary sort by messageId to ensure consistent order
      return a.messageId.toString().compareTo(b.messageId.toString());
    });

    print('🔍 [COLLAGE] Building collage for group $groupId: totalImages=$totalImages, slotList.length=${slotList.length}');
    print('🔍 [COLLAGE] Found ${allGroupMessages.length} messages in group (sorted by imageIndex)');

    // ✅ CRITICAL: Map messages to indices - if duplicate imageIndex, keep first one (stable)
    for (final msg in allGroupMessages) {
      if (msg.imageIndex != null && msg.imageIndex! >= 0 && msg.imageIndex! < slotList.length) {
        // ✅ Only map if not already mapped (prevent overwriting with duplicate imageIndex)
        if (!indexToMessage.containsKey(msg.imageIndex!)) {
          indexToMessage[msg.imageIndex!] = msg;
          print('🔍 [COLLAGE] Mapped message ${msg.messageId} to index ${msg.imageIndex}');
        } else {
          print('⚠️ [COLLAGE] Duplicate imageIndex ${msg.imageIndex} - keeping first message ${indexToMessage[msg.imageIndex!]?.messageId}');
        }
      }
    }

    // ✅ Count filled slots and get their indices
    final filledSlots = <int>[];
    for (int i = 0; i < slotList.length; i++) {
      if (slotList[i] != null && slotList[i]!.isNotEmpty) {
        filledSlots.add(i);
      }
    }
    final filledCount = filledSlots.length;

    // ✅ RECEIVER SIDE LOG: Detailed filledCount calculation
    final userId = LocalAuthService.getUserId();
    final bool isMe = anchorMsg.senderId == userId;
    print('📱 [RECEIVER COLLAGE BUILD] Group $groupId - isMe=$isMe, isReceiver=${!isMe}');
    print('📱 [RECEIVER COLLAGE BUILD] filledCount=$filledCount, totalImages=$totalImages, slotList.length=${slotList.length}');
    print('📱 [RECEIVER COLLAGE BUILD] filledSlots indices: $filledSlots');
    print('📱 [RECEIVER COLLAGE BUILD] Slot URLs: ${slotList.map((url) => url != null && url.isNotEmpty ? "has_url" : "null").toList()}');
    print('📱 [RECEIVER COLLAGE BUILD] All group messages count: ${allGroupMessages.length}');
    print('📱 [RECEIVER COLLAGE BUILD] indexToMessage keys: ${indexToMessage.keys.toList()}');

    // ✅ CRITICAL: Log each slot in detail
    for (int i = 0; i < slotList.length; i++) {
      final url = slotList[i];
      final msg = indexToMessage[i];
      print('📱 [RECEIVER COLLAGE BUILD] Slot[$i]: url=${url != null && url.isNotEmpty ? "present" : "null"}, msg=${msg != null ? msg.messageId : "null"}, imageIndex=${msg?.imageIndex}');
    }

    print('🔍 [COLLAGE] Filled slots: $filledCount/$totalImages (indices: $filledSlots)');
    print('🔍 [COLLAGE] Slot URLs: ${slotList.map((url) => url != null && url.isNotEmpty ? "has_url" : "null").toList()}');

    // ✅ CRITICAL: If no filled slots, return empty widget
    if (filledCount == 0) {
      print('⚠️ [COLLAGE] No filled slots for group $groupId');
      return const SizedBox.shrink();
    }

    final maxWidth = MediaQuery.of(context).size.width * 0.70;

    // ✅ Build tile widget for a filled slot index
    Widget buildSlotTile(int slotIndex) {
      final url = slotList[slotIndex];

      // ✅ This should never be null/empty since we filtered filledSlots
      if (url == null || url.isEmpty) {
        print('⚠️ [COLLAGE] Slot $slotIndex is empty but in filledSlots list');
        return const SizedBox.shrink();
      }

      final msg = indexToMessage[slotIndex];

      // ✅ Get full image URL - prefer highQualityUrl, then messageContent
      String fullImageUrl = url;
      if (msg != null) {
        // ✅ Use high quality URL if available, otherwise use messageContent
        if (msg.highQualityUrl != null && msg.highQualityUrl!.isNotEmpty) {
          fullImageUrl = msg.highQualityUrl!;
        } else if (msg.messageContent.isNotEmpty && msg.messageContent != url) {
          // If messageContent is different and not empty, use it
          fullImageUrl = msg.messageContent;
        }
      }

      // ✅ Get thumbnail (if message exists)
      String? thumb;
      if (msg != null) {
        thumb = msg.thumbnailBase64;
        if (thumb != null && thumb.isNotEmpty && thumb.contains(',')) {
          thumb = thumb.split(',').last.trim();
        }
      }

      final bool isRemote = fullImageUrl.startsWith('http');
      final bool isLocal = !isRemote;

      print('🔍 [COLLAGE] Building slot $slotIndex: fullImageUrl=${fullImageUrl.length > 50 ? fullImageUrl.substring(0, 50) + "..." : fullImageUrl}, msg=${msg != null ? "found" : "null"}, isRemote=$isRemote');

      // ✅ Build image widget with thumbnail first, then full image
      Widget imageWidget;

      if (isLocal) {
        final provider = ResizeImage(
          FileImage(File(fullImageUrl)),
          width: 1200,
          height: 1200,
        );
        imageWidget = OrientationAwareImage(
          provider: provider,
          thumbBase64: thumb,
        );
      } else {
        final provider = ResizeImage(
          CachedNetworkImageProvider(fullImageUrl),
          width: 1200,
          height: 1200,
        );
        // ✅ Track image load for collage images (auto-hide download button)
        final collageMessageId = msg?.messageId.toString();
        imageWidget = OrientationAwareImage(
          provider: provider,
          thumbBase64: thumb,
          onImageLoaded: collageMessageId != null ? () {
            if (!_loadedImages.contains(collageMessageId)) {
              _loadedImages.add(collageMessageId);
              // ✅ FIX: Debounce to prevent flickering
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {});
                }
              });
              print("✅ [COLLAGE IMAGE LOADED] Image loaded for message $collageMessageId - hiding download button");
            }
          } : null,
        );
      }

      final bool isRemoteSlot = fullImageUrl.startsWith('http');
      final userId = LocalAuthService.getUserId();
      final bool isMeSlot = msg?.senderId == userId;
      
      return Stack(
        children: [
          GestureDetector(
        onTap: () {
          if (msg != null) {
                _openImageFullScreen(msg!);
          } else {
            // ✅ If message not found, try to open from URL directly
            print('⚠️ [COLLAGE] Message not found for slot $slotIndex, opening URL directly');
            // You can add a fallback image viewer here if needed
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(0), // ✅ No border
          child: imageWidget,
        ),
          ),
          // ✅ RECEIVER SIDE: Download button for collage images (WhatsApp style)
          if (!isMeSlot && isRemoteSlot && msg != null)
            _buildDownloadControls(msg!, fullImageUrl),
        ],
      );
    }

    // ✅ NEW: Build layered book stack design
    // ✅ RECEIVER SIDE LOG: Log layout selection
    print('📱 [RECEIVER COLLAGE BUILD] Selecting layout - filledCount=$filledCount');

    // ✅ CRITICAL FIX: Get image URLs in order based on slot indices (0, 1, 2, ...)
    // ✅ APP RESTART FIX: Always use slotList order to ensure consistent image positions
    final List<String> imageUrls = [];
    // ✅ CRITICAL: Iterate slots in order (0, 1, 2, ...) to maintain sender's sequence
    for (int i = 0; i < slotList.length; i++) {
      if (slotList[i] != null && slotList[i]!.isNotEmpty) {
        final msg = indexToMessage[i];
        String url = slotList[i]!;
        // Use high quality URL if available
        if (msg != null && msg.highQualityUrl != null && msg.highQualityUrl!.isNotEmpty) {
          url = msg.highQualityUrl!;
        }
        imageUrls.add(url);
        print('🔍 [COLLAGE URL ORDER] Added image at slot $i: url=${url.length > 50 ? url.substring(0, 50) + "..." : url}, msgId=${msg?.messageId}');
      }
    }
    
    // ✅ APP RESTART FIX: Log final image order to verify consistency
    print('🔍 [COLLAGE URL ORDER] Final imageUrls count: ${imageUrls.length}, order: slots 0-${imageUrls.length - 1}');

    // ✅ Build layered book stack widget
    Widget layeredBookStack(List<String> images) {
      final userId = LocalAuthService.getUserId();
      final bool isMe = anchorMsg.senderId == userId;
      Future<ImageInfo> loadInfo(ImageProvider provider) async {
        final c = Completer<ImageInfo>();
        final stream = provider.resolve(const ImageConfiguration());
        late ImageStreamListener listener;
        listener = ImageStreamListener((info, _) {
          c.complete(info);
          stream.removeListener(listener);
        }, onError: (error, stack) {
          stream.removeListener(listener);
          c.completeError(error);
        });
        stream.addListener(listener);
        return c.future;
      }
      final topUrl = images.isNotEmpty ? images.last : '';
      final topProvider = topUrl.startsWith('http')
          ? CachedNetworkImageProvider(topUrl)
          : FileImage(File(topUrl)) as ImageProvider;
      return FutureBuilder<ImageInfo>(
        future: loadInfo(topProvider),
        builder: (context, snap) {
          final screen = MediaQuery.of(context).size;
          final double bubbleWidth = screen.width * 0.70;
          double cardW = bubbleWidth;
          double cardH = bubbleWidth * 0.66;
          if (snap.hasData) {
            final w = snap.data!.image.width.toDouble();
            final h = snap.data!.image.height.toDouble();
            final ratio = h / w;
            cardH = bubbleWidth * ratio;
            if (ratio > 1.0) {
              final double maxH = screen.height * 0.55;
              if (cardH > maxH) cardH = maxH;
            }
          }
          final stackH = cardH + 60;
          return SizedBox(
            height: stackH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (int i = 0; i < images.length; i++)
                  Positioned(
                    top: (images.length - 1 - i) * 8,
                    left: isMe ? 0 : (images.length - 1 - i) * 8,
                    right: isMe ? (images.length - 1 - i) * 8 : 0,
                    child: GestureDetector(
                      onTap: () {
                        final slotIndex = filledSlots[i];
                        final msg = indexToMessage[slotIndex];
                        if (msg != null) {
                          _openImageFullScreen(msg);
                        }
                      },
                      child: Container(
                        height: cardH,
                        width: cardW,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 4,
                              spreadRadius: -2,
                              color: Colors.black26,
                            )
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Builder(
                            builder: (context) {
                              final slotIndex = filledSlots[i];
                              final msg = indexToMessage[slotIndex];
                              String? thumb = msg?.thumbnailBase64;
                              if (thumb != null && thumb.isNotEmpty && thumb.contains(',')) {
                                thumb = thumb.split(',').last.trim();
                              }
                              final provider = images[i].startsWith('http')
                                  ? ResizeImage(
                                CachedNetworkImageProvider(images[i]),
                                width: (cardW * 2).toInt(),
                                height: (cardH * 2).toInt(),
                              )
                                  : ResizeImage(
                                FileImage(File(images[i])),
                                width: (cardW * 2).toInt(),
                                height: (cardH * 2).toInt(),
                              );
                              return OrientationAwareImage(
                                provider: provider,
                                thumbBase64: thumb,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                // Extra back cards to visibly indicate a bundle even if only one image is loaded
                if ((totalImages - images.length) > 0)
                  for (int j = 0; j < ((totalImages - images.length) >= 2 ? 2 : 1); j++)
                    Positioned(
                      top: (images.length + j + 1) * 8,
                      left: isMe ? 0 : (images.length + j + 1) * 8,
                      right: isMe ? (images.length + j + 1) * 8 : 0,
                      child: Container(
                        height: cardH,
                        width: cardW,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(
                              blurRadius: 4,
                              spreadRadius: -2,
                              color: Colors.black26,
                            )
                          ],
                        ),
                      ),
                    ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Text(
                      (totalImages - images.length) > 0 ? '+${totalImages - images.length}' : '$totalImages',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _formatTime(anchorMsg.timestamp),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                )
              ],
            ),
          );
        },
      );
    }

    Widget grid;
    if (filledCount == 1) {
      print('📱 [RECEIVER COLLAGE BUILD] Using layout1 (single image)');
      grid = buildSlotTile(filledSlots[0]);
    } else {
      // ✅ Use layered book stack for 2+ images
      print('📱 [RECEIVER COLLAGE BUILD] Using layered book stack (${filledCount} images)');
      grid = layeredBookStack(imageUrls);
    }

    // ✅ OLD LAYOUT CODE REMOVED - Using layered book stack for all 2+ images

    //final userId = LocalAuthService.getUserId();
    //final bool isMe = anchorMsg.senderId == userId;
    final String time = _formatTime(anchorMsg.timestamp);
    final int remainingCount = totalImages - filledCount;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openImageFullScreen(anchorMsg),
      onLongPress: () => _showMessageOptions(anchorMsg),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.hardEdge,
        child: Container(
          width: maxWidth,
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: filledCount == 4
                ? ((maxWidth - 2) / 2 * 2) + 2
                : double.infinity,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            children: [
              grid,
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Text(
                    remainingCount > 0 ? '+$remainingCount' : '$totalImages',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        time,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      if (isMe) const SizedBox(width: 4),
                      if (isMe) _buildMessageTicks(anchorMsg),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCollageForMessages(List<Message> groupMessages, Message anchor) {
    // ✅ CRITICAL FIX: Ensure messages are sorted by imageIndex to maintain sender's sequence
    // ✅ APP RESTART FIX: Use stable sort with messageId as secondary key to ensure consistent ordering
    // Sort by imageIndex first, then by messageId as secondary key for absolute consistency
    groupMessages.sort((a, b) {
      final aIndex = a.imageIndex ?? -1;
      final bIndex = b.imageIndex ?? -1;

      // If both have imageIndex, sort by imageIndex first
      if (aIndex >= 0 && bIndex >= 0) {
        final indexCompare = aIndex.compareTo(bIndex);
        // ✅ CRITICAL: If imageIndex is same, use messageId for stable sorting (ensures same order on app restart)
        if (indexCompare != 0) {
          return indexCompare;
        }
        // ✅ Secondary sort by messageId to ensure consistent order even if imageIndex is duplicate
        return a.messageId.toString().compareTo(b.messageId.toString());
      }

      // If only one has imageIndex, prioritize it
      if (aIndex >= 0) return -1;
      if (bIndex >= 0) return 1;

      // If neither has imageIndex, sort by timestamp, then messageId for consistency
      final timestampCompare = a.timestamp.compareTo(b.timestamp);
      if (timestampCompare != 0) {
        return timestampCompare;
      }
      // ✅ Secondary sort by messageId for absolute consistency
      return a.messageId.toString().compareTo(b.messageId.toString());
    });

    final int count = groupMessages.length;
    // ✅ FIX: WhatsApp style - reduce width to prevent overflow (70% instead of 75%)
    final double maxWidth = MediaQuery.of(context).size.width * 0.70;

    Widget buildTile(Message m, {VoidCallback? onTap}) {
      final String url = m.messageContent;
      String? thumb = m.thumbnailBase64;
      if (thumb != null && thumb.isNotEmpty && thumb.contains(',')) {
        thumb = thumb.split(',').last.trim();
      }
      final bool isRemote = url.startsWith('http');
      final bool isLocal = !isRemote;

      // ✅ Orientation-aware rendering with thumbnail until dimensions resolve
      final ImageProvider provider = isLocal
          ? ResizeImage(
        FileImage(File(url)),
        width: 1200,
        height: 1200,
      )
          : ResizeImage(
        CachedNetworkImageProvider(url),
        width: 1200,
        height: 1200,
      );
      final imageWidget = OrientationAwareImage(
        provider: provider,
        thumbBase64: thumb,
      );

      return GestureDetector(
        onTap: onTap ?? () => _openImageFullScreen(m),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: imageWidget,
        ),
      );
    }

    // ✅ FIX: Proper collage layout for 1, 2, 3, 4, 5+ images like WhatsApp (auto-adjust)
    Widget grid;
    if (count == 1) {
      // ✅ 1 image - full width, no gaps
      grid = buildTile(groupMessages[0]);
    } else if (count == 2) {
      // ✅ 2 images - side by side (equal width)
      // ✅ FIX: Use fixed SizedBox instead of Expanded to prevent infinite height
      // ✅ FIX: Reduce width with safety margin to prevent overflow
      final double safetyMargin = 3.0; // Safety margin to prevent overflow
      final double tileWidth = (maxWidth - 2 - safetyMargin) / 2; // 2px gap + safety margin
      final double tileHeight = maxWidth * 0.66; // slightly taller for better presence
      grid = SizedBox(
        width: maxWidth,
        height: tileHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: tileWidth,
              height: tileHeight,
              child: buildTile(groupMessages[0]),
            ),
            const SizedBox(width: 2),
            SizedBox(
              width: tileWidth,
              height: tileHeight,
              child: buildTile(groupMessages[1]),
            ),
          ],
        ),
      );
    } else if (count == 3) {
      // ✅ 3 images - 1 large on left, 2 stacked on right (WhatsApp style)
      // ✅ FIX: Use fixed SizedBox instead of Expanded to prevent infinite height
      // ✅ FIX: Reduce width with larger safety margin to prevent overflow
      final double safetyMargin = 3.0; // Safety margin to prevent overflow
      final double leftWidth = (maxWidth - 2 - safetyMargin) * 2 / 3; // 2/3 width for left, minus gap and safety
      final double rightWidth = (maxWidth - 2 - safetyMargin) / 3; // 1/3 width for right, minus gap and safety
      final double leftHeight = maxWidth * 0.76; // slightly taller for better presence
      final double rightTileHeight = (leftHeight - 2) / 2; // Each right tile height

      grid = SizedBox(
        width: maxWidth,
        height: leftHeight,
        child: SizedBox(
          width: maxWidth, // ✅ FIX: Constrain Row width to prevent overflow
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: leftWidth,
                height: leftHeight,
                child: buildTile(groupMessages[0]),
              ),
              const SizedBox(width: 2),
              SizedBox(
                width: rightWidth,
                height: leftHeight,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: rightWidth,
                      height: rightTileHeight,
                      child: buildTile(groupMessages[1]),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      width: rightWidth,
                      height: rightTileHeight,
                      child: buildTile(groupMessages[2]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else if (count == 4) {
      // ✅ 4 images - 2x2 grid (WhatsApp style: width full, height adjusts to prevent overflow)
      // ✅ FIX: Calculate dimensions properly to prevent overflow - account for gaps
      // ✅ FIX: Reduce available width with larger safety margin to ensure no overflow
      final double gapWidth = 2.0; // Gap between images
      final double safetyMargin = 3.0; // Safety margin to prevent overflow (6.9px se zyada)
      final double availableWidth = maxWidth - gapWidth - safetyMargin; // Total width minus gap and safety margin
      final double tileWidth = availableWidth / 2; // Each tile gets half of available width
      // ✅ WhatsApp style: Square tiles for 2x2 grid (width = height)
      final double tileHeight = tileWidth; // Square tiles
      // ✅ FIX: Calculate total height to prevent overflow - account for gap
      final double gapHeight = 2.0; // Gap between rows
      final double totalHeight = (tileHeight * 2) + gapHeight; // 2 rows + 1 gap

      // ✅ FIX: Wrap in SizedBox with fixed dimensions to prevent overflow
      grid = SizedBox(
        width: maxWidth, // ✅ Fixed width to prevent right overflow
        height: totalHeight, // ✅ Fixed height to prevent bottom overflow
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: maxWidth, // ✅ FIX: Constrain Row width to prevent overflow
              height: tileHeight, // ✅ FIX: Constrain Row height
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: tileWidth,
                    height: tileHeight,
                    child: buildTile(groupMessages[0]),
                  ),
                  SizedBox(width: gapWidth),
                  SizedBox(
                    width: tileWidth,
                    height: tileHeight,
                    child: buildTile(groupMessages[1]),
                  ),
                ],
              ),
            ),
            SizedBox(height: gapHeight),
            SizedBox(
              width: maxWidth, // ✅ FIX: Constrain Row width to prevent overflow
              height: tileHeight, // ✅ FIX: Constrain Row height
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: tileWidth,
                    height: tileHeight,
                    child: buildTile(groupMessages[2]),
                  ),
                  SizedBox(width: gapWidth),
                  SizedBox(
                    width: tileWidth,
                    height: tileHeight,
                    child: buildTile(groupMessages[3]),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      // ✅ 5+ images - 2x2 grid with +N overlay on last tile (WhatsApp style)
      // ✅ FIX: Use fixed SizedBox instead of Expanded to prevent infinite height
      // ✅ FIX: Reduce width with larger safety margin to prevent overflow
      final double safetyMargin = 3.0; // Safety margin to prevent overflow
      final double tileWidth = (maxWidth - 2 - safetyMargin) / 2; // 2px gap + safety margin
      final double tileHeight = tileWidth; // Square tiles
      final double totalHeight = (tileHeight * 2) + 2; // 2 rows + 1 gap

      grid = SizedBox(
        width: maxWidth,
        height: totalHeight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: maxWidth, // ✅ FIX: Constrain Row width to prevent overflow
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: tileWidth,
                    height: tileHeight,
                    child: buildTile(groupMessages[0]),
                  ),
                  const SizedBox(width: 2),
                  SizedBox(
                    width: tileWidth,
                    height: tileHeight,
                    child: buildTile(groupMessages[1]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: maxWidth, // ✅ FIX: Constrain Row width to prevent overflow
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: tileWidth,
                    height: tileHeight,
                    child: buildTile(groupMessages[2]),
                  ),
                  const SizedBox(width: 2),
                  SizedBox(
                    width: tileWidth,
                    height: tileHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        buildTile(groupMessages[3]),
                        // ✅ Show +N overlay if more than 4 images
                        if (count > 4)
                          Container(
                            color: Colors.black54,
                            child: Center(
                              child: Text(
                                '+${count - 4}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final userId = LocalAuthService.getUserId();
    final bool isMe = anchor.senderId == userId;
    final String time = _formatTime(anchor.timestamp);

    // ✅ CRITICAL: Get upload progress for loading indicator (WhatsApp style)
    final tempId = anchor.messageId.toString();
    final uploadProgress = _uploadProgress[tempId];
    final isUploading = uploadProgress != null && uploadProgress < 100;

    return GestureDetector(
      // ✅ FIX: Only click on image itself, not surrounding space
        behavior: HitTestBehavior.opaque,
        onTap: () => _openImageFullScreen(anchor),
        // ✅ FIX: Long press on collage to show info (WhatsApp style)
        onLongPress: () => _showMessageOptions(anchor),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.hardEdge,
          child: Container(
            width: maxWidth, // ✅ FIX: Fixed width to prevent right overflow
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: count == 4
                  ? ((maxWidth - 2) / 2 * 2) + 2 // Exact height for 4 images
                  : double.infinity,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                // ✅ FIX: ClipRRect with InkWell for proper click area (only image area)
                InkWell(
                  onTap: () => _openImageFullScreen(anchor),
                  onLongPress: () => _showMessageOptions(anchor),
                  child: grid, // ✅ FIX: Grid already has proper sizing with SizedBox, no need for outer SizedBox
                ),
                // ✅ CRITICAL: WhatsApp-style loading indicator when uploading
                if (isMe && isUploading && uploadProgress != null)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              strokeWidth: 2,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${uploadProgress.toInt()}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                // ✅ FIX: Remove dots/bubble from collage - only show time (no ticks)
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      time,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w400),
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
    );
  }

  // ✅ CRITICAL: WhatsApp style progressive loading - Low quality FIRST, then high quality
  // ✅ FIXED: OPTIMIZED WHATSAPP-STYLE PROGRESSIVE IMAGE WIDGET WITH THUMBNAIL SUPPORT
  Widget _buildImageWithBlurHash(Message msg, String mediaUrl) {
    // ✅ CLEAN AND VALIDATE THUMBNAIL BASE64
    String? thumbnailBase64 = msg.thumbnailBase64?.trim();

    if (thumbnailBase64 != null && thumbnailBase64.isNotEmpty) {
      // Remove data URI prefix if present (e.g., "data:image/jpeg;base64,")
      if (thumbnailBase64.contains(',')) {
        thumbnailBase64 = thumbnailBase64.split(',').last.trim();
      }
    }

    final bool isRemote = mediaUrl.startsWith('http');
    final bool isLocal = !isRemote;

    // ✅ CRITICAL: WhatsApp style - Show INSTANT low quality preview, then thumbnail, then high quality
    if (isLocal) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(mediaUrl),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: 200,
            cacheHeight: 200,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              return child;
            },
          ),
          if (thumbnailBase64 != null && thumbnailBase64.isNotEmpty)
            Positioned.fill(
              child: Image.memory(
                base64Decode(thumbnailBase64),
                fit: BoxFit.cover,
                cacheWidth: 150,
                cacheHeight: 150,
                gaplessPlayback: true,
              ),
            ),
          OrientationAwareImage(
            provider: ResizeImage(
              FileImage(File(mediaUrl)),
              width: 800,
              height: 800,
            ),
            thumbBase64: thumbnailBase64,
            forcePortraitFitHeight: true,
          ),
        ],
      );
    }

    // ✅ Track image load for auto-hiding download button
    final messageId = msg.messageId.toString();
   // final isRemote = mediaUrl.startsWith('http');

    return OrientationAwareImage(
      provider: ResizeImage(
        CachedNetworkImageProvider(mediaUrl),
        width: 800,
        height: 800,
      ),
      thumbBase64: thumbnailBase64,
      forcePortraitFitHeight: true,
      onImageLoaded: isRemote ? () {
        // ✅ Mark image as loaded (auto-hide download button like WhatsApp)
        if (!_loadedImages.contains(messageId)) {
          _loadedImages.add(messageId);
          if (mounted) setState(() {});
          print("✅ [IMAGE LOADED] Image loaded for message $messageId - hiding download button");
        }
      } : null,
    );
  }


  Widget _buildLocalMediaPreview(String localPath, Message msg, bool isMe) {
    final tempId = msg.messageId.toString();
    final uploadProgress = _uploadProgress[tempId];
    final isUploading = uploadProgress != null && uploadProgress < 100;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => MediaViewerScreen(
              mediaUrl: localPath,
              messageId: 'local_preview',
              isLocalFile: true,
              chatId: widget.chatId,
            ),
          ),
        );
      },
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.65,
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.65,
                height: 300, // ✅ SAME HEIGHT MAINTAINED
                color: Colors.grey[300],
                child: Image.file(
                  File(localPath),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return _buildMediaError(localPath, error.toString());
                  },
                ),
              ),
            ),

            if (isUploading && uploadProgress != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${uploadProgress.toInt()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

            Positioned(
              bottom: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(msg.timestamp),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    if (isMe) const SizedBox(width: 4),
                    if (isMe)
                      _buildMessageTicks(msg, isUploading: isUploading),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageTicks(Message msg, {bool isUploading = false}) {
    if (isUploading) {
      return Icon(
        Icons.access_time,
        size: 12,
        color: Colors.grey[300],
      );
    }

    if (msg.isRead == 1) {
      return const Icon(
        Icons.done_all,
        size: 12,
        color: Colors.blue,
      );
    } else if (msg.isDelivered == 1) {
      return const Icon(
        Icons.done_all,
        size: 12,
        color: Colors.grey,
      );
    } else {
      return const Icon(
        Icons.done,
        size: 12,
        color: Colors.grey,
      );
    }
  }

  // ✅ DOWNLOAD FUNCTION - Download image to local storage (WhatsApp style)
  Future<void> _downloadImage(Message msg, String imageUrl) async {
    final messageId = msg.messageId.toString();
    
    // Check if already downloading
    if (_downloadingMessages.contains(messageId)) {
      print("⚠️ Image $messageId is already being downloaded");
      return;
    }
    
    // Check if already downloaded
    if (_downloadedMessages.contains(messageId)) {
      print("✅ Image $messageId is already downloaded");
      return;
    }
    
    try {
      // Mark as downloading
      _downloadingMessages.add(messageId);
      _downloadProgress[messageId] = 0.0;
      if (mounted) setState(() {});
      
      print("⬇️ Starting download for message $messageId from $imageUrl");
      
      // Get downloads directory
      final directory = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${directory.path}/downloads');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      
      // Generate filename
      final uri = Uri.parse(imageUrl);
      final filename = uri.pathSegments.last;
      final ext = filename.contains('.') ? filename.substring(filename.lastIndexOf('.')) : '.jpg';
      final downloadPath = '${downloadDir.path}/${messageId}$ext';
      
      // Download file with progress tracking
      final request = http.Request('GET', Uri.parse(imageUrl));
      final streamedResponse = await http.Client().send(request);
      
      if (streamedResponse.statusCode == 200) {
        final contentLength = streamedResponse.contentLength ?? 0;
        final file = File(downloadPath);
        final sink = file.openWrite();
        int downloaded = 0;
        
        await streamedResponse.stream.listen(
          (chunk) {
            sink.add(chunk);
            downloaded += chunk.length;
            if (contentLength > 0 && mounted) {
              final progress = (downloaded / contentLength * 100).clamp(0.0, 100.0);
              _downloadProgress[messageId] = progress;
              setState(() {});
            }
          },
          onDone: () async {
            await sink.close();
            
            // Update message with local path
            msg.messageContent = downloadPath; // Update to local path
            await _messageBox.put(msg.messageId, msg);
            
            // Mark as downloaded
            _downloadedMessages.add(messageId);
            _downloadingMessages.remove(messageId);
            _downloadProgress.remove(messageId);
            
            print("✅ Image downloaded successfully: $downloadPath");
            
            if (mounted) {
              setState(() {
                _needsRefresh = true;
              });
            }
          },
          onError: (error) {
            sink.close();
            throw error;
          },
          cancelOnError: true,
        ).asFuture();
      } else {
        throw Exception('Failed to download: ${streamedResponse.statusCode}');
      }
    } catch (e) {
      print("❌ Download error for $messageId: $e");
      _downloadingMessages.remove(messageId);
      _downloadProgress.remove(messageId);
      if (mounted) setState(() {});
      
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: ${e.toString()}')),
        );
      }
    }
  }
  
  // ✅ CANCEL DOWNLOAD FUNCTION
  void _cancelDownload(String messageId) {
    _downloadingMessages.remove(messageId);
    _downloadProgress.remove(messageId);
    if (mounted) setState(() {});
    print("❌ Download cancelled for $messageId");
  }

  // ✅ BUILD DOWNLOAD CONTROLS (Download arrow, Loading, Cancel button - WhatsApp style - CENTERED)
  Widget _buildDownloadControls(Message msg, String mediaUrl) {
    final messageId = msg.messageId.toString();
    final isDownloading = _downloadingMessages.contains(messageId);
    // Check if already downloaded (not a remote URL or file exists locally)
    final isDownloaded = _downloadedMessages.contains(messageId) || 
                        (!mediaUrl.startsWith('http') && File(mediaUrl).existsSync());
    // ✅ Check if image is fully loaded/cached (auto-hide download button like WhatsApp)
    final isImageLoaded = _loadedImages.contains(messageId);
    final downloadProgress = _downloadProgress[messageId] ?? 0.0;
    
    // ✅ WhatsApp style: Hide download button if image is downloaded OR fully loaded
    if (isDownloaded || isImageLoaded) {
      return const SizedBox.shrink(); // Completely hide like WhatsApp
    }
    
    // ✅ WhatsApp style: Center the download button in the middle of image
    // ✅ FIX: Allow image tap even when downloading (open full screen like WhatsApp)
    return Positioned.fill(
      child: Stack(
        children: <Widget>[
          // ✅ Transparent tap area for opening full screen (even while downloading)
          GestureDetector(
            onTap: () {
              // ✅ Always allow opening full screen (like WhatsApp)
              _openImageFullScreen(msg);
            },
            child: Container(
              color: Colors.transparent,
            ),
          ),
          // ✅ Download button overlay (only responds to center tap)
          Center(
            child: GestureDetector(
              onTap: () {
                if (isDownloading) {
                  // Cancel download
                  _cancelDownload(messageId);
                } else if (!isDownloaded) {
                  // Start download
                  _downloadImage(msg, mediaUrl);
                }
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  shape: BoxShape.circle,
                ),
                child: isDownloading
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        // Circular progress indicator
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            value: downloadProgress > 0 ? downloadProgress / 100 : null,
                            strokeWidth: 3,
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        // Cancel button (cross icon)
                        const Icon(
                          Icons.close,
                          size: 18,
                          color: Colors.white,
                        ),
                      ],
                    )
                  : isDownloaded
                      ? const Icon(
                          Icons.download_done,
                          size: 28,
                          color: Colors.white,
                        )
                  : const Icon(
                      Icons.download,
                      size: 28,
                      color: Colors.white,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    // ✅ FIX: 12-hour format with AM/PM
    int hour = timestamp.hour;
    int minute = timestamp.minute;
    String period = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
  }

  Widget _buildMediaError(String url, String error) {
    return Container(
      color: Colors.grey[300],
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image, color: Colors.grey, size: 40),
          SizedBox(height: 8),
          Text(
            'Image',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ✅ IMPLEMENTED: UNREAD MESSAGE SEPARATOR BUBBLE
  Widget _buildUnreadSeparator() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text('New Messages', style: TextStyle(fontSize: 12)),
      ),
    );
  }

  Widget _buildDateHeader(String date) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFDCF8C6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        date,
        style: const TextStyle(
            color: Colors.black87,
            fontSize: 12,
            fontWeight: FontWeight.w500
        ),
      ),
    );
  }

  Widget _buildEncryptionNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(
          top: BorderSide(color: Colors.grey[300]!),
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 14, color: Colors.grey),
          const SizedBox(width: 8),
          Text(
            'Messages and calls are end-to-end encrypted',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    if (_imageFile == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              _imageFile!,
              width: 100,
              height: 100,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              onTap: () => setState(() => _imageFile = null),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Column(
      children: [
        // ✅ REPLY PREVIEW
        _buildReplyPreview(),

        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.grey[100],
          child: Row(
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 100),
                  padding: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        onPressed: () {},
                        icon: Icon(Icons.emoji_emotions_outlined, color: Colors.grey[600]),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          autofocus: false,
                          maxLines: null,
                          onChanged: (_) => _startTyping(),
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: "Type a message...",
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      // ✅ FIX: Add camera option alongside gallery
                      PopupMenuButton<String>(
                        icon: Icon(Icons.add_circle_outline, color: Colors.grey[600]),
                        onSelected: (value) async {
                          if (value == 'gallery') {
                            _openMultiPicker();
                          } else if (value == 'camera') {
                            await _pickImageFromCamera();
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'camera',
                            child: Row(
                              children: [
                                Icon(Icons.camera_alt, color: Colors.grey),
                                SizedBox(width: 8),
                                Text('Camera'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'gallery',
                            child: Row(
                              children: [
                                Icon(Icons.photo_library, color: Colors.grey),
                                SizedBox(width: 8),
                                Text('Gallery'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: const Color(0xFF075E54),
                child: IconButton(
                  onPressed: _isSending ? null : _sendMessage,
                  icon: const Icon(Icons.send, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ✅ FORWARD SELECTED MESSAGES
  Future<void> _forwardSelectedMessages() async {
    if (selectedMessageIds.isEmpty) return;

    final targetChatId = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewChatPage(isForForwarding: true),
      ),
    );

    if (targetChatId != null && targetChatId is int) {
      final messageIdsForForwarding = selectedMessageIds
          .map((id) => int.tryParse(id) ?? 0)
          .where((id) => id != 0)
          .toSet();

      await ChatService.forwardMessages(
        originalMessageIds: messageIdsForForwarding,
        targetChatId: targetChatId,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Forwarded ${selectedMessageIds.length} messages")),
      );

      setState(() {
        selectedMessageIds.clear();
        _selectionMode = false;
      });
    }
  }

  // ✅ DELETE SELECTED MESSAGES
  void _deleteSelectedMessages() {
    if (selectedMessageIds.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Messages?"),
        content: Text("Are you sure you want to delete ${selectedMessageIds.length} messages?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _performDeleteSelected();
            },
            child: const Text("DELETE", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _performDeleteSelected() {
    final userId = LocalAuthService.getUserId();
    if (userId == null) return;

    for (final messageId in selectedMessageIds) {
      ChatService.deleteMessage(
        messageId: messageId,
        userId: userId,
        role: 'sender', // Adjust based on your logic
      );
    }

    setState(() {
      _selectionMode = false;
      selectedMessageIds.clear();
      _needsRefresh = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Deleted ${selectedMessageIds.length} messages")),
    );
  }

  Future<void> _forwardSingleMessage(String messageId) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewChatPage(isForForwarding: true),
      ),
    );

    if (result != null && result is Map) {
      final targetChatId = result['chatId'] as int;

      await ChatService.forwardMessages(
        originalMessageIds: {int.parse(messageId)},
        targetChatId: targetChatId,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Message forwarded!")),
      );
    }
  }

  Future<void> _showDeleteConfirmation(String messageId) async {
    final message = _messageBox.values.firstWhereOrNull((m) => m.messageId == messageId);
    if (message == null) return;

    final userId = LocalAuthService.getUserId();
    final isMe = message.senderId == userId;

    final String deleteRole = isMe ? 'sender' : 'receiver';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Message?"),
        content: Text(
          isMe
              ? "Are you sure you want to delete this message for everyone?"
              : "Are you sure you want to delete this message for yourself?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("CANCEL"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("DELETE", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (result == true) {
      if (userId == null) return;

      await ChatService.deleteMessage(
        messageId: messageId,
        userId: userId,
        role: deleteRole,
      );

      setState(() {
        selectedMessageIds.clear();
        _needsRefresh = true;
      });
    }
  }

  // ✅ HELPER FUNCTION FOR UNREAD SEPARATOR
  int _getUnreadStartIndex(List<Message> messages) {
    for (int i = 0; i < messages.length; i++) {
      if (messages[i].isRead == 0) {
        return i;
      }
    }
    return -1;
  }

  @override
  @override
  Widget build(BuildContext context) {
    final titleText =
    _resolvedTitle.isNotEmpty ? _resolvedTitle : widget.otherUserName;
    final initial =
    titleText.isNotEmpty ? titleText[0].toUpperCase() : 'U';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFF075E54),
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.grey[300],
              child: Text(
                initial,
                style: const TextStyle(color: Color(0xFF075E54)),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleText,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _isOtherUserTyping
                        ? 'Typing...'
                        : (_userStatus == "online"
                        ? "online"
                        : "offline"),
                    style: TextStyle(
                      fontSize: 12,
                      color: _isOtherUserTyping || _userStatus == "online"
                          ? Colors.greenAccent
                          : Colors.white.withOpacity(0.7),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.videocam, color: Colors.white),
              onPressed: () {}),
          IconButton(
              icon: const Icon(Icons.call, color: Colors.white),
              onPressed: () {}),
          if (selectedMessageIds.isNotEmpty &&
              selectedMessageIds.length == 1 &&
              _hasTextMessagesSelected())
            IconButton(
              icon: const Icon(Icons.copy, color: Colors.white),
              onPressed: _copySelectedMessages,
            ),
          if (selectedMessageIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.forward, color: Colors.white),
              onPressed: _forwardSelectedMessages,
            ),
          if (selectedMessageIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.white),
              onPressed: _deleteSelectedMessages,
            ),
          IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onPressed: () {}),
        ],
      ),

      body: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (_focusNode.hasFocus) _focusNode.unfocus();
              if (_selectionMode) _clearSelection();
            },
            child: Container(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/chat_bg.png'),
                  fit: BoxFit.cover,
                ),
              ),
              child: Column(
                children: [
                  _buildEncryptionNotice(),

                  /// 🔥 COLLAGE + MESSAGE LIST
                  Expanded(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _collageVersionNotifier,
                      builder: (context, _, __) {
                        return ValueListenableBuilder<Box<Message>>(
                          valueListenable: _messageBox.listenable(),
                          builder: (context, box, __) {
                            final messages = _getOptimizedMessages();

                            if (messages.isEmpty) {
                              return const Center(
                                child:
                                Text("Say hi to start the conversation!"),
                              );
                            }

                            WidgetsBinding.instance
                                .addPostFrameCallback((_) {
                              if (_shouldScrollToBottom &&
                                  _hasInitialScrollDone) {
                                _scrollToBottomSmooth();
                              }
                            });

                            return ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(8),
                              itemCount:
                              messages.length + (_isLoadingMore ? 1 : 0),
                              physics:
                              const ClampingScrollPhysics(),
                              itemBuilder: (context, index) {
                                if (_isLoadingMore && index == 0) {
                                  return const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                    ),
                                  );
                                }

                                final adjustedIndex =
                                _isLoadingMore ? index - 1 : index;
                                if (adjustedIndex >= messages.length) {
                                  return const SizedBox.shrink();
                                }

                                final msg = messages[adjustedIndex];
                                // ✅ DEBUG: Log when rendering message in list
                                final hasGroupId = (msg.groupId ?? '').isNotEmpty;
                                if (hasGroupId) {
                                  print('🔍 [LIST RENDER] Rendering message ${msg.messageId} in list at index $adjustedIndex, groupId=${msg.groupId}, imageIndex=${msg.imageIndex}');
                                }
                                return _buildMessageBubble(
                                  msg,
                                  key: _getMessageKey(msg),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),

                  _buildImagePreview(),
                  _buildInputArea(),
                ],
              ),
            ),
          ),

          _buildFloatingScrollButton(),
          _buildSelectionBottomBar(),
        ],
      ),
    );
  }

}

class SingleImageBubble extends StatefulWidget {
  final Message msg;
  final String mediaUrl;
  final bool isMe;
  final VoidCallback? onImageLoaded; // ✅ Callback when image loads
  const SingleImageBubble({Key? key, required this.msg, required this.mediaUrl, required this.isMe, this.onImageLoaded}) : super(key: key);
  @override
  State<SingleImageBubble> createState() => _SingleImageBubbleState();
}

class _SingleImageBubbleState extends State<SingleImageBubble> {
  bool _resolved = false;
  bool _isVertical = false;
  bool _isSquare = false;
  double _imgW = 0.0;
  double _imgH = 0.0;
  @override
  void initState() {
    super.initState();
    if (widget.mediaUrl.startsWith('http')) {
      final provider = CachedNetworkImageProvider(widget.mediaUrl);
      final stream = provider.resolve(const ImageConfiguration());
      ImageStreamListener? listener;
      listener = ImageStreamListener((info, _) {
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        _isVertical = h > w;
        _isSquare = h == w;
        _imgW = w;
        _imgH = h;
        if (mounted) {
          setState(() {
            _resolved = true;
          });
          // ✅ Notify parent that image is loaded (auto-hide download button)
          widget.onImageLoaded?.call();
        }
        stream.removeListener(listener!);
      }, onError: (error, stack) {
        stream.removeListener(listener!);
      });
      stream.addListener(listener);
    } else {
      final provider = FileImage(File(widget.mediaUrl));
      final stream = provider.resolve(const ImageConfiguration());
      ImageStreamListener? listener;
      listener = ImageStreamListener((info, _) {
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        _isVertical = h > w;
        _isSquare = h == w;
        _imgW = w;
        _imgH = h;
        if (mounted) {
          setState(() {
            _resolved = true;
          });
          // ✅ Notify parent that image is loaded (auto-hide download button)
          widget.onImageLoaded?.call();
        }
        stream.removeListener(listener!);
      }, onError: (error, stack) {
        stream.removeListener(listener!);
      });
      stream.addListener(listener);
    }
  }
  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final maxWidth = screen.width * 0.70;
    double height;
    if (_imgW > 0 && _imgH > 0) {
      final aspect = _imgH / _imgW;
      final calcHeight = maxWidth * aspect;
      final maxHeight = screen.height * 0.55;
      height = _isVertical
          ? calcHeight > maxHeight ? maxHeight : calcHeight
          : calcHeight;
      if (height < 120.0) height = 120.0;
    } else {
      height = screen.height * 0.40;
    }
    final msg = widget.msg;
    String? thumbnailBase64 = msg.thumbnailBase64?.trim();
    if (thumbnailBase64 != null && thumbnailBase64.isNotEmpty && thumbnailBase64.contains(',')) {
      thumbnailBase64 = thumbnailBase64.split(',').last.trim();
    }
    final isRemote = widget.mediaUrl.startsWith('http');
    if (!isRemote) {
      final Alignment align = _isSquare ? Alignment.center : (_isVertical ? Alignment.topCenter : Alignment.center);
      final BoxFit fitMode = _isSquare ? BoxFit.contain : (_isVertical ? BoxFit.fitWidth : BoxFit.fitHeight);
      return Container(
        width: maxWidth,
        height: height,
        color: Colors.transparent,
        child: Image.file(
          File(widget.mediaUrl),
          fit: fitMode,
          alignment: align,
        ),
      );
    } else {
      final Alignment align = _isSquare ? Alignment.center : (_isVertical ? Alignment.topCenter : Alignment.center);
      final BoxFit fitMode = _isSquare ? BoxFit.contain : (_isVertical ? BoxFit.fitWidth : BoxFit.fitHeight);
      return Container(
        width: maxWidth,
        height: height,
        color: Colors.transparent,
        child: CachedNetworkImage(
          imageUrl: widget.mediaUrl,
          memCacheWidth: 1200,
          memCacheHeight: 1200,
          maxWidthDiskCache: 1600,
          maxHeightDiskCache: 1600,
          imageBuilder: (context, imageProvider) {
            // ✅ Notify parent that image is loaded (auto-hide download button)
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.onImageLoaded?.call();
            });
            return Image(
            image: imageProvider,
            fit: fitMode,
            alignment: align,
            width: maxWidth,
            height: height,
            );
          },
          placeholder: (context, url) {
            if (thumbnailBase64 != null && thumbnailBase64.isNotEmpty) {
              try {
                final bytes = base64Decode(thumbnailBase64);
                return Image.memory(
                  bytes,
                  fit: fitMode,
                  alignment: align,
                  width: maxWidth,
                  height: height,
                  gaplessPlayback: true,
                  cacheWidth: 300,
                  cacheHeight: 300,
                );
              } catch (_) {}
            }
            return Container(color: Colors.transparent);
          },
          errorWidget: (context, url, error) {
            if (thumbnailBase64 != null && thumbnailBase64.isNotEmpty) {
              try {
                final bytes = base64Decode(thumbnailBase64);
                return Image.memory(
                  bytes,
                  fit: fitMode,
                  alignment: align,
                  width: maxWidth,
                  height: height,
                  gaplessPlayback: true,
                  cacheWidth: 300,
                  cacheHeight: 300,
                );
              } catch (_) {}
            }
            return const Center(child: Icon(Icons.broken_image, color: Colors.grey));
          },
        ),
      );
    }
  }
}
