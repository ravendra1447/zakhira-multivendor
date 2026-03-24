import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'marketplace_chat_database.dart';

class MarketplaceChatParticipant {
  final int id;
  final int chatRoomId;
  final int userId;
  final int? lastReadMessageId;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final DateTime? lastActiveAt;
  final bool isTyping;
  final DateTime? typingSince;

  MarketplaceChatParticipant({
    required this.id,
    required this.chatRoomId,
    required this.userId,
    this.lastReadMessageId,
    this.isOnline = false,
    this.lastSeenAt,
    this.lastActiveAt,
    this.isTyping = false,
    this.typingSince,
  });

  // From JSON (from API)
  factory MarketplaceChatParticipant.fromJson(Map<String, dynamic> json) {
    return MarketplaceChatParticipant(
      id: json['id'] as int,
      chatRoomId: json['chat_room_id'] as int,
      userId: json['user_id'] as int,
      lastReadMessageId: json['last_read_message_id'] as int?,
      isOnline: json['is_online'] as bool? ?? false,
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.parse(json['last_seen_at'] as String)
          : null,
      lastActiveAt: json['last_active_at'] != null
          ? DateTime.parse(json['last_active_at'] as String)
          : null,
      isTyping: json['typing_status'] as bool? ?? false,
      typingSince: json['typing_since'] != null
          ? DateTime.parse(json['typing_since'] as String)
          : null,
    );
  }

  // From SQLite
  factory MarketplaceChatParticipant.fromMap(Map<String, dynamic> map) {
    return MarketplaceChatParticipant(
      id: map['id'] as int,
      chatRoomId: map['chat_room_id'] as int,
      userId: map['user_id'] as int,
      lastReadMessageId: map['last_read_message_id'] as int?,
      isOnline: (map['is_online'] as int) == 1,
      lastSeenAt: map['last_seen_at'] != null
          ? DateTime.parse(map['last_seen_at'] as String)
          : null,
      lastActiveAt: map['last_active_at'] != null
          ? DateTime.parse(map['last_active_at'] as String)
          : null,
      isTyping: (map['typing_status'] as int) == 1,
      typingSince: map['typing_since'] != null
          ? DateTime.parse(map['typing_since'] as String)
          : null,
    );
  }

  // To SQLite
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chat_room_id': chatRoomId,
      'user_id': userId,
      'last_read_message_id': lastReadMessageId,
      'is_online': isOnline ? 1 : 0,
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'last_active_at': lastActiveAt?.toIso8601String(),
      'typing_status': isTyping ? 1 : 0,
      'typing_since': typingSince?.toIso8601String(),
    };
  }

  // Save to SQLite
  Future<void> saveToLocal() async {
    final db = await MarketplaceChatDatabase.database;
    await db.insert(
      'marketplace_chat_participants',
      toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Update in SQLite
  Future<void> updateToLocal() async {
    final db = await MarketplaceChatDatabase.database;
    await db.update(
      'marketplace_chat_participants',
      toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Delete from SQLite
  Future<void> deleteFromLocal() async {
    final db = await MarketplaceChatDatabase.database;
    await db.delete(
      'marketplace_chat_participants',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Get from SQLite by ID
  static Future<MarketplaceChatParticipant?> getFromLocal(int id) async {
    final db = await MarketplaceChatDatabase.database;
    final maps = await db.query(
      'marketplace_chat_participants',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return MarketplaceChatParticipant.fromMap(maps.first);
    }
    return null;
  }

  // Get participant for chat room and user
  static Future<MarketplaceChatParticipant?> getParticipant(int chatRoomId, int userId) async {
    final db = await MarketplaceChatDatabase.database;
    final maps = await db.query(
      'marketplace_chat_participants',
      where: 'chat_room_id = ? AND user_id = ?',
      whereArgs: [chatRoomId, userId],
    );

    if (maps.isNotEmpty) {
      return MarketplaceChatParticipant.fromMap(maps.first);
    }
    return null;
  }

  // Get all participants for a chat room
  static Future<List<MarketplaceChatParticipant>> getAllForChatRoom(int chatRoomId) async {
    final db = await MarketplaceChatDatabase.database;
    final maps = await db.query(
      'marketplace_chat_participants',
      where: 'chat_room_id = ?',
      whereArgs: [chatRoomId],
    );

    return maps.map((map) => MarketplaceChatParticipant.fromMap(map)).toList();
  }

  // Update online status
  Future<void> updateOnlineStatus(bool online) async {
    final db = await MarketplaceChatDatabase.database;
    await db.update(
      'marketplace_chat_participants',
      {
        'is_online': online ? 1 : 0,
        'last_seen_at': online ? null : DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Update typing status
  Future<void> updateTypingStatus(bool typing) async {
    final db = await MarketplaceChatDatabase.database;
    await db.update(
      'marketplace_chat_participants',
      {
        'typing_status': typing ? 1 : 0,
        'typing_since': typing ? DateTime.now().toIso8601String() : null,
        'last_active_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Update last read message
  Future<void> updateLastReadMessage(int messageId) async {
    final db = await MarketplaceChatDatabase.database;
    await db.update(
      'marketplace_chat_participants',
      {
        'last_read_message_id': messageId,
        'last_active_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Update last active time
  Future<void> updateLastActiveTime() async {
    final db = await MarketplaceChatDatabase.database;
    await db.update(
      'marketplace_chat_participants',
      {'last_active_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Get formatted last seen
  String get formattedLastSeen {
    if (lastSeenAt == null) return '';
    
    final now = DateTime.now();
    final difference = now.difference(lastSeenAt!);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${lastSeenAt!.day}/${lastSeenAt!.month}/${lastSeenAt!.year}';
    }
  }

  // Get online status display
  String get onlineStatusDisplay {
    if (isOnline) return 'Online';
    if (lastSeenAt != null) return 'Last seen ${formattedLastSeen}';
    return 'Offline';
  }
}
