import 'dart:convert';

class Product {
  final int? id;
  final int userId;
  final String name;
  final String? category;
  final String? subcategory;
  final String availableQty;
  final String description;
  final String status; // 'draft' or 'publish'
  final List<Map<String, dynamic>> priceSlabs;
  final Map<String, List<String>> attributes;
  final Map<String, String> selectedAttributeValues;
  final List<Map<String, dynamic>> variations; // Color items with images
  final List<String> sizes;
  final List<String> images; // Image URLs
  final bool marketplaceEnabled; // Show in marketplace or not
  final String stockMode; // 'simple', 'color_size', or 'always_available'
  final Map<String, Map<String, int>>? stockByColorSize; // {color: {size: qty}}
  final String? instagramUrl; // Instagram page URL
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Product({
    this.id,
    required this.userId,
    required this.name,
    this.category,
    this.subcategory,
    required this.availableQty,
    required this.description,
    required this.status,
    required this.priceSlabs,
    required this.attributes,
    required this.selectedAttributeValues,
    required this.variations,
    required this.sizes,
    required this.images,
    this.marketplaceEnabled = false,
    this.stockMode = 'simple',
    this.stockByColorSize,
    this.instagramUrl,
    this.createdAt,
    this.updatedAt,
  });

  // Convert to Map for database
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'category': category,
      'subcategory': subcategory,
      'available_qty': availableQty,
      'description': description,
      'status': status,
      'price_slabs': priceSlabs,
      'attributes': attributes,
      'selected_attribute_values': selectedAttributeValues,
      'variations': variations,
      'sizes': sizes,
      'images': images,
      'marketplace_enabled': marketplaceEnabled ? 1 : 0,
      'stock_mode': stockMode,
      'stock_by_color_size': stockByColorSize,
      'product_insta_url': instagramUrl,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  // Create from Map (from database)
  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as int?,
      userId: map['user_id'] as int,
      name: map['name'] as String,
      category: map['category'] as String?,
      subcategory: map['subcategory'] as String?,
      availableQty: map['available_qty'] as String? ?? '0',
      description: map['description'] as String? ?? '',
      status: map['status'] as String? ?? 'draft',
      priceSlabs: (map['price_slabs'] is String)
          ? (map['price_slabs'] as String).isNotEmpty
              ? List<Map<String, dynamic>>.from(
                  jsonDecode(map['price_slabs'] as String))
              : []
          : (map['price_slabs'] != null && map['price_slabs'] is List)
              ? List<Map<String, dynamic>>.from(
                  (map['price_slabs'] as List).map((e) {
                    if (e is Map) {
                      return Map<String, dynamic>.from(e);
                    }
                    return <String, dynamic>{};
                  }))
              : [],
      attributes: (map['attributes'] is String)
          ? (map['attributes'] as String).isNotEmpty
              ? Map<String, List<String>>.from(
                  (jsonDecode(map['attributes'] as String) as Map).map((k, v) {
                    if (v is List) {
                      return MapEntry(k.toString(), List<String>.from(v.map((e) => e.toString())));
                    }
                    return MapEntry(k.toString(), <String>[]);
                  }))
              : {}
          : (map['attributes'] != null && map['attributes'] is Map)
              ? Map<String, List<String>>.from(
                  (map['attributes'] as Map).map((k, v) {
                    if (v is List) {
                      return MapEntry(k.toString(), List<String>.from(v.map((e) => e.toString())));
                    }
                    return MapEntry(k.toString(), <String>[]);
                  }))
              : {},
      selectedAttributeValues: (map['selected_attribute_values'] is String)
          ? (map['selected_attribute_values'] as String).isNotEmpty
              ? Map<String, String>.from(
                  jsonDecode(map['selected_attribute_values'] as String))
              : {}
          : (map['selected_attribute_values'] != null && map['selected_attribute_values'] is Map)
              ? Map<String, String>.from(
                  (map['selected_attribute_values'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())))
              : {},
      variations: (map['variations'] is String)
          ? (map['variations'] as String).isNotEmpty
              ? List<Map<String, dynamic>>.from(
                  jsonDecode(map['variations'] as String))
              : []
          : (map['variations'] != null && map['variations'] is List)
              ? List<Map<String, dynamic>>.from(
                  (map['variations'] as List).map((e) {
                    if (e is Map) {
                      return Map<String, dynamic>.from(e);
                    }
                    return <String, dynamic>{};
                  }))
              : [],
      sizes: (map['sizes'] is String)
          ? (map['sizes'] as String).isNotEmpty
              ? List<String>.from((jsonDecode(map['sizes'] as String) as List).map((e) => e.toString()))
              : []
          : (map['sizes'] != null && map['sizes'] is List)
              ? List<String>.from((map['sizes'] as List).map((e) => e.toString()))
              : [],
      images: (map['images'] is String)
          ? (map['images'] as String).isNotEmpty
              ? List<String>.from((jsonDecode(map['images'] as String) as List).map((e) => e.toString()))
              : []
          : (map['images'] != null && map['images'] is List)
              ? List<String>.from((map['images'] as List).map((e) => e.toString()))
              : [],
      marketplaceEnabled: map['marketplace_enabled'] != null
          ? (map['marketplace_enabled'] == 1 || map['marketplace_enabled'] == true)
          : false,
      stockMode: map['stock_mode'] as String? ?? 'simple',
      stockByColorSize: (map['stock_by_color_size'] is String)
          ? (map['stock_by_color_size'] as String).isNotEmpty
              ? Map<String, Map<String, int>>.from(
                  (jsonDecode(map['stock_by_color_size'] as String) as Map).map(
                    (k, v) => MapEntry(
                      k.toString(),
                      Map<String, int>.from(
                        (v as Map).map((sk, sv) => MapEntry(sk.toString(), (sv as num).toInt())),
                      ),
                    ),
                  ))
              : null
          : (map['stock_by_color_size'] != null && map['stock_by_color_size'] is Map)
              ? Map<String, Map<String, int>>.from(
                  (map['stock_by_color_size'] as Map).map(
                    (k, v) => MapEntry(
                      k.toString(),
                      Map<String, int>.from(
                        (v as Map).map((sk, sv) => MapEntry(sk.toString(), (sv as num).toInt())),
                      ),
                    ),
                  ))
              : null,
      instagramUrl: map['product_insta_url'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  // Convert to JSON for API
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'category': category,
      'subcategory': subcategory,
      'available_qty': availableQty,
      'description': description,
      'status': status,
      'price_slabs': priceSlabs,
      'attributes': attributes,
      'selected_attribute_values': selectedAttributeValues,
      'variations': variations,
      'sizes': sizes,
      'images': images,
      'marketplace_enabled': marketplaceEnabled ? 1 : 0,
      'stock_mode': stockMode,
      'stock_by_color_size': stockByColorSize,
      'product_insta_url': instagramUrl,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  // Create copy with method
  Product copyWith({
    int? id,
    int? userId,
    String? name,
    String? category,
    String? subcategory,
    String? availableQty,
    String? description,
    String? status,
    List<Map<String, dynamic>>? priceSlabs,
    Map<String, List<String>>? attributes,
    Map<String, String>? selectedAttributeValues,
    List<Map<String, dynamic>>? variations,
    List<String>? sizes,
    List<String>? images,
    bool? marketplaceEnabled,
    String? stockMode,
    Map<String, Map<String, int>>? stockByColorSize,
    String? instagramUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      availableQty: availableQty ?? this.availableQty,
      description: description ?? this.description,
      status: status ?? this.status,
      priceSlabs: priceSlabs ?? this.priceSlabs,
      attributes: attributes ?? this.attributes,
      selectedAttributeValues: selectedAttributeValues ?? this.selectedAttributeValues,
      variations: variations ?? this.variations,
      sizes: sizes ?? this.sizes,
      images: images ?? this.images,
      marketplaceEnabled: marketplaceEnabled ?? this.marketplaceEnabled,
      stockMode: stockMode ?? this.stockMode,
      stockByColorSize: stockByColorSize ?? this.stockByColorSize,
      instagramUrl: instagramUrl ?? this.instagramUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

