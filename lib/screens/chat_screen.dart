import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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

  bool _isKeyboardOpen = false;
  bool _isFirstLoad = true;
  bool _shouldScrollToBottom = true;
  bool _hasInitialScrollDone = false;

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

  // ✅ PERMANENT FIX: Use Hive to store loaded status
  bool get _areMessagesLoaded {
    return _authBox.get('messages_loaded_${widget.chatId}', defaultValue: false) ?? false;
  }

  set _areMessagesLoaded(bool value) {
    _authBox.put('messages_loaded_${widget.chatId}', value);
  }

  // ✅ API BASE URL
  static const String apiBase = "http://184.168.126.71/api";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _scrollController = ScrollController(keepScrollOffset: true);

    ChatService.initSocket();
    ChatService.ensureConnected();

    _lastReadMessageId = int.tryParse(_authBox.get('lastReadMessageId_${widget.chatId}', defaultValue: '0').toString()) ?? 0;

    // ✅ IMMEDIATE SCROLL TO BOTTOM ON INIT
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _jumpToBottom();
      }
    });

    Future.delayed(const Duration(milliseconds: 50), () async {
      ChatService.joinRoom(widget.chatId);

      if (!_areMessagesLoaded) {
        await _fetchMessages();
      } else {
        print("✅ Using previously loaded messages for chat ${widget.chatId}");
        if (mounted) setState(() {});
      }

      await _resolveHeader();

      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _jumpToBottom();
          _isFirstLoad = false;
        }
      });
      _hasInitialScrollDone = true;
    });

    // ✅ FIXED: STRONG DUPLICATE PROTECTION IN NEW MESSAGE LISTENER
    _newMessageSubscription = ChatService.onNewMessage.listen((msg) async {
      if (mounted && msg.chatId == widget.chatId) {
        if (_processedMessageIds.contains(msg.messageId)) {
          print("⚠️ DUPLICATE BLOCKED in UI: ${msg.messageId}");
          return;
        }

        _processedMessageIds.add(msg.messageId);

        Future.delayed(const Duration(seconds: 30), () {
          _processedMessageIds.remove(msg.messageId);
        });

        final existingMessage = _messageBox.values.firstWhereOrNull(
              (existingMsg) => existingMsg.messageId == msg.messageId && existingMsg.chatId == widget.chatId,
        );

        if (existingMessage == null) {
          print("💾 New message from socket: ${msg.messageId}");
          print("📸 Low quality URL available: ${msg.lowQualityUrl != null && msg.lowQualityUrl!.isNotEmpty}");
          print("🎨 BlurHash available: ${msg.blurHash != null && msg.blurHash!.isNotEmpty}");
          print("🖼️ Thumbnail Base64 available: ${msg.thumbnailBase64 != null && msg.thumbnailBase64!.isNotEmpty}");

          // ✅ AUTO-START PROGRESSIVE LOADING FOR NEW MESSAGES
          _startProgressiveLoading(msg);

          await _resolveHeader();
          if (_shouldScrollToBottom) {
            _jumpToBottom();
          }
        } else {
          print("⚠️ Duplicate message from socket: ${msg.messageId}");
        }
      }
    });

    // ✅ UPLOAD PROGRESS LISTENER
    _uploadProgressSubscription = ChatService.onUploadProgress.listen((progressData) {
      final tempId = progressData['tempId'];
      final progress = progressData['progress'];

      if (mounted && tempId != null) {
        setState(() {
          if (progress >= 0) {
            _uploadProgress[tempId] = progress;
          } else {
            _uploadProgress.remove(tempId);
          }
        });
      }
    });

    // ✅ MESSAGE DELIVERED LISTENER - FOR TICKS UPDATE
    _messageDeliveredSubscription = ChatService.onMessageDelivered.listen((messageId) {
      if (mounted) {
        print("✅ Message delivered update: $messageId");
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

    _scrollController.addListener(() {
      _updateLastReadMessageId();
      _updateScrollToBottomPreference();

      if (_scrollController.offset <= _scrollController.position.minScrollExtent + 100) {
        _loadMoreMessages();
      }
    });

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        setState(() {
          _isKeyboardOpen = true;
        });
      } else {
        setState(() {
          _isKeyboardOpen = false;
        });
      }
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

    // ✅ CLEANUP LOADING TIMERS
    _loadTimers.forEach((key, timer) => timer.cancel());
    _loadTimers.clear();

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
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ✅ IMPROVED JUMP TO BOTTOM - WHATSAPP STYLE
  void _jumpToBottom() {
    if (!_scrollController.hasClients) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
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

  void _updateScrollToBottomPreference() {
    if (!_scrollController.hasClients) return;
    final double currentOffset = _scrollController.offset;
    final double maxOffset = _scrollController.position.maxScrollExtent;
    final double threshold = 100.0;

    setState(() {
      _shouldScrollToBottom = (maxOffset - currentOffset) <= threshold;
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

    final messages = _messageBox.values
        .where((msg) => msg.chatId == widget.chatId)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

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

    // ✅ CHECK IF MESSAGE IS ALREADY FULLY LOADED
    if (_fullyLoadedMessages.contains(messageId)) {
      print("✅ Message already fully loaded: $messageId");
      _imageLoadStages[messageId] = 3; // Mark as high quality loaded
      return;
    }

    // ✅ CHECK IF ALREADY LOADING
    if (_imageLoadStages.containsKey(messageId)) {
      print("⚠️ Already loading: $messageId");
      return;
    }

    print("🚀 Starting WhatsApp-style loading: $messageId");
    print("   - BlurHash: ${msg.blurHash != null ? 'Available' : 'Not Available'}");
    print("   - Low Quality URL: ${msg.lowQualityUrl ?? 'Not Available'}");
    print("   - High Quality URL: ${msg.highQualityUrl ?? 'Not Available'}");

    // Start with stage 1 (low quality loading)
    _imageLoadStages[messageId] = 1;

    // Auto-load high quality after low quality is visible
    _loadTimers[messageId] = Timer(const Duration(milliseconds: 800), () {
      if (_imageLoadStages[messageId] == 2 && mounted) {
        _loadHighQualityImage(msg);
      }
    });

    if (mounted) setState(() {});
  }

  void _markLowQualityLoaded(Message msg) {
    final messageId = msg.messageId;
    print("✅ Low quality loaded: $messageId");
    _imageLoadStages[messageId] = 2;

    if (mounted) setState(() {});
  }

  void _loadHighQualityImage(Message msg) {
    final messageId = msg.messageId;

    if (_imageLoadStages[messageId] == 3) return;

    print("🔄 Loading high quality: $messageId");
    _imageLoadStages[messageId] = 3;

    // ✅ MARK AS FULLY LOADED ONCE HIGH QUALITY LOADS
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fullyLoadedMessages.add(messageId);
        setState(() {});
      }
    });

    if (mounted) setState(() {});
  }

  // ✅ FIXED: WHATSAPP-STYLE PROGRESSIVE IMAGE WIDGET WITH PERSISTENCE
  Widget _buildWhatsAppStyleImage(Message msg, String mediaUrl) {
    final messageId = msg.messageId;
    final loadStage = _imageLoadStages[messageId] ?? 0;

    // ✅ FIX: ONLY START LOADING IF NOT ALREADY LOADED
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_imageLoadStages[messageId] == null &&
          !_fullyLoadedMessages.contains(messageId) &&
          (msg.messageType == 'media' || msg.messageType == 'encrypted_media')) {
        _startProgressiveLoading(msg);
      }
    });

    return Stack(
      children: [
        // ✅ 1. BLUR HASH - INSTANT (0ms) - ONLY SHOW IF LOW QUALITY NOT LOADED
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

        // ✅ 2. LOW QUALITY IMAGE - FAST (100-500ms)
        if (loadStage >= 1)
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: msg.lowQualityUrl ?? mediaUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) {
                // Show blur hash while low quality loads
                return msg.blurHash != null
                    ? BlurHash(hash: msg.blurHash!, imageFit: BoxFit.cover)
                    : Container(color: Colors.grey[300]);
              },
              errorWidget: (context, url, error) {
                // If low quality fails, load high quality directly
                _loadHighQualityImage(msg);
                return Container(color: Colors.grey[300]);
              },
              imageBuilder: (context, imageProvider) {
                // Low quality loaded successfully
                if (loadStage == 1) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _markLowQualityLoaded(msg);
                  });
                }
                return Image(image: imageProvider, fit: BoxFit.cover);
              },
            ),
          ),

        // ✅ 3. HIGH QUALITY IMAGE - SLOW (500ms-2s) - FADE IN OVER LOW QUALITY
        if (loadStage >= 3)
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: msg.highQualityUrl ?? mediaUrl,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 300),
              placeholder: (context, url) {
                // Show low quality while high quality loads
                return Container(); // Low quality already visible in background
              },
              imageBuilder: (context, imageProvider) {
                // High quality loaded - fade in over low quality
                return AnimatedOpacity(
                  opacity: 1.0,
                  duration: const Duration(milliseconds: 400),
                  child: Image(image: imageProvider, fit: BoxFit.cover),
                );
              },
            ),
          ),

        // ✅ LOADING INDICATOR (Only show if loading in progress and not fully loaded)
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

  Future<void> _resolveHeader() async {
    try {
      String? phone = _authBox.get('otherUserPhone');
      if (phone == null || phone.toString().trim().isEmpty) {
        final msgs = _messageBox.values
            .where((m) => m.chatId == widget.chatId)
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

        for (final m in msgs) {
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

  // ✅ LOAD MORE MESSAGES FOR INFINITE SCROLL
  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final messages = _messageBox.values
          .where((msg) => msg.chatId == widget.chatId)
          .toList();

      if (messages.isNotEmpty) {
        messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        _oldestMessageTime = messages.first.timestamp;
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
  // ✅ FIXED: ALWAYS LOAD LAST 50 MESSAGES FROM SERVER (WHATSAPP STYLE)
  Future<void> _fetchMessages() async {
    try {
      print("🔄 Loading last 50 messages from server for chat ${widget.chatId}");

      final url = Uri.parse("$apiBase/get_messages.php?chat_id=${widget.chatId}");

      print("🌐 Request URL: $url");

      final res = await http.get(url);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);

        if (data["success"] == true && data["messages"] != null) {
          int newMessagesCount = 0;
          int duplicateCount = 0;

          final messages = List.from(data["messages"]);
          print("📥 Received ${messages.length} messages from server");

          for (var msg in messages) {
            final messageId = msg["message_id"]?.toString();
            final tempId = msg["temp_id"]?.toString();
            final idToProcess = messageId ?? tempId;

            if (idToProcess == null) continue;

            // ✅ LESS STRICT DUPLICATE CHECK FOR FRESH INSTALL
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
      });

    } catch (e) {
      print("❌ Fetch messages error: $e");
      setState(() {
        _areMessagesLoaded = true;
      });
    }
  }

  // ✅ FIXED: BETTER INCOMING MESSAGE HANDLING
  Future<void> _handleIncomingData(dynamic data) async {
    try {
      final messageId = data["message_id"]?.toString();
      final tempId = data["temp_id"]?.toString();
      final idToProcess = messageId ?? tempId;

      if (idToProcess == null) {
        print("❌ Incoming data has no valid message_id or temp_id");
        return;
      }

      // ✅ IMPROVED MESSAGE TYPE DETECTION
      String messageText = data["message_text"]?.toString() ?? "";
      String messageType = data["message_type"]?.toString() ?? "text";

      // ✅ AUTO-DETECT MEDIA MESSAGES
      bool hasMedia = (data["media_url"] != null && data["media_url"].toString().isNotEmpty) ||
          (data["low_quality_url"] != null && data["low_quality_url"].toString().isNotEmpty) ||
          (data["high_quality_url"] != null && data["high_quality_url"].toString().isNotEmpty);

      if (hasMedia) {
        messageType = "media";
        messageText = "media"; // Set text to "media" for media messages
      }

      // ✅ EXTRACT MEDIA URLs
      String? mediaUrl = data["media_url"]?.toString();
      String? lowQualityUrl = data["low_quality_url"]?.toString();
      String? highQualityUrl = data["high_quality_url"]?.toString();
      String? blurHash = data["blur_hash"]?.toString();
      String? thumbnailBase64 = data["thumbnail_data"]?.toString() ?? data["thumbnail"]?.toString();

      // ✅ CONVERT TO FULL URLS IF NEEDED
      mediaUrl = _convertToFullUrl(mediaUrl);
      lowQualityUrl = _convertToFullUrl(lowQualityUrl);
      highQualityUrl = _convertToFullUrl(highQualityUrl);

      print("🔍 PROCESSING MESSAGE:");
      print("   - ID: $idToProcess");
      print("   - Type: $messageType");
      print("   - Has Media: $hasMedia");
      print("   - Text: $messageText");
      print("   - Media URL: $mediaUrl");
      print("   - Low Quality: $lowQualityUrl");
      print("   - High Quality: $highQualityUrl");

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
      );

      await ChatService.saveMessageLocal(msg);
      print("💾 Saved message: $idToProcess (Type: $messageType)");

      // ✅ START PROGRESSIVE LOADING FOR MEDIA MESSAGES
      if (messageType == 'media' && mounted && !_fullyLoadedMessages.contains(msg.messageId)) {
        _startProgressiveLoading(msg);
      }

    } catch (e) {
      print("❌ Error handling incoming data: $e");
      print("❌ Problematic data: ${data.toString()}");
    }
  }

// ✅ ADD THIS HELPER FUNCTION (Class mein add karein)
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

        await ChatService.sendMediaMessage(
          chatId: widget.chatId,
          receiverId: widget.otherUserId,
          mediaPath: _imageFile!.path,
          senderName: _authBox.get('userName'),
          receiverName: _resolvedTitle.isNotEmpty ? _resolvedTitle : widget.otherUserName,
          senderPhoneNumber: _authBox.get('userPhone'),
          receiverPhoneNumber: _otherUserPhone ?? _authBox.get('otherUserPhone'),
        );

        setState(() => _imageFile = null);
      } else {
        await ChatService.sendMessage(
          chatId: widget.chatId,
          receiverId: widget.otherUserId,
          messageContent: text,
          messageType: 'text',
          senderName: _authBox.get('userName'),
          receiverName: _resolvedTitle.isNotEmpty ? _resolvedTitle : widget.otherUserName,
          senderPhoneNumber: _authBox.get('userPhone'),
          receiverPhoneNumber: _otherUserPhone ?? _authBox.get('otherUserPhone'),
        );

        _controller.clear();
      }

      _resolveHeader();

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

  // ✅ UPDATED MEDIA MESSAGE BUBBLE WITH PERSISTENT LOADING
  Widget _buildMediaMessageBubble(Message msg, {required bool isMe, required bool isSelected}) {
    final color = isMe ? const Color(0xFFDCF8C6) : Colors.white;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (selectedMessageIds.isNotEmpty) {
          setState(() {
            selectedMessageIds.clear();
          });
        } else if (_focusNode.hasFocus) {
          _focusNode.unfocus();
        } else {
          _openImageFullScreen(msg);
        }
      },
      onLongPress: () {
        setState(() {
          final msgId = msg.messageId.toString();
          if (selectedMessageIds.contains(msgId)) {
            selectedMessageIds.remove(msgId);
          } else {
            selectedMessageIds.clear();
            selectedMessageIds.add(msgId);
          }
        });
      },
      child: RepaintBoundary(
        child: Container(
          decoration: BoxDecoration(
            border: isSelected ? Border.all(color: Colors.lightGreen, width: 2) : null,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              padding: const EdgeInsets.all(6),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
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
                  // ✅ USE PERSISTENT PROGRESSIVE IMAGE LOADER
                  _buildMediaMessage(msg, msg.messageContent, Colors.black),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ✅ UPDATED MEDIA MESSAGE WITH PERSISTENT LOADING
  Widget _buildMediaMessage(Message msg, String mediaUrl, Color textColor) {
    final userId = LocalAuthService.getUserId();
    final bool isMe = msg.senderId == userId;
    final tempId = msg.messageId.toString();
    final uploadProgress = _uploadProgress[tempId];
    final isUploading = uploadProgress != null && uploadProgress < 100;

    // ✅ INSTANT LOCAL PREVIEW
    if (mediaUrl.startsWith('/') || File(mediaUrl).existsSync()) {
      return _buildLocalMediaPreview(mediaUrl, msg, isMe);
    }

    // ✅ PERSISTENT WHATSAPP-STYLE PROGRESSIVE LOADING
    return GestureDetector(
      onTap: () => _openImageFullScreen(msg),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.65,
        ),
        child: Stack(
          children: [
            // ✅ SMART PERSISTENT PROGRESSIVE IMAGE LOADING
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.65,
                height: 300,
                color: Colors.transparent,
                child: _buildWhatsAppStyleImage(msg, mediaUrl),
              ),
            ),

            // ✅ UPLOAD PROGRESS (for sender only)
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

            // ✅ TIME STAMP WITH TICKS
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

  // ✅ WHATSAPP-STYLE LOCAL MEDIA PREVIEW
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
            // ✅ INSTANT LOCAL IMAGE SHOW
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.65,
                height: 300,
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

            // ✅ UPLOAD PROGRESS INDICATOR
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

            // ✅ TIME AND TICKS OVERLAY
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

  // ✅ FIXED: WHATSAPP-STYLE MESSAGE TICKS
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


  // ✅ FIXED MESSAGE BUBBLE FOR BETTER MESSAGE HANDLING
  Widget _buildMessageBubble(Message msg, {Key? key}) {
    final String msgId = msg.messageId.toString();
    final bool isSelected = selectedMessageIds.contains(msgId);
    final userId = LocalAuthService.getUserId();
    final bool isMe = msg.senderId == userId;

    // ✅ IMPROVED MEDIA DETECTION
    final bool isMediaMessage = msg.messageType == 'media' ||
        msg.messageType == 'encrypted_media' ||
        (msg.lowQualityUrl != null && msg.lowQualityUrl!.isNotEmpty) ||
        (msg.highQualityUrl != null && msg.highQualityUrl!.isNotEmpty);

    if (msg.messageId.toString().startsWith('temp_') && isMediaMessage) {
      return _buildMediaMessageBubble(msg, isMe: isMe, isSelected: isSelected);
    }

    if ((isMe && msg.isDeletedSender == 1) || (!isMe && msg.isDeletedReceiver == 1)) {
      return const SizedBox.shrink();
    }

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

    return RepaintBoundary(
      key: key,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (selectedMessageIds.isNotEmpty) {
            setState(() {
              selectedMessageIds.clear();
            });
          } else if (_focusNode.hasFocus) {
            _focusNode.unfocus();
          } else if (isMediaMessage) {
            _openImageFullScreen(msg);
          }
        },
        onLongPress: () {
          setState(() {
            if (selectedMessageIds.contains(msgId)) {
              selectedMessageIds.remove(msgId);
            } else {
              selectedMessageIds.clear();
              selectedMessageIds.add(msgId);
            }
          });
        },
        child: Container(
          decoration: BoxDecoration(
            border: isSelected ? Border.all(color: Colors.lightGreen, width: 2) : null,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Align(
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
                  if (contentDeleted)
                    Text(
                        content,
                        style: TextStyle(color: Colors.red[800], fontSize: 14, fontStyle: FontStyle.italic)
                    )

                  // ✅ TEXT MESSAGE
                  else if (msg.messageType == 'text' && !isMediaMessage)
                    Text(content, style: TextStyle(color: textColor, fontSize: 16))

                  // ✅ MEDIA MESSAGE
                  else if (isMediaMessage)
                      _buildMediaMessage(msg, msg.messageContent, textColor)

                    // ✅ FALLBACK FOR UNKNOWN TYPES - SHOW ORIGINAL CONTENT
                    else
                      Text(
                        content.isNotEmpty ? content : "📎 Attachment",
                        style: TextStyle(color: textColor, fontSize: 16),
                      ),

                  // ✅ TIME STAMP FOR TEXT MESSAGES
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
        ),
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  // ✅ FIXED: BETTER MEDIA ERROR WIDGET
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

  // ✅ OPTIMIZED DATE HEADER
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
    return Container(
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
                  IconButton(
                    onPressed: _pickImage,
                    icon: Icon(Icons.photo_library, color: Colors.grey[600]),
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
    );
  }

  // ✅ FORWARD MESSAGES FUNCTION
  Future<void> _forwardMessages() async {
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
        const SnackBar(content: Text("Messages forwarded!")),
      );

      setState(() {
        selectedMessageIds.clear();
      });
    }
  }

  // ✅ DELETE MESSAGE FUNCTION
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
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleText = _resolvedTitle.isNotEmpty ? _resolvedTitle : widget.otherUserName;
    final initial = titleText.isNotEmpty ? titleText[0].toUpperCase() : 'U';

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
        actions: [
          IconButton(icon: const Icon(Icons.videocam, color: Colors.white), onPressed: () {}),
          IconButton(icon: const Icon(Icons.call, color: Colors.white), onPressed: () {}),
          if (selectedMessageIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.forward, color: Colors.white),
              onPressed: _forwardMessages,
            ),
          if (selectedMessageIds.length == 1)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.white),
              onPressed: () => _showDeleteConfirmation(selectedMessageIds.first),
            ),
          IconButton(icon: const Icon(Icons.more_vert, color: Colors.white), onPressed: () {}),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          if (_focusNode.hasFocus) {
            _focusNode.unfocus();
          }
          if (selectedMessageIds.isNotEmpty) {
            setState(() {
              selectedMessageIds.clear();
            });
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
                    final messages = box.values
                        .where((msg) => msg.chatId == widget.chatId)
                        .where((msg) => !msg.messageId.toString().startsWith('temp_') ||
                        (msg.messageId.toString().startsWith('temp_') && msg.messageType == 'media'))
                        .toList();

                    if (messages.isEmpty) {
                      return const Center(child: Text("Say hi to start the conversation!"));
                    }

                    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _jumpToBottom();
                    });

                    return CustomScrollView(
                      controller: _scrollController,
                      reverse: false,
                      physics: const BouncingScrollPhysics(),
                      cacheExtent: 2000,
                      slivers: [
                        if (_isLoadingMore)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            ),
                          ),

                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                                (context, index) {
                              if (index >= messages.length) return null;

                              final msg = messages[index];
                              final previousMsg = index > 0 ? messages[index - 1] : null;
                              final currentDate = formatDateHeader(msg.timestamp);
                              final previousDate = previousMsg != null
                                  ? formatDateHeader(previousMsg.timestamp)
                                  : null;

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
                            childCount: messages.length,
                            addAutomaticKeepAlives: true,
                            addRepaintBoundaries: true,
                          ),
                        ),
                      ],
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
    );
  }
}