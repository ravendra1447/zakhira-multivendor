import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../services/marketplace/marketplace_chat_service.dart';
import '../../../models/marketplace/marketplace_chat_message.dart';
import '../../../models/marketplace/marketplace_chat_room.dart';
import '../../../models/product.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';

class MarketplaceChatScreen extends StatefulWidget {
  final MarketplaceChatRoom chatRoom;
  final Product? product; // Optional product info for initial display
  final int currentUserId;

  const MarketplaceChatScreen({
    super.key,
    required this.chatRoom,
    required this.currentUserId,
    this.product,
  });

  @override
  State<MarketplaceChatScreen> createState() => _MarketplaceChatScreenState();
}

class _MarketplaceChatScreenState extends State<MarketplaceChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  final MarketplaceChatService _chatService = MarketplaceChatService();

  List<MarketplaceChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isSending = false;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  void _initializeChat() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      print('🔍 Initializing chat for room: ${widget.chatRoom.id}');
      print('🔍 Current user ID: ${widget.currentUserId}');

      // Initialize socket connection with retry
      bool socketConnected = false;
      int retryCount = 0;
      const maxRetries = 3;

      while (!socketConnected && retryCount < maxRetries) {
        try {
          print('🔄 Socket connection attempt ${retryCount + 1}/$maxRetries');
          await _chatService.initializeSocket(widget.currentUserId);

          // Wait a bit for connection to establish
          await Future.delayed(const Duration(seconds: 1));

          if (_chatService.isConnected) {
            socketConnected = true;
            print('✅ Socket connected successfully on attempt ${retryCount + 1}');
            break;
          } else {
            print('❌ Socket not connected after attempt ${retryCount + 1}');
            retryCount++;
            if (retryCount < maxRetries) {
              await Future.delayed(const Duration(seconds: 2));
            }
          }
        } catch (e) {
          print('❌ Socket initialization failed on attempt ${retryCount + 1}: $e');
          retryCount++;
          if (retryCount < maxRetries) {
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }

      if (!socketConnected) {
        print('❌ Socket failed to connect after $maxRetries attempts');
        // Load local messages as fallback
        _loadLocalMessages();
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      // Set up socket listeners
      _setupSocketListeners();
      print('✅ Socket listeners set up');

      // Join chat room
      _chatService.joinChatRoom(widget.chatRoom.id);
      print('✅ Joined chat room: ${widget.chatRoom.id}');

      // Wait a moment for room to be joined, then get chat history
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          print('🔍 Fetching chat history...');
          try {
            _chatService.getChatHistory(widget.chatRoom.id);
          } catch (e) {
            print('❌ Error fetching chat history: $e');
            _loadLocalMessages();
          }
        }
      });

      // Also try to load local messages immediately as fallback
      _loadLocalMessages();

      // Set timeout for chat history - if not loaded in 5 seconds, show local messages
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _messages.isEmpty) {
          print('⚠️ Chat history timeout, using local messages only');
          _loadLocalMessages();
        }
      });

      // If no product info, try to load it
      if (widget.product == null) {
        _loadProductFromChatRoom();
      }

      // Send product info message if product is provided
      if (widget.product != null) {
        _sendProductInfoMessage();
      }

    } catch (e) {
      print('Error initializing chat: $e');
      // If socket fails, at least load local messages
      _loadLocalMessages();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize chat: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Load product info from chat room
  void _loadProductFromChatRoom() async {
    try {
      print('🔄 Loading product info for chat room: ${widget.chatRoom.id}');
      // TODO: Implement API call to get product info from chat room
      // For now, we'll try to get it from the chat room's product_id
    } catch (e) {
      print('❌ Error loading product from chat room: $e');
    }
  }

  void _setupSocketListeners() {
    _chatService.on('new_message', _onNewMessage);
    _chatService.on('chat_history', _onChatHistory);
    _chatService.on('connect', (_) {
      setState(() => _isConnected = true);
    });
    _chatService.on('disconnect', (_) {
      setState(() => _isConnected = false);
    });
  }

  void _onNewMessage(dynamic data) {
    final message = MarketplaceChatMessage.fromJson(data);

    // Check if message already exists to avoid duplicates
    // First, remove any temporary messages with the same content from the same sender
    final tempMessagesToRemove = _messages.where((msg) =>
    msg.id.toString().startsWith('17') && // Temporary IDs start with current timestamp
        msg.senderId == message.senderId &&
        msg.messageContent.trim() == message.messageContent.trim()
    ).toList();

    if (tempMessagesToRemove.isNotEmpty) {
      setState(() {
        _messages.removeWhere((msg) => tempMessagesToRemove.contains(msg));
      });
    }

    // Check if real message already exists
    final existingIndex = _messages.indexWhere((msg) => msg.id == message.id);
    if (existingIndex == -1) {
      setState(() {
        _messages.add(message);
      });
      _scrollToBottom();

      // Save to local SQLite
      _chatService.saveMessageToLocal(message);

      print('✅ New message added: ${message.id} from ${message.senderName}');
    } else {
      print('⚠️ Duplicate message ignored: ${message.id} from ${message.senderName}');
    }

    // Mark as read if not from current user
    if (!message.isFromCurrentUser(widget.currentUserId)) {
      _chatService.markMessagesRead(widget.chatRoom.id, message.id);
    }
  }

  void _onChatHistory(dynamic data) {
    print('🔍 Received chat history data: ${data.runtimeType}');
    print('🔍 Data keys: ${data is Map ? data.keys : 'Not a map'}');

    if (data is Map && data.containsKey('messages')) {
      final messagesList = data['messages'] as List;
      print('🔍 Messages list length: ${messagesList.length}');

      final messages = messagesList
          .map((msg) {
        print('🔍 Processing message: ${msg.runtimeType}');
        return MarketplaceChatMessage.fromJson(msg);
      })
          .toList();

      setState(() {
        _messages = messages;
      });
      _scrollToBottom();

      // Save all messages to local SQLite
      for (final message in messages) {
        _chatService.saveMessageToLocal(message);
      }

      print('✅ Chat history loaded: ${messages.length} messages');
    } else {
      print('❌ Invalid chat history data format');
    }
  }

  // Load local messages as fallback
  void _loadLocalMessages() async {
    try {
      final localMessages = await _chatService.getLocalMessages(widget.chatRoom.id);
      if (localMessages.isNotEmpty) {
        setState(() {
          _messages = localMessages;
        });
        _scrollToBottom();
        print('✅ Local messages loaded: ${localMessages.length} messages');
      }
    } catch (e) {
      print('Error loading local messages: $e');
    }
  }

  void _sendProductInfoMessage() {
    if (widget.product == null) return;

    _chatService.sendProductInfoMessage(
      chatRoomId: widget.chatRoom.id,
      productId: widget.product!.id!,
      productName: widget.product!.name,
      price: widget.product!.price ?? 0.0,
      image: _getProductImage(),
    );
  }

  String _getProductImage() {
    if (widget.product == null) return '';

    // Get first image from variations or main images
    if (widget.product!.variations.isNotEmpty) {
      final variation = widget.product!.variations.first;
      if (variation['image'] != null) {
        return variation['image'].toString();
      }
    }

    if (widget.product!.images.isNotEmpty) {
      return widget.product!.images.first;
    }

    return '';
  }

  void _sendMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    setState(() => _isSending = true);

    try {
      // Create temporary message for immediate display
      final tempMessage = MarketplaceChatMessage(
        id: DateTime.now().millisecondsSinceEpoch, // Temporary ID
        chatRoomId: widget.chatRoom.id,
        senderId: widget.currentUserId,
        messageType: 'text',
        messageContent: message,
        isRead: false,
        isDelivered: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        senderName: 'You',
        encryptedContent: '',
        encryptionKey: '',
        localStatus: MessageLocalStatus.sending,
      );

      // Add message immediately to UI
      setState(() {
        _messages.add(tempMessage);
      });
      _scrollToBottom();

      _messageController.clear();

      // Send via socket
      _chatService.sendMessage(
        chatRoomId: widget.chatRoom.id,
        messageContent: message,
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: $e')),
      );
    } finally {
      setState(() => _isSending = false);
    }
  }

  Future<void> _sendImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 70,
      );

      if (image != null) {
        final File imageFile = File(image.path);
        final imageUrl = await _chatService.uploadChatImage(imageFile);

        _chatService.sendMessage(
          chatRoomId: widget.chatRoom.id,
          messageContent: imageUrl,
          messageType: 'image',
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send image: $e')),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Helper methods for message status
  IconData _getMessageStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sent:
        return Icons.done;
      case MessageStatus.delivered:
        return Icons.done_all;
      case MessageStatus.read:
        return Icons.done_all;
    }
  }

  Color _getMessageStatusColor(MessageStatus status) {
    switch (status) {
      case MessageStatus.sent:
        return Colors.grey.shade400;
      case MessageStatus.delivered:
        return Colors.grey.shade600;
      case MessageStatus.read:
        return Colors.blue;
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _chatService.off('new_message');
    _chatService.off('chat_history');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildProductInfo(),
          Expanded(
            child: _buildMessageList(),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.black),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.chatRoom.getOtherUserName(widget.currentUserId),
            style: AppTypography.bodyMedium(context).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _isConnected ? Colors.green : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _isConnected ? 'Online' : 'Offline',
                style: AppTypography.caption(context).copyWith(
                  color: _isConnected ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        // Refresh button
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.black),
          onPressed: () {
            print('🔄 Refreshing chat messages...');
            _chatService.getChatHistory(widget.chatRoom.id);
            _loadLocalMessages();
          },
        ),
        IconButton(
          icon: const Icon(Icons.more_vert, color: Colors.black),
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildProductInfo() {
    if (widget.product == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Product Image
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.sm),
            child: CachedNetworkImage(
              imageUrl: _getProductImage(),
              width: 60,
              height: 60,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: Colors.grey.shade200,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey.shade200,
                child: const Icon(Icons.image, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),

          // Product Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.product!.name,
                  style: AppTypography.bodyMedium(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '₹${widget.product!.price?.toStringAsFixed(1) ?? '0.0'}',
                  style: AppTypography.bodySmall(context).copyWith(
                    color: AppColors.primary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Text(
                      'Product ID: ${widget.product!.id}',
                      style: AppTypography.caption(context).copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        // Navigate to product detail
                        Navigator.pop(context);
                      },
                      child: const Text('View Product'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    print('🔍 Building message list: ${_messages.length} messages, Loading=$_isLoading');

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Start a conversation',
              style: AppTypography.bodyMedium(context).copyWith(
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _buildMessageBubble(message);
      },
    );
  }

  Widget _buildMessageBubble(MarketplaceChatMessage message) {
    final isFromMe = message.isFromCurrentUser(widget.currentUserId);

    print('🔍 Building message bubble: ID=${message.id}, FromMe=$isFromMe, Sender=${message.senderName}, Content=${message.messageContent}');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: isFromMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isFromMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey.shade300,
              child: message.senderAvatar != null
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: message.senderAvatar!,
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                ),
              )
                  : Icon(
                Icons.person,
                size: 20,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],

          Flexible(
            child: Column(
              crossAxisAlignment: isFromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (message.hasProductInfo) _buildProductInfoMessage(message.productInfo!),
                if (message.messageType == 'image') _buildImageMessage(message),
                if (message.messageType == 'text') _buildTextMessage(message, isFromMe),

                const SizedBox(height: 2),
                Text(
                  message.displayTime,
                  style: AppTypography.caption(context).copyWith(
                    color: Colors.grey.shade500,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),

          if (isFromMe) ...[
            const SizedBox(width: AppSpacing.sm),
            // Show message status
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(
                  _getMessageStatusIcon(message.status),
                  size: 16,
                  color: _getMessageStatusColor(message.status),
                ),
                if (message.readTimeDisplay != null)
                  Text(
                    message.readTimeDisplay!,
                    style: AppTypography.caption(context).copyWith(
                      color: Colors.grey.shade500,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextMessage(MarketplaceChatMessage message, bool isFromMe) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isFromMe ? AppColors.primary(context) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(AppSpacing.md),
      ),
      child: Text(
        message.messageContent,
        style: AppTypography.bodySmall(context).copyWith(
          color: isFromMe ? Colors.white : Colors.black.withOpacity(0.87),
        ),
      ),
    );
  }

  Widget _buildImageMessage(MarketplaceChatMessage message) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 200),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.md),
        child: CachedNetworkImage(
          imageUrl: message.messageContent,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            height: 150,
            color: Colors.grey.shade200,
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            height: 150,
            color: Colors.grey.shade200,
            child: const Icon(Icons.broken_image, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  Widget _buildProductInfoMessage(MarketplaceProductInfo productInfo) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.sm),
            child: CachedNetworkImage(
              imageUrl: productInfo.image,
              width: 50,
              height: 50,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: Colors.grey.shade200,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey.shade200,
                child: const Icon(Icons.image, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productInfo.productName,
                  style: AppTypography.bodySmall(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  productInfo.formattedPrice,
                  style: AppTypography.bodySmall(context).copyWith(
                    color: AppColors.primary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.image,
              color: Colors.grey.shade600,
            ),
            onPressed: _sendImage,
          ),

          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.md),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.md),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.md),
                  borderSide: BorderSide(color: AppColors.primary(context)),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),

          const SizedBox(width: AppSpacing.sm),

          IconButton(
            icon: _isSending
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary(context)),
              ),
            )
                : Icon(
              Icons.send,
              color: AppColors.primary(context),
            ),
            onPressed: _isSending ? null : _sendMessage,
          ),
        ],
      ),
    );
  }
}
  