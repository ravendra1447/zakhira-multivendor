import 'dart:async';
import 'dart:io' as IO;
import 'package:socket_io_client/socket_io_client.dart';
import '../marketplace/marketplace_chat_service.dart';
import '../../config.dart';
import 'package:hive/hive.dart';

class SellerNotificationService {
  static final SellerNotificationService _instance = SellerNotificationService._internal();
  factory SellerNotificationService() => _instance;
  SellerNotificationService._internal();

  final MarketplaceChatService _chatService = MarketplaceChatService();
  IO.Socket? _socket;
  Timer? _heartbeatTimer;
  bool _isInitialized = false;
  int? _sellerId;

  // Initialize seller notification service
  Future<void> initialize(int sellerId) async {
    if (_isInitialized) return;
    
    _sellerId = sellerId;
    _isInitialized = true;
    
    print('🔔 Initializing seller notification service for user: $sellerId');
    
    await _connectSocket();
    _startHeartbeat();
  }

  // Connect to socket and listen for notifications
  Future<void> _connectSocket() async {
    try {
      await _chatService.initializeSocket(_sellerId!);
      
      // Listen for notifications
      _chatService.on('new_chat_notification', _handleNewNotification);
      
      print('✅ Seller notification service connected');
    } catch (e) {
      print('❌ Failed to connect seller notification service: $e');
      // Retry after 5 seconds
      Timer(const Duration(seconds: 5), () => _connectSocket());
    }
  }

  // Handle new chat notifications
  void _handleNewNotification(dynamic data) {
    final notification = data as Map<String, dynamic>;
    final chatRoomId = notification['chatRoomId'];
    final senderId = notification['senderId'];
    final message = notification['message'];
    final productInfo = notification['productInfo'];
    
    print('🔔 Seller received notification: $notification');
    
    // Show local notification (you can integrate with flutter_local_notifications)
    print('📱 New customer inquiry: ${productInfo?['product_name'] ?? 'Unknown product'}');
    print('💬 Message: $message');
    print('👤 From customer: $senderId');
    print('🆔 Chat Room: $chatRoomId');
  }

  // Start heartbeat to keep connection alive
  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_chatService.isConnected) {
        print('💓 Seller service heartbeat - connection active');
      } else {
        print('💓 Seller service heartbeat - reconnecting...');
        _connectSocket();
      }
    });
  }

  // Disconnect service
  void disconnect() {
    _heartbeatTimer?.cancel();
    _chatService.off('new_chat_notification');
    _chatService.disconnect();
    _isInitialized = false;
    print('🔌 Seller notification service disconnected');
  }

  // Check if service is connected
  bool get isConnected => _chatService.isConnected;
}
