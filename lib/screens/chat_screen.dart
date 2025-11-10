import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;

import '../config.dart';
import '../models/chat_model.dart';
import '../services/chat_service.dart';
import '../services/local_auth_service.dart';
import '../services/contact_service.dart';
import 'multi_image_picker_screen.dart';
import 'new_chat_page.dart';
import 'media_viewer_screen.dart';

// ✅ THUMBNAIL CACHE MANAGEMENT
Future<String> getThumbnailCachePath(String imagePath) async {
  final cacheDir = await getTemporaryDirectory();
  final thumbsDir = Directory(p.join(cacheDir.path, "thumbs"));
  if (!thumbsDir.existsSync()) thumbsDir.createSync(recursive: true);

  final fileName = p.basenameWithoutExtension(imagePath);
  final thumbPath = p.join(thumbsDir.path, "${fileName}_thumb.jpg");
  return thumbPath;
}

Future<Uint8List> generateSenderThumbnail(String imagePath) async {
  try {
    final file = File(imagePath);
    if (!file.existsSync()) return Uint8List(0);

    final cachePath = await getThumbnailCachePath(imagePath);
    final cachedFile = File(cachePath);
    if (cachedFile.existsSync()) {
      return await cachedFile.readAsBytes();
    }

    final bytes = await file.readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) return bytes;

    final thumbnail = img.copyResize(original, width: 200);
    final compressedBytes = Uint8List.fromList(img.encodeJpg(thumbnail, quality: 50));

    await cachedFile.writeAsBytes(compressedBytes);
    return compressedBytes;
  } catch (e) {
    return Uint8List(0);
  }
}

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
  StreamSubscription? _groupUploadCompleteSubscription;

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

  // ✅ DUPLICATE PROTECTION
  final Set<String> _processedMessageIds = {};

  // ✅ UPLOAD PROGRESS TRACKING
  final Map<String, double> _uploadProgress = {};

  // ✅ FIXED: PERSISTENT LOADING STATES
  final Map<String, int> _imageLoadStages = {};
  final Map<String, Timer> _loadTimers = {};
  final Set<String> _fullyLoadedMessages = {};

  // ✅ LOAD MORE MESSAGES
  DateTime _oldestMessageTime = DateTime.now();
  bool _hasMoreMessages = true;

  // ✅ MULTIPLE IMAGES UPLOAD TRACKING
  final Map<String, List<String>> _groupUploads = {};
  final Map<String, int> _groupUploadProgress = {};

  // ✅ CRITICAL FIX: FORCE UI REFRESH COUNTER
  int _forceRefreshCounter = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _scrollController = ScrollController(
      keepScrollOffset: true,
    );

    _initializeChat();
    _restoreScrollPosition();
  }

  // ✅ CRITICAL FIX: BETTER CHAT INITIALIZATION
  void _initializeChat() {
    print("🚀 INITIALIZING CHAT SCREEN FOR CHAT ID: ${widget.chatId}");

    ChatService.initSocket();
    ChatService.ensureConnected();

    _lastReadMessageId = int.tryParse(_authBox.get('lastReadMessageId_${widget.chatId}', defaultValue: '0').toString()) ?? 0;

    _scrollController.addListener(() {
      _updateScrollToBottomPreference();
      _updateLastReadMessageId();
      _updateFloatingButtonVisibility();

      if (_scrollController.offset <= _scrollController.position.minScrollExtent + 200 &&
          _hasMoreMessages &&
          !_isLoadingMore) {
        _loadMoreMessages();
      }
    });

    // ✅ CRITICAL FIX: BETTER NEW MESSAGE LISTENER
    _newMessageSubscription = ChatService.onNewMessage.listen((Message msg) {
      print("📨 NEW MESSAGE RECEIVED IN CHATSCREEN: ${msg.messageId} for chat: ${msg.chatId}");

      if (!mounted) return;

      // ✅ ONLY PROCESS MESSAGES FOR CURRENT CHAT
      if (msg.chatId == widget.chatId) {
        print("✅ PROCESSING MESSAGE FOR CURRENT CHAT: ${msg.messageId}");

        if (_processedMessageIds.contains(msg.messageId)) {
          print("⚠️ DUPLICATE MESSAGE BLOCKED: ${msg.messageId}");
          return;
        }

        _processedMessageIds.add(msg.messageId);
        Future.delayed(const Duration(seconds: 30), () {
          _processedMessageIds.remove(msg.messageId);
        });

        // ✅ CRITICAL FIX: FORCE UI REFRESH IMMEDIATELY
        _forceUIRefresh();

        // ✅ AUTO SCROLL TO BOTTOM FOR NEW MESSAGES
        if (_isAtBottom) {
          _scrollToBottomSmooth();
        }

        // ✅ RESOLVE HEADER IF NEEDED
        _resolveHeader();

        // ✅ START PROGRESSIVE LOADING FOR MEDIA
        if ((msg.messageType == 'media' || msg.messageType == 'encrypted_media') &&
            !_fullyLoadedMessages.contains(msg.messageId)) {
          _startProgressiveLoading(msg);
        }
      }
    });

    // ✅ UPLOAD PROGRESS LISTENER
    _uploadProgressSubscription = ChatService.onUploadProgress.listen((progressData) {
      if (!mounted) return;

      final tempId = progressData['tempId'];
      final progress = progressData['progress'];

      if (tempId != null) {
        setState(() {
          if (progress >= 0) {
            _uploadProgress[tempId] = progress;
          } else {
            _uploadProgress.remove(tempId);
          }
        });
      }
    });

    // ✅ MESSAGE DELIVERED LISTENER
    _messageDeliveredSubscription = ChatService.onMessageDelivered.listen((messageId) {
      if (!mounted) return;
      _forceUIRefresh();
    });

    // ✅ GROUP UPLOAD COMPLETE LISTENER
    _groupUploadCompleteSubscription = ChatService.onGroupUploadComplete.listen((data) {
      if (!mounted) return;

      final groupId = data['group_id'];
      final uploadedImages = data['uploaded_images'];
      final totalImages = data['total_images'];

      print("🎉 Group upload completed: $groupId ($uploadedImages/$totalImages)");

      setState(() {
        _groupUploadProgress[groupId] = 100;
      });
    });

    // ✅ TYPING STATUS LISTENER
    _typingSubscription = ChatService.onTypingStatus.listen((typingInfo) {
      if (!mounted) return;

      if (typingInfo['chatId'] == widget.chatId && typingInfo['userId'] != LocalAuthService.getUserId()) {
        setState(() {
          _isOtherUserTyping = typingInfo['isTyping'] ?? false;
        });
      }
    });

    // ✅ USER STATUS LISTENER
    _statusSubscription = ChatService.onUserStatus.listen((statusInfo) {
      if (!mounted) return;

      if (statusInfo['userId'] == widget.otherUserId.toString()) {
        setState(() {
          _userStatus = statusInfo['status'] ?? "offline";
        });
      }
    });

    _focusNode.addListener(() {
      if (!mounted) return;

      if (_focusNode.hasFocus) {
        setState(() {
          _isKeyboardOpen = true;
        });
        if (_shouldScrollToBottom) {
          _scrollToBottomSmooth();
        }
      } else {
        setState(() {
          _isKeyboardOpen = false;
        });
      }
    });

    // ✅ INITIAL DATA LOAD
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadInitialData();
      }
    });
  }

  // ✅ CRITICAL FIX: BETTER INITIAL DATA LOADING
  void _loadInitialData() async {
    print("🔄 LOADING INITIAL DATA FOR CHAT...");

    ChatService.joinRoom(widget.chatId);

    if (!_areMessagesLoaded) {
      await _fetchMessages();
    } else {
      if (mounted) setState(() {});
    }

    await _resolveHeader();

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToBottomSmooth();
        _isFirstLoad = false;
        _hasInitialScrollDone = true;
      }
    });
  }

  // ✅ CRITICAL FIX: FORCE UI REFRESH METHOD
  void _forceUIRefresh() {
    if (!mounted) return;

    print("🔄 FORCING UI REFRESH...");
    setState(() {
      _needsRefresh = true;
      _forceRefreshCounter++; // This forces ValueListenableBuilder to rebuild
    });
  }

  bool get _areMessagesLoaded {
    return _authBox.get('messages_loaded_${widget.chatId}', defaultValue: false) ?? false;
  }

  set _areMessagesLoaded(bool value) {
    _authBox.put('messages_loaded_${widget.chatId}', value);
  }

  // ✅ CRITICAL FIX: BETTER MESSAGE FETCHING
  List<Message> _getOptimizedMessages() {
    // ✅ ALWAYS REFRESH IF NEEDED
    if (_needsRefresh || _cachedMessages.isEmpty) {
      final messages = _messageBox.values
          .where((msg) => msg.chatId == widget.chatId)
          .where((msg) => !msg.messageId.toString().startsWith('temp_') ||
          (msg.messageId.toString().startsWith('temp_') && msg.messageType == 'media'))
          .toList();

      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      _cachedMessages = messages;
      _needsRefresh = false;

      print("📊 MESSAGES LOADED: ${_cachedMessages.length} messages");
    }

    return _cachedMessages;
  }

  void _scrollToBottomSmooth() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _shouldScrollToBottom) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

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

  void _updateScrollToBottomPreference() {
    if (!_scrollController.hasClients) return;

    final double currentOffset = _scrollController.offset;
    final double maxOffset = _scrollController.position.maxScrollExtent;

    setState(() {
      _isAtBottom = (maxOffset - currentOffset) <= _scrollThreshold;
      _shouldScrollToBottom = _isAtBottom;
    });

    _saveScrollPosition();
  }

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
    print("🔌 DISPOSING CHAT SCREEN...");
    WidgetsBinding.instance.removeObserver(this);
    _stopTyping();
    _focusNode.unfocus();
    _focusNode.dispose();
    _typingTimer?.cancel();

    // ✅ CRITICAL FIX: PROPER STREAM CLEANUP
    _typingSubscription?.cancel();
    _statusSubscription?.cancel();
    _newMessageSubscription?.cancel();
    _uploadProgressSubscription?.cancel();
    _messageDeliveredSubscription?.cancel();
    _groupUploadCompleteSubscription?.cancel();
    _updateTimer?.cancel();

    _loadTimers.forEach((key, timer) => timer.cancel());
    _loadTimers.clear();

    _saveScrollPosition();

    _scrollController.dispose();
    _processedMessageIds.clear();
    _uploadProgress.clear();
    _imageLoadStages.clear();
    _fullyLoadedMessages.clear();
    _groupUploads.clear();
    _groupUploadProgress.clear();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final bottomInset = WidgetsBinding.instance.window.viewInsets.bottom;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (bottomInset > 0.0 && _focusNode.hasFocus && _shouldScrollToBottom) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _jumpToBottom() {
    if (!_scrollController.hasClients) return;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _shouldScrollToBottom) {
        try {
          final maxScroll = _scrollController.position.maxScrollExtent;
          if (maxScroll > 0) {
            _scrollController.jumpTo(maxScroll);
          }
        } catch (e) {
          print("Scroll error: $e");
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

  void _startProgressiveLoading(Message msg) {
    final messageId = msg.messageId;

    if (_fullyLoadedMessages.contains(messageId)) {
      _imageLoadStages[messageId] = 3;
      return;
    }

    if (_imageLoadStages.containsKey(messageId)) {
      return;
    }

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

  void _handleSwipeStart(DragStartDetails details, Message message) {
    if (_selectionMode) return;
    _swipeMessage = message;
    _isSwiping = true;
  }

  void _handleSwipeUpdate(DragUpdateDetails details) {
    if (!_isSwiping || _selectionMode) return;

    _swipeOffset += details.delta.dx;

    if (_swipeOffset > 0) {
      _swipeOffset = _swipeOffset.clamp(0.0, 100.0);
    } else {
      _swipeOffset = 0.0;
    }

    setState(() {});
  }

  void _handleSwipeEnd(DragEndDetails details) {
    if (!_isSwiping || _selectionMode) return;

    if (_swipeOffset > 60) {
      _startReply(_swipeMessage!);
      HapticFeedback.lightImpact();
    }

    _swipeOffset = 0.0;
    _isSwiping = false;
    _swipeMessage = null;
    setState(() {});
  }

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
          _scrollToBottom();
          HapticFeedback.lightImpact();
        },
        child: const Icon(Icons.arrow_downward, color: Colors.white, size: 20),
      ),
    );
  }

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

  Widget _buildSelectionBottomBar() {
    if (!_selectionMode) return const SizedBox.shrink();

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF075E54),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _clearSelection,
          ),
          Text(
            "${selectedMessageIds.length}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          Row(
            children: [
              if (_hasTextMessagesSelected())
                IconButton(
                  icon: const Icon(Icons.copy, color: Colors.white),
                  onPressed: _copySelectedMessages,
                ),
              IconButton(
                icon: const Icon(Icons.forward, color: Colors.white),
                onPressed: _forwardSelectedMessages,
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.white),
                onPressed: _deleteSelectedMessages,
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _hasTextMessagesSelected() {
    for (final messageId in selectedMessageIds) {
      final message = _messageBox.values.firstWhereOrNull((m) => m.messageId == messageId);
      if (message != null && message.messageType == 'text') {
        return true;
      }
    }
    return false;
  }

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
          backgroundColor: const Color(0xFF075E54),
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

  void _copySingleMessage(String messageId) {
    final message = _messageBox.values.firstWhereOrNull((m) => m.messageId == messageId);
    if (message != null && message.messageType == 'text') {
      Clipboard.setData(ClipboardData(text: message.messageContent));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Message copied"),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF075E54),
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

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) return;

    setState(() => _isLoadingMore = true);

    try {
      final currentScroll = _scrollController.offset;
      final messages = _getOptimizedMessages();

      if (messages.isNotEmpty) {
        _oldestMessageTime = messages.first.timestamp;

        await Future.delayed(const Duration(milliseconds: 500));

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

  // ✅ CRITICAL FIX: BETTER MESSAGE FETCHING
  Future<void> _fetchMessages() async {
    try {
      print("🔄 FETCHING MESSAGES FOR CHAT ${widget.chatId}...");

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

    } catch (e) {
      print("❌ Fetch messages error: $e");
      setState(() {
        _areMessagesLoaded = true;
        _needsRefresh = true;
      });
    }
  }

  // ✅ CRITICAL FIX: BETTER INCOMING DATA HANDLING
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
      String? lowQualityUrl = data["low_quality_url"]?.toString();
      String? highQualityUrl = data["high_quality_url"]?.toString();
      String? blurHash = data["blur_hash"]?.toString();
      String? thumbnailBase64 = data["thumbnail_data"]?.toString() ?? data["thumbnail"]?.toString();
      String? replyToMessageId = data["reply_to_message_id"]?.toString();
      bool isForwarded = data["is_forwarded"] == true || data["is_forwarded"] == 1;
      String? forwardedFrom = data["forwarded_from"]?.toString();

      // ✅ EXTRACT GROUP DATA FOR MULTIPLE IMAGES
      final String? groupId = data["group_id"]?.toString();
      final int imageIndex = data["image_index"] ?? 0;
      final int totalImages = data["total_images"] ?? 1;

      mediaUrl = _convertToFullUrl(mediaUrl);
      lowQualityUrl = _convertToFullUrl(lowQualityUrl);
      highQualityUrl = _convertToFullUrl(highQualityUrl);

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
        lowQualityUrl: lowQualityUrl,
        highQualityUrl: highQualityUrl,
        blurHash: blurHash,
        thumbnailBase64: thumbnailBase64,
        replyToMessageId: replyToMessageId,
        isForwarded: isForwarded,
        forwardedFrom: forwardedFrom,
        extraData: groupId != null ? {
          'groupId': groupId,
          'imageIndex': imageIndex,
          'totalImages': totalImages,
        } : null,
      );

      await ChatService.saveMessageLocal(msg);

      if (messageType == 'media' && mounted && !_fullyLoadedMessages.contains(msg.messageId)) {
        _startProgressiveLoading(msg);
      }

      // ✅ CRITICAL FIX: FORCE UI REFRESH AFTER SAVING
      _forceUIRefresh();

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
      MaterialPageRoute(
        builder: (context) => MediaViewerScreen(
          mediaUrl: message.messageContent,
          messageId: message.messageId,
          isLocalFile: isLocalFile,
          chatId: widget.chatId,
        ),
      ),
    );
  }

  // ✅ OPTIMIZED THUMBNAIL IMAGE BUILDER WITH CACHE
  Future<Widget> _buildCachedThumbnailImage(String imagePath, Message msg, {BorderRadius borderRadius = BorderRadius.zero, double? height}) async {
    final thumbPath = await getThumbnailCachePath(imagePath);
    final cachedFile = File(thumbPath);

    if (cachedFile.existsSync()) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Container(
          height: height,
          color: Colors.grey[300],
          child: Image.file(cachedFile, fit: BoxFit.cover),
        ),
      );
    } else {
      final newThumb = await generateSenderThumbnail(imagePath);
      await cachedFile.writeAsBytes(newThumb);
      return ClipRRect(
        borderRadius: borderRadius,
        child: Container(
          height: height,
          color: Colors.grey[300],
          child: Image.memory(newThumb, fit: BoxFit.cover),
        ),
      );
    }
  }

  // 🧠 Main collage entry point with thumbnail support
  Widget _buildMultipleImagesPreview(
      Message msg,
      List<String> imageUrls,
      bool isMe,
      bool isUploading,
      double? uploadProgress,
      ) {
    final totalImages = imageUrls.length;

    return GestureDetector(
      onTap: () {
        if (imageUrls.isNotEmpty) {
          _openImageFullScreen(msg);
        }
      },
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.70,
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (totalImages == 1)
              _collageItem(imageUrls[0], msg)
            else if (totalImages == 2)
              _buildTwoImageCollage(imageUrls, msg)
            else if (totalImages == 3)
                _buildThreeImageCollage(imageUrls, msg)
              else if (totalImages == 4)
                  _buildFourImageCollage(imageUrls, msg)
                else
                  _buildGridCollage(imageUrls, msg),

            const SizedBox(height: 6),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          ],
        ),
      ),
    );
  }

  Widget _buildTwoImageCollage(List<String> urls, Message msg) {
    return Row(
      children: [
        Expanded(
          child: _collageItem(urls[0], msg),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: _collageItem(urls[1], msg),
        ),
      ],
    );
  }

  Widget _buildThreeImageCollage(List<String> urls, Message msg) {
    return Column(
      children: [
        _collageItem(urls[0], msg, heightFactor: 0.6),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: _collageItem(urls[1], msg, heightFactor: 0.8),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: _collageItem(urls[2], msg, heightFactor: 0.8),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFourImageCollage(List<String> urls, Message msg) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _collageItem(urls[0], msg, heightFactor: 0.8),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: _collageItem(urls[1], msg, heightFactor: 0.8),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: _collageItem(urls[2], msg, heightFactor: 0.8),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: _collageItem(urls[3], msg, heightFactor: 0.8),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGridCollage(List<String> urls, Message msg) {
    final totalImages = urls.length;
    final displayImages = urls.take(4).toList();
    final remaining = totalImages - 4;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _collageItem(displayImages[0], msg, heightFactor: 0.8),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: _collageItem(displayImages[1], msg, heightFactor: 0.8),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: _collageItem(displayImages[2], msg, heightFactor: 0.8),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Stack(
                children: [
                  _collageItem(displayImages[3], msg, heightFactor: 0.8),
                  if (remaining > 0)
                    Container(
                      color: Colors.black54,
                      child: Center(
                        child: Text(
                          "+$remaining",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _collageItem(String url, Message msg, {double heightFactor = 1.0}) {
    return AspectRatio(
      aspectRatio: heightFactor,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _buildCachedImage(url, msg),
      ),
    );
  }

  Widget _buildCachedImage(String imageUrl, Message msg) {
    final isLocalFile = imageUrl.startsWith('/') ||
        imageUrl.startsWith('file://') ||
        File(imageUrl).existsSync();

    if (isLocalFile) {
      return FutureBuilder<Widget>(
        future: _buildCachedThumbnailImage(imageUrl, msg),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return snapshot.data ?? _imageErrorPlaceholder();
          }
          return _imageLoadingPlaceholder();
        },
      );
    } else {
      return _buildNetworkImage(imageUrl);
    }
  }

  Widget _imageErrorPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: const Icon(Icons.photo, color: Colors.grey, size: 40),
    );
  }

  Widget _imageLoadingPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _buildNetworkImage(String imageUrl) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) => _imageLoadingPlaceholder(),
      errorWidget: (context, url, error) => _imageErrorPlaceholder(),
    );
  }

  // ✅ SINGLE IMAGE PICKER - MODIFIED: DIRECT SEND
  Future<void> _pickSingleImage() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1080,
        maxHeight: 1920,
      );

      if (pickedFile != null) {
        // ✅ DIRECTLY SEND THE IMAGE WITHOUT SHOWING PREVIEW
        await _sendSingleImageDirectly(File(pickedFile.path));
      }
    } catch (e) {
      print("Error picking single image: $e");
    }
  }

  // ✅ NEW METHOD: DIRECT SINGLE IMAGE SENDING
  Future<void> _sendSingleImageDirectly(File imageFile) async {
    if (_isSending) return;

    setState(() {
      _isSending = true;
      _shouldScrollToBottom = true;
    });

    try {
      _jumpToBottom();

      // ✅ CRITICAL: FORCE UI REFRESH BEFORE SENDING
      _forceUIRefresh();

      await ChatService.sendMediaMessage(
        chatId: widget.chatId,
        receiverId: widget.otherUserId,
        mediaPath: imageFile.path,
        senderName: _authBox.get('userName'),
        receiverName: _resolvedTitle.isNotEmpty ? _resolvedTitle : widget.otherUserName,
        senderPhoneNumber: _authBox.get('userPhone'),
        receiverPhoneNumber: _otherUserPhone ?? _authBox.get('otherUserPhone'),
        replyToMessageId: _replyingToMessage?.messageId,
      );

      setState(() {
        _replyingToMessage = null;
      });

      _resolveHeader();

      // ✅ CRITICAL: FORCE FINAL UI REFRESH
      _forceUIRefresh();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpToBottom();
      });

    } catch (e) {
      print("Error sending single image directly: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send image')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  // ✅ MULTIPLE IMAGE PICKER - UPDATED FOR NEW API
  Future<void> _pickMultipleImages() async {
    try {
      final List<File>? selectedImages = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MultiImagePickerScreen(
            chatId: widget.chatId,
            receiverId: widget.otherUserId,
            maxSelection: 10,
          ),
        ),
      );

      if (selectedImages != null && selectedImages.isNotEmpty) {
        await _sendMultipleImagesWithNewAPI(selectedImages);
      }
    } catch (e) {
      print("Error in multiple image picker: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to pick images')),
      );
    }
  }

  // ✅ CRITICAL FIX: BETTER MULTIPLE IMAGES SENDING
  Future<void> _sendMultipleImagesWithNewAPI(List<File> imageFiles) async {
    setState(() {
      _isSending = true;
      _shouldScrollToBottom = true;
    });

    try {
      // ✅ CRITICAL: FORCE UI REFRESH BEFORE SENDING
      _forceUIRefresh();

      await ChatService.sendMultipleMediaMessages(
        chatId: widget.chatId,
        receiverId: widget.otherUserId,
        mediaPaths: imageFiles.map((file) => file.path).toList(),
        senderName: _authBox.get('userName'),
        receiverName: _resolvedTitle.isNotEmpty ? _resolvedTitle : widget.otherUserName,
        senderPhoneNumber: _authBox.get('userPhone'),
        receiverPhoneNumber: _otherUserPhone ?? _authBox.get('otherUserPhone'),
      );

      print("✅ Multiple images sent via PARALLEL API: ${imageFiles.length} images");

      // ✅ CRITICAL: FORCE UI REFRESH AFTER SENDING
      _forceUIRefresh();

    } catch (e) {
      print("❌ Error sending multiple images: $e");
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  // ✅ TAKE PHOTO FROM CAMERA - MODIFIED: DIRECT SEND
  Future<void> _takePhoto() async {
    try {
      final XFile? pickedFile = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 75,
        maxWidth: 1080,
        maxHeight: 1920,
      );

      if (pickedFile != null) {
        // ✅ DIRECTLY SEND THE PHOTO WITHOUT SHOWING PREVIEW
        await _sendSingleImageDirectly(File(pickedFile.path));
      }
    } catch (e) {
      print("Error taking photo: $e");
    }
  }

  // ✅ CRITICAL FIX: BETTER SEND MESSAGE WITH INSTANT UI UPDATE
  Future<void> _sendMessage() async {
    if (_isSending) {
      return;
    }

    String text = _controller.text.trim();
    if (text.isEmpty && _imageFile == null) return;

    _stopTyping();

    setState(() {
      _isSending = true;
      _shouldScrollToBottom = true;
    });

    try {
      if (_imageFile != null) {
        _jumpToBottom();

        // ✅ CRITICAL: FORCE UI REFRESH BEFORE SENDING
        _forceUIRefresh();

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

        setState(() {
          _imageFile = null;
          _replyingToMessage = null;
        });
      } else {
        // ✅ CRITICAL: FORCE UI REFRESH BEFORE SENDING TEXT
        _forceUIRefresh();

        await ChatService.sendMessage(
          chatId: widget.chatId,
          receiverId: widget.otherUserId,
          messageContent: text,
          messageType: 'text',
          senderName: _authBox.get('userName'),
          receiverName: _resolvedTitle.isNotEmpty ? _resolvedTitle : widget.otherUserName,
          senderPhoneNumber: _authBox.get('userPhone'),
          receiverPhoneNumber: _otherUserPhone ?? _authBox.get('otherUserPhone'),
          replyToMessageId: _replyingToMessage?.messageId,
        );

        _controller.clear();
        setState(() {
          _replyingToMessage = null;
        });
      }

      _resolveHeader();

      // ✅ CRITICAL: FORCE FINAL UI REFRESH
      _forceUIRefresh();

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

  // ✅ UPDATED MESSAGE BUBBLE WITH COLLAGE SUPPORT
  Widget _buildMessageBubble(Message msg, {Key? key}) {
    final String msgId = msg.messageId.toString();
    final bool isSelected = selectedMessageIds.contains(msgId);
    final userId = LocalAuthService.getUserId();
    final bool isMe = msg.senderId == userId;

    final bool isMediaMessage = msg.messageType == 'media' ||
        msg.messageType == 'encrypted_media' ||
        (msg.lowQualityUrl != null && msg.lowQualityUrl!.isNotEmpty) ||
        (msg.highQualityUrl != null && msg.highQualityUrl!.isNotEmpty);

    // ✅ REAL MULTIPLE IMAGES DETECTION
    final imageUrls = _getImageUrlsFromMessage(msg);
    final bool hasMultipleImages = imageUrls.length > 1;

    // ✅ CHECK IF THIS IS FIRST MESSAGE IN GROUP (to avoid duplicates)
    final bool shouldShowMessage = _shouldShowMessageInGroup(msg);

    // ✅ IF NOT FIRST IN GROUP, RETURN EMPTY (WhatsApp behavior)
    if (!shouldShowMessage && hasMultipleImages) {
      return const SizedBox.shrink();
    }

    if (msg.messageId.toString().startsWith('temp_') && isMediaMessage) {
      return _buildMediaMessageBubble(msg, isMe: isMe, isSelected: isSelected);
    }

    if ((isMe && msg.isDeletedSender == 1) || (!isMe && msg.isDeletedReceiver == 1)) {
      return const SizedBox.shrink();
    }

    final color = isMe ? const Color(0xFFDCF8C6) : Colors.white;
    final selectedColor = isMe ? const Color(0xFFC5E1A5) : const Color(0xFFE0E0E0);
    final textColor = Colors.black;

    final bool contentDeleted = !isMe && msg.isDeletedSender == 1;
    final String content = contentDeleted ? '❌ This message was deleted' : msg.messageContent;

    final borderRadius = BorderRadius.only(
      topLeft: isMe ? const Radius.circular(16) : const Radius.circular(2),
      topRight: isMe ? const Radius.circular(2) : const Radius.circular(16),
      bottomLeft: const Radius.circular(16),
      bottomRight: const Radius.circular(16),
    );

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
                color: isSelected ? selectedColor : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
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
                        color: isSelected ? selectedColor : color,
                        borderRadius: borderRadius,
                        boxShadow: isSelected ? [] : [
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
                              style: TextStyle(
                                  color: Colors.red[800],
                                  fontSize: 14,
                                  fontStyle: FontStyle.italic
                              ),
                            )

                          else if (msg.messageType == 'text' && !isMediaMessage)
                            Text(
                                content,
                                style: TextStyle(color: textColor, fontSize: 16)
                            )

                          else if (isMediaMessage)
                              hasMultipleImages && imageUrls.length > 1
                                  ? _buildMultipleImagesPreview(msg, imageUrls, isMe, false, null)
                                  : _buildSingleMediaMessage(msg, msg.messageContent, textColor, isMe)

                            else
                              Text(
                                content.isNotEmpty ? content : "📎 Attachment",
                                style: TextStyle(color: textColor, fontSize: 16),
                              ),

                          // ✅ TIMESTAMP FOR ALL MESSAGES
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatTime(msg.timestamp),
                                style: TextStyle(
                                  color: isSelected ? Colors.black87 : Colors.black54,
                                  fontSize: 11,
                                ),
                              ),
                              if (isMe) const SizedBox(width: 4),
                              if (isMe)
                                _buildMessageTicks(msg),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ✅ SELECTION CHECKBOX
                  if (_selectionMode)
                    Positioned(
                      top: 12,
                      left: isMe ? null : 12,
                      right: isMe ? 12 : null,
                      child: GestureDetector(
                        onTap: () => _toggleSelection(msgId),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF075E54) : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? const Color(0xFF075E54) : Colors.grey,
                              width: 2,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, size: 16, color: Colors.white)
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

  // ✅ SINGLE MEDIA MESSAGE (For non-collage images)
  Widget _buildSingleMediaMessage(Message msg, String mediaUrl, Color textColor, bool isMe) {
    final tempId = msg.messageId.toString();
    final uploadProgress = _uploadProgress[tempId];
    final isUploading = uploadProgress != null && uploadProgress < 100;

    final isLocalFile = mediaUrl.startsWith('/') ||
        mediaUrl.startsWith('file://') ||
        mediaUrl.contains('cache/') ||
        mediaUrl.contains('temp_') ||
        File(mediaUrl).existsSync();

    return GestureDetector(
      onTap: () => _openImageFullScreen(msg),
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
                height: 300,
                color: Colors.transparent,
                child: isLocalFile
                    ? FutureBuilder<Widget>(
                  future: _buildCachedThumbnailImage(mediaUrl, msg),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.done) {
                      return snapshot.data ?? _imageErrorPlaceholder();
                    }
                    return _imageLoadingPlaceholder();
                  },
                )
                    : _buildWhatsAppStyleImage(msg, mediaUrl),
              ),
            ),

            if (isMe && isUploading && uploadProgress != null)
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

  // ✅ COMPLETE MULTIPLE IMAGES DETECTION
  List<String> _getImageUrlsFromMessage(Message msg) {
    final groupData = _getMessageGroupData(msg);
    if (groupData != null) {
      return _getGroupImageUrls(groupData['groupId'], groupData['totalImages']);
    }

    final consecutiveGroup = _getConsecutiveImageGroup(msg);
    if (consecutiveGroup.length > 1) {
      return consecutiveGroup.map((m) => m.messageContent).toList();
    }

    return [msg.messageContent];
  }

  bool _hasMultipleImages(Message msg) {
    return _getImageUrlsFromMessage(msg).length > 1;
  }

  Map<String, dynamic>? _getMessageGroupData(Message msg) {
    if (msg.extraData != null && msg.extraData!.isNotEmpty) {
      try {
        final data = (msg.extraData!);
        if (data['groupId'] != null) {
          return {
            'groupId': data['groupId'],
            'imageIndex': data['imageIndex'] ?? 0,
            'totalImages': data['totalImages'] ?? 1,
          };
        }
      } catch (e) {
        print("Error parsing group data: $e");
      }
    }
    return null;
  }

  List<String> _getGroupImageUrls(String groupId, int totalImages) {
    final messages = _getOptimizedMessages();
    final List<String> urls = [];

    for (int i = 0; i < totalImages; i++) {
      final messageId = '${groupId}_$i';
      final message = messages.firstWhereOrNull((m) => m.messageId == messageId);
      if (message != null) {
        urls.add(message.messageContent);
      }
    }

    return urls;
  }

  List<Message> _getConsecutiveImageGroup(Message currentMsg) {
    final messages = _getOptimizedMessages();
    final currentIndex = messages.indexOf(currentMsg);
    final List<Message> group = [currentMsg];

    if (currentIndex == -1) return group;

    for (int i = currentIndex - 1; i >= 0; i--) {
      final prevMsg = messages[i];
      if (_isImageMessage(prevMsg) &&
          currentMsg.timestamp.difference(prevMsg.timestamp).inMinutes <= 2 &&
          prevMsg.senderId == currentMsg.senderId) {
        group.insert(0, prevMsg);
      } else {
        break;
      }
    }

    for (int i = currentIndex + 1; i < messages.length; i++) {
      final nextMsg = messages[i];
      if (_isImageMessage(nextMsg) &&
          nextMsg.timestamp.difference(currentMsg.timestamp).inMinutes <= 2 &&
          nextMsg.senderId == currentMsg.senderId) {
        group.add(nextMsg);
      } else {
        break;
      }
    }

    return group;
  }

  bool _isImageMessage(Message msg) {
    return msg.messageType == 'media' ||
        msg.messageType == 'encrypted_media' ||
        msg.messageContent.contains('.jpg') ||
        msg.messageContent.contains('.png') ||
        msg.messageContent.contains('.jpeg') ||
        (msg.messageContent.startsWith('/') && File(msg.messageContent).existsSync());
  }

  bool _shouldShowMessageInGroup(Message msg) {
    if (!_hasMultipleImages(msg)) return true;

    final group = _getConsecutiveImageGroup(msg);
    if (group.isEmpty) return true;

    return group.first.messageId == msg.messageId;
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

  // ✅ SHOW MESSAGE OPTIONS
  void _showMessageOptions(Message msg) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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

  // ✅ MEDIA MESSAGE BUBBLE
  Widget _buildMediaMessageBubble(Message msg, {required bool isMe, required bool isSelected}) {
    final color = isMe ? const Color(0xFFDCF8C6) : Colors.white;
    final selectedColor = isMe ? const Color(0xFFC5E1A5) : const Color(0xFFE0E0E0);

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
              _enterSelectionMode(msg.messageId);
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? selectedColor : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              children: [
                Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    padding: const EdgeInsets.all(6),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? selectedColor : color,
                      borderRadius: BorderRadius.only(
                        topLeft: isMe ? const Radius.circular(16) : const Radius.circular(2),
                        topRight: isMe ? const Radius.circular(2) : const Radius.circular(16),
                        bottomLeft: const Radius.circular(16),
                        bottomRight: const Radius.circular(16),
                      ),
                      boxShadow: isSelected ? [] : [
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
                        if (msg.replyToMessageId != null && msg.replyToMessageId!.isNotEmpty)
                          _buildReplyInMessage(msg),

                        _buildSingleMediaMessage(msg, msg.messageContent, Colors.black, isMe),
                      ],
                    ),
                  ),
                ),

                if (_selectionMode)
                  Positioned(
                    top: 12,
                    left: isMe ? null : 12,
                    right: isMe ? 12 : null,
                    child: GestureDetector(
                      onTap: () => _toggleSelection(msg.messageId),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF075E54) : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? const Color(0xFF075E54) : Colors.grey,
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, size: 16, color: Colors.white)
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

  // ✅ OPTIMIZED WHATSAPP-STYLE PROGRESSIVE IMAGE WIDGET
  Widget _buildWhatsAppStyleImage(Message msg, String mediaUrl) {
    final isNetworkImage = mediaUrl.startsWith('http');

    if (!isNetworkImage) {
      return FutureBuilder<Widget>(
        future: _buildCachedThumbnailImage(mediaUrl, msg),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return snapshot.data ?? _imageErrorPlaceholder();
          }
          return _imageLoadingPlaceholder();
        },
      );
    }

    final messageId = msg.messageId;
    final loadStage = _imageLoadStages[messageId] ?? 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_imageLoadStages[messageId] == null &&
          !_fullyLoadedMessages.contains(messageId) &&
          (msg.messageType == 'media' || msg.messageType == 'encrypted_media')) {
        _startProgressiveLoading(msg);
      }
    });

    return Stack(
      children: [
        if (msg.blurHash != null && msg.blurHash!.isNotEmpty && loadStage < 2)
          Positioned.fill(
            child: Container(
              color: Colors.grey[200],
              child: BlurHash(
                hash: msg.blurHash!,
                imageFit: BoxFit.cover,
              ),
            ),
          ),

        if (loadStage >= 1)
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: msg.lowQualityUrl ?? mediaUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) {
                return msg.blurHash != null
                    ? BlurHash(hash: msg.blurHash!, imageFit: BoxFit.cover)
                    : _imageLoadingPlaceholder();
              },
              errorWidget: (context, url, error) {
                _loadHighQualityImage(msg);
                return _imageErrorPlaceholder();
              },
              imageBuilder: (context, imageProvider) {
                if (loadStage == 1) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _markLowQualityLoaded(msg);
                  });
                }
                return Image(image: imageProvider, fit: BoxFit.cover);
              },
            ),
          ),

        if (loadStage >= 3)
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: msg.highQualityUrl ?? mediaUrl,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 300),
              placeholder: (context, url) => Container(),
              imageBuilder: (context, imageProvider) {
                return AnimatedOpacity(
                  opacity: 1.0,
                  duration: const Duration(milliseconds: 400),
                  child: Image(image: imageProvider, fit: BoxFit.cover),
                );
              },
            ),
          ),

        if ((loadStage == 1 || loadStage == 3) && !_fullyLoadedMessages.contains(messageId))
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            ),
          ),
      ],
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

  String _formatTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  // ✅ UNREAD MESSAGE SEPARATOR BUBBLE
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

  // ❌ REMOVED IMAGE PREVIEW WIDGET SINCE WE DON'T NEED IT ANYMORE
  Widget _buildImagePreview() {
    return const SizedBox.shrink(); // Always return empty widget
  }

  // ✅ UPDATED INPUT AREA WITH MULTIPLE IMAGE OPTIONS
  Widget _buildInputArea() {
    return Column(
      children: [
        _buildReplyPreview(),

        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.grey[100],
          child: Row(
            children: [
              IconButton(
                onPressed: _takePhoto,
                icon: Icon(Icons.camera_alt, color: Colors.grey[600]),
              ),

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

                      PopupMenuButton<String>(
                        icon: Icon(Icons.attach_file, color: Colors.grey[600]),
                        onSelected: (value) {
                          if (value == 'gallery_multiple') {
                            _pickMultipleImages();
                          } else if (value == 'gallery_single') {
                            _pickSingleImage(); // This will now directly send the image
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'gallery_multiple',
                            child: Row(
                              children: [
                                Icon(Icons.photo_library, color: Colors.green),
                                SizedBox(width: 8),
                                Text('Gallery (Multiple)'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'gallery_single',
                            child: Row(
                              children: [
                                Icon(Icons.photo, color: Colors.blue),
                                SizedBox(width: 8),
                                Text('Single Image'),
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
        role: 'sender',
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

  int _getUnreadStartIndex(List<Message> messages) {
    for (int i = 0; i < messages.length; i++) {
      if (messages[i].isRead == 0) {
        return i;
      }
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final titleText = _resolvedTitle.isNotEmpty ? _resolvedTitle : widget.otherUserName;
    final initial = titleText.isNotEmpty ? titleText[0].toUpperCase() : 'U';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: _selectionMode ? const Color(0xFF075E54) : const Color(0xFF075E54),
        elevation: 1,
        leading: _selectionMode
            ? IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: _clearSelection,
        )
            : IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: _selectionMode
            ? Text(
          "${selectedMessageIds.length}",
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        )
            : Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.grey[300],
              child: Text(initial, style: const TextStyle(color: Color(0xFF075E54))),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleText,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _isOtherUserTyping
                        ? 'Typing...'
                        : (_userStatus == "online" ? "online" : "offline"),
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
        actions: _selectionMode
            ? [
          if (_hasTextMessagesSelected())
            IconButton(
              icon: const Icon(Icons.copy, color: Colors.white),
              onPressed: _copySelectedMessages,
            ),
          IconButton(
            icon: const Icon(Icons.forward, color: Colors.white),
            onPressed: _forwardSelectedMessages,
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.white),
            onPressed: _deleteSelectedMessages,
          ),
        ]
            : [
          IconButton(icon: const Icon(Icons.videocam, color: Colors.white), onPressed: () {}),
          IconButton(icon: const Icon(Icons.call, color: Colors.white), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_vert, color: Colors.white), onPressed: () {}),
        ],
      ),
      body: Stack(
        children: [
          GestureDetector(
            onTap: () {
              if (_focusNode.hasFocus) {
                _focusNode.unfocus();
              }
              if (_selectionMode) {
                _clearSelection();
              }
            },
            behavior: HitTestBehavior.translucent,
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
                  Expanded(
                    child: ValueListenableBuilder<Box<Message>>(
                      valueListenable: _messageBox.listenable(),
                      builder: (context, box, child) {
                        // ✅ CRITICAL FIX: USE FORCE REFRESH COUNTER TO TRIGGER REBUILDS
                        final messages = _getOptimizedMessages();

                        print("🔄 VALUE LISTENABLE BUILDER REBUILDING: ${messages.length} messages, counter: $_forceRefreshCounter");

                        if (messages.isEmpty) {
                          return const Center(child: Text("Say hi to start the conversation!"));
                        }

                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_shouldScrollToBottom && _hasInitialScrollDone) {
                            _scrollToBottomSmooth();
                          }
                        });

                        return ListView.builder(
                          controller: _scrollController,
                          reverse: false,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.all(8),
                          itemCount: messages.length + (_isLoadingMore ? 1 : 0),
                          cacheExtent: 2000,
                          itemBuilder: (context, index) {
                            if (_isLoadingMore && index == 0) {
                              return const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                              );
                            }

                            final adjustedIndex = _isLoadingMore ? index - 1 : index;
                            if (adjustedIndex >= messages.length) return const SizedBox.shrink();

                            final msg = messages[adjustedIndex];
                            final previousMsg = adjustedIndex > 0 ? messages[adjustedIndex - 1] : null;
                            final currentDate = formatDateHeader(msg.timestamp);
                            final previousDate = previousMsg != null
                                ? formatDateHeader(previousMsg.timestamp)
                                : null;

                            if (adjustedIndex == _getUnreadStartIndex(messages)) {
                              return Column(
                                children: [
                                  _buildUnreadSeparator(),
                                  if (previousDate != currentDate)
                                    _buildDateHeader(currentDate),
                                  _buildMessageBubble(msg, key: ValueKey(msg.messageId)),
                                ],
                              );
                            }

                            if (previousDate != currentDate) {
                              return Column(
                                children: [
                                  _buildDateHeader(currentDate),
                                  _buildMessageBubble(msg, key: ValueKey(msg.messageId)),
                                ],
                              );
                            }

                            return _buildMessageBubble(msg, key: ValueKey(msg.messageId));
                          },
                        );
                      },
                    ),
                  ),
                  _buildImagePreview(), // This will always return SizedBox.shrink() now
                  if (!_selectionMode) _buildInputArea(),
                ],
              ),
            ),
          ),

          _buildFloatingScrollButton(),

          if (_selectionMode)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildSelectionBottomBar(),
            ),
        ],
      ),
    );
  }
}