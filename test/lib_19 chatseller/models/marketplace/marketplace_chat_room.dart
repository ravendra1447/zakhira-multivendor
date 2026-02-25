import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'marketplace_chat_database.dart';

class MarketplaceChatRoom {
  final int id;
  final int productId;
  final int buyerId;
  final int sellerId;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? productName;
  final String? productImages;
  final String? buyerName;
  final String? sellerName;
  final int unreadCount;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final DateTime? lastActiveAt;

  MarketplaceChatRoom({
    required this.id,
    required this.productId,
    required this.buyerId,
    required this.sellerId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.productName,
    this.productImages,
    this.buyerName,
    this.sellerName,
    this.unreadCount = 0,
    this.lastMessage,
    this.lastMessageTime,
    this.lastActiveAt,
  });

  // From JSON (from API)
  factory MarketplaceChatRoom.fromJson(Map<String, dynamic> json) {
    return MarketplaceChatRoom(
      id: json['id'] as int,
      productId: json['product_id'] as int,
      buyerId: json['buyer_id'] as int,
      sellerId: json['seller_id'] as int,
      status: json['status'] as String? ?? 'active',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      productName: json['product_name'] as String?,
      productImages: json['product_images'] as String?,
      buyerName: json['buyer_name'] as String?,
      sellerName: json['seller_name'] as String?,
      unreadCount: json['unread_count'] as int? ?? 0,
      lastMessage: json['last_message'] as String?,
      lastMessageTime: json['last_message_time'] != null
          ? DateTime.parse(json['last_message_time'] as String)
          : null,
      lastActiveAt: json['last_active_at'] != null
          ? DateTime.parse(json['last_active_at'] as String)
          : null,
    );
  }

  // From SQLite
  factory MarketplaceChatRoom.fromMap(Map<String, dynamic> map) {
    return MarketplaceChatRoom(
      id: map['id'] as int,
      productId: map['product_id'] as int,
      buyerId: map['buyer_id'] as int,
      sellerId: map['seller_id'] as int,
      status: map['status'] as String? ?? 'active',
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      productName: map['product_name'] as String?,
      productImages: map['product_images'] as String?,
      buyerName: map['buyer_name'] as String?,
      sellerName: map['seller_name'] as String?,
      unreadCount: map['unread_count'] as int? ?? 0,
      lastMessage: map['last_message'] as String?,
      lastMessageTime: map['last_message_time'] != null
          ? DateTime.parse(map['last_message_time'] as String)
          : null,
      lastActiveAt: map['last_active_at'] != null
          ? DateTime.parse(map['last_active_at'] as String)
          : null,
    );
  }

  // To SQLite
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'product_name': productName,
      'product_images': productImages,
      'buyer_name': buyerName,
      'seller_name': sellerName,
      'unread_count': unreadCount,
      'last_message': lastMessage,
      'last_message_time': lastMessageTime?.toIso8601String(),
      'last_active_at': lastActiveAt?.toIso8601String(),
    };
  }

  // Get first product image if multiple images exist
  String? get firstProductImage {
    if (productImages == null || productImages!.isEmpty) return null;
    
    try {
      final images = productImages!.split(',');
      return images.isNotEmpty ? images.first.trim() : null;
    } catch (e) {
      return productImages;
    }
  }

  // Get display name for the other user (not current user)
  String getOtherUserName(int currentUserId) {
    if (currentUserId == buyerId) {
      return sellerName ?? 'Seller';
    } else {
      return buyerName ?? 'Buyer';
    }
  }

  // Check if current user is seller
  bool isCurrentUserSeller(int currentUserId) {
    return currentUserId == sellerId;
  }

  // Check if current user is buyer
  bool isCurrentUserBuyer(int currentUserId) {
    return currentUserId == buyerId;
  }

  // Get formatted last message time
  String get formattedLastMessageTime {
    if (lastMessageTime == null) return '';
    
    final now = DateTime.now();
    final difference = now.difference(lastMessageTime!);

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

  // Save to SQLite
  Future<void> saveToLocal() async {
    final db = await MarketplaceChatDatabase.database;
    await db.insert(
      'marketplace_chat_rooms',
      toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Update in SQLite
  Future<void> updateToLocal() async {
    final db = await MarketplaceChatDatabase.database;
    await db.update(
      'marketplace_chat_rooms',
      toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Delete from SQLite
  Future<void> deleteFromLocal() async {
    final db = await MarketplaceChatDatabase.database;
    await db.delete(
      'marketplace_chat_rooms',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Get from SQLite by ID
  static Future<MarketplaceChatRoom?> getFromLocal(int id) async {
    final db = await MarketplaceChatDatabase.database;
    final maps = await db.query(
      'marketplace_chat_rooms',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return MarketplaceChatRoom.fromMap(maps.first);
    }
    return null;
  }

  // Get all chat rooms for a user from SQLite
  static Future<List<MarketplaceChatRoom>> getAllForUser(int userId) async {
    final db = await MarketplaceChatDatabase.database;
    final maps = await db.query(
      'marketplace_chat_rooms',
      where: 'buyer_id = ? OR seller_id = ?',
      whereArgs: [userId, userId],
      orderBy: 'last_active_at DESC',
    );

    return maps.map((map) => MarketplaceChatRoom.fromMap(map)).toList();
  }

  // Update unread count
  Future<void> updateUnreadCount(int count) async {
    final db = await MarketplaceChatDatabase.database;
    await db.update(
      'marketplace_chat_rooms',
      {'unread_count': count, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Update last message
  Future<void> updateLastMessage(String message, DateTime messageTime) async {
    final db = await MarketplaceChatDatabase.database;
    await db.update(
      'marketplace_chat_rooms',
      {
        'last_message': message,
        'last_message_time': messageTime.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'last_active_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
