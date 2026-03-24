import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../config.dart';
import '../../models/marketplace/marketplace_chat_database.dart';
import '../../models/marketplace/marketplace_chat_message.dart';
import '../../models/marketplace/marketplace_chat_room.dart';
import '../../models/marketplace/marketplace_chat_participant.dart';
import 'chat_encryption.dart';

class MarketplaceChatService {
  static final MarketplaceChatService _instance = MarketplaceChatService._internal();
  factory MarketplaceChatService() => _instance;
  MarketplaceChatService._internal();

  final Map<String, Function(dynamic)> _eventListeners = {};
  IO.Socket? _socket;
  bool _isConnected = false;
  int? _currentUserId;
  int? _currentChatRoomId;

  // Add event listener
  void on(String event, Function(dynamic) callback) {
    _eventListeners[event] = callback;
  }

  // Remove event listener
  void off(String event) {
    _eventListeners.remove(event);
  }

  // Emit event to listeners
  void _emitToListeners(String event, dynamic data) {
    final callback = _eventListeners[event];
    if (callback != null) {
      callback(data);
    }
  }

  // Getters
  bool get isConnected => _isConnected;
  int? get currentUserId => _currentUserId;
  int? get currentChatRoomId => _currentChatRoomId;

  // Initialize socket connection
  Future<void> initializeSocket(int userId) async {
    _currentUserId = userId;
    
    try {
      // Dispose existing socket if any
      if (_socket != null) {
        _socket!.disconnect();
        _socket = null;
      }

      print('🔄 Creating fresh socket connection...');
      _socket = IO.io(
        Config.chatServerUrl, // Use direct server URL
        <String, dynamic>{
          'transports': ['websocket', 'polling'],
          'autoConnect': true,
          'reconnection': true,
          'reconnectionDelay': 1000,
          'reconnectionAttempts': 5,
          'timeout': 10000, // 10 seconds timeout
          'forceNew': true, // Force new connection
        },
      );

      // Set up socket listeners FIRST before connecting
      _setupSocketListeners();
      
      // Connect socket
      _socket!.connect();
      
      print('🌐 Attempting to connect to: ${Config.chatServerUrl}');
      
      // Wait for connection
      await Future.delayed(const Duration(seconds: 2));
      
      // Register with user ID (consistent with main server)
      if (_socket!.connected) {
        _socket!.emit('register', userId);
        print('👤 Emitted register for user $userId');
      } else {
        print('❌ Socket not connected, cannot register user');
      }

    } catch (e) {
      print('Error initializing socket: $e');
      throw Exception('Failed to initialize chat connection');
    }
  }

  void _setupSocketListeners() {
    if (_socket == null) return;

    _socket!.on('connect', (_) {
      print('✅ Chat socket connected successfully');
      _isConnected = true;
      
      // Re-register after reconnection
      if (_currentUserId != null) {
        _socket!.emit('register', _currentUserId);
        print('🔄 Re-registered user $_currentUserId after reconnection');
      }
    });

    _socket!.on('connect_error', (data) {
      print('❌ Chat socket connect error: $data');
      _isConnected = false;
    });

    _socket!.on('disconnect', (data) {
      print('🔌 Chat socket disconnected: $data');
      _isConnected = false;
    });

    _socket!.on('error', (data) {
      print('❌ Chat socket error: $data');
      _isConnected = false;
    });

    _socket!.on('user_joined_success', (data) {
      print('User joined chat successfully: $data');
    });

    _socket!.on('joined_chat_room', (data) {
      print('🏠 Joined chat room event received: $data');
      if (data != null && data['chatRoomId'] != null) {
        _currentChatRoomId = data['chatRoomId'];
        print('✅ Current chat room ID set to: $_currentChatRoomId');
        print('🔍 Room ID type: ${_currentChatRoomId.runtimeType}');
      } else {
        print('❌ Invalid joined_chat_room data: $data');
      }
    });

    _socket!.on('new_message', (messageData) {
      print('New message received: $messageData');
      // Forward to chat screen listeners
      _emitToListeners('new_message', messageData);
    });

    _socket!.on('messages_read', (data) {
      print('Messages marked as read: $data');
      _emitToListeners('messages_read', data);
    });

    _socket!.on('chat_history', (data) {
      print('📜 Chat history event received: $data');
      if (data != null && data['messages'] != null) {
        print('📜 Messages count: ${data['messages'].length}');
        // Forward to chat screen listeners
        _emitToListeners('chat_history', data);
      } else {
        print('❌ Invalid chat history data: $data');
      }
    });

    _socket!.on('new_chat_notification', (data) {
      print('New chat notification: $data');
      _emitToListeners('new_chat_notification', data);
    });
  }

  // Join a specific chat room
  void joinChatRoom(int chatRoomId) {
    if (_socket == null || !_isConnected) {
      print('❌ Cannot join room - socket not connected');
      throw Exception('Socket not connected');
    }

    print('🚪 Attempting to join chat room: $chatRoomId');
    print('🔍 Socket connected: $_isConnected, Socket exists: ${_socket != null}');
    _socket!.emit('join_chat_room', {
      'chatRoomId': chatRoomId,
      'userId': _currentUserId,
    });
    print('✅ Sent join_chat_room event for room: $chatRoomId');
    
    // Add timeout to check if room was joined
    Future.delayed(const Duration(seconds: 2), () {
      if (_currentChatRoomId != chatRoomId) {
        print('❌ Room $chatRoomId not joined, current room: $_currentChatRoomId');
      } else {
        print('✅ Room $chatRoomId successfully joined');
      }
    });
  }

  // Send a message
  void sendMessage({
    required int chatRoomId,
    required String messageContent,
    String messageType = 'text',
    Map<String, dynamic>? productInfo,
    List<Map<String, dynamic>>? attachments,
    String? tempId, // ✅ Add tempId parameter
  }) {
    if (_socket == null || !_isConnected) {
      throw Exception('Socket not connected');
    }

    try {
      // Generate encryption key for this message
      final encryptionKey = ChatEncryption.generateKey();
      
      // Encrypt and compress the message content
      final encryptedContent = ChatEncryption.compressAndEncrypt(messageContent, encryptionKey);

      _socket!.emit('send_message', {
        'chatRoomId': chatRoomId,
        'senderId': _currentUserId,
        'messageContent': messageContent, // Send original for immediate display
        'encryptedContent': encryptedContent, // Send encrypted for storage
        'encryptionKey': encryptionKey, // Send key for server-side encryption
        'messageType': messageType,
        'productInfo': productInfo,
        'attachments': attachments ?? [], // Add attachments
        'tempId': tempId, // ✅ Send tempId for tracking
      });
    } catch (e) {
      print('Error encrypting message: $e');
      throw Exception('Failed to encrypt and send message');
    }
  }

  // Send product info message
  void sendProductInfoMessage({
    required int chatRoomId,
    required int productId,
    required String productName,
    required double price,
    required String image,
    int? minimumOrder,
  }) {
    final productInfo = {
      'product_id': productId,
      'product_name': productName,
      'price': price,
      'image': image,
      if (minimumOrder != null) 'minimum_order': minimumOrder,
    };

    sendMessage(
      chatRoomId: chatRoomId,
      messageContent: 'Product inquiry',
      messageType: 'product_info',
      productInfo: productInfo,
    );
  }

  // Mark messages as read
  void markMessagesRead(int chatRoomId, int messageId) {
    if (_socket == null || !_isConnected) {
      throw Exception('Socket not connected');
    }

    _socket!.emit('mark_messages_read', {
      'chatRoomId': chatRoomId,
      'userId': _currentUserId,
      'messageId': messageId,
    });
  }

  // Get chat history
  void getChatHistory(int chatRoomId, {int limit = 50, int offset = 0}) {
    if (_socket == null || !_isConnected) {
      print('❌ Cannot get chat history - socket not connected');
      throw Exception('Socket not connected');
    }

    print('📜 Requesting chat history for room: $chatRoomId');
    _socket!.emit('get_chat_history', {
      'chatRoomId': chatRoomId,
      'userId': _currentUserId,
      'limit': limit,
      'offset': offset,
    });
    print('✅ Sent get_chat_history event for room: $chatRoomId');
  }

  // Create or get chat room for product
  Future<MarketplaceChatRoom> createOrGetChatRoom({
    required int productId,
    required int buyerId,
    required int sellerId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${Config.apiBaseUrl}/chat_marketplace/create-or-get-room'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'productId': productId,
          'buyerId': buyerId,
          'sellerId': sellerId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('🏠 API Response for chat room creation: $data');
        if (data['success']) {
          final chatRoom = MarketplaceChatRoom.fromJson(data['chatRoom']);
          print('✅ Parsed chat room: ID=${chatRoom.id}, Product=${chatRoom.productId}');
          // Save to local SQLite
          await chatRoom.saveToLocal();
          return chatRoom;
        } else {
          throw Exception(data['message'] ?? 'Failed to create/get chat room');
        }
      } else {
        throw Exception('HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      print('Error creating/getting chat room: $e');
      throw Exception('Failed to create/get chat room');
    }
  }

  // Get seller by product ID
  Future<int> getSellerByProductId(int productId) async {
    try {
      final response = await http.get(
        Uri.parse('${Config.apiBaseUrl}/chat_marketplace/seller-by-product/$productId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          return data['sellerId'];
        } else {
          throw Exception(data['message'] ?? 'Seller not found');
        }
      } else if (response.statusCode == 404) {
        throw Exception('Product not found');
      } else {
        throw Exception('HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting seller by product: $e');
      throw Exception('Failed to get seller information');
    }
  }

  // Get user's chat rooms
  Future<List<MarketplaceChatRoom>> getUserChatRooms(int userId) async {
    try {
      // First try to get from local SQLite for faster response
      final localRooms = await MarketplaceChatRoom.getAllForUser(userId);
      
      // Then fetch from server for latest data
      final response = await http.get(
        Uri.parse('${Config.apiBaseUrl}/chat_marketplace/user-rooms/$userId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          final rooms = List<Map<String, dynamic>>.from(data['rooms']);
          final serverRooms = rooms.map((room) => MarketplaceChatRoom.fromJson(room)).toList();
          
          // Update local SQLite with latest data
          for (final room in serverRooms) {
            await room.saveToLocal();
          }
          
          return serverRooms;
        } else {
          throw Exception(data['message'] ?? 'Failed to get chat rooms');
        }
      } else {
        throw Exception('HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting user chat rooms: $e');
      // Return local data if server fails
      return await MarketplaceChatRoom.getAllForUser(userId);
    }
  }

  // Upload image for chat
  Future<String> uploadChatImage(File imageFile) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${Config.apiBaseUrl}/chat_marketplace/upload-image'),
      );

      request.files.add(
        await http.MultipartFile.fromPath(
          'image',
          imageFile.path,
          filename: imageFile.path.split('/').last,
        ),
      );

      final response = await request.send();

      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final data = jsonDecode(responseData);
        if (data['success']) {
          return data['imageUrl'];
        } else {
          throw Exception(data['message'] ?? 'Failed to upload image');
        }
      } else {
        throw Exception('HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      print('Error uploading chat image: $e');
      throw Exception('Failed to upload image');
    }
  }

  // Dispose socket connection
  void dispose() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket = null;
    }
    _isConnected = false;
    _currentUserId = null;
    _currentChatRoomId = null;
  }

  // ===== SOCKET CLEANUP =====

  // Disconnect socket
  void disconnect() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket = null;
    }
    _isConnected = false;
    _currentUserId = null;
    _currentChatRoomId = null;
    _eventListeners.clear();
  }

  // ===== LOCAL SQLITE OPERATIONS =====

  // Get messages from local SQLite
  Future<List<MarketplaceChatMessage>> getLocalMessages(int chatRoomId) async {
    try {
      return await MarketplaceChatMessage.getAllForChatRoom(chatRoomId);
    } catch (e) {
      print('Error getting local messages: $e');
      return [];
    }
  }

  // Save message to local SQLite
  Future<void> saveMessageToLocal(MarketplaceChatMessage message) async {
    try {
      await message.saveToLocal();
    } catch (e) {
      print('Error saving message to local: $e');
    }
  }

  // Get pending messages (failed to send)
  Future<List<MarketplaceChatMessage>> getPendingMessages(int chatRoomId) async {
    try {
      return await MarketplaceChatMessage.getPendingMessages(chatRoomId);
    } catch (e) {
      print('Error getting pending messages: $e');
      return [];
    }
  }

  // Update message status locally
  Future<void> updateMessageStatusLocally(int messageId, MessageStatus status) async {
    try {
      final message = await MarketplaceChatMessage.getFromLocal(messageId);
      if (message != null) {
        await message.updateStatus(status);
      }
    } catch (e) {
      print('Error updating message status locally: $e');
    }
  }

  // Get chat room from local SQLite
  Future<MarketplaceChatRoom?> getLocalChatRoom(int chatRoomId) async {
    try {
      return await MarketplaceChatRoom.getFromLocal(chatRoomId);
    } catch (e) {
      print('Error getting local chat room: $e');
      return null;
    }
  }

  // Update chat room locally
  Future<void> updateChatRoomLocally(MarketplaceChatRoom chatRoom) async {
    try {
      await chatRoom.updateToLocal();
    } catch (e) {
      print('Error updating chat room locally: $e');
    }
  }

  // Get participant from local SQLite
  Future<MarketplaceChatParticipant?> getLocalParticipant(int chatRoomId, int userId) async {
    try {
      return await MarketplaceChatParticipant.getParticipant(chatRoomId, userId);
    } catch (e) {
      print('Error getting local participant: $e');
      return null;
    }
  }

  // Save participant to local SQLite
  Future<void> saveParticipantToLocal(MarketplaceChatParticipant participant) async {
    try {
      await participant.saveToLocal();
    } catch (e) {
      print('Error saving participant to local: $e');
    }
  }

  // Clear all local data (for logout)
  Future<void> clearAllLocalData() async {
    try {
      await MarketplaceChatDatabase.clearAllData();
    } catch (e) {
      print('Error clearing local data: $e');
    }
  }

  // Sync pending messages with server
  Future<void> syncPendingMessages() async {
    if (_currentChatRoomId == null) return;

    try {
      final pendingMessages = await getPendingMessages(_currentChatRoomId!);
      
      for (final message in pendingMessages) {
        // Retry sending pending messages
        await message.updateLocalStatus(MessageLocalStatus.sending);
        
        // Resend via socket
        _socket!.emit('send_message', {
          'chatRoomId': message.chatRoomId,
          'senderId': message.senderId,
          'messageContent': message.messageContent,
          'messageType': message.messageType,
          'productInfo': message.productInfo?.toJson(),
        });
      }
    } catch (e) {
      print('Error syncing pending messages: $e');
    }
  }
}
