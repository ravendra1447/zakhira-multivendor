import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/product.dart';
import 'local_auth_service.dart';

/// Local Database Service for Products
/// Stores products locally before syncing with server
class ProductDatabaseService {
  static final ProductDatabaseService _instance =
      ProductDatabaseService._internal();
  factory ProductDatabaseService() => _instance;
  ProductDatabaseService._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'products.db');

    return await openDatabase(
      path,
      version: 3, // Increment version for migration (added stock fields)
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add marketplace_enabled column
      try {
        await db.execute('''
          ALTER TABLE products ADD COLUMN marketplace_enabled INTEGER DEFAULT 0
        ''');
        print('✅ Database migrated: Added marketplace_enabled column');
      } catch (e) {
        // Column might already exist
        print('⚠️ Migration note: $e');
      }
    }
    
    if (oldVersion < 3) {
      // Add stock_mode and stock_by_color_size columns
      try {
        await db.execute('''
          ALTER TABLE products ADD COLUMN stock_mode TEXT DEFAULT 'simple'
        ''');
        await db.execute('''
          ALTER TABLE products ADD COLUMN stock_by_color_size TEXT
        ''');
        print('✅ Database migrated: Added stock_mode and stock_by_color_size columns');
      } catch (e) {
        // Column might already exist
        print('⚠️ Migration note: $e');
      }
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        category TEXT,
        available_qty TEXT NOT NULL,
        description TEXT,
        status TEXT NOT NULL DEFAULT 'draft',
        price_slabs TEXT,
        attributes TEXT,
        selected_attribute_values TEXT,
        variations TEXT,
        sizes TEXT,
        images TEXT,
        marketplace_enabled INTEGER DEFAULT 0,
        stock_mode TEXT DEFAULT 'simple',
        stock_by_color_size TEXT,
        created_at TEXT,
        updated_at TEXT,
        server_id INTEGER,
        synced INTEGER DEFAULT 0
      )
    ''');

    // Index for faster queries
    await db.execute('''
      CREATE INDEX idx_user_status ON products(user_id, status)
    ''');
  }

  /// Insert or Update Product
  Future<int> saveProduct(Product product) async {
    final db = await database;
    final map = product.toMap();

    // Remove id if null for insert
    if (map['id'] == null) {
      map.remove('id');
    }

    // Convert complex fields to JSON strings
    map['price_slabs'] = jsonEncode(product.priceSlabs);
    map['attributes'] = jsonEncode(product.attributes);
    map['selected_attribute_values'] = jsonEncode(
      product.selectedAttributeValues,
    );
    map['variations'] = jsonEncode(product.variations);
    map['sizes'] = jsonEncode(product.sizes);
    map['images'] = jsonEncode(product.images);
    map['marketplace_enabled'] = product.marketplaceEnabled ? 1 : 0;
    map['stock_mode'] = product.stockMode;
    map['stock_by_color_size'] = product.stockByColorSize != null
        ? jsonEncode(product.stockByColorSize)
        : null;
    map['created_at'] = DateTime.now().toIso8601String();
    map['updated_at'] = DateTime.now().toIso8601String();
    map['synced'] = 0; // Not synced yet

    if (product.id == null) {
      // Insert new product
      return await db.insert('products', map);
    } else {
      // Update existing product
      return await db.update(
        'products',
        map,
        where: 'id = ?',
        whereArgs: [product.id],
      );
    }
  }

  /// Get all products for current user
  Future<List<Product>> getProducts({
    String? status,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    final userId = LocalAuthService.getUserId();

    if (userId == null) {
      return [];
    }

    String whereClause = 'user_id = ?';
    List<dynamic> whereArgs = [userId];

    if (status != null) {
      whereClause += ' AND status = ?';
      whereArgs.add(status);
    }

    String query =
        'SELECT * FROM products WHERE $whereClause ORDER BY updated_at DESC';

    if (limit != null) {
      query += ' LIMIT $limit';
      if (offset != null) {
        query += ' OFFSET $offset';
      }
    }

    final List<Map<String, dynamic>> maps = await db.rawQuery(query, whereArgs);
    return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
  }

  /// Get single product by ID
  Future<Product?> getProduct(int id) async {
    final db = await database;
    final maps = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return Product.fromMap(maps.first);
  }

  /// Get product by server ID
  Future<Product?> getProductByServerId(int serverId) async {
    final db = await database;
    final maps = await db.query(
      'products',
      where: 'server_id = ?',
      whereArgs: [serverId],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return Product.fromMap(maps.first);
  }

  /// Delete product
  Future<int> deleteProduct(int id) async {
    final db = await database;
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  /// Mark product as synced
  Future<void> markAsSynced(int localId, int serverId) async {
    final db = await database;
    await db.update(
      'products',
      {
        'server_id': serverId,
        'synced': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  /// Get unsynced products
  Future<List<Product>> getUnsyncedProducts() async {
    final db = await database;
    final userId = LocalAuthService.getUserId();

    if (userId == null) {
      return [];
    }

    final maps = await db.query(
      'products',
      where: 'user_id = ? AND synced = 0',
      whereArgs: [userId],
    );

    return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
  }

  /// Update product from server data
  Future<void> updateFromServer(Product product) async {
    final db = await database;

    // Check if product exists by server_id
    if (product.id != null) {
      final existing = await getProductByServerId(product.id!);
      if (existing != null) {
        // Update existing
        final map = product.toMap();
        map['price_slabs'] = jsonEncode(product.priceSlabs);
        map['attributes'] = jsonEncode(product.attributes);
        map['selected_attribute_values'] = jsonEncode(
          product.selectedAttributeValues,
        );
        map['variations'] = jsonEncode(product.variations);
        map['sizes'] = jsonEncode(product.sizes);
        map['images'] = jsonEncode(product.images);
        map['synced'] = 1;
        map['server_id'] = product.id;

        await db.update(
          'products',
          map,
          where: 'server_id = ?',
          whereArgs: [product.id],
        );
        return;
      }
    }

    // Insert new product from server
    final map = product.toMap();
    map['price_slabs'] = jsonEncode(product.priceSlabs);
    map['attributes'] = jsonEncode(product.attributes);
    map['selected_attribute_values'] = jsonEncode(
      product.selectedAttributeValues,
    );
    map['variations'] = jsonEncode(product.variations);
    map['sizes'] = jsonEncode(product.sizes);
    map['images'] = jsonEncode(product.images);
    map['synced'] = 1;
    map['server_id'] = product.id;
    map.remove('id'); // Let database auto-generate local id

    await db.insert('products', map);
  }

  /// Clear all products (for logout or reset)
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('products');
  }
}

