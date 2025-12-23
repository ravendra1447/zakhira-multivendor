import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' hide Message;
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import '../main.dart';
import '../models/chat_model.dart' hide MessageAdapter;
import '../screens/chat_screen.dart';
import '../services/local_auth_service.dart';
import '../utils/sound_utils.dart';

class MyFirebaseMessagingService {
  static final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  static final _messageStreamController = StreamController<Message>.broadcast();
  static Stream<Message> get onNewMessage => _messageStreamController.stream;

  static const String _fcmTokenSaveUrl = "http://184.168.126.71:3000/api/save-fcm-token";

  /// 🛑 Background message handler को PUBLIC बनाएं
  @pragma('vm:entry-point')
  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    print("💤 Background message: ${message.messageId}");

    // Ensure Hive is properly initialized in background
    await Hive.initFlutter();
    Hive.registerAdapter(MessageAdapter());

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
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    final DarwinInitializationSettings initializationSettingsIOS =
    DarwinInitializationSettings();

    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        // when user taps notification
        final payload = response.payload;
        if (payload != null) {
          try {
            final data = jsonDecode(payload);
            _navigateToChat(data);
          } catch (e) {
            print("❌ Notification tap payload parse error: $e");
          }
        }
      },
    );

    // ✅ Foreground Message Listener
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      print('📩 Foreground message received: ${message.notification?.title}');
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
      _navigateToChat(message.data);
    });

    // ✅ Check if app was launched via terminated notification
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
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

  /// Handle Navigation on notification tap
  static void _navigateToChat(Map<String, dynamic> data) {
    try {
      final chatId = int.tryParse(data['chatId'] ?? '');
      final otherUserId = int.tryParse(data['otherUserId'] ?? '');
      final otherUserName = data['otherUserName'];

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
      }
    } catch (e) {
      print("❌ Error navigating to chat: $e");
    }
  }

  /// Local Notification - Used only for background messages
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'chat_channel',
        'Chat Notifications',
        channelDescription: 'Chat app notifications',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
      );

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
      );

      await _flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        platformDetails,
        payload: jsonEncode(message.data),
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
}