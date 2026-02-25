import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import '../config.dart';
import 'local_auth_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Initialize notification services
  Future<void> initialize() async {
    // Request notification permissions
    await _requestPermissions();

    // Initialize local notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    
    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Initialize FCM
    await _initializeFCM();
  }

  // Request notification permissions
  Future<void> _requestPermissions() async {
    final messaging = FirebaseMessaging.instance;
    
    // Request permission for iOS
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted permission');
    } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
      print('User granted provisional permission');
    } else {
      print('User declined or has not accepted permission');
    }
  }

  // Initialize FCM and get token
  Future<void> _initializeFCM() async {
    final messaging = FirebaseMessaging.instance;
    
    // Get the FCM token
    String? token = await messaging.getToken();
    print('FCM Token: $token');
    
    // Save token to backend
    if (token != null) {
      await _saveFCMToken(token);
    }

    // Listen for token refresh
    messaging.onTokenRefresh.listen((token) {
      print('FCM Token refreshed: $token');
      _saveFCMToken(token);
    });

    // Listen for foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Listen for background messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle notification when app is opened from notification
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
  }

  // Save FCM token to backend
  Future<void> _saveFCMToken(String token) async {
    try {
      final userId = await _getCurrentUserId();
      if (userId != null) {
        final response = await http.post(
          Uri.parse('${Config.baseNodeApiUrl}/notifications/save-fcm-token'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'userId': userId,
            'fcmToken': token,
          }),
        );

        if (response.statusCode == 200) {
          print('FCM token saved successfully');
        } else {
          print('Failed to save FCM token: ${response.body}');
        }
      }
    } catch (e) {
      print('Error saving FCM token: $e');
    }
  }

  // Get current user ID
  Future<String?> _getCurrentUserId() async {
    try {
      final userId = LocalAuthService.getUserId(); // Static method call
      return userId?.toString();
    } catch (e) {
      print('Error getting current user ID: $e');
      return null;
    }
  }

  // Handle foreground messages
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('Received foreground message: ${message.messageId}');
    
    // Show local notification
    await _showLocalNotification(
      message.notification?.title ?? 'New Notification',
      message.notification?.body ?? 'You have a new message',
      message.data,
    );
  }

  // Handle message when app is opened from notification
  void _handleMessageOpenedApp(RemoteMessage message) {
    print('App opened from notification: ${message.messageId}');
    
    // Navigate based on notification type
    _navigateBasedOnNotification(message.data);
  }

  // Show local notification
  Future<void> _showLocalNotification(String title, String body, Map<String, dynamic> data) async {
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'whatsapp_chat_channel',
      'WhatsApp Chat Notifications',
      channelDescription: 'Notifications for orders and updates',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      styleInformation: BigTextStyleInformation(
        body,
        htmlFormatBigText: true,
        contentTitle: title,
        htmlFormatContentTitle: true,
      ),
    );

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      platformChannelSpecifics,
      payload: jsonEncode(data),
    );
  }

  // Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) {
      final data = jsonDecode(payload);
      _navigateBasedOnNotification(data);
    }
  }

  // Navigate based on notification type
  void _navigateBasedOnNotification(Map<String, dynamic> data) {
    final type = data['type'];
    
    switch (type) {
      case 'order_confirmation':
        // Navigate to order details screen
        // Navigator.pushNamed(context, '/order-details', arguments: data['orderId']);
        break;
      case 'new_order_admin':
        // Navigate to admin orders screen
        // Navigator.pushNamed(context, '/admin-orders');
        break;
      case 'order_status_update':
        // Navigate to order details screen
        // Navigator.pushNamed(context, '/order-details', arguments: data['orderId']);
        break;
      default:
        // Navigate to notifications screen
        // Navigator.pushNamed(context, '/notifications');
        break;
    }
  }

  // Get user notifications
  static Future<List<Map<String, dynamic>>> getUserNotifications() async {
    try {
      final notificationService = NotificationService();
      final userId = await notificationService._getCurrentUserId();
      if (userId == null) return [];

      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/notifications/user/$userId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['notifications']);
      } else {
        throw Exception('Failed to fetch notifications');
      }
    } catch (e) {
      print('Error fetching notifications: $e');
      return [];
    }
  }

  // Mark notification as read
  static Future<void> markNotificationAsRead(int notificationId) async {
    try {
      final response = await http.put(
        Uri.parse('${Config.baseNodeApiUrl}/notifications/$notificationId/read'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to mark notification as read');
      }
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  // Get unread notification count
  static Future<int> getUnreadNotificationCount() async {
    try {
      final notificationService = NotificationService();
      final userId = await notificationService._getCurrentUserId();
      if (userId == null) return 0;

      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/notifications/user/$userId/unread-count'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['count'] ?? 0;
      } else {
        return 0;
      }
    } catch (e) {
      print('Error getting unread count: $e');
      return 0;
    }
  }
}

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Handling a background message: ${message.messageId}');
  
  // Show local notification when app is in background
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'whatsapp_chat_channel',
    'WhatsApp Chat Notifications',
    channelDescription: 'Notifications for orders and updates',
    importance: Importance.high,
    priority: Priority.high,
    showWhen: true,
    icon: '@mipmap/ic_launcher',
  );

  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);

  await flutterLocalNotificationsPlugin.show(
    0,
    message.notification?.title ?? 'New Notification',
    message.notification?.body ?? 'You have a new message',
    platformChannelSpecifics,
    payload: jsonEncode(message.data),
  );
}
