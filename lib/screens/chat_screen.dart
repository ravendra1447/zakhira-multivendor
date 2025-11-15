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
  StreamSubscription? _thumbnailReadySubscription;

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

      // ✅ LOAD MORE MESSAGES WHEN NEAR TOP
      if (_scrollController.offset <= _scrollController.position.minScrollExtent + 200 &&
          _hasMoreMessages &&
          !_isLoadingMore) {
        _loadMoreMessages();
      }
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
        if (_processedMessageIds.contains(msg.messageId)) {
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
          // ✅ FIX: Only scroll if at bottom (prevent fluctuation)
          if (_shouldScrollToBottom) {
            _scrollToBottomSmooth();
          }
          HapticFeedback.selectionClick();

          // ✅ FIX: Resolve header without blocking UI
          unawaited(_resolveHeader());

          if ((msg.messageType == 'media' || msg.messageType == 'encrypted_media') &&
              !_fullyLoadedMessages.contains(msg.messageId)) {
            _startProgressiveLoading(msg);
          }
        }

        // ✅ FIX: Batch refresh to prevent fluctuation
        _needsRefresh = true;
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
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

    // ✅ THUMBNAIL READY LISTENER - Refresh UI when thumbnail is updated
    _thumbnailReadySubscription = ChatService.onThumbnailReady.listen((thumbnailData) {
      if (mounted) {
        final tempId = thumbnailData['tempId']?.toString();
        final message = thumbnailData['message'] as Message?;

        if (message != null && message.chatId == widget.chatId) {
          print("🖼️ Thumbnail ready for message: $tempId, refreshing UI");
          setState(() {
            _needsRefresh = true;
          });
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
    if (!_needsRefresh && _cachedMessages.isNotEmpty) {
      return _cachedMessages;
    }

    final messages = _messageBox.values
        .where((msg) => msg.chatId == widget.chatId)
        .where((msg) {
          // ✅ FIX: Completely hide ALL temp_ messages (no dot bubbles at all)
          final isTemp = msg.messageId.toString().startsWith('temp_');
          if (isTemp) {
            // ✅ FIX: Only show temp media if it has thumbnail AND is uploading
            if (msg.messageType == 'media' || msg.messageType == 'encrypted_media') {
              final tempId = msg.messageId.toString();
              final hasThumbnail = msg.thumbnailBase64 != null && msg.thumbnailBase64!.isNotEmpty;
              final uploadProgress = _uploadProgress[tempId];
              final isUploading = uploadProgress != null && uploadProgress < 100;
              
              // Only show if has thumbnail AND is uploading (no empty dot bubbles)
              return hasThumbnail && isUploading;
            }
            // Hide all temp text messages completely
            return false;
          }
          
          // Show all non-temp messages
          return true;
        })
        .toList();

    // ✅ EFFICIENT: Sort only when needed
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // ✅ FIX: Deduplication - Remove duplicate messages by messageId
    final Map<String, Message> uniqueMessages = {};
    for (final m in messages) {
      final msgId = m.messageId.toString();
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
    
    final deduplicatedMessages = uniqueMessages.values.toList();
    
    // ✅ DEDUPE GROUPED MEDIA: show only anchor (smallest imageIndex present)
    final Map<String, int> groupAnchors = {};
    for (final m in deduplicatedMessages) {
      final gid = m.groupId;
      if (gid != null && gid.isNotEmpty) {
        final idx = m.imageIndex ?? 0;
        if (!groupAnchors.containsKey(gid) || idx < groupAnchors[gid]!) {
          groupAnchors[gid] = idx;
        }
      }
    }

    if (groupAnchors.isNotEmpty) {
      try {
        final anchorsLog = groupAnchors.entries.map((e) => '${e.key}:${e.value}').join(', ');
        print('🧩 Group anchors computed: $anchorsLog');
      } catch (_) {}
    }

    final filtered = <Message>[];
    for (final m in deduplicatedMessages) {
      final gid = m.groupId;
      if (gid == null || gid.isEmpty) {
        filtered.add(m);
      } else {
        final anchor = groupAnchors[gid] ?? 0;
        if ((m.imageIndex ?? 0) == anchor) {
          filtered.add(m);
        }
      }
    }

    _cachedMessages = filtered;
    _needsRefresh = false;

    return filtered;
  }

  // ✅ IMPLEMENTED: FRAME-SYNCED AUTO-SCROLL
  void _scrollToBottomSmooth() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _shouldScrollToBottom) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150), // ✅ FIX: Faster scroll animation
          curve: Curves.easeOut,
        );
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
    _updateTimer?.cancel();

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
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ✅ OPTIMIZED JUMP TO BOTTOM
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

    } catch (e) {
      print("❌ Fetch messages error: $e");
      setState(() {
        _areMessagesLoaded = true;
        _needsRefresh = true;
      });
    }
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
        groupId: data["group_id"]?.toString(),
        imageIndex: data["image_index"] != null ? int.tryParse(data["image_index"].toString()) : null,
        totalImages: data["total_images"] != null ? int.tryParse(data["total_images"].toString()) : null,
      );

      await ChatService.saveMessageLocal(msg);

      if (messageType == 'media' && mounted && !_fullyLoadedMessages.contains(msg.messageId)) {
        _startProgressiveLoading(msg);
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
    final String msgId = msg.messageId.toString();
    final bool isSelected = selectedMessageIds.contains(msgId);
    final userId = LocalAuthService.getUserId();
    final bool isMe = msg.senderId == userId;

    // ✅ FIX: Completely hide ALL temp messages without thumbnail (no dot bubbles)
    final isTemp = msg.messageId.toString().startsWith('temp_');
    if (isTemp) {
      // Only show temp media if it has thumbnail AND is uploading
      if (msg.messageType == 'media' || msg.messageType == 'encrypted_media') {
        final tempId = msg.messageId.toString();
        final hasThumbnail = msg.thumbnailBase64 != null && msg.thumbnailBase64!.isNotEmpty;
        final uploadProgress = _uploadProgress[tempId];
        final isUploading = uploadProgress != null && uploadProgress < 100;
        
        if (!hasThumbnail || !isUploading) {
          // Don't show temp media without thumbnail or if not uploading
          return const SizedBox.shrink();
        }
        
        return _buildMediaMessageBubble(msg, isMe: isMe, isSelected: isSelected);
      }
      // Hide all temp text messages completely
      return const SizedBox.shrink();
    }

    final bool isMediaMessage = msg.messageType == 'media' ||
        msg.messageType == 'encrypted_media' ||
        (msg.lowQualityUrl != null && msg.lowQualityUrl!.isNotEmpty) ||
        (msg.highQualityUrl != null && msg.highQualityUrl!.isNotEmpty);

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
              _enterSelectionMode(msg.messageId);
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
                        // ✅ REPLY PREVIEW IN MEDIA MESSAGE
                        if (msg.replyToMessageId != null && msg.replyToMessageId!.isNotEmpty)
                          _buildReplyInMessage(msg),

                        _buildMediaMessage(msg, msg.messageContent, Colors.black),
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

  Widget _buildMediaMessage(Message msg, String mediaUrl, Color textColor) {
    if ((msg.groupId ?? '').isNotEmpty) {
      final String gid = msg.groupId!;
      final List<Message> groupMessages = _messageBox.values
          .where((m) => m.groupId == gid && m.chatId == widget.chatId)
          .toList();
      print('🧩 BuildMedia: msg=${msg.messageId} gid=$gid count=${groupMessages.length} idx=${msg.imageIndex}');
      if (groupMessages.isNotEmpty) {
        // ✅ FIX: Sort by imageIndex to maintain sender's sequence (same logic as _buildCollageForMessages)
        groupMessages.sort((a, b) {
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
          final idxs = groupMessages.map((m) => m.imageIndex?.toString() ?? 'null').join(',');
          print('🧩 Group ${gid} indices after sort: [$idxs]');
        } catch (_) {}
        final int anchorIndex = groupMessages.first.imageIndex ?? 0; // smallest index present
        print('🧩 Group ${gid} anchorIndex=$anchorIndex currentIdx=${msg.imageIndex ?? 0}');
        if ((msg.imageIndex ?? 0) == anchorIndex) {
          print('🧩 Rendering collage for group $gid at anchor message ${groupMessages.first.messageId}');
          return _buildCollageForMessages(groupMessages, groupMessages.first);
        } else {
          print('🧩 Non-anchor message ${msg.messageId} hidden for group $gid');
          return const SizedBox.shrink();
        }
      }
    } else {
      final cluster = _getContiguousMediaCluster(msg);
      print('🧩 Fallback cluster for ${msg.messageId}: size=${cluster.length}');
      if (cluster.length >= 2) {
        cluster.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        final Message anchor = cluster.first;
        print('🧩 Fallback anchor=${anchor.messageId} for msg=${msg.messageId}');
        if (msg.messageId == anchor.messageId) {
          print('🧩 Rendering fallback collage for anchor ${anchor.messageId}');
          return _buildCollageForMessages(cluster, anchor);
        } else {
          return const SizedBox.shrink();
        }
      }
    }
    final userId = LocalAuthService.getUserId();
    final bool isMe = msg.senderId == userId;
    final tempId = msg.messageId.toString();
    final uploadProgress = _uploadProgress[tempId];
    final isUploading = uploadProgress != null && uploadProgress < 100;

    if (mediaUrl.startsWith('/') || File(mediaUrl).existsSync()) {
      return _buildLocalMediaPreview(mediaUrl, msg, isMe);
    }

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
                height: 300, // ✅ SAME HEIGHT MAINTAINED
                color: Colors.transparent,
                child: _buildImageWithBlurHash(msg, mediaUrl),
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

  List<Message> _getContiguousMediaCluster(Message msg, {int windowSeconds = 20}) {
    final all = _messageBox.values
        .where((m) => m.chatId == widget.chatId)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final int idx = all.indexWhere((m) => m.messageId == msg.messageId);
    if (idx == -1) return [msg];
    final cluster = <Message>[msg];
    // expand backward
    int i = idx - 1;
    while (i >= 0) {
      final m = all[i];
      if (m.senderId != msg.senderId) break;
      if (m.messageType != 'media' && m.messageType != 'encrypted_media') break;
      final diff = msg.timestamp.difference(m.timestamp).inSeconds.abs();
      if (diff > windowSeconds) break;
      cluster.add(m);
      i--;
    }
    // expand forward
    i = idx + 1;
    while (i < all.length) {
      final m = all[i];
      if (m.senderId != msg.senderId) break;
      if (m.messageType != 'media' && m.messageType != 'encrypted_media') break;
      final diff = m.timestamp.difference(msg.timestamp).inSeconds.abs();
      if (diff > windowSeconds) break;
      cluster.add(m);
      i++;
    }
    // ensure uniqueness
    final ids = <String>{};
    final unique = <Message>[];
    for (final m in cluster) {
      final id = m.messageId.toString();
      if (!ids.contains(id)) {
        ids.add(id);
        unique.add(m);
      }
    }
    try {
      final logIds = unique.map((m) => m.messageId.toString()).join(',');
      print('🧩 Cluster unique ids for ${msg.messageId}: [$logIds]');
    } catch (_) {}
    return unique;
  }

  Widget _buildMediaGroupCollage(Message firstMsg) {
    final List<Message> groupMessages = _messageBox.values
        .where((m) => m.groupId == firstMsg.groupId)
        .toList();
    
    // ✅ FIX: Sort by imageIndex to maintain sender's sequence (same logic as other functions)
    groupMessages.sort((a, b) {
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
    
    return _buildCollageForMessages(groupMessages, firstMsg);
  }

  Widget _buildCollageForMessages(List<Message> groupMessages, Message anchor) {
    // ✅ FIX: Ensure messages are sorted by imageIndex to maintain sender's sequence
    // Sort by imageIndex first, then by timestamp as fallback for consistency
    groupMessages.sort((a, b) {
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
    
    final int count = groupMessages.length;
    final double maxWidth = MediaQuery.of(context).size.width * 0.65;

    Widget buildTile(Message m, {VoidCallback? onTap}) {
      final String url = m.messageContent;
      String? thumb = m.thumbnailBase64;
      if (thumb != null && thumb.isNotEmpty && thumb.contains(',')) {
        thumb = thumb.split(',').last.trim();
      }
      final bool isRemote = url.startsWith('http');
      final bool isLocal = !isRemote;
      Widget imageWidget = isLocal
          ? Image.file(
              File(url),
              fit: BoxFit.cover,
              cacheWidth: 600, // ✅ FIX: Better quality thumbnail
              cacheHeight: 600,
            )
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              memCacheWidth: 400, // ✅ FIX: Optimized cache size
              memCacheHeight: 400,
              maxWidthDiskCache: 800,
              maxHeightDiskCache: 800,
              placeholder: (context, url) {
                // ✅ FIX: Show thumbnail immediately, no grey placeholder
                if (thumb != null && thumb.isNotEmpty) {
                  try {
                    final bytes = base64Decode(thumb);
                    return Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true, // ✅ FIX: Prevent flicker
                      cacheWidth: 200, // ✅ FIX: Optimized for performance
                      cacheHeight: 200,
                    );
                  } catch (_) {}
                }
                // ✅ FIX: Transparent instead of grey
                return Container(color: Colors.transparent);
              },
              errorWidget: (context, url, error) {
                // ✅ FIX: Show thumbnail on error
                if (thumb != null && thumb.isNotEmpty) {
                  try {
                    final bytes = base64Decode(thumb);
                    return Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      cacheWidth: 200,
                      cacheHeight: 200,
                    );
                  } catch (_) {}
                }
                return const Center(child: Icon(Icons.broken_image, color: Colors.grey));
              },
            );
      
      return GestureDetector(
        onTap: onTap ?? () => _openImageFullScreen(m), // ✅ FIX: Open specific image on tap
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: imageWidget,
        ),
      );
    }

    // ✅ FIX: Proper collage layout for 2, 3, 4+ images like WhatsApp
    Widget grid;
    if (count == 1) {
      grid = buildTile(groupMessages[0]);
    } else if (count == 2) {
      // ✅ FIX: 2 images - side by side
      grid = Row(
        children: [
          Expanded(child: buildTile(groupMessages[0])),
          const SizedBox(width: 2),
          Expanded(child: buildTile(groupMessages[1])),
        ],
      );
    } else if (count == 3) {
      // ✅ FIX: 3 images - 1 large on left, 2 stacked on right
      grid = Row(
        children: [
          Expanded(
            flex: 2,
            child: buildTile(groupMessages[0]),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              children: [
                Expanded(child: buildTile(groupMessages[1])),
                const SizedBox(height: 2),
                Expanded(child: buildTile(groupMessages[2])),
              ],
            ),
          ),
        ],
      );
    } else if (count == 4) {
      // ✅ FIX: 4 images - 2x2 grid
      grid = Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: buildTile(groupMessages[0])),
                const SizedBox(width: 2),
                Expanded(child: buildTile(groupMessages[1])),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Row(
              children: [
                Expanded(child: buildTile(groupMessages[2])),
                const SizedBox(width: 2),
                Expanded(child: buildTile(groupMessages[3])),
              ],
            ),
          ),
        ],
      );
    } else {
      // ✅ FIX: 5+ images - 2x2 grid with +N overlay
      grid = Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: buildTile(groupMessages[0])),
                const SizedBox(width: 2),
                Expanded(child: buildTile(groupMessages[1])),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Row(
              children: [
                Expanded(child: buildTile(groupMessages[2])),
                const SizedBox(width: 2),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      buildTile(groupMessages[3]),
                      if (count > 4)
                        Container(
                          color: Colors.black45,
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
      );
    }

    final userId = LocalAuthService.getUserId();
    final bool isMe = anchor.senderId == userId;
    final String time = _formatTime(anchor.timestamp);

    return GestureDetector(
      onTap: () => _openImageFullScreen(anchor),
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        // ✅ FIX: Add border to collage container (like before)
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.grey.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: maxWidth,
                height: count == 1 ? 300 : (count <= 2 ? 200 : 300), // ✅ FIX: Dynamic height
                child: grid,
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
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w400),
                    ),
                    if (isMe) const SizedBox(width: 4),
                    if (isMe) _buildMessageTicks(anchor),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ OPTIMIZED WHATSAPP-STYLE PROGRESSIVE IMAGE WIDGET - SAME SIZE MAINTAINED
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

    // ✅ FIX: Use CachedNetworkImage for better caching and no reload
    return CachedNetworkImage(
      imageUrl: mediaUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: 800, // ✅ FIX: Limit cache size for performance
      memCacheHeight: 800,
      maxWidthDiskCache: 1200,
      maxHeightDiskCache: 1200,
      placeholder: (context, url) {
        // ✅ FIX: Show thumbnail immediately, no grey placeholder
        if (thumbnailBase64 != null && thumbnailBase64.isNotEmpty) {
          try {
            final thumbnailBytes = base64Decode(thumbnailBase64);
            return Image.memory(
              thumbnailBytes,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true, // Prevents flicker
              cacheWidth: 200, // ✅ FIX: Optimized cache size
              cacheHeight: 200,
            );
          } catch (e) {
            // Return transparent container instead of grey
            return Container(color: Colors.transparent);
          }
        }
        // ✅ FIX: Transparent instead of grey
        return Container(color: Colors.transparent);
      },
      errorWidget: (context, url, error) {
        // ✅ FIX: On error, show thumbnail if available
        if (thumbnailBase64 != null && thumbnailBase64.isNotEmpty) {
          try {
            final thumbnailBytes = base64Decode(thumbnailBase64);
            return Image.memory(
              thumbnailBytes,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              cacheWidth: 200,
              cacheHeight: 200,
            );
          } catch (e) {
            return const Center(
              child: Icon(Icons.broken_image, color: Colors.grey, size: 40),
            );
          }
        }
        return const Center(
          child: Icon(Icons.broken_image, color: Colors.grey, size: 40),
        );
      },
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

  String _formatTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
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
          // ✅ UPDATED: ADD COPY BUTTON TO APP BAR WHEN SINGLE TEXT MESSAGE SELECTED
          if (selectedMessageIds.isNotEmpty && selectedMessageIds.length == 1 && _hasTextMessagesSelected())
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
                        final messages = _getOptimizedMessages();

                        if (messages.isEmpty) {
                          return const Center(child: Text("Say hi to start the conversation!"));
                        }

                        // ✅ AUTO-SCROLL TO BOTTOM ON NEW MESSAGES
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_shouldScrollToBottom && _hasInitialScrollDone) {
                            _scrollToBottomSmooth();
                          }
                        });

                        return ListView.builder(
                          controller: _scrollController,
                          reverse: false,
                          physics: const ClampingScrollPhysics(), // ✅ FIX: Smoother scrolling
                          padding: const EdgeInsets.all(8),
                          itemCount: messages.length + (_isLoadingMore ? 1 : 0),
                          cacheExtent: 1000, // ✅ FIX: Increased for smoother scrolling
                          addAutomaticKeepAlives: false, // ✅ FIX: Better performance
                          addRepaintBoundaries: true, // ✅ FIX: Prevent unnecessary repaints
                          itemExtent: null, // ✅ FIX: Allow variable heights for better performance
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
                            if (adjustedIndex >= messages.length) return null;

                            final msg = messages[adjustedIndex];
                            final previousMsg = adjustedIndex > 0 ? messages[adjustedIndex - 1] : null;
                            final currentDate = formatDateHeader(msg.timestamp);
                            final previousDate = previousMsg != null
                                ? formatDateHeader(previousMsg.timestamp)
                                : null;

                            // ✅ ADD UNREAD SEPARATOR AT APPROPRIATE PLACE
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
                  _buildImagePreview(),
                  _buildInputArea(),
                ],
              ),
            ),
          ),

          // ✅ FLOATING SCROLL TO BOTTOM BUTTON
          _buildFloatingScrollButton(),

          // ✅ SELECTION BOTTOM BAR
          _buildSelectionBottomBar(),
        ],
      ),
    );
  }
}