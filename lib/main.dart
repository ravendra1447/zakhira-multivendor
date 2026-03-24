import 'dart:isolate';
import 'dart:ui';
import 'dart:developer'; // Added for logging
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as fln;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'services/cart_service.dart';

import 'package:whatsappchat/models/chat_model.dart';
import 'package:whatsappchat/models/contact.dart';
import 'package:whatsappchat/screens/chat_list_screen.dart';
import 'package:whatsappchat/screens/contact_list_page.dart';
import 'package:whatsappchat/services/local_auth_service.dart';
import 'package:whatsappchat/services/chat_service.dart';
import 'package:whatsappchat/services/my_firebase_messaging_service.dart';
import 'package:whatsappchat/services/contact_service_optimized.dart'; // ✅ NEW: Optimized Service Import
import 'package:whatsappchat/screens/chat_home.dart' hide Contact;
import 'package:whatsappchat/screens/phone_otp_login.dart';
import 'package:whatsappchat/screens/verify_mpin_page.dart';
import 'package:whatsappchat/utils/sound_utils.dart';
import 'package:whatsappchat/theme/app_theme.dart';
import 'package:whatsappchat/services/cache_initializer.dart';
import 'package:whatsappchat/services/http_overrides.dart';
import 'package:whatsappchat/services/theme_service.dart';

// ----------------- Hive Models -----------------
@HiveType(typeId: 3)
class Chat {
  @HiveField(0)
  final int chatId;
  @HiveField(1)
  final List<int> userIds;
  @HiveField(2)
  final String chatTitle;
  @HiveField(3)
  final int? contactId;

  Chat({
    required this.chatId,
    required this.userIds,
    required this.chatTitle,
    this.contactId,
  });
}

class MessageAdapter extends TypeAdapter<Message> {
  @override
  final int typeId = 0;

  @override
  Message read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Message(
      messageId: fields[0] as String,
      chatId: fields[1] as int,
      senderId: fields[2] as int,
      receiverId: fields[3] as int,
      messageContent: fields[4] as String,
      messageType: fields[5] as String,
      isRead: fields[6] as int,
      timestamp: fields[7] as DateTime,
      isDelivered: fields[8] as int,
      senderName: fields[9] as String?,
      receiverName: fields[10] as String?,
      senderPhoneNumber: fields[11] as String?,
      receiverPhoneNumber: fields[12] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Message obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.messageId)
      ..writeByte(1)
      ..write(obj.chatId)
      ..writeByte(2)
      ..write(obj.senderId)
      ..writeByte(3)
      ..write(obj.receiverId)
      ..writeByte(4)
      ..write(obj.messageContent)
      ..writeByte(5)
      ..write(obj.messageType)
      ..writeByte(6)
      ..write(obj.isRead)
      ..writeByte(7)
      ..write(obj.timestamp)
      ..writeByte(8)
      ..write(obj.isDelivered)
      ..writeByte(9)
      ..write(obj.senderName)
      ..writeByte(10)
      ..write(obj.receiverName)
      ..writeByte(11)
      ..write(obj.senderPhoneNumber)
      ..writeByte(12)
      ..write(obj.receiverPhoneNumber);
  }
}

class ContactAdapter extends TypeAdapter<Contact> {
  @override
  final int typeId = 4;

  @override
  Contact read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    // Ensure all fields used by the service are read
    return Contact(
      contactId: fields[0] as int,
      ownerUserId: fields[1] as int,
      contactName: fields[2] as String,
      contactPhone: fields[3] as String,
      isOnApp: fields[4] as bool,
      appUserId: fields[5] as int?,
      // ✅ Added fields to be consistent with Contact model used in service
      isDeleted: fields[6] as bool,
      updatedAt: fields[7] as DateTime,
      lastMessageTime: fields[8] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, Contact obj) {
    // ✅ Updated to write all 9 fields (0-8)
    writer
      ..writeByte(9) // Total number of fields
      ..writeByte(0)
      ..write(obj.contactId)
      ..writeByte(1)
      ..write(obj.ownerUserId ?? 0) // Handle nullable int
      ..writeByte(2)
      ..write(obj.contactName)
      ..writeByte(3)
      ..write(obj.contactPhone)
      ..writeByte(4)
      ..write(obj.isOnApp)
      ..writeByte(5)
      ..write(obj.appUserId)
    // ✅ New fields for service compatibility
      ..writeByte(6)
      ..write(obj.isDeleted)
      ..writeByte(7)
      ..write(obj.updatedAt)
      ..writeByte(8)
      ..write(obj.lastMessageTime);
  }
}

class ChatAdapter extends TypeAdapter<Chat> {
  @override
  final int typeId = 3;

  @override
  Chat read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Chat(
      chatId: fields[0] as int,
      userIds: (fields[1] as List).cast<int>(),
      chatTitle: fields[2] as String,
      contactId: fields[3] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, Chat obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.chatId)
      ..writeByte(1)
      ..write(obj.userIds)
      ..writeByte(2)
      ..write(obj.chatTitle)
      ..writeByte(3)
      ..write(obj.contactId);
  }
}

// ----------------- Global NavigatorKey -----------------
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ----------------- Local Notifications -----------------
final fln.FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
fln.FlutterLocalNotificationsPlugin();

// ✅ Notification Channel Setup
const String channelId = 'chat_channel';
const String channelName = 'Chat Notifications';

// ----------------- FCM Background Handler -----------------
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 🛑 अब public method को call करें
  await MyFirebaseMessagingService.handleBackgroundMessage(message);
}

// ----------------- MAIN -----------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  //ImpellerInitializer.disable();

  // Firebase Init
  await Firebase.initializeApp();

  // ❌ REMOVED: startupSync call. The sync will be triggered later via Isolate.spawn.
  // ContactService.startupSync(ownerUserId: 0);

  // Initialize Cache Services First
  await CacheInitializer.initializeAll();

  // Hive Init
  await Hive.initFlutter();
  Hive.registerAdapter(MessageAdapter());
  Hive.registerAdapter(ContactAdapter());
  Hive.registerAdapter(ChatAdapter());
  await Hive.openBox<Message>('messages');
  await Hive.openBox<Chat>('chatList');
  await Hive.openBox<Contact>('contacts');
  await Hive.openBox('chatScroll');
  await Hive.openBox('meta');
  await Hive.openBox('authBox');

  // FCM Background Handler Registration
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Local Notifications Init
  const fln.AndroidInitializationSettings initializationSettingsAndroid =
  fln.AndroidInitializationSettings('@mipmap/ic_launcher');

  const fln.DarwinInitializationSettings initializationSettingsIOS =
  fln.DarwinInitializationSettings();

  const fln.InitializationSettings initializationSettings =
  fln.InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Notification Channel Create
  final fln.AndroidFlutterLocalNotificationsPlugin? androidPlugin =
  flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
      fln.AndroidFlutterLocalNotificationsPlugin>();

  if (androidPlugin != null) {
    await androidPlugin.createNotificationChannel(
      const fln.AndroidNotificationChannel(
        channelId,
        channelName,
        description: 'Chat app notifications',
        importance: fln.Importance.max,
        playSound: true,
        sound: fln.RawResourceAndroidNotificationSound('default'),
        showBadge: true,
      ),
    );
  }

  // Other Services Init
  await ChatService.init();
  await SoundUtils.init();
  ChatService.ensureConnected();

  // Initialize Theme Service
  await ThemeService().init();

  // FCM Service Init (for chat and order notifications)
  await MyFirebaseMessagingService.initialize();

  runApp(const MyApp());
}

// ----------------- App UI -----------------
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ThemeService _themeService = ThemeService();

  @override
  void initState() {
    super.initState();
    _themeService.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      title: 'Chatting App',
      themeMode: _themeService.themeMode,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: const SplashGate(),
      //home: const ChatListScreen(),
    );
  }
}

class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  @override
  void initState() {
    super.initState();
    _decideRoute();
  }

  Future<void> _decideRoute() async {
    // 2-second delay for splash screen visibility
    await Future.delayed(const Duration(seconds: 2));

    final hasUser = LocalAuthService.isLoggedIn();
    final userId = LocalAuthService.getUserId();

    if (!mounted) return;

    if (!hasUser) {
      // User not logged in, go to Phone Login
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PhoneLoginPage()),
      );
    } else {
      // User is logged in

      // ✅ CRITICAL FIX: Background Contact Sync Trigger
      // Heavy contact sync को main thread को block किए बिना Isolate में शुरू करें
      if (userId != null && userId > 0) {
        log('Starting background contact sync for User ID: $userId');
        
        // Set user ID for cart service
        CartService.setUserId(userId);
        await CartService.loadCartFromServer();
        log('Cart service initialized for User ID: $userId');
        try {
          await Isolate.spawn(fetchPhoneContactsInIsolate, {
            'ownerUserId': userId,
            'rootIsolateToken': RootIsolateToken.instance,
          });
          log('Background Contact Sync successfully triggered.');
        } catch (e) {
          log('Error spawning contact isolate: $e');
        }
      }

      // ✅ Check if MPIN is set AND enabled
      final hasMpin = LocalAuthService.hasMpin();
      final isMpinEnabled = LocalAuthService.isMpinEnabled();

      if (hasMpin && isMpinEnabled) {
        // Go to MPIN verification page
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const VerifyMpinPage()),
        );
      } else {
        // Go to Chat Home page directly (MPIN not set or disabled)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ChatHomePage()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF075E54), // WhatsApp green color
      body: Stack(
        children: [
          // Background pattern (optional)
          Positioned.fill(
            child: Opacity(
              opacity: 0.05,
              child: Image.asset(
                'assets/icon/zakhira_logo.jpeg',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(),
              ),
            ),
          ),

          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // LOGO Container with shadow
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 15,
                        spreadRadius: 3,
                        offset: const Offset(0, 5),
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white,
                      width: 3,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(27),
                    child: Image.asset(
                      'assets/icon/zakhira_logo.jpeg',
                      width: 134,
                      height: 134,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        // If image fails to load, show a placeholder
                        return Container(
                          color: const Color(0xFF075E54),
                          child: const Center(
                            child: Icon(
                              Icons.chat,
                              size: 70,
                              color: Colors.white,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 35),

                // App Name
                const Text(
                  'Zakhira Chat',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    shadows: [
                      Shadow(
                        blurRadius: 5,
                        color: Colors.black26,
                        offset: Offset(1, 1),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Tagline
                const Text(
                  'End-to-End Encrypted',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    fontStyle: FontStyle.italic,
                  ),
                ),

                const SizedBox(height: 50),

                // Loading indicator
                Column(
                  children: [
                    SizedBox(
                      width: 25,
                      height: 25,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                        backgroundColor: Colors.white.withOpacity(0.2),
                      ),
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      'Initializing...',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bottom copyright/version
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Column(
              children: [
                const Text(
                  'from',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Meta Technologies',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Version 1.0.0',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}