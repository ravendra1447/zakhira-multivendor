import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'marketplace_chat_database.dart';
import 'marketplace_attachment.dart';

class MarketplaceChatMessage {
  final int id;
  final int chatRoomId;
  final int senderId;
  final String messageType; // 'text', 'image', 'product_info'
  final String messageContent;
  final MarketplaceProductInfo? productInfo;
  final bool isRead;
  final bool isDelivered;
  final DateTime? deliveryTime;
  final DateTime? readTime;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? senderName;
  final String? senderAvatar;
  final String encryptedContent;
  final String encryptionKey;
  final MessageLocalStatus localStatus;
  final List<MarketplaceAttachment>? attachments;
  final String? tempId;

  MarketplaceChatMessage({
    required this.id,
    required this.chatRoomId,
    required this.senderId,
    required this.messageType,
    required this.messageContent,
    this.productInfo,
    required this.isRead,
    this.isDelivered = false,
    this.deliveryTime,
    this.readTime,
    required this.createdAt,
    required this.updatedAt,
    this.senderName,
    this.senderAvatar,
    required this.encryptedContent,
    required this.encryptionKey,
    this.localStatus = MessageLocalStatus.sent,
    this.attachments,
    this.tempId,
  });

  // From JSON (from API)
  factory MarketplaceChatMessage.fromJson(Map<String, dynamic> json) {
    // Parse attachments if present
    List<MarketplaceAttachment>? attachments;
    if (json['attachments'] != null && json['attachments'] is List) {
      attachments = (json['attachments'] as List)
          .map((item) => MarketplaceAttachment.fromJson(item))
          .toList();
    }

    return MarketplaceChatMessage(
      id: json['id'] as int,
      chatRoomId: json['chat_room_id'] as int,
      senderId: json['sender_id'] as int,
      messageType: json['message_type'] as String? ?? 'text',
      messageContent: json['message_content'] as String,
      productInfo: json['product_info'] != null
          ? MarketplaceProductInfo.fromJson(json['product_info'])
          : null,
      isRead: (json['is_read'] as int? ?? 0) == 1,
      isDelivered: (json['is_delivered'] as int? ?? 0) == 1,
      deliveryTime: json['delivery_time'] != null
          ? DateTime.parse(json['delivery_time'] as String)
          : null,
      readTime: json['read_time'] != null
          ? DateTime.parse(json['read_time'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      senderName: json['sender_name'] as String?,
      senderAvatar: json['sender_avatar'] as String?,
      encryptedContent: json['encrypted_content'] as String? ?? '',
      encryptionKey: json['encryption_key'] as String? ?? '',
      localStatus: MessageLocalStatus.sent,
      attachments: attachments,
    );
  }

  // From SQLite
  factory MarketplaceChatMessage.fromMap(Map<String, dynamic> map) {
    return MarketplaceChatMessage(
      id: map['id'] as int,
      chatRoomId: map['chat_room_id'] as int,
      senderId: map['sender_id'] as int,
      messageType: map['message_type'] as String? ?? 'text',
      messageContent: map['message_content'] as String,
      productInfo: map['product_info'] != null
          ? MarketplaceProductInfo.fromJson(jsonDecode(map['product_info']))
          : null,
      isRead: (map['is_read'] as int) == 1,
      isDelivered: (map['is_delivered'] as int) == 1,
      deliveryTime: map['delivery_time'] != null
          ? DateTime.parse(map['delivery_time'] as String)
          : null,
      readTime: map['read_time'] != null
          ? DateTime.parse(map['read_time'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      senderName: map['sender_name'] as String?,
      senderAvatar: map['sender_avatar'] as String?,
      encryptedContent: map['encrypted_content'] as String,
      encryptionKey: map['encryption_key'] as String,
      localStatus: _parseLocalStatus(map['local_status'] as String?),
      tempId: map['temp_id'] as String?,
    );
  }

  // To SQLite
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chat_room_id': chatRoomId,
      'sender_id': senderId,
      'message_type': messageType,
      'message_content': messageContent,
      'product_info': productInfo != null ? jsonEncode(productInfo!.toJson()) : null,
      'is_read': isRead ? 1 : 0,
      'is_delivered': isDelivered ? 1 : 0,
      'delivery_time': deliveryTime?.toIso8601String(),
      'read_time': readTime?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sender_name': senderName,
      'sender_avatar': senderAvatar,
      'encrypted_content': encryptedContent,
      'encryption_key': encryptionKey,
      'local_status': localStatus.name,
      'temp_id': tempId,
    };
  }

  // Parse local status from string
  static MessageLocalStatus _parseLocalStatus(String? status) {
    switch (status) {
      case 'pending':
        return MessageLocalStatus.pending;
      case 'sending':
        return MessageLocalStatus.sending;
      case 'sent':
        return MessageLocalStatus.sent;
      case 'failed':
        return MessageLocalStatus.failed;
      default:
        return MessageLocalStatus.sent;
    }
  }

  // Check if message is from current user
  bool isFromCurrentUser(int currentUserId) {
    return senderId == currentUserId;
  }

  // Check if message has product info
  bool get hasProductInfo => productInfo != null;

  // Get message status for display
  MessageStatus get status {
    if (isRead) return MessageStatus.read;
    if (isDelivered) return MessageStatus.delivered;
    return MessageStatus.sent;
  }

  // Get formatted time
  String get formattedTime {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  // Get time for display
  String get displayTime {
    final hour = createdAt.hour.toString().padLeft(2, '0');
    final minute = createdAt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // Get read time for display
  String? get readTimeDisplay {
    if (readTime == null) return null;
    final hour = readTime!.hour.toString().padLeft(2, '0');
    final minute = readTime!.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // Save to SQLite
  Future<void> saveToLocal() async {
    final db = await MarketplaceChatDatabase.database;
    await db.insert(
      'marketplace_chat_messages',
      toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Update in SQLite
  Future<void> updateToLocal() async {
    final db = await MarketplaceChatDatabase.database;
    await db.update(
      'marketplace_chat_messages',
      toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Delete from SQLite
  Future<void> deleteFromLocal() async {
    final db = await MarketplaceChatDatabase.database;
    await db.delete(
      'marketplace_chat_messages',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Get from SQLite by ID
  static Future<MarketplaceChatMessage?> getFromLocal(int id) async {
    final db = await MarketplaceChatDatabase.database;
    final maps = await db.query(
      'marketplace_chat_messages',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return MarketplaceChatMessage.fromMap(maps.first);
    }
    return null;
  }

  // Get all messages for a chat room from SQLite
  static Future<List<MarketplaceChatMessage>> getAllForChatRoom(int chatRoomId) async {
    final db = await MarketplaceChatDatabase.database;
    final maps = await db.query(
      'marketplace_chat_messages',
      where: 'chat_room_id = ?',
      whereArgs: [chatRoomId],
      orderBy: 'created_at ASC',
    );

    return maps.map((map) => MarketplaceChatMessage.fromMap(map)).toList();
  }

  // Get pending messages for a chat room
  static Future<List<MarketplaceChatMessage>> getPendingMessages(int chatRoomId) async {
    final db = await MarketplaceChatDatabase.database;
    final maps = await db.query(
      'marketplace_chat_messages',
      where: 'chat_room_id = ? AND local_status = ?',
      whereArgs: [chatRoomId, 'pending'],
      orderBy: 'created_at ASC',
    );

    return maps.map((map) => MarketplaceChatMessage.fromMap(map)).toList();
  }

  // Update message status
  Future<void> updateStatus(MessageStatus newStatus) async {
    final db = await MarketplaceChatDatabase.database;
    final now = DateTime.now();
    
    Map<String, dynamic> updates = {
      'updated_at': now.toIso8601String(),
    };

    switch (newStatus) {
      case MessageStatus.delivered:
        updates['is_delivered'] = 1;
        updates['delivery_time'] = now.toIso8601String();
        break;
      case MessageStatus.read:
        updates['is_read'] = 1;
        updates['read_time'] = now.toIso8601String();
        updates['is_delivered'] = 1;
        updates['delivery_time'] = now.toIso8601String();
        break;
      case MessageStatus.sent:
        updates['local_status'] = 'sent';
        break;
    }

    await db.update(
      'marketplace_chat_messages',
      updates,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Update local status
  Future<void> updateLocalStatus(MessageLocalStatus newStatus) async {
    final db = await MarketplaceChatDatabase.database;
    await db.update(
      'marketplace_chat_messages',
      {
        'local_status': newStatus.name,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

enum MessageStatus {
  sent,
  delivered,
  read,
}

enum MessageLocalStatus {
  pending,
  sending,
  sent,
  failed,
}

class MarketplaceProductInfo {
  final int productId;
  final String productName;
  final double price;
  final double? maxPrice; // For price range
  final String image;

  MarketplaceProductInfo({
    required this.productId,
    required this.productName,
    required this.price,
    this.maxPrice,
    required this.image,
  });

  factory MarketplaceProductInfo.fromJson(Map<String, dynamic> json) {
    return MarketplaceProductInfo(
      productId: json['product_id'] as int,
      productName: json['product_name'] as String,
      price: (json['price'] as num).toDouble(),
      maxPrice: json['max_price'] != null ? (json['max_price'] as num).toDouble() : null,
      image: json['image'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'product_name': productName,
      'price': price,
      if (maxPrice != null) 'max_price': maxPrice,
      'image': image,
    };
  }

  // Get formatted price
  String get formattedPrice {
    if (maxPrice != null && maxPrice! > price) {
      return '₹${price.toStringAsFixed(2)}-${maxPrice!.toStringAsFixed(2)}';
    }
    return '₹${price.toStringAsFixed(1)}';
  }
}
