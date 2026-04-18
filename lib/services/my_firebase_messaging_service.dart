import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as fln;
import 'package:wakelock_plus/wakelock_plus.dart';
import '../config.dart';
import '../main.dart'; // Import for navigatorKey
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import '../models/chat_model.dart' hide MessageAdapter;
import '../models/marketplace/marketplace_chat_room.dart';
import '../models/product.dart'; // Add Product import
import '../screens/chat_screen.dart';
import '../screens/marketplace/marketplace_chat_screen.dart';
import '../screens/order/admin_all_orders_screen.dart';
import '../screens/order/order_detail_screen.dart';
import '../screens/order/dashboard_screen.dart';
import '../services/local_auth_service.dart';
import '../utils/sound_utils.dart';
import '../config.dart';

class MyFirebaseMessagingService {
  static String get _fcmTokenSaveUrl => '${Config.baseNodeApiUrl}/save_fcm_token';
  static final fln.FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = fln.FlutterLocalNotificationsPlugin();
  static final _messageStreamController = StreamController<Message>.broadcast();
  static Stream<Message> get onNewMessage => _messageStreamController.stream;

  /// 🛑 Background message handler को PUBLIC बनाएं
  @pragma('vm:entry-point')
  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    print("💤 Background message: ${message.messageId}");

    // Ensure Hive is properly initialized in background
    await Hive.initFlutter();
    Hive.registerAdapter(MessageAdapter());

    // Check if it's an order notification
    if (message.data['type'] == 'order_confirmation' ||
        message.data['type'] == 'new_order_admin' ||
        message.data['type'] == 'order_status_update') {
      // Handle order notifications in background
      await _showOrderLocalNotification(message);
      return;
    }

    if (message.data.isNotEmpty) {
      final msg = Message.fromMap(message.data);
      final box = await Hive.openBox<Message>('messages');
      await box.put(msg.messageId, msg);
    }

    await _showLocalNotification(message);
  }

  /// Initialize FCM and Local Notifications
  static Future<void> initialize() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // 🔐 Permission for iOS & Android
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 📱 Local Notification Init
    const fln.AndroidInitializationSettings initializationSettingsAndroid =
    fln.AndroidInitializationSettings('@mipmap/ic_launcher');

    final fln.DarwinInitializationSettings initializationSettingsIOS =
    fln.DarwinInitializationSettings();

    final fln.InitializationSettings initializationSettings = fln.InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        // when user taps notification
        final payload = response.payload;
        print("🔔 Notification tapped with payload: $payload"); // Debug log

        if (payload != null) {
          try {
            final data = json.decode(payload);
            print("🔔 Parsed notification data: $data"); // Debug log
            _navigateToChat(data);
          } catch (e) {
            print("❌ Notification tap payload parse error: $e");
          }
        } else {
          print("❌ Notification payload is null");
        }
      },
    );

    // ✅ Foreground Message Listener
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      print('📩 Foreground message received: ${message.notification?.title}');

      // Check if it's an order notification
      if (message.data['type'] == 'order_confirmation' ||
          message.data['type'] == 'new_order_admin' ||
          message.data['type'] == 'order_status_update') {
        // Handle order notifications
        await _handleOrderNotification(message);
        return;
      }

      // Check if it's a marketplace chat notification
      if (message.data['type'] == 'new_chat_message') {
        // Handle marketplace chat notifications
        await _handleMarketplaceChatNotification(message);
        return;
      }

      if (message.data.isNotEmpty) {
        // ✅ DEBUG: Log Firebase data to check for group_id
        print('🔍 [FIREBASE DATA] All keys: ${message.data.keys.toList()}');
        print('🔍 [FIREBASE DATA] group_id: ${message.data["group_id"]}, image_index: ${message.data["image_index"]}, total_images: ${message.data["total_images"]}');

        final msg = Message.fromMap(message.data);

        // ✅ DEBUG: Log extracted groupId
        print('🔍 [FIREBASE MSG] Extracted - groupId: ${msg.groupId}, imageIndex: ${msg.imageIndex}, totalImages: ${msg.totalImages}');

        final box = Hive.box<Message>('messages');
        await box.put(msg.messageId, msg);
        SoundUtils.playReceiveSound();
        _messageStreamController.sink.add(msg);
      }
      // 👉 Foreground में popup नहीं दिखाना (WhatsApp जैसा)
    });

    // ✅ Background / Terminated - Click Listener
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      // Handle marketplace chat navigation
      if (message.data['type'] == 'new_chat_message') {
        _navigateToMarketplaceChat(message.data);
        return;
      }

      _navigateToChat(message.data);
    });

    // ✅ Check if app was launched via terminated notification
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      // Handle marketplace chat navigation
      if (initialMessage.data['type'] == 'new_chat_message') {
        _navigateToMarketplaceChat(initialMessage.data);
        return;
      }

      _navigateToChat(initialMessage.data);
    }

    // ✅ Background notification display - अब public method use करें
    FirebaseMessaging.onBackgroundMessage(handleBackgroundMessage);

    // ♻️ Token refresh listener
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      saveFcmTokenToServer(newToken: newToken);
    });

    await saveFcmTokenToServer();
  }

  /// Handle Order Notifications
  static Future<void> _handleOrderNotification(RemoteMessage message) async {
    print('🛒 Order notification received: ${message.notification?.title}');

    // Show local notification for orders (even in foreground)
    await _showOrderLocalNotification(message);

    // Play notification sound
    SoundUtils.playReceiveSound();
  }

  /// Show Order Local Notification
  static Future<void> _showOrderLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;

    final fln.AndroidNotificationDetails androidDetails = fln.AndroidNotificationDetails(
      'order_channel',
      'Order Notifications',
      channelDescription: 'Order updates and confirmations',
      importance: fln.Importance.max,
      priority: fln.Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      largeIcon: const fln.DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      styleInformation: fln.BigTextStyleInformation(
        notification?.body ?? 'You have a new order update',
        htmlFormatBigText: true,
        contentTitle: notification?.title ?? 'Order Update',
        htmlFormatContentTitle: true,
      ),
    );

    final fln.NotificationDetails platformDetails = fln.NotificationDetails(
      android: androidDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      notification?.hashCode ?? DateTime.now().millisecondsSinceEpoch.remainder(100000),
      notification?.title ?? 'Order Update',
      notification?.body ?? 'You have a new order update',
      platformDetails,
      payload: json.encode(message.data),
    );
  }

  /// Handle Navigation on notification tap
  static void _navigateToChat(Map<String, dynamic> data) {
    try {
      print("🔍 Navigation data received: $data");

      // Check if it's an order notification
      final type = data['type'];
      print("🔍 Notification type: $type"); // Debug log

      if (type == 'order_confirmation' || type == 'new_order_admin' || type == 'order_status_update') {
        _navigateToOrder(data);
        return;
      }

      // Check if it's a marketplace chat notification
      if (type == 'new_chat_message') {
        _navigateToMarketplaceChat(data);
        return;
      }

      final chatId = int.tryParse(data['chatId'] ?? '');
      final otherUserId = int.tryParse(data['otherUserId'] ?? '');
      final otherUserName = data['otherUserName'];

      print("🔍 Chat data - chatId: $chatId, otherUserId: $otherUserId, otherUserName: $otherUserName"); // Debug log

      if (chatId != null && otherUserId != null && otherUserName != null) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              chatId: chatId,
              otherUserId: otherUserId,
              otherUserName: otherUserName,
            ),
          ),
        );
      } else {
        print("❌ Missing data for navigation");
        print("❌ Available keys in data: ${data.keys.toList()}"); // Debug log
      }
    } catch (e) {
      print("❌ Error navigating to chat: $e");
    }
  }

  /// Navigate to Marketplace Chat
  static Future<void> _navigateToMarketplaceChat(Map<String, dynamic> data) async {
    try {
      print("🏪 Navigating to marketplace chat with data: $data");

      final chatRoomId = int.tryParse(data['chatRoomId']?.toString() ?? '');
      final senderId = int.tryParse(data['senderId']?.toString() ?? '');

      if (chatRoomId != null && senderId != null) {
        // Get current user ID
        final currentUserId = LocalAuthService.getUserId();

        if (currentUserId == null) {
          print("❌ User not logged in for marketplace chat");
          return;
        }

        // Get proper chat room data from server instead of creating mock
        print("🔍 Fetching chat room data for ID: $chatRoomId");
        try {
          final response = await http.get(
            Uri.parse('${Config.apiBaseUrl}/chat_marketplace/room/$chatRoomId'),
            headers: {
              'Content-Type': 'application/json',
            },
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data['success'] && data['chatRoom'] != null) {
              final chatRoom = MarketplaceChatRoom.fromJson(data['chatRoom']);
              print("✅ Loaded chat room from server: ID=${chatRoom.id}, Product=${chatRoom.productId}");

              // Load product info if not available
              Product? product;
              if (chatRoom.productName != null && chatRoom.productName!.isNotEmpty) {
                // Parse product images - handle both String and List types
                List<String> imageList = [];
                if (chatRoom.productImages != null) {
                  if (chatRoom.productImages is String) {
                    // If it's a JSON string, try to parse it
                    try {
                      final parsed = json.decode(chatRoom.productImages as String);
                      if (parsed is List) {
                        imageList = parsed.map((item) => item.toString()).toList();
                      }
                    } catch (e) {
                      // If parsing fails, treat as single image string
                      imageList = [chatRoom.productImages as String];
                    }
                  } else if (chatRoom.productImages is List) {
                    // If it's already a list, use it directly
                    imageList = (chatRoom.productImages as List).map((item) => item.toString()).toList();
                  }
                }

                product = Product(
                  id: chatRoom.productId,
                  name: chatRoom.productName ?? 'Unknown Product',
                  userId: chatRoom.sellerId,
                  images: imageList,
                  description: '',
                  availableQty: '0',
                  status: 'publish',
                  category: '',
                  subcategory: '',
                  priceSlabs: [],
                  variations: [],
                  sizes: [],
                  attributes: {},
                  selectedAttributeValues: {},
                  price: 0.0,
                  marketplaceEnabled: true,
                  stockMode: 'simple',
                  stockByColorSize: null,
                  instagramUrl: '',
                  sellerName: chatRoom.sellerName,
                  createdAt: chatRoom.createdAt,
                  updatedAt: chatRoom.updatedAt,
                );
              }

              navigatorKey.currentState?.push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    chatId: chatRoom.id,
                    otherUserId: currentUserId == chatRoom.sellerId 
                        ? chatRoom.buyerId 
                        : chatRoom.sellerId,
                    otherUserName: currentUserId == chatRoom.sellerId 
                        ? "Buyer" 
                        : "Seller",
                    isMarketplaceChat: true, // ✅ Enable marketplace chat
                    marketplaceChatRoom: chatRoom, // ✅ Pass chat room data
                    product: product, // ✅ Pass product info
                  ),
                ),
              );
            } else {
              print("❌ Failed to load chat room: ${data['message']}");
            }
          } else {
            print("❌ HTTP Error loading chat room: ${response.statusCode}");
            // Fallback to mock room
            _createMockChatRoomAndNavigate(chatRoomId, senderId, currentUserId, data);
          }
        } catch (e) {
          print("❌ Error loading chat room: $e");
          // Fallback to mock room
          _createMockChatRoomAndNavigate(chatRoomId, senderId, currentUserId, data);
        }
      } else {
        print("❌ Missing marketplace chat data - chatRoomId: $chatRoomId, senderId: $senderId");
      }
    } catch (e) {
      print("❌ Error navigating to marketplace chat: $e");
    }
  }

  // Create mock chat room as fallback
  static void _createMockChatRoomAndNavigate(int chatRoomId, int senderId, int currentUserId, Map<String, dynamic> data) {
    try {
      // Create mock chat room for navigation
      final chatRoom = MarketplaceChatRoom(
        id: chatRoomId,
        productId: 0, // Will be updated from server
        buyerId: currentUserId == senderId ? 1 : senderId, // Determine buyer/seller
        sellerId: currentUserId == senderId ? senderId : currentUserId,
        status: 'active',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Load product info if available
      Product? product;

      if (data['productInfo'] != null) {
        try {
          dynamic productData = data['productInfo'];
          if (productData is Map<String, dynamic>) {
            // Parse images - handle both String and List types
            List<String> imageList = [];
            if (productData['images'] != null) {
              if (productData['images'] is String) {
                // If it's a JSON string, try to parse it
                try {
                  final parsed = json.decode(productData['images']);
                  if (parsed is List) {
                    imageList = parsed.map((item) => item.toString()).toList();
                  }
                } catch (e) {
                  // If parsing fails, treat as single image string
                  imageList = [productData['images']];
                }
              } else if (productData['images'] is List) {
                // If it's already a list, use it directly
                imageList = (productData['images'] as List).map((item) => item.toString()).toList();
              }
            }

            product = Product(
              id: productData['id'] ?? 0,
              name: productData['name'] ?? 'Unknown Product',
              userId: productData['userId'] ?? 0,
              images: imageList,
              description: productData['description'] ?? '',
              availableQty: productData['availableQty']?.toString() ?? '0',
              status: productData['status'] ?? 'publish',
              category: productData['category'],
              subcategory: productData['subcategory'],
              priceSlabs: productData['priceSlabs'] is List
                  ? (productData['priceSlabs'] as List).map((item) => Map<String, dynamic>.from(item)).toList()
                  : [],
              attributes: productData['attributes'] is Map
                  ? Map<String, List<String>>.from(
                  Map<String, dynamic>.from(productData['attributes']).map(
                          (key, value) => MapEntry(key, List<String>.from(value))
                  )
              )
                  : {},
              selectedAttributeValues: productData['selectedAttributeValues'] is Map
                  ? Map<String, String>.from(productData['selectedAttributeValues'])
                  : {},
              variations: productData['variations'] is List
                  ? (productData['variations'] as List).map((item) => Map<String, dynamic>.from(item)).toList()
                  : [],
              sizes: productData['sizes'] is List
                  ? (productData['sizes'] as List).map((item) => item.toString()).toList()
                  : [],
              price: double.tryParse(productData['price']?.toString() ?? '0') ?? 0.0,
              marketplaceEnabled: (productData['marketplaceEnabled'] is bool
                  ? productData['marketplaceEnabled']
                  : (productData['marketplaceEnabled'] is int
                  ? productData['marketplaceEnabled'] == 1
                  : true)),
              stockMode: productData['stockMode'] ?? 'simple',
              stockByColorSize: productData['stockByColorSize'] != null
                  ? Map<String, Map<String, int>>.from(productData['stockByColorSize'])
                  : null,
              instagramUrl: productData['instagramUrl'],
              sellerName: productData['sellerName'],
              createdAt: productData['createdAt'] != null
                  ? DateTime.parse(productData['createdAt'])
                  : null,
              updatedAt: productData['updatedAt'] != null
                  ? DateTime.parse(productData['updatedAt'])
                  : null,
            );
          }
        } catch (e) {
          print("❌ Error parsing product info: $e");
        }
      } else {
        // Try to load product info from chat room
        print("🔍 No product info in notification, trying to load from chat room...");
        _loadProductFromChatRoom(chatRoomId, chatRoom, currentUserId);
      }

      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: chatRoom.id,
            otherUserId: currentUserId == chatRoom.sellerId 
                ? chatRoom.buyerId 
                : chatRoom.sellerId,
            otherUserName: currentUserId == chatRoom.sellerId 
                ? "Buyer" 
                : "Seller",
            isMarketplaceChat: true, // ✅ Enable marketplace chat
            marketplaceChatRoom: chatRoom, // ✅ Pass chat room data
            product: product, // ✅ Pass product info
          ),
        ),
      );
    } catch (e) {
      print("❌ Error creating mock chat room: $e");
    }
  }

  // Load product info from chat room
  static void _loadProductFromChatRoom(int chatRoomId, MarketplaceChatRoom chatRoom, int currentUserId) {
    try {
      // TODO: Implement API call to get product info from chat room
      print("🔄 Loading product info for chat room: $chatRoomId");
      // For now, we'll update the chat room after navigation
    } catch (e) {
      print("❌ Error loading product from chat room: $e");
    }
  }

  /// Navigate to Order Details/Admin Dashboard
  static void _navigateToOrder(Map<String, dynamic> data) {
    try {
      final type = data['type'];
      final orderId = data['orderId'];

      if (type == 'new_order_admin') {
        // Navigate directly to order details for admin
        try {
          final orderIdInt = int.parse(orderId);
          navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => OrderDetailScreen(orderId: orderIdInt),
            ),
                (route) => false,
          );
          print("🛒 Admin navigated to order details for new order - Order ID: $orderId");
        } catch (e) {
          print("❌ Error parsing orderId or navigating for admin: $e");
          // Fallback to dashboard if order details fail
          navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => DashboardScreen(),
            ),
                (route) => false,
          );
        }
      } else if (type == 'order_confirmation') {
        // Navigate to user order details
        try {
          final orderIdInt = int.parse(orderId);
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => OrderDetailScreen(orderId: orderIdInt),
            ),
          );
          print("🛒 Navigated to order details for Order ID: $orderId");
        } catch (e) {
          print("❌ Error parsing orderId or navigating: $e");
        }
      } else if (type == 'order_status_update') {
        // Navigate to order details
        try {
          final orderIdInt = int.parse(orderId);
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => OrderDetailScreen(orderId: orderIdInt),
            ),
          );
          print("🛒 Navigated to order details for status update - Order ID: $orderId");
        } catch (e) {
          print("❌ Error parsing orderId or navigating: $e");
        }
      }
    } catch (e) {
      print("❌ Error navigating to order: $e");
    }
  }

  /// Local Notification - Used only for background messages
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      const fln.AndroidNotificationDetails androidDetails = fln.AndroidNotificationDetails(
        'chat_channel',
        'Chat Notifications',
        channelDescription: 'Chat app notifications',
        importance: fln.Importance.max,
        priority: fln.Priority.high,
        showWhen: true,
      );

      const fln.NotificationDetails platformDetails = fln.NotificationDetails(
        android: androidDetails,
      );

      await _flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        platformDetails,
        payload: json.encode(message.data),
      );
    }
  }

  /// Get FCM token
  static Future<String?> getFcmToken() async {
    return await FirebaseMessaging.instance.getToken();
  }

  /// Save FCM token to Server
  static Future<void> saveFcmTokenToServer({String? newToken}) async {
    String? token = newToken ?? await getFcmToken();
    if (token == null) {
      print("⚠️ FCM Token null");
      return;
    }

    final userId = LocalAuthService.getUserId();
    if (userId == null) return;

    try {
      final res = await http.post(
        Uri.parse(_fcmTokenSaveUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          "fcmToken": token,
        }),
      );

      if (res.statusCode == 200) {
        print("✅ FCM token saved");
      } else {
        print("❌ Failed to save token: ${res.body}");
      }
    } catch (e) {
      print("⚠️ Error saving FCM token: $e");
    }
  }

  /// Handle marketplace chat notifications
  static Future<void> _handleMarketplaceChatNotification(RemoteMessage message) async {
    print('🏪 Marketplace chat notification received: ${message.notification?.title}');

    final chatRoomId = message.data['chatRoomId'];
    final senderId = message.data['senderId'];
    final productInfo = message.data['productInfo'];

    print('📱 Chat Room: $chatRoomId, Sender: $senderId, Product: $productInfo');

    // Show local notification for marketplace chat
    await _showMarketplaceChatNotification(
      title: message.notification?.title ?? 'New Message',
      body: message.notification?.body ?? 'You have a new marketplace message',
      chatRoomId: chatRoomId,
      senderId: senderId,
      productInfo: productInfo,
    );
  }

  /// Show local notification for marketplace chat
  static Future<void> _showMarketplaceChatNotification({
    required String title,
    required String body,
    String? chatRoomId,
    String? senderId,
    String? productInfo,
  }) async {
    const fln.AndroidNotificationDetails androidPlatformChannelSpecifics =
    fln.AndroidNotificationDetails(
      'marketplace_chat',
      'Marketplace Chat',
      channelDescription: 'Marketplace chat notifications',
      importance: fln.Importance.high,
      priority: fln.Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      largeIcon: const fln.DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    );

    const fln.NotificationDetails platformChannelSpecifics =
    fln.NotificationDetails(android: androidPlatformChannelSpecifics);

    await _flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      platformChannelSpecifics,
      payload: json.encode({
        'type': 'new_chat_message',
        'chatRoomId': chatRoomId,
        'senderId': senderId,
        'productInfo': productInfo,
      }),
    );
  }

  /// Get current context
  static BuildContext? _getCurrentContext() {
    // Try to get current context from navigator
    return navigatorKey.currentContext;
  }
}