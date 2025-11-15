import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:blurhash_dart/blurhash_dart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'package:path/path.dart' as path;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_compress/video_compress.dart';

import '../config.dart';
import '../main.dart';
import '../models/chat_model.dart' hide Chat;
import 'crypto_manager.dart';
import '../utils/sound_utils.dart';

class ChatService {
  static late Box<Chat> _chatBox;
  static Box get _authBox => Hive.box('authBox');
  static Box<Message> get _messageBox => Hive.box<Message>('messages');

  static const String apiBase = "http://184.168.126.71/api";
  static const String socketBase = "http://184.168.126.71:3000";
  static final Dio _dio = Dio();

  static IO.Socket? _socket;
  static bool _isInitialized = false;
  static Timer? _pingTimer;
  static Timer? _statusUpdateTimer;

  static final StreamController<Map<String, dynamic>> _typingStatusController =
  StreamController.broadcast();
  static Stream<Map<String, dynamic>> get onTypingStatus =>
      _typingStatusController.stream;

  static final StreamController<Message> _newMessageController =
  StreamController<Message>.broadcast();
  static Stream<Message> get onNewMessage => _newMessageController.stream;

  static final StreamController<Map<String, dynamic>> _userStatusController =
  StreamController.broadcast();
  static Stream<Map<String, dynamic>> get onUserStatus =>
      _userStatusController.stream;

  static final StreamController<String> _messageDeliveredController =
  StreamController<String>.broadcast();
  static Stream<String> get onMessageDelivered => _messageDeliveredController.stream;

  static final StreamController<String> _messageSentController =
  StreamController<String>.broadcast();
  static Stream<String> get onMessageSent => _messageSentController.stream;

  static final StreamController<Map<String, dynamic>> _uploadProgressController =
  StreamController.broadcast();
  static Stream<Map<String, dynamic>> get onUploadProgress =>
      _uploadProgressController.stream;

  static final StreamController<Map<String, dynamic>> _messageDeletedController =
  StreamController.broadcast();
  static Stream<Map<String, dynamic>> get onMessageDeleted =>
      _messageDeletedController.stream;

  static final StreamController<Map<String, dynamic>> _chatClearedController =
  StreamController.broadcast();
  static Stream<Map<String, dynamic>> get onChatCleared =>
      _chatClearedController.stream;

  static final StreamController<Map<String, dynamic>> _userBlockedController =
  StreamController.broadcast();
  static Stream<Map<String, dynamic>> get onUserBlocked =>
      _userBlockedController.stream;

  static final StreamController<Map<String, dynamic>> _thumbnailReadyController =
  StreamController.broadcast();
  static Stream<Map<String, dynamic>> get onThumbnailReady =>
      _thumbnailReadyController.stream;

  static final _cryptoManager = CryptoManager();
  static final Set<String> _processedMessageIds = {};
  static final Set<String> _uploadingMediaIds = {};
  static final Set<String> _blockedUsers = {};

  // ✅ Track connected state to prevent multiple connections
  static bool _isConnecting = false;
  static DateTime? _lastSocketInitTime;

  static Future<void> init() async {
    _chatBox = Hive.box<Chat>('chatList');
    await _cryptoManager.init();
    _isInitialized = true;
    print("✅ Initialized ChatService");

    // ✅ DELAYED socket initialization to prevent race conditions
    Future.delayed(const Duration(milliseconds: 500), () {
      initSocket();
    });
  }

  static void initSocket() {
    // ✅ STRONG CHECK: Prevent multiple socket initializations
    if (_isConnecting) {
      print("⚠️ Socket connection already in progress, skipping...");
      return;
    }

    // ✅ PREVENT RAPID RE-INITIALIZATION (min 5 seconds between attempts)
    if (_lastSocketInitTime != null &&
        DateTime.now().difference(_lastSocketInitTime!).inSeconds < 5) {
      print("⚠️ Too soon for socket re-initialization, skipping...");
      return;
    }

    if (_socket != null && _socket!.connected) {
      print("✅ Socket already connected, skipping re-initialization");
      return;
    }

    final userId = _authBox.get('userId');
    if (userId == null) {
      print("❌ User ID not found in authBox");
      return;
    }

    _isConnecting = true;
    _lastSocketInitTime = DateTime.now();

    try {
      print("🔄 Creating fresh socket connection...");

      // ✅ CLEAN UP OLD SOCKET COMPLETELY
      if (_socket != null) {
        _cleanupSocketListeners();
        _socket!.disconnect();
        _socket!.destroy();
        _socket = null;
      }

      _socket = IO.io(
        socketBase,
        IO.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .enableAutoConnect()
            .enableReconnection()
            .setReconnectionAttempts(3)
            .setReconnectionDelay(3000)
            .setTimeout(10000)
            .build(),
      );

      // ✅ SETUP CONNECTION LISTENERS FIRST
      _socket!.onConnect((_) {
        _isConnecting = false;
        print("✅ Fresh socket connection established");
        _socket!.emit("register", userId);
        print("👤 Emitted 'register' for user $userId");

        // ✅ SETUP HEARTBEAT
        _setupHeartbeat();

        // ✅ JOIN CHAT ROOMS
        _joinChatRooms();

        // ✅ SETUP MESSAGE LISTENERS AFTER CONNECTION
        _setupMessageListeners();

        print("✅ Socket setup completed successfully");
      });

      _socket!.onDisconnect((reason) {
        _isConnecting = false;
        print("❌ Socket disconnected: $reason");
        _cleanupTimers();
      });

      _socket!.onConnectError((err) {
        _isConnecting = false;
        print("❌ Socket connect error: $err");
        _cleanupTimers();
      });

      _socket!.onError((err) {
        print("❌ Socket general error: $err");
      });

      // ✅ CONNECT SOCKET
      _socket!.connect();

    } catch (e) {
      _isConnecting = false;
      print("❌ Socket init error: $e");
      _cleanupTimers();
    }
  }

  // ✅ SEPARATE FUNCTION TO CLEANUP OLD LISTENERS
  static void _cleanupSocketListeners() {
    if (_socket != null) {
      _socket!.off("connect");
      _socket!.off("disconnect");
      _socket!.off("connect_error");
      _socket!.off("error");
      _socket!.off("ping");
      _socket!.off("new_message");
      _socket!.off("receive_message");
      _socket!.off("message_delivered");
      _socket!.off("mark_delivered_bulk");
      _socket!.off("message_read");
      _socket!.off("user_typing");
      _socket!.off("user_status");
      _socket!.off("media_upload_progress");
      _socket!.off("media_message_ready");
      _socket!.off("message_deleted");
      _socket!.off("chat_cleared");
      _socket!.off("user_blocked");
      _socket!.off("user_unblocked");
      _socket!.off("user_blocked_by");
      _socket!.off("user_unblocked_by");
      _socket!.off("message_thumbnail_ready"); // ✅ Added thumbnail ready cleanup
    }
    print("✅ Cleaned up old socket listeners");
  }

  // ✅ SEPARATE FUNCTION FOR HEARTBEAT
  static void _setupHeartbeat() {
    // Clean up old timers
    _pingTimer?.cancel();
    _statusUpdateTimer?.cancel();

    // Setup ping-pong heartbeat
    _socket!.on("ping", (_) {
      print("❤️ Received 'ping', sending 'pong'");
      _socket!.emit("pong");
    });

    _pingTimer = Timer.periodic(const Duration(seconds: 25), (timer) {
      if (_socket != null && _socket!.connected) {
        _socket!.emit("pong");
        print("❤️ Proactively sending 'pong' heartbeat");
      } else {
        _pingTimer?.cancel();
      }
    });

    // Setup status update heartbeat
    final userId = _authBox.get('userId');
    _statusUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_socket != null && _socket!.connected && userId != null) {
        _socket!.emit("user_status", {"userId": userId, "status": "online"});
        print("🌐 Sending online status heartbeat");
      } else {
        _statusUpdateTimer?.cancel();
      }
    });
  }

  // ✅ SEPARATE FUNCTION FOR JOINING CHAT ROOMS
  static void _joinChatRooms() {
    final chatIds = _messageBox.values.map((m) => m.chatId).toSet();
    for (final id in chatIds) {
      _socket!.emit("join_chat", id);
      print("✅ Joined chat room: $id");
    }
    print("✅ Joined ${chatIds.length} chat rooms");
  }

  // ✅ SEPARATE FUNCTION FOR MESSAGE LISTENERS
  static void _setupMessageListeners() {
    // ✅ NEW MESSAGE LISTENER with STRONG duplicate protection
    _socket!.on("new_message", (data) async {
      print("📨 [new_message] event received");
      try {
        final messageId = data["message_id"]?.toString();
        final tempId = data["temp_id"]?.toString();
        final idToProcess = messageId ?? tempId;

        if (idToProcess == null) {
          print("❌ [new_message] No valid message ID");
          return;
        }

        // ✅ STRONG DUPLICATE CHECK
        if (_processedMessageIds.contains(idToProcess)) {
          print("⚠️ [new_message] Duplicate blocked: $idToProcess");
          return;
        }

        await _handleIncomingData(data, source: "new_message");
        SoundUtils.playReceiveSound();
      } catch (e) {
        print("❌ [new_message] Error: $e");
      }
    });

    // ✅ RECEIVE MESSAGE LISTENER with STRONG duplicate protection
    _socket!.on("receive_message", (data) async {
      print("📨 [receive_message] event received");
      try {
        final messageId = data["message_id"]?.toString();
        final tempId = data["temp_id"]?.toString();
        final idToProcess = messageId ?? tempId;

        if (idToProcess == null) {
          print("❌ [receive_message] No valid message ID");
          return;
        }

        // ✅ STRONG DUPLICATE CHECK
        if (_processedMessageIds.contains(idToProcess)) {
          print("⚠️ [receive_message] Duplicate blocked: $idToProcess");
          return;
        }

        await _handleIncomingData(data, source: "receive_message", forceDelivered: true);
      } catch (e) {
        print("❌ [receive_message] Error: $e");
      }
    });

    // ✅ MEDIA MESSAGE READY LISTENER with STRONG duplicate protection
    _socket!.on("media_message_ready", (data) async {
      print("📨 [media_message_ready] event received");
      try {
        final messageId = data["message_id"]?.toString();
        final tempId = data["temp_id"]?.toString();
        final idToProcess = messageId ?? tempId;

        if (idToProcess == null) {
          print("❌ [media_message_ready] No valid message ID");
          return;
        }

        // ✅ STRONG DUPLICATE CHECK
        if (_processedMessageIds.contains(idToProcess)) {
          print("⚠️ [media_message_ready] Duplicate blocked: $idToProcess");
          return;
        }

        await _handleIncomingData(data, source: "media_message_ready", forceDelivered: true);
      } catch (e) {
        print("❌ [media_message_ready] Error: $e");
      }
    });

    // ✅ MESSAGE THUMBNAIL READY LISTENER - NEW EVENT HANDLER
    _socket!.on("message_thumbnail_ready", (data) async {
      print("🖼️ [message_thumbnail_ready] event received");
      try {
        final tempId = data["temp_id"]?.toString();
        final thumbnailBase64 = data["thumbnail_data"]?.toString();

        if (tempId != null && thumbnailBase64 != null && thumbnailBase64.isNotEmpty) {
          await _updateThumbnail(tempId, thumbnailBase64);
          print("✅ Thumbnail updated for tempId: $tempId");
        } else {
          print("❌ [message_thumbnail_ready] Invalid data: tempId=$tempId, thumbnail=${thumbnailBase64 != null ? 'available' : 'null'}");
        }
      } catch (e) {
        print("❌ [message_thumbnail_ready] Error: $e");
      }
    });

    // ✅ MESSAGE DELIVERED LISTENER
    _socket!.on("message_delivered", (data) async {
      final messageId = data["message_id"]?.toString();
      if (messageId != null) {
        await updateDeliveryStatus(messageId, 1);
        print("✅ [message_delivered] Delivery confirmed: $messageId");
        SoundUtils.playDeliveredSound();
      }
    });

    // ✅ BULK MESSAGE DELIVERED LISTENER
    _socket!.on("mark_delivered_bulk", (data) async {
      final ids = data["message_ids"] as List<dynamic>? ?? [];
      int updatedCount = 0;

      for (var id in ids) {
        final msg = _messageBox.get(id.toString()) as Message?;
        if (msg != null && msg.isDelivered == 0) {
          msg.isDelivered = 1;
          await _messageBox.put(msg.messageId, msg);
          _newMessageController.add(msg);
          updatedCount++;
        }
      }
      print("✅ [mark_delivered_bulk] Updated $updatedCount messages");
    });

    // ✅ MESSAGE READ LISTENER
    _socket!.on("message_read", (data) async {
      try {
        List<dynamic> messageIds = [];
        if (data["message_ids"] != null) {
          messageIds = data["message_ids"];
        } else if (data["message_id"] != null) {
          messageIds = [data["message_id"]];
        }

        if (messageIds.isEmpty) return;

        int readCount = 0;
        for (var id in messageIds) {
          final messageId = id.toString();
          await markMessageReadLocal(messageId);
          readCount++;
        }

        print("✅ [message_read] Marked $readCount messages as read");
        SoundUtils.playReadSound();
      } catch (e) {
        print("❌ [message_read] Error: $e");
      }
    });

    // ✅ MESSAGE DELETED LISTENER
    _socket!.on("message_deleted", (data) async {
      print("🗑️ [message_deleted] event received");
      try {
        final messageId = data["message_id"]?.toString();
        final userId = data["user_id"]?.toString();
        final role = data["role"]?.toString();
        final chatId = data["chat_id"]?.toString();

        if (messageId != null && userId != null && role != null) {
          await _updateMessageDeletionStatusLocal(messageId, role);
          _messageDeletedController.sink.add({
            "message_id": messageId,
            "user_id": userId,
            "role": role,
            "chat_id": chatId
          });
          print("✅ Message deletion processed: $messageId by $role");
        }
      } catch (e) {
        print("❌ [message_deleted] Error: $e");
      }
    });

    // ✅ CHAT CLEARED LISTENER
    _socket!.on("chat_cleared", (data) async {
      print("🧹 [chat_cleared] event received");
      try {
        final chatId = data["chat_id"]?.toString();
        final userId = data["user_id"]?.toString();

        if (chatId != null && userId != null) {
          await _clearChatLocal(int.parse(chatId), int.parse(userId));
          _chatClearedController.sink.add({
            "chat_id": chatId,
            "user_id": userId
          });
          print("✅ Chat cleared: $chatId for user $userId");
        }
      } catch (e) {
        print("❌ [chat_cleared] Error: $e");
      }
    });

    // ✅ USER BLOCKED LISTENER
    _socket!.on("user_blocked", (data) {
      print("🚫 [user_blocked] event received");
      try {
        final userId = data["user_id"]?.toString();
        final blockedUserId = data["blocked_user_id"]?.toString();

        if (userId != null && blockedUserId != null) {
          _blockedUsers.add(blockedUserId);
          _userBlockedController.sink.add({
            "user_id": userId,
            "blocked_user_id": blockedUserId,
            "action": "blocked"
          });
          print("✅ User blocked: $blockedUserId by $userId");
        }
      } catch (e) {
        print("❌ [user_blocked] Error: $e");
      }
    });

    // ✅ USER UNBLOCKED LISTENER
    _socket!.on("user_unblocked", (data) {
      print("🔓 [user_unblocked] event received");
      try {
        final userId = data["user_id"]?.toString();
        final unblockedUserId = data["unblocked_user_id"]?.toString();

        if (userId != null && unblockedUserId != null) {
          _blockedUsers.remove(unblockedUserId);
          _userBlockedController.sink.add({
            "user_id": userId,
            "unblocked_user_id": unblockedUserId,
            "action": "unblocked"
          });
          print("✅ User unblocked: $unblockedUserId by $userId");
        }
      } catch (e) {
        print("❌ [user_unblocked] Error: $e");
      }
    });

    // ✅ USER BLOCKED BY LISTENER
    _socket!.on("user_blocked_by", (data) {
      print("🚫 [user_blocked_by] event received");
      try {
        final userId = data["user_id"]?.toString();
        final blockedByUserId = data["blocked_by_user_id"]?.toString();

        if (userId != null && blockedByUserId != null) {
          _userBlockedController.sink.add({
            "user_id": userId,
            "blocked_by_user_id": blockedByUserId,
            "action": "blocked_by"
          });
          print("✅ User $userId was blocked by $blockedByUserId");
        }
      } catch (e) {
        print("❌ [user_blocked_by] Error: $e");
      }
    });

    // ✅ USER UNBLOCKED BY LISTENER
    _socket!.on("user_unblocked_by", (data) {
      print("🔓 [user_unblocked_by] event received");
      try {
        final userId = data["user_id"]?.toString();
        final unblockedByUserId = data["unblocked_by_user_id"]?.toString();

        if (userId != null && unblockedByUserId != null) {
          _userBlockedController.sink.add({
            "user_id": userId,
            "unblocked_by_user_id": unblockedByUserId,
            "action": "unblocked_by"
          });
          print("✅ User $userId was unblocked by $unblockedByUserId");
        }
      } catch (e) {
        print("❌ [user_unblocked_by] Error: $e");
      }
    });

    // ✅ USER TYPING LISTENER
    _socket!.on("user_typing", (data) {
      print("✍️ [user_typing] event received");
      _typingStatusController.sink.add({
        "chatId": data["chat_id"],
        "userId": data["user_id"],
        "isTyping": data["isTyping"] ?? false
      });
    });

    // ✅ USER STATUS LISTENER
    _socket!.on("user_status", (data) {
      print("🌐 [user_status] event received");
      _userStatusController.sink.add({
        "userId": data["userId"]?.toString(),
        "status": data["status"]?.toString() ?? "offline"
      });
    });

    // ✅ MEDIA UPLOAD PROGRESS LISTENER
    _socket!.on("media_upload_progress", (data) {
      final tempId = data["temp_id"]?.toString();
      final progress = data["progress"]?.toDouble();
      if (tempId != null && progress != null) {
        _uploadProgressController.sink.add({
          "tempId": tempId,
          "progress": progress,
        });
      }
    });

    print("✅ All socket listeners setup completed");
  }

  // ✅ NEW FUNCTION: UPDATE THUMBNAIL FOR MESSAGE
  static Future<void> _updateThumbnail(String tempId, String thumbnailBase64) async {
    try {
      // ✅ CLEAN THUMBNAIL BASE64 - Remove data URI prefix if present
      String cleanedThumbnail = thumbnailBase64.trim();
      if (cleanedThumbnail.contains(',')) {
        cleanedThumbnail = cleanedThumbnail.split(',').last.trim();
      }

      print("🖼️ Updating thumbnail for tempId: $tempId, length: ${cleanedThumbnail.length} chars");

      // Find message by tempId
      final msg = _messageBox.get(tempId) as Message?;
      if (msg != null) {
        // Update thumbnail with cleaned value
        msg.thumbnailBase64 = cleanedThumbnail;
        await _messageBox.put(tempId, msg);

        // Notify UI about thumbnail update
        _thumbnailReadyController.sink.add({
          "tempId": tempId,
          "thumbnailBase64": cleanedThumbnail,
          "message": msg
        });

        // Also notify via new message controller for UI refresh
        _newMessageController.add(msg);

        print("✅ Thumbnail updated for message: $tempId");
      } else {
        // ✅ Also try to find by messageId if tempId not found
        final allMessages = _messageBox.values.where((m) => m.messageId.toString() == tempId).toList();
        if (allMessages.isNotEmpty) {
          final msg = allMessages.first;
          msg.thumbnailBase64 = cleanedThumbnail;
          await _messageBox.put(msg.messageId, msg);

          _thumbnailReadyController.sink.add({
            "tempId": tempId,
            "thumbnailBase64": cleanedThumbnail,
            "message": msg
          });

          _newMessageController.add(msg);
          print("✅ Thumbnail updated for message by messageId: $tempId");
        } else {
          print("⚠️ No message found with tempId: $tempId");
        }
      }
    } catch (e) {
      print("❌ Error updating thumbnail: $e");
    }
  }

  // ✅ IMPROVED THUMBNAIL GENERATION FUNCTION
  static Future<Map<String, String?>> _generateThumbnail(String mediaPath) async {
    try {
      final ext = mediaPath.split('.').last.toLowerCase();
      String? thumbnailBase64;

      print("🎨 Generating thumbnail for: $mediaPath");

      if (['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
        // ✅ FIX: Generate small thumbnail (5-10 KB) - 80x80, quality 40
        final compressedThumbnail = await FlutterImageCompress.compressWithFile(
          mediaPath,
          quality: 40, // ✅ Reduced to 40 for 5-10 KB size
          minWidth: 80, // ✅ Reduced to 80 for smaller file size
          minHeight: 80, // ✅ Reduced to 80 for smaller file size
        );

        if (compressedThumbnail != null) {
          // ✅ Additional check: if still too large, compress further
          var finalThumbnail = compressedThumbnail;
          var sizeKB = (compressedThumbnail.length / 1024);
          
          if (sizeKB > 10) {
            // Recompress with even lower quality if still too large
            final furtherCompressed = await FlutterImageCompress.compressWithList(
              compressedThumbnail,
              quality: 30,
              minWidth: 60,
              minHeight: 60,
            );
            if (furtherCompressed != null) {
              finalThumbnail = furtherCompressed;
              sizeKB = (furtherCompressed.length / 1024);
            }
          }
          
          thumbnailBase64 = base64Encode(finalThumbnail);
          print("✅ Generated image thumbnail: ${sizeKB.toStringAsFixed(2)} KB (${finalThumbnail.length} bytes)");
        }
      } else if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) {
        // ✅ FIX: Generate small video thumbnail
        try {
          final thumbnailFile = await VideoCompress.getFileThumbnail(
            mediaPath,
            quality: 50, // ✅ Reduced from 85 to 50
          );
          final thumbnailBytes = await thumbnailFile.readAsBytes();
          
          // ✅ FIX: Further compress video thumbnail to 5-10 KB
          var compressedVideoThumbnail = await FlutterImageCompress.compressWithList(
            thumbnailBytes,
            quality: 40,
            minWidth: 80,
            minHeight: 80,
          );
          
          // ✅ Additional compression if still too large
          if (compressedVideoThumbnail != null) {
            var sizeKB = (compressedVideoThumbnail.length / 1024);
            if (sizeKB > 10) {
              final furtherCompressed = await FlutterImageCompress.compressWithList(
                compressedVideoThumbnail,
                quality: 30,
                minWidth: 60,
                minHeight: 60,
              );
              if (furtherCompressed != null) {
                compressedVideoThumbnail = furtherCompressed;
                sizeKB = (furtherCompressed.length / 1024);
              }
            }
            
            thumbnailBase64 = base64Encode(compressedVideoThumbnail);
            print("✅ Generated video thumbnail: ${sizeKB.toStringAsFixed(2)} KB");
          } else {
            thumbnailBase64 = base64Encode(thumbnailBytes);
            final sizeKB = (thumbnailBytes.length / 1024).toStringAsFixed(2);
            print("✅ Generated video thumbnail (fallback): ${sizeKB} KB");
          }
        } catch (e) {
          print("❌ Video thumbnail error: $e");
        }
      }

      return {
        'thumbnailBase64': thumbnailBase64,
      };
    } catch (e) {
      print("❌ Error in thumbnail generation: $e");
      return {
        'thumbnailBase64': null,
      };
    }
  }

  // ✅ THUMBNAIL WIDGET BUILDER
  static Widget buildThumbnail(Message msg) {
    if (msg.messageType == 'media') {
      if (msg.thumbnailBase64 != null && msg.thumbnailBase64!.isNotEmpty) {
        try {
          final bytes = base64Decode(msg.thumbnailBase64!);
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: 150,
            height: 150,
            errorBuilder: (context, error, stackTrace) {
              return _buildThumbnailPlaceholder();
            },
          );
        } catch (e) {
          return _buildThumbnailPlaceholder();
        }
      } else {
        return _buildThumbnailPlaceholder();
      }
    } else {
      // For text messages, show the message content
      return Text(
        msg.messageContent,
        style: const TextStyle(fontSize: 16),
      );
    }
  }

  static Widget _buildThumbnailPlaceholder() {
    return Container(
      width: 150,
      height: 150,
      color: Colors.grey[300],
      child: const Icon(
        Icons.image,
        color: Colors.grey,
        size: 50,
      ),
    );
  }

  // ✅ FIXED INCOMING MESSAGE HANDLER WITH THUMBNAIL SUPPORT
  static Future<void> _handleIncomingData(dynamic data,
      {String source = "", bool forceDelivered = false}) async {
    String? idToProcess;

    try {
      final currentUserId = _authBox.get('userId');
      if (currentUserId == null) {
        print("❌ User ID not found in authBox");
        return;
      }

      final messageId = data["message_id"]?.toString();
      final tempId = data["temp_id"]?.toString();
      idToProcess = messageId ?? tempId;

      if (idToProcess == null) {
        print("❌ Incoming data has no valid message_id or temp_id. Ignoring.");
        return;
      }

      print("📥 Processing message from $source: $idToProcess");

      // ✅ STEP 1: STRONG DUPLICATE CHECK
      if (_processedMessageIds.contains(idToProcess)) {
        print("⚠️ Message already being processed: $idToProcess");
        return;
      }
      _processedMessageIds.add(idToProcess);

      // Auto-remove from processed set after 10 seconds
      Future.delayed(const Duration(seconds: 10), () {
        _processedMessageIds.remove(idToProcess!);
      });

      // ✅ STEP 2: Check if message already exists in database
      final existingMessage = _messageBox.values.firstWhereOrNull(
            (msg) => msg.messageId == idToProcess,
      );

      if (existingMessage != null) {
        print("⚠️ Message already exists in database: $idToProcess");

        // Update delivery status if needed
        if (forceDelivered && existingMessage.isDelivered == 0) {
          existingMessage.isDelivered = 1;
          await _messageBox.put(idToProcess, existingMessage);
          _newMessageController.add(existingMessage);
          print("✅ Updated delivery status for existing message: $idToProcess");
        }
        return;
      }

      // ✅ STEP 3: Handle tempId to messageId conversion
      if (tempId != null && messageId != null) {
        await updateMessageId(tempId, messageId, forceDelivered ? 1 : 0);
        print("✅ TempId converted: $tempId -> $messageId");
        idToProcess = messageId;

        // Check again after conversion
        final existingWithNewId = _messageBox.values.firstWhereOrNull(
              (msg) => msg.messageId == messageId,
        );

        if (existingWithNewId != null) {
          print("⚠️ Message already exists with new ID: $messageId");
          return;
        }
      }

      // ✅ STEP 4: EXTRACT AND PROCESS MESSAGE DATA
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
        print("🖼️ Thumbnail extracted from server: ${thumbnailBase64.length} chars");
      }

      String encryptedContent = data["message_text"]?.toString() ?? "";
      String messageType = data["message_type"]?.toString() ?? "text";
      final replyToMessageId = data["reply_to_message_id"]?.toString();
      final mediaUrl = data["media_url"]?.toString();

      print("🔍 RAW DATA FROM SERVER:");
      print("   - Source: $source");
      print("   - Message Type: $messageType");
      print("   - Thumbnail: ${thumbnailBase64 != null && thumbnailBase64.isNotEmpty ? 'Available (${thumbnailBase64.length} chars)' : 'Not Available'}");
      print("   - Media URL: ${mediaUrl ?? 'Not Available'}");
      print("   - Encrypted Content Length: ${encryptedContent.length}");

      // ✅ STEP 5: DECRYPT AND EXTRACT CONTENT BASED ON MESSAGE TYPE
      String finalContent = "";
      String finalMessageType = "text";
      String? finalThumbnailBase64 = thumbnailBase64;
      String? finalMediaUrl = mediaUrl;

      if (messageType == "encrypted" || messageType == "encrypted_media") {
        print("🔓 Processing encrypted message: $messageType");

        try {
          Map<String, dynamic> decryptedData;

          if (messageType == "encrypted_media") {
            print("🎯 Using media-specific decryption");
            decryptedData = await _cryptoManager.decryptMediaMessage(encryptedContent);
          } else {
            decryptedData = await _cryptoManager.decryptAndDecompress(encryptedContent);
          }

          print("🔍 Decrypted Result: $decryptedData");

          finalMessageType = decryptedData["type"]?.toString() ?? "text";
          finalContent = decryptedData["content"]?.toString() ?? "";

          if (decryptedData.containsKey("thumbnail")) {
            String? extractedThumbnail = decryptedData["thumbnail"]?.toString();
            if (extractedThumbnail != null && extractedThumbnail.isNotEmpty) {
              if (extractedThumbnail.contains(',')) {
                extractedThumbnail = extractedThumbnail.split(',').last;
              }
              extractedThumbnail = extractedThumbnail.trim();
              finalThumbnailBase64 = extractedThumbnail;
              print("🖼️ Thumbnail extracted from decrypted data: ${finalThumbnailBase64.length} chars");
            }
          }

          if (decryptedData.containsKey("media_url")) {
            finalMediaUrl = decryptedData["media_url"]?.toString();
          }
          if (decryptedData.containsKey("high_quality_url") && finalMediaUrl == null) {
            finalMediaUrl = decryptedData["high_quality_url"]?.toString();
          }
          if (decryptedData.containsKey("low_quality_url") && finalMediaUrl == null) {
            finalMediaUrl = decryptedData["low_quality_url"]?.toString();
          }

          print("✅ DECRYPTION SUCCESSFUL:");
          print("   - Final Type: $finalMessageType");
          print("   - Final Content: '${finalContent.length > 50 ? finalContent.substring(0, 50) + '...' : finalContent}'");

        } catch (e) {
          print("❌ Decryption failed: $e");
          // Fallback for decryption failure
          finalContent = encryptedContent;
          finalMessageType = messageType.replaceAll("encrypted_", "");
        }
      } else {
        // ✅ UNENCRYPTED MESSAGES - direct processing
        finalContent = encryptedContent;
        finalMessageType = messageType;
      }

      // ✅ STEP 6: CONTENT CLEANUP AND VALIDATION
      if (finalContent.startsWith('{') && finalContent.endsWith('}')) {
        try {
          final jsonParsed = jsonDecode(finalContent);
          if (jsonParsed is Map<String, dynamic>) {
            // Extract content from JSON structure if present
            if (jsonParsed.containsKey('content')) {
              finalContent = jsonParsed['content']?.toString() ?? finalContent;
            }
            if (jsonParsed.containsKey('media_url') && finalMediaUrl == null) {
              finalMediaUrl = jsonParsed['media_url']?.toString();
            }
            if (jsonParsed.containsKey('thumbnail') && (finalThumbnailBase64 == null || finalThumbnailBase64!.isEmpty)) {
              String? extractedThumbnail = jsonParsed['thumbnail']?.toString();
              // ✅ Clean thumbnail from JSON too
              if (extractedThumbnail != null && extractedThumbnail.isNotEmpty) {
                if (extractedThumbnail.contains(',')) {
                  extractedThumbnail = extractedThumbnail.split(',').last;
                }
                finalThumbnailBase64 = extractedThumbnail.trim();
              }
            }
            print("✅ Cleaned JSON content");
          }
        } catch (e) {
          print("⚠️ Content is not valid JSON, using as-is");
        }
      }

      // ✅ STEP 7: AUTO-DETECT MEDIA TYPE FROM CONTENT
      if (finalMessageType == "text" &&
          (_isMediaContent(finalContent) || finalThumbnailBase64 != null || finalMediaUrl != null)) {
        finalMessageType = "media";
        print("🎯 Auto-detected as media from content/thumbnail/media_url");
      }

      // ✅ STEP 8: PREPARE MESSAGE METADATA
      final messageTimestamp = DateTime.tryParse(data["timestamp"]?.toString() ?? "") ?? DateTime.now();
      final chatId = int.tryParse(data["chat_id"]?.toString() ?? "0") ?? 0;
      final senderId = int.tryParse(data["sender_id"]?.toString() ?? "0") ?? 0;
      final receiverId = int.tryParse(data["receiver_id"]?.toString() ?? "0") ?? 0;

      // For media messages, use media URL as content if available
      if (finalMessageType == "media" && finalMediaUrl != null) {
        finalContent = finalMediaUrl;
      }

      // ✅ STEP 9: FINAL CONTENT-BASED DUPLICATE CHECK
      final contentDuplicateCheck = _messageBox.values.firstWhereOrNull(
            (msg) =>
        msg.chatId == chatId &&
            msg.senderId == senderId &&
            msg.messageContent == finalContent &&
            msg.timestamp.difference(messageTimestamp).inSeconds.abs() < 5,
      );

      if (contentDuplicateCheck != null) {
        print("⚠️ CONTENT DUPLICATE - Similar message exists: ${contentDuplicateCheck.messageId}");

        // ✅ UPDATE EXISTING MESSAGE with new data
        if (forceDelivered && contentDuplicateCheck.isDelivered == 0) {
          contentDuplicateCheck.isDelivered = 1;
        }
        if (finalThumbnailBase64 != null && finalThumbnailBase64.isNotEmpty) {
          // ✅ Always update thumbnail if new one is available (even if old exists, update it)
          contentDuplicateCheck.thumbnailBase64 = finalThumbnailBase64;
          print("✅ Updated thumbnail for existing message: ${contentDuplicateCheck.messageId}");
        }
        if (replyToMessageId != null) {
          contentDuplicateCheck.replyToMessageId = replyToMessageId;
        }

        final String? dupGroupId = data["group_id"]?.toString();
        final int? dupImageIndex = data["image_index"] != null ? int.tryParse(data["image_index"].toString()) : null;
        final int? dupTotalImages = data["total_images"] != null ? int.tryParse(data["total_images"].toString()) : null;
        if (dupGroupId != null && dupGroupId.isNotEmpty) {
          contentDuplicateCheck.groupId = dupGroupId;
          contentDuplicateCheck.imageIndex = dupImageIndex;
          contentDuplicateCheck.totalImages = dupTotalImages;
        }

        await _messageBox.put(contentDuplicateCheck.messageId, contentDuplicateCheck);

        if (_newMessageController.hasListener) {
          _newMessageController.add(contentDuplicateCheck);
        }

        print("✅ Updated existing message with new data: ${contentDuplicateCheck.messageId}");
        return;
      }

      // ✅ STEP 10: CREATE AND SAVE NEW MESSAGE
      // ✅ FIX: Properly extract group_id, image_index, and total_images with debug logging
      final String? groupId = data["group_id"]?.toString();
      
      // ✅ FIX: Handle image_index extraction - can be int or string
      int? imageIndex;
      if (data["image_index"] != null) {
        final imageIndexValue = data["image_index"];
        if (imageIndexValue is int) {
          imageIndex = imageIndexValue;
        } else if (imageIndexValue is String) {
          imageIndex = int.tryParse(imageIndexValue);
        } else {
          imageIndex = int.tryParse(imageIndexValue.toString());
        }
      }
      
      // ✅ FIX: Handle total_images extraction - can be int or string
      int? totalImages;
      if (data["total_images"] != null) {
        final totalImagesValue = data["total_images"];
        if (totalImagesValue is int) {
          totalImages = totalImagesValue;
        } else if (totalImagesValue is String) {
          totalImages = int.tryParse(totalImagesValue);
        } else {
          totalImages = int.tryParse(totalImagesValue.toString());
        }
      }
      
      // ✅ DEBUG: Log extracted values
      if (groupId != null || imageIndex != null || totalImages != null) {
        print("🧩 GROUP DATA EXTRACTED: groupId=$groupId, imageIndex=$imageIndex, totalImages=$totalImages");
        print("🧩 RAW DATA: group_id=${data["group_id"]}, image_index=${data["image_index"]} (type: ${data["image_index"]?.runtimeType}), total_images=${data["total_images"]}");
      }
      final msg = Message(
        messageId: idToProcess,
        chatId: chatId,
        senderId: senderId,
        receiverId: receiverId,
        messageContent: finalContent,
        messageType: finalMessageType,
        isRead: 0,
        isDelivered: forceDelivered ? 1 : 0,
        timestamp: messageTimestamp,
        senderName: data["sender_name"]?.toString(),
        receiverName: data["receiver_name"]?.toString(),
        senderPhoneNumber: data["sender_phone"]?.toString(),
        receiverPhoneNumber: data["receiver_phone"]?.toString(),
        thumbnailBase64: finalThumbnailBase64,
        replyToMessageId: replyToMessageId,
        isForwarded: data["is_forwarded"] == 1 ? true : false,
        forwardedFrom: data["forwarded_from"]?.toString(),
        groupId: groupId,
        imageIndex: imageIndex,
        totalImages: totalImages,
      );

      await saveMessageLocal(msg);

      print("💾 NEW MESSAGE SAVED:");
      print("   - ID: $idToProcess");
      print("   - Type: $finalMessageType");
      print("   - Content: '${finalContent.length > 30 ? finalContent.substring(0, 30) + '...' : finalContent}'");
      print("   - Thumbnail: ${finalThumbnailBase64 != null && finalThumbnailBase64.isNotEmpty ? 'Available (${finalThumbnailBase64.length} chars)' : 'Not Available'}");
      print("   - Thumbnail in Message Object: ${msg.thumbnailBase64 != null && msg.thumbnailBase64!.isNotEmpty ? 'Available (${msg.thumbnailBase64!.length} chars)' : 'Not Available'}");
      print("   - Chat: $chatId");
      print("   - Sender: $senderId");
      print("   - Timestamp: $messageTimestamp");

      // ✅ STEP 11: NOTIFY UI
      if (_newMessageController.hasListener) {
        _newMessageController.add(msg);
      }

      // ✅ STEP 12: SEND DELIVERY CONFIRMATION (if message is for current user)
      final isForCurrentUser = currentUserId.toString() != data["sender_id"].toString();
      if (isForCurrentUser && _socket != null && _socket!.connected) {
        _socket!.emit("message_delivered", {
          "message_id": idToProcess,
          "chat_id": chatId,
          "receiver_id": currentUserId,
        });
        await updateDeliveryStatus(idToProcess, 1);
        print("✅ Delivery confirmation sent for: $idToProcess");
      }

      // ✅ STEP 13: PLAY SOUND FOR INCOMING MESSAGES
      if (isForCurrentUser && source == "new_message") {
        SoundUtils.playReceiveSound();
      }

      print("✅ Message processing completed: $idToProcess");

    } catch (e, st) {
      print("❌ CRITICAL ERROR in _handleIncomingData: $e");
      print("Stack trace: $st");
      print("Problematic data: ${data.toString()}");
    } finally {
      if (idToProcess != null) {
        _processedMessageIds.remove(idToProcess);
      }
    }
  }

// ✅ IMPROVED MEDIA CONTENT DETECTION
  static bool _isMediaContent(String content) {
    if (content.isEmpty) return false;

    final lowerContent = content.toLowerCase();
    return lowerContent.startsWith('http') ||
        lowerContent.contains('/uploads/') ||
        lowerContent.contains('/media/') ||
        lowerContent.endsWith('.jpg') ||
        lowerContent.endsWith('.jpeg') ||
        lowerContent.endsWith('.png') ||
        lowerContent.endsWith('.mp4') ||
        lowerContent.endsWith('.mov') ||
        lowerContent.endsWith('.gif') ||
        lowerContent.endsWith('.webp') ||
        lowerContent.endsWith('.avi') ||
        lowerContent.endsWith('.mkv') ||
        lowerContent.contains('image') ||
        lowerContent.contains('video');
  }

  // ✅ FIXED MEDIA PROCESSING WITH THUMBNAIL
  static Future<void> _processAndSendMedia({
    required String mediaPath,
    required int chatId,
    required int receiverId,
    required String tempId,
    required int userId,
    String? senderName,
    String? receiverName,
    String? senderPhoneNumber,
    String? receiverPhoneNumber,
    String? replyToMessageId,
    String? groupId,
    int? imageIndex,
    int? totalImages,
  }) async {
    if (_uploadingMediaIds.contains(tempId)) {
      print("⚠️ Media $tempId is already being uploaded");
      return;
    }

    _uploadingMediaIds.add(tempId);

    try {
      // ✅ STEP 1: Check if temp message exists
      final existingTempMsg = _messageBox.get(tempId) as Message?;
      if (existingTempMsg == null) {
        print("❌ Temporary message not found");
        return;
      }

      // ✅ FIX: Use existing thumbnail if already generated (for media groups)
      String? thumbnailBase64 = existingTempMsg.thumbnailBase64;
      
      // ✅ STEP 2: GENERATE THUMBNAIL ONLY IF NOT ALREADY PRESENT
      if (thumbnailBase64 == null || thumbnailBase64.isEmpty) {
        print("🎨 Generating thumbnail...");
        final mediaData = await _generateThumbnail(mediaPath);
        thumbnailBase64 = mediaData['thumbnailBase64'];
        
        // ✅ FIX: Update temp message with thumbnail immediately
        if (thumbnailBase64 != null && thumbnailBase64.isNotEmpty) {
          existingTempMsg.thumbnailBase64 = thumbnailBase64;
          await _messageBox.put(tempId, existingTempMsg);
          // ✅ FIX: Notify UI immediately with thumbnail
          _thumbnailReadyController.sink.add({
            'tempId': tempId,
            'thumbnailBase64': thumbnailBase64,
            'message': existingTempMsg,
          });
        }
      }

      print("✅ Media Data Generated:");
      print("   - Thumbnail: ${thumbnailBase64 != null ? 'Available' : 'NULL'}");

      // ✅ STEP 3: Compress media
      Uint8List fileBytes;
      final ext = mediaPath.split('.').last.toLowerCase();

      if (['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
        final compressedBytes = await FlutterImageCompress.compressWithFile(
          mediaPath,
          quality: 85,
          minWidth: 1200,
          minHeight: 1200,
        );
        fileBytes = Uint8List.fromList(compressedBytes ?? await File(mediaPath).readAsBytes());
      } else if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) {
        final MediaInfo? info = await VideoCompress.compressVideo(
          mediaPath,
          quality: VideoQuality.MediumQuality,
          deleteOrigin: false,
          includeAudio: true,
        );
        if (info != null && info.file != null) {
          fileBytes = await File(info.file!.path).readAsBytes();
        } else {
          fileBytes = await File(mediaPath).readAsBytes();
        }
      } else {
        fileBytes = await File(mediaPath).readAsBytes();
      }

      final originalName = path.basename(mediaPath);
      final totalSize = fileBytes.length;

      print("📦 Prepared media for upload: $originalName ($totalSize bytes)");

      // ✅ STEP 4: Upload using server's 3-step process
      final String? mediaUrl = await _uploadMediaToServer(
          fileBytes,
          originalName,
          totalSize,
          tempId,
          chatId: chatId,
          senderId: userId,
          receiverId: receiverId,
          onProgress: (progress) {
            _uploadProgressController.sink.add({
              'tempId': tempId,
              'progress': progress,
            });
          }
      );

      if (mediaUrl == null) {
        throw Exception("Failed to upload media to server.");
      }

      print("✅ Media uploaded successfully: $mediaUrl");

      // ✅ STEP 5: Send final media message via socket
      final fileName = mediaUrl.split('/').last;
      final fullMediaUrl = '${Config.baseNodeApiUrl}/media/file/$fileName';

      // ✅ Prepare CLEAN media payload (NO TYPE SHOWN TO USER)
      final encryptedData = await _cryptoManager.encryptMediaPayload(fullMediaUrl, thumbnailBase64);
      final encryptedContent = encryptedData['content'];
      final encryptedType = encryptedData['type'];

      // ✅ Send via socket
      if (_socket != null && _socket!.connected) {
        _socket!.emit("send_message", {
          "chat_id": chatId,
          "sender_id": userId,
          "receiver_id": receiverId,
          "message_text": encryptedContent,
          "message_type": encryptedType,
          "temp_id": tempId,
          "media_url": fullMediaUrl,
          "thumbnail_data": thumbnailBase64 ?? "",
          "sender_name": senderName,
          "receiver_name": receiverName,
          "sender_phone": senderPhoneNumber,
          "receiver_phone": receiverPhoneNumber,
          "reply_to_message_id": replyToMessageId,
          "timestamp": DateTime.now().toIso8601String(),
          if (groupId != null) "group_id": groupId,
          if (imageIndex != null) "image_index": imageIndex,
          if (totalImages != null) "total_images": totalImages,
        });
        print("📤 Emitted send_message for temp_id: $tempId");
      }

      // ✅ STEP 6: Update local temporary message ONLY ONCE
      if (existingTempMsg.thumbnailBase64 == null) {
        existingTempMsg.thumbnailBase64 = thumbnailBase64;
      }
      if (groupId != null) {
        existingTempMsg.groupId = groupId;
        existingTempMsg.imageIndex = imageIndex;
        existingTempMsg.totalImages = totalImages;
      }
      existingTempMsg.isDelivered = 1;
      await _messageBox.put(tempId, existingTempMsg);

      // Notify UI of update
      _newMessageController.add(existingTempMsg);

      print("✅ Media message sent successfully");

      // ✅ STEP 7: Send push notification
      await _sendPushNotification(receiverId, '📷 Media', chatId, userId, senderName ?? 'User');

    } catch (e) {
      print("❌ Media upload error: $e");
      _uploadProgressController.sink.add({
        'tempId': tempId,
        'progress': -1.0,
      });
    } finally {
      _uploadingMediaIds.remove(tempId);
    }
  }

  // ✅ CORRECTED: Upload using server's 3-step API
  static Future<String?> _uploadMediaToServer(
      Uint8List fileBytes,
      String fileName,
      int totalSize,
      String tempId, {
        required int chatId,
        required int senderId,
        required int receiverId,
        required Function(double) onProgress,
      }) async {
    try {
      const int chunkSize = 512 * 1024;
      final int totalChunks = (fileBytes.length / chunkSize).ceil();

      print("📤 Uploading $fileName in $totalChunks chunks...");

      // ✅ STEP 1: Initialize upload session
      final initResponse = await _dio.post(
        "${Config.baseNodeApiUrl}/media/init",
        data: {
          "chat_id": chatId,
          "sender_id": senderId,
          "original_name": fileName,
          "total_size": totalSize,
        },
      );

      if (initResponse.statusCode != 200 || initResponse.data['success'] != true) {
        throw Exception("Upload initialization failed: ${initResponse.data}");
      }

      final String uploadId = initResponse.data['upload_id'];
      print("✅ Upload session started: $uploadId");

      // ✅ STEP 2: Upload chunks
      int completedChunks = 0;
      for (int i = 0; i < totalChunks; i++) {
        final int start = i * chunkSize;
        final int end = min(start + chunkSize, fileBytes.length);
        final Uint8List chunkBytes = fileBytes.sublist(start, end);

        int attempt = 0;
        bool success = false;

        while (attempt < 3 && !success) {
          try {
            final FormData form = FormData.fromMap({
              "upload_id": uploadId,
              "chunk": MultipartFile.fromBytes(chunkBytes, filename: "$fileName.part$i"),
            });

            final response = await _dio.post(
                "${Config.baseNodeApiUrl}/media/chunk",
                data: form
            );

            if (response.statusCode != 200 || response.data['success'] != true) {
              throw Exception("Chunk upload failed: ${response.data}");
            }

            completedChunks++;
            final double progress = (completedChunks / totalChunks) * 100;
            onProgress(progress);

            print("📦 Chunk ${i + 1}/$totalChunks uploaded ($progress%)");
            success = true;
          } catch (e) {
            attempt++;
            if (attempt < 3) {
              print("⚠️ Retry chunk ${i + 1}, attempt $attempt");
              await Future.delayed(const Duration(seconds: 2));
            } else {
              throw Exception("❌ Chunk ${i + 1} failed after 3 attempts: $e");
            }
          }
        }
      }

      // ✅ STEP 3: Finalize upload
      final finalizeResponse = await _dio.post(
          "${Config.baseNodeApiUrl}/media/finalize",
          data: {
            "upload_id": uploadId,
            "receiver_id": receiverId,
            "temp_id": tempId,
          }
      );

      if (finalizeResponse.statusCode == 200 && finalizeResponse.data['success'] == true) {
        final String mediaUrl = finalizeResponse.data['data']['media_url'];
        print("✅ Upload finalized: $mediaUrl");
        onProgress(100);
        return mediaUrl;
      } else {
        throw Exception("Finalize upload failed: ${finalizeResponse.data}");
      }

    } catch (e) {
      print("❌ Upload failed for $fileName: $e");
      onProgress(-1.0);
      return null;
    }
  }

  static Future<void> sendMediaGroup({
    required int chatId,
    required int receiverId,
    required List<String> mediaPaths,
    String? senderName,
    String? receiverName,
    String? senderPhoneNumber,
    String? receiverPhoneNumber,
    String? replyToMessageId,
  }) async {
    if (!_isInitialized) {
      throw Exception("ChatService has not been initialized. Cannot send media group.");
    }

    if (_socket == null || !_socket!.connected) {
      initSocket();
      await Future.delayed(const Duration(seconds: 2));
      if (_socket == null || !_socket!.connected) {
        throw Exception("Socket not connected. Cannot send media group.");
      }
    }

    final userId = _authBox.get('userId');
    if (userId == null) throw Exception("User ID not found");

    final String groupId = 'grp_${chatId}_${DateTime.now().microsecondsSinceEpoch}';
    final int total = mediaPaths.length;
    final baseTimestamp = DateTime.now();

    // ✅ FIX: Generate thumbnails FIRST for instant UI display (parallel)
    final List<Future<Map<String, dynamic>>> thumbnailFutures = [];
    for (int i = 0; i < mediaPaths.length; i++) {
      thumbnailFutures.add(_generateThumbnail(mediaPaths[i]));
    }
    
    // ✅ FIX: Wait for all thumbnails in parallel
    final thumbnailResults = await Future.wait(thumbnailFutures);

    // ✅ FIX: Create all temp messages with thumbnails INSTANTLY (no delay)
    final List<Message> tempMessages = [];
    for (int i = 0; i < mediaPaths.length; i++) {
      final String path = mediaPaths[i];
      final String tempId = 'temp_${chatId}_${baseTimestamp.microsecondsSinceEpoch}_$i';
      final thumbnailBase64 = thumbnailResults[i]['thumbnailBase64'];

      final tempMsg = Message(
        messageId: tempId,
        chatId: chatId,
        senderId: userId,
        receiverId: receiverId,
        messageContent: path,
        messageType: 'media',
        isRead: 0,
        isDelivered: 0,
        timestamp: baseTimestamp.add(Duration(milliseconds: i)), // ✅ FIX: Sequential timestamps
        senderName: senderName,
        receiverName: receiverName,
        senderPhoneNumber: senderPhoneNumber,
        receiverPhoneNumber: receiverPhoneNumber,
        replyToMessageId: replyToMessageId,
        groupId: groupId,
        imageIndex: i,
        totalImages: total,
        thumbnailBase64: thumbnailBase64, // ✅ FIX: Add thumbnail immediately
      );

      await saveMessageLocal(tempMsg);
      tempMessages.add(tempMsg);
    }

    // ✅ FIX: Notify UI ONCE with all messages for instant display (no fluctuation)
    for (final tempMsg in tempMessages) {
      _newMessageController.add(tempMsg);
      _messageSentController.sink.add(tempMsg.messageId);
    }
    SoundUtils.playSendSound();

    // ✅ FIX: Send all media in PARALLEL (like WhatsApp)
    final List<Future<void>> uploadFutures = [];
    for (int i = 0; i < mediaPaths.length; i++) {
      uploadFutures.add(_processAndSendMedia(
        mediaPath: mediaPaths[i],
        chatId: chatId,
        receiverId: receiverId,
        tempId: tempMessages[i].messageId,
        userId: userId,
        senderName: senderName,
        receiverName: receiverName,
        senderPhoneNumber: senderPhoneNumber,
        receiverPhoneNumber: receiverPhoneNumber,
        replyToMessageId: replyToMessageId,
        groupId: groupId,
        imageIndex: i,
        totalImages: total,
      ));
    }
    
    // ✅ FIX: Process all uploads in parallel (don't wait)
    unawaited(Future.wait(uploadFutures));
  }

  // ------------------- MEDIA UPLOAD FUNCTIONS -------------------

  /// Send media message using server's 3-step upload process
  static Future<void> sendMediaMessage({
    required int chatId,
    required int receiverId,
    required String mediaPath,
    String? senderName,
    String? receiverName,
    String? senderPhoneNumber,
    String? receiverPhoneNumber,
    String? replyToMessageId,
  }) async {
    final tempId = 'temp_${chatId}_${DateTime.now().microsecondsSinceEpoch}';
    if (!_isInitialized) {
      throw Exception("ChatService has not been initialized. Cannot send media message.");
    }

    if (_socket == null || !_socket!.connected) {
      print("❌ Socket not connected. Attempting to reconnect...");
      initSocket();
      await Future.delayed(const Duration(seconds: 2));
      if (_socket == null || !_socket!.connected) {
        throw Exception("Socket not connected. Cannot send media message.");
      }
    }

    final userId = _authBox.get('userId');
    if (userId == null) throw Exception("User ID not found");

    try {
      // ✅ STEP 1: Create immediate temporary message for instant UI update
      final tempMsg = Message(
        messageId: tempId,
        chatId: chatId,
        senderId: userId,
        receiverId: receiverId,
        messageContent: mediaPath,
        messageType: 'media',
        isRead: 0,
        isDelivered: 0,
        timestamp: DateTime.now(),
        senderName: senderName,
        receiverName: receiverName,
        senderPhoneNumber: senderPhoneNumber,
        receiverPhoneNumber: receiverPhoneNumber,
        replyToMessageId: replyToMessageId,
      );

      await saveMessageLocal(tempMsg);
      print("💾 Saved temporary media message with instant preview: $tempId");

      // ✅ Notify UI immediately
      _newMessageController.add(tempMsg);
      _messageSentController.sink.add(tempId);
      SoundUtils.playSendSound();

      // ✅ STEP 2: Process and upload media in background WITH THUMBNAIL
      _processAndSendMedia(
        mediaPath: mediaPath,
        chatId: chatId,
        receiverId: receiverId,
        tempId: tempId,
        userId: userId,
        senderName: senderName,
        receiverName: receiverName,
        senderPhoneNumber: senderPhoneNumber,
        receiverPhoneNumber: receiverPhoneNumber,
        replyToMessageId: replyToMessageId,
      );

    } catch (e) {
      print("❌ Initial media message setup error: $e");
      rethrow;
    }
  }

  // ------------------- SEND MESSAGE FUNCTIONS -------------------
  static Future<void> sendMessage({
    required int chatId,
    required int receiverId,
    required String messageContent,
    required String messageType,
    String? senderName,
    String? receiverName,
    String? senderPhoneNumber,
    String? receiverPhoneNumber,
    bool isForwarded = false,
    String? replyToMessageId,
  }) async {
    if (!_isInitialized) {
      throw Exception("ChatService has not been initialized. Cannot send message.");
    }

    if (_socket == null || !_socket!.connected) {
      print("❌ Socket not connected. Attempting to reconnect...");
      initSocket();
      await Future.delayed(const Duration(seconds: 2));
      if (_socket == null || !_socket!.connected) {
        throw Exception("Socket not connected. Cannot send message.");
      }
    }

    try {
      final userId = _authBox.get('userId');
      if (userId == null) return;

      final Map<String, dynamic> messagePayload = {
        'type': messageType,
        'content': messageContent,
      };

      if (isForwarded) {
        messagePayload['is_forwarded'] = true;
      }

      final String payloadString = jsonEncode(messagePayload);
      final encryptedData = await _cryptoManager.encryptAndCompress(payloadString);
      final encryptedContent = encryptedData['content'];
      final encryptedType = encryptedData['type'];

      final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';

      final tempMsg = Message(
        messageId: tempId,
        chatId: chatId,
        senderId: userId,
        receiverId: receiverId,
        messageContent: messageContent,
        messageType: messageType,
        isRead: 0,
        timestamp: DateTime.now(),
        isDelivered: 0,
        senderName: senderName,
        receiverName: receiverName,
        senderPhoneNumber: senderPhoneNumber,
        receiverPhoneNumber: receiverPhoneNumber,
        replyToMessageId: replyToMessageId,
        isForwarded: isForwarded,
      );

      await saveMessageLocal(tempMsg);
      print("💾 Saved temporary message locally with ID: $tempId");

      _socket!.emit("send_message", {
        "chat_id": chatId,
        "sender_id": userId,
        "receiver_id": receiverId,
        "message_text": encryptedContent,
        "message_type": encryptedType,
        "temp_id": tempId,
        "sender_name": senderName,
        "receiver_name": receiverName,
        "sender_phone": senderPhoneNumber,
        "receiver_phone": receiverPhoneNumber,
        "reply_to_message_id": replyToMessageId,
        "is_forwarded": isForwarded ? 1 : 0,
      });

      print("✅ Emitted 'send_message' to socket server");
      SoundUtils.playSendSound();

      // ✅ Send push notification to the receiver
      try {
        const apiUrl = 'http://184.168.126.71:3000/api/send-notification';
        final response = await http.post(
          Uri.parse(apiUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'receiverId': receiverId,
            'messageText': messageContent,
            'chatId': chatId,
            'senderId': userId,
            'senderName': senderName ?? 'User',
          }),
        );

        if (response.statusCode == 200) {
          print('✅ Notification sent successfully!');
        } else {
          print('❌ Failed to send notification: ${response.body}');
        }
      } catch (e) {
        print('❌ Error sending notification: $e');
      }

    } catch (e) {
      print("❌ sendMessage error: $e");
      rethrow;
    }
  }

  /// Send push notification for media
  static Future<void> _sendPushNotification(int receiverId, String messageText, int chatId, int senderId, String senderName) async {
    try {
      const apiUrl = 'http://184.168.126.71:3000/api/send-notification';
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'receiverId': receiverId,
          'messageText': messageText,
          'chatId': chatId,
          'senderId': senderId,
          'senderName': senderName,
          'type': 'media'
        }),
      );

      if (response.statusCode == 200) {
        print('✅ Media notification sent successfully!');
      } else {
        print('❌ Failed to send media notification: ${response.body}');
      }
    } catch (e) {
      print('❌ Error sending media notification: $e');
    }
  }

  // ------------------- UTILITY METHODS -------------------

  static Future<void> updateMessageId(String tempId, String newMessageId, int status) async {
    try {
      final msg = _messageBox.get(tempId) as Message?;
      if (msg != null) {
        // ✅ FIRST: Check if new message ID already exists
        final existingWithNewId = _messageBox.values.firstWhereOrNull(
              (m) => m.messageId == newMessageId,
        );

        if (existingWithNewId != null) {
          print("⚠️ Message with new ID already exists: $newMessageId");
          // Delete the temporary message to avoid duplicates
          await _messageBox.delete(tempId);
          return;
        }

        // ✅ Update message ID and status
        msg.messageId = newMessageId;
        msg.isDelivered = status;

        await _messageBox.delete(tempId);
        await _messageBox.put(newMessageId, msg);

        print("✅ TempId $tempId replaced with $newMessageId (status=$status)");

        _newMessageController.add(msg);
      } else {
        print("⚠️ No message found with tempId=$tempId");
      }
    } catch (e) {
      print("❌ Error updating MessageId: $e");
    }
  }

  static Future<void> updateDeliveryStatus(String messageId, int status) async {
    try {
      final msg = _messageBox.get(messageId) as Message?;
      if (msg != null) {
        msg.isDelivered = status;
        await _messageBox.put(messageId, msg);
        print("✅ Delivery status updated for $messageId = $status");

        _newMessageController.add(msg);
        _messageDeliveredController.sink.add(messageId);
      } else {
        print("⚠️ No message found with ID $messageId");
      }
    } catch (e) {
      print("❌ Error updating delivery status: $e");
    }
  }

  static Future<void> saveMessageLocal(Message message) async {
    try {
      // ✅ FINAL SAFETY CHECK before saving
      final existingMessage = _messageBox.values.firstWhereOrNull(
            (msg) =>
        msg.messageId == message.messageId ||
            (msg.chatId == message.chatId &&
                msg.senderId == message.senderId &&
                msg.messageContent == message.messageContent &&
                msg.timestamp.difference(message.timestamp).inSeconds.abs() < 3),
      );

      if (existingMessage != null) {
        print("⚠️ DUPLICATE BLOCKED in saveMessageLocal: ${message.messageId}");
        print("   Existing ID: ${existingMessage.messageId}");
        return;
      }

      await _messageBox.put(message.messageId, message);
      print("💾 Message saved to local storage: ${message.messageId}");
    } catch (e) {
      print("❌ Error saving message locally: $e");
    }
  }

  static Future<void> markMessageReadLocal(String messageId) async {
    try {
      final msg = (_messageBox.get(messageId) as Message?);
      if (msg != null) {
        msg.isRead = 1;
        await _messageBox.put(messageId, msg);
        print("💾 Local Hive updated as read: $messageId");

        _newMessageController.add(msg);
      } else {
        print("⚠️ No message found in Hive with ID $messageId");
      }
    } catch (e) {
      print("❌ Error marking message read locally: $e");
    }
  }

  static List<Message> getLocalMessages(int chatId) {
    try {
      return _messageBox.values
          .where((m) => m.chatId == chatId)
          .where((m) => !m.messageId.toString().startsWith('temp_'))
          .cast<Message>()
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } catch (e) {
      print("❌ Error getting local messages: $e");
      return [];
    }
  }

  static void joinRoom(int chatId) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit("join_chat", chatId);
      print("✅ Joined room: $chatId");
    } else {
      print("⚠️ Socket not connected, trying to reconnect...");
      initSocket();
      Future.delayed(const Duration(seconds: 2), () {
        if (_socket != null && _socket!.connected) {
          _socket!.emit("join_chat", chatId);
        }
      });
    }
  }

  static void leaveRoom(int chatId) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit("leave_room", {"chat_id": chatId});
      print("🚪 Left room: $chatId");
    }
  }

  static void startTyping(int chatId) {
    final userId = _authBox.get('userId');
    if (_socket != null && _socket!.connected && userId != null) {
      _socket!.emit("typing_start", {"chat_id": chatId, "user_id": userId});
    }
  }

  static void stopTyping(int chatId) {
    final userId = _authBox.get('userId');
    if (_socket != null && _socket!.connected && userId != null) {
      _socket!.emit("typing_stop", {"chat_id": chatId, "user_id": userId});
    }
  }

  static Future<int?> createChat(int otherUserId) async {
    try {
      final userId = _authBox.get('userId');
      if (userId == null) return null;

      final res = await http.post(
        Uri.parse("$apiBase/create_chat.php"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "sender_id": userId.toString(),
          "receiver_id": otherUserId.toString(),
        }),
      );

      if (res.statusCode != 200) {
        print("❌ HTTP Error: ${res.statusCode}");
        return null;
      }

      final data = jsonDecode(res.body);
      if (data["success"] == true && data.containsKey("chat_id")) {
        final chatId = int.tryParse(data["chat_id"].toString());
        if (chatId != null) {
          final chat = Chat(
            chatId: chatId,
            contactId: otherUserId,
            userIds: [],
            chatTitle: '',
          );
          await _chatBox.put(chatId, chat);
          print("💾 Saved new chat in Hive for chatId=$chatId");
        }
        return chatId;
      }
      return null;
    } catch (e) {
      print("❌ Create chat error: $e");
      return null;
    }
  }

  static Future<void> fetchMessages(int chatId) async {
    try {
      final res =
      await http.get(Uri.parse("$apiBase/get_messages.php?chat_id=$chatId"));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data["success"] == true && data["messages"] != null) {
          for (var msg in data["messages"]) {
            await _handleIncomingData(msg);
          }
          print("✅ Messages loaded for chatId=$chatId: ${data["messages"].length}");
        }
      } else {
        print("❌ HTTP Error: ${res.statusCode}");
      }
    } catch (e) {
      print("❌ Fetch messages error: $e");
    }
  }

  /// Fetch all messages for home screen
  static Future<void> fetchAllChatsAndMessages() async {
    if (!_isInitialized) return;

    final chatIds = _messageBox.values.map((m) => m.chatId).toSet();
    for (final chatId in chatIds) {
      await fetchMessages(chatId);
    }
    print("✅ Fetched all messages for home screen");
  }

  /// Mark all messages of a user as delivered (double tick)
  static Future<void> markAllMessagesAsDelivered(int userId) async {
    try {
      final messages = _messageBox.values
          .where((m) => m.receiverId == userId && m.isDelivered == 0)
          .toList();

      final messageIds = <int>[];
      for (final msg in messages) {
        msg.isDelivered = 1;
        await _messageBox.put(msg.messageId, msg);
        _newMessageController.add(msg);

        messageIds.add(msg.messageId as int);
      }

      if (messageIds.isNotEmpty && ChatService._socket != null && ChatService._socket!.connected) {
        ChatService._socket!.emit("mark_delivered_bulk", {
          "message_ids": messageIds,
          "receiver_id": userId,
        });
      }

      print("✅ All messages marked delivered locally and server notified for userId=$userId");
    } catch (e) {
      print("❌ Error marking messages delivered: $e");
    }
  }

  /// Ensure socket is connected and user online
  static Future<void> ensureConnected() async {
    final userId = _authBox.get('userId');
    if (userId == null) return;

    if (_socket == null || !_socket!.connected) {
      print("⚠️ Socket disconnected. Reconnecting...");
      initSocket();
      // Wait for connection
      await Future.delayed(const Duration(seconds: 2));
    }

    // Ensure user status is online
    if (_socket != null && _socket!.connected) {
      _socket!.emit("user_status", {"userId": userId, "status": "online"});
      print("🌐 Ensured online status");
    }
  }

  static Future<void> markMessageRead(String messageId, int chatId) async {
    try {
      final userId = _authBox.get('userId');
      if (userId == null) return;

      await markMessageReadLocal(messageId);

      final res = await http.post(
        Uri.parse("$apiBase/mark_read.php"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"message_id": messageId}),
      );
      if (res.statusCode == 200) {
        print("✅ Marked as read on server via API: $messageId");
      } else {
        print("❌ API error marking read: ${res.statusCode}");
      }

      if (_socket != null && _socket!.connected) {
        _socket!.emit("mark_read_bulk", {
          "message_ids": [messageId],
          "chat_id": chatId,
          "reader_id": userId,
        });
        print("📤 Sent 'mark_read_bulk' event to socket for $messageId");
      }

    } catch (e) {
      print("❌ Mark read error: $e");
    }
  }

  static Future<void> _updateMessageDeletionStatusLocal(String messageId, String role) async {
    try {
      final msg = _messageBox.values.firstWhereOrNull((m) => m.messageId == messageId);
      if (msg != null) {

        if (role == 'sender') {
          msg.isDeletedSender = 1;
        } else if (role == 'receiver') {
          msg.isDeletedReceiver = 1;
        }

        if (msg.isDeletedSender == 1 && msg.isDeletedReceiver == 1) {
          await _messageBox.delete(messageId);
          print("✅ Message deleted completely locally: $messageId");
        } else {
          await _messageBox.put(messageId, msg);
          print("✅ Message marked as deleted by $role locally: $messageId");
        }

        _newMessageController.add(msg);
      }
    } catch (e) {
      print("❌ Error updating local deletion status: $e");
    }
  }

  // ------------------- NEW API COMPATIBLE FUNCTIONS -------------------

  // ✅ CLEAR CHAT FUNCTION
  static Future<void> clearChat(int chatId) async {
    try {
      final userId = _authBox.get('userId');
      if (userId == null) return;

      const apiUrl = "${Config.baseNodeApiUrl}/chats/clear";

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "chat_id": chatId,
          "user_id": userId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["success"] == true) {
          print("✅ Chat cleared successfully: $chatId");
        } else {
          print("❌ Failed to clear chat: ${data['message']}");
        }
      } else {
        print("❌ HTTP Error clearing chat: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ Error clearing chat: $e");
    }
  }

  // ✅ BLOCK USER FUNCTION
  static Future<void> blockUser(int blockedUserId) async {
    try {
      final userId = _authBox.get('userId');
      if (userId == null) return;

      const apiUrl = "${Config.baseNodeApiUrl}/users/block";

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": userId,
          "blocked_user_id": blockedUserId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["success"] == true) {
          _blockedUsers.add(blockedUserId.toString());
          print("✅ User blocked successfully: $blockedUserId");
        } else {
          print("❌ Failed to block user: ${data['message']}");
        }
      } else {
        print("❌ HTTP Error blocking user: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ Error blocking user: $e");
    }
  }

  // ✅ UNBLOCK USER FUNCTION
  static Future<void> unblockUser(int blockedUserId) async {
    try {
      final userId = _authBox.get('userId');
      if (userId == null) return;

      const apiUrl = "${Config.baseNodeApiUrl}/users/unblock";

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": userId,
          "blocked_user_id": blockedUserId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["success"] == true) {
          _blockedUsers.remove(blockedUserId.toString());
          print("✅ User unblocked successfully: $blockedUserId");
        } else {
          print("❌ Failed to unblock user: ${data['message']}");
        }
      } else {
        print("❌ HTTP Error unblocking user: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ Error unblocking user: $e");
    }
  }

  // ✅ CHECK IF USER IS BLOCKED
  static bool isUserBlocked(int userId) {
    return _blockedUsers.contains(userId.toString());
  }

  // ✅ GET COMBINED MESSAGES (PHP + NODE)
  static Future<List<Message>> getCombinedMessages(int chatId) async {
    try {
      final apiUrl = "${Config.baseNodeApiUrl}/messages/combined/$chatId";

      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["success"] == true && data["messages"] != null) {
          final messages = List<Map<String, dynamic>>.from(data["messages"]);
          final List<Message> parsedMessages = [];

          for (var msg in messages) {
            await _handleIncomingData(msg);
            final message = _messageBox.get(msg["message_id"]?.toString());
            if (message != null) {
              parsedMessages.add(message);
            }
          }

          print("✅ Combined messages loaded: ${parsedMessages.length} messages");
          return parsedMessages;
        }
      }
    } catch (e) {
      print("❌ Error getting combined messages: $e");
    }

    // Fallback to local messages
    return getLocalMessages(chatId);
  }

  // ✅ FORWARD MESSAGES (UPDATED FOR NEW API)
  static Future<void> forwardMessages({
    required Set<int> originalMessageIds,
    required int targetChatId,
  }) async {
    if (!_isInitialized) {
      throw Exception("ChatService has not been initialized.");
    }

    final List<Message> messagesToForward = originalMessageIds
        .map((id) => _messageBox.get(id.toString()))
        .whereType<Message>()
        .toList();

    print("DEBUG: Forwarding ${messagesToForward.length} messages to chatId=$targetChatId");

    for (final msg in messagesToForward) {
      await _forwardMessage(
        originalMessage: msg,
        targetChatId: targetChatId,
      );
    }
  }

  static Future<void> _forwardMessage({
    required Message originalMessage,
    required int targetChatId,
  }) async {
    final myUserId = _authBox.get('userId');
    if (myUserId == null) return;

    final chat = _chatBox.get(targetChatId) as Chat?;
    final receiverId = chat?.contactId;

    if (receiverId == null) {
      print("⚠️ Forward failed: receiverId is null for chatId=$targetChatId");
      return;
    }

    print(
        "➡️ Forwarding messageId=${originalMessage.messageId} from userId=$myUserId to receiverId=$receiverId for chatId=$targetChatId");

    _socket?.emit("forward_messages", {
      "original_message_id": originalMessage.messageId,
      "forwarded_by_id": myUserId,
      "to_chat_id": targetChatId,
      "to_user_id": receiverId,
    });
  }

  // ✅ DELETE MESSAGE (UPDATED FOR NEW API)
  static Future<void> deleteMessage({
    required String messageId,
    required int userId,
    required String role, // 'sender' or 'receiver'
  }) async {
    try {
      const apiUrl = "${Config.baseNodeApiUrl}/delete_message";

      final res = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "messageId": messageId,
          "userId": userId,
          "role": role,
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data["success"] == true) {
          print("✅ Message deletion processed successfully on server: $messageId");

          await _updateMessageDeletionStatusLocal(messageId, role);

        } else {
          print("❌ Server reported failure in deletion: ${data['error']}");
        }
      } else {
        print("❌ HTTP Error during message deletion: ${res.statusCode}");
      }
    } catch (e) {
      print("❌ Error deleting message: $e");
    }
  }

  // ✅ LOCAL CHAT CLEARANCE
  static Future<void> _clearChatLocal(int chatId, int userId) async {
    try {
      final messages = _messageBox.values.where((m) => m.chatId == chatId).toList();
      int clearedCount = 0;

      for (final msg in messages) {
        if (msg.receiverId == userId) {
          msg.isDeletedReceiver = 1;
          await _messageBox.put(msg.messageId, msg);
          clearedCount++;
        }
      }

      print("✅ Cleared $clearedCount messages locally for chat $chatId");
    } catch (e) {
      print("❌ Error clearing chat locally: $e");
    }
  }

  // ------------------- UTILITY METHODS -------------------
  static bool get isInitialized => _isInitialized;

  static Set<String> get uploadingMediaIds => _uploadingMediaIds;

  static void cancelMediaUpload(String tempId) {
    _uploadingMediaIds.remove(tempId);
    print("🛑 Media upload cancelled: $tempId");
  }

  // ✅ Get full media URL with automatic decryption
  static String getMediaUrl(String mediaPath) {
    if (mediaPath.startsWith('http')) {
      return mediaPath;
    } else if (mediaPath.startsWith('/uploads/')) {
      // Server automatically decrypts via /media/file/:filename endpoint
      final fileName = mediaPath.split('/').last;
      return '${Config.baseNodeApiUrl}/media/file/$fileName';
    } else {
      return mediaPath;
    }
  }

  // ✅ CLEANUP TIMERS FUNCTION
  static void _cleanupTimers() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _statusUpdateTimer?.cancel();
    _statusUpdateTimer = null;
    print("✅ Cleaned up socket timers");
  }

  static bool get isConnected => _socket?.connected ?? false;

  static void disposeSocket() {
    final userId = _authBox.get('userId');
    if (_socket != null && _socket!.connected && userId != null) {
      _socket!.emit("user_status", {
        "userId": userId,
        "status": "offline"
      });
    }

    _cleanupTimers();
    _cleanupSocketListeners();

    _socket?.disconnect();
    _socket?.destroy();
    _socket = null;
    _isInitialized = false;
    _isConnecting = false;

    // ✅ CLEAR PROCESSED MESSAGE IDs
    _processedMessageIds.clear();
    _uploadingMediaIds.clear();

    // ✅ CLOSE ALL STREAM CONTROLLERS
    _typingStatusController.close();
    _newMessageController.close();
    _userStatusController.close();
    _messageDeliveredController.close();
    _messageSentController.close();
    _uploadProgressController.close();
    _messageDeletedController.close();
    _chatClearedController.close();
    _userBlockedController.close();
    _thumbnailReadyController.close(); // ✅ Added thumbnail controller cleanup

    print("🔌 Socket completely disposed");
  }
}