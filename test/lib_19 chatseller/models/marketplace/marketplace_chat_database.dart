import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class MarketplaceChatDatabase {
  static Database? _database;
  static const String _databaseName = 'marketplace_chat.db';
  static const int _databaseVersion = 1;

  // Get database instance
  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // Initialize database
  static Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // Create tables
  static Future<void> _onCreate(Database db, int version) async {
    // Create chat rooms table
    await db.execute('''
      CREATE TABLE marketplace_chat_rooms (
        id INTEGER PRIMARY KEY,
        product_id INTEGER NOT NULL,
        buyer_id INTEGER NOT NULL,
        seller_id INTEGER NOT NULL,
        status TEXT DEFAULT 'active',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        product_name TEXT,
        product_images TEXT,
        buyer_name TEXT,
        seller_name TEXT,
        unread_count INTEGER DEFAULT 0,
        last_message TEXT,
        last_message_time TEXT,
        last_active_at TEXT
      )
    ''');

    // Create messages table
    await db.execute('''
      CREATE TABLE marketplace_chat_messages (
        id INTEGER PRIMARY KEY,
        chat_room_id INTEGER NOT NULL,
        sender_id INTEGER NOT NULL,
        message_type TEXT DEFAULT 'text',
        message_content TEXT NOT NULL,
        encrypted_content TEXT NOT NULL,
        product_info TEXT,
        is_read INTEGER DEFAULT 0,
        is_delivered INTEGER DEFAULT 0,
        delivery_time TEXT,
        read_time TEXT,
        encryption_key TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sender_name TEXT,
        sender_avatar TEXT,
        local_status TEXT DEFAULT 'pending',
        temp_id TEXT
      )
    ''');

    // Create participants table
    await db.execute('''
      CREATE TABLE marketplace_chat_participants (
        id INTEGER PRIMARY KEY,
        chat_room_id INTEGER NOT NULL,
        user_id INTEGER NOT NULL,
        last_read_message_id INTEGER,
        is_online INTEGER DEFAULT 0,
        last_seen_at TEXT,
        last_active_at TEXT,
        typing_status INTEGER DEFAULT 0,
        typing_since TEXT
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_chat_room_messages ON marketplace_chat_messages(chat_room_id, created_at)');
    await db.execute('CREATE INDEX idx_sender_messages ON marketplace_chat_messages(sender_id, created_at)');
    await db.execute('CREATE INDEX idx_unread_messages ON marketplace_chat_messages(is_read, chat_room_id)');
    await db.execute('CREATE INDEX idx_participant_rooms ON marketplace_chat_participants(user_id, chat_room_id)');
  }

  // Upgrade database
  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle database upgrades here
  }

  // Close database
  static Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  // Clear all data (for testing)
  static Future<void> clearAllData() async {
    final db = await database;
    await db.delete('marketplace_chat_messages');
    await db.delete('marketplace_chat_rooms');
    await db.delete('marketplace_chat_participants');
  }
}
