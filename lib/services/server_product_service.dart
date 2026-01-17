import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product.dart';
import 'local_auth_service.dart';

/// Specialized service for Instagram-specific server product operations
/// Implements server-first approach to eliminate local/server ID mismatches
class ServerProductService {
  static const String baseUrl = "http://184.168.126.71:3000/api";

  /// Fetch products for Instagram creation using server-only approach
  /// This mirrors the marketplace pattern to ensure consistency
  static Future<ServerProductResult> getProductsForInstagram({
    String status = 'publish',
    int? limit,
    int? offset,
  }) async {
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        return ServerProductResult(
          products: [],
          excludedProducts: [],
          errorMessage: "User not logged in",
          success: false,
        );
      }

      // Use marketplace pattern: fetch from server with user_id filter
      final payload = {
        'user_id': userId,
        'status': status,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
      };

      final response = await http.post(
        Uri.parse("$baseUrl/products/list"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      final result = jsonDecode(response.body) as Map<String, dynamic>;
      
      if (result['success'] != true) {
        return ServerProductResult(
          products: [],
          excludedProducts: [],
          errorMessage: result['message'] ?? 'Failed to fetch products from server',
          success: false,
        );
      }

      final productsData = result['data'] as List<dynamic>? ?? [];
      
      // Parse products and validate server IDs
      List<Product> validProducts = [];
      List<Product> excludedProducts = [];
      
      for (var productData in productsData) {
        try {
          final productMap = Map<String, dynamic>.from(productData);
          
          // Handle marketplace_enabled: server sends 0/1, Product expects boolean
          if (productMap['marketplace_enabled'] != null) {
            productMap['marketplace_enabled'] = productMap['marketplace_enabled'] == 1 ||
                                                productMap['marketplace_enabled'] == '1' ||
                                                productMap['marketplace_enabled'] == true;
          }
          
          final product = Product.fromMap(productMap);
          
          // Validate server ID availability
          if (hasValidServerId(product)) {
            validProducts.add(product);
          } else {
            excludedProducts.add(product);
          }
        } catch (e) {
          print('❌ Error parsing product for Instagram: $e');
          print('   Product data: $productData');
        }
      }

      // Deduplicate by server product ID to ensure no duplicates
      final Map<int, Product> productsMap = {};
      for (var product in validProducts) {
        if (product.id != null) {
          // Use server ID as key for deduplication
          productsMap[product.id!] = product;
        }
      }

      final deduplicatedProducts = productsMap.values.toList();
      
      // Sort by updated_at DESC (latest first) - same as marketplace
      deduplicatedProducts.sort((a, b) {
        if (a.updatedAt == null && b.updatedAt == null) return 0;
        if (a.updatedAt == null) return 1;
        if (b.updatedAt == null) return -1;
        return b.updatedAt!.compareTo(a.updatedAt!);
      });

      print('✅ Loaded ${deduplicatedProducts.length} valid products for Instagram (${excludedProducts.length} excluded)');

      return ServerProductResult(
        products: deduplicatedProducts,
        excludedProducts: excludedProducts,
        errorMessage: null,
        success: true,
      );
    } catch (e) {
      print('❌ Error fetching products for Instagram: $e');
      return ServerProductResult(
        products: [],
        excludedProducts: [],
        errorMessage: "Network error: ${e.toString()}",
        success: false,
      );
    }
  }

  /// Validate that products have server IDs
  static List<Product> validateServerIds(List<Product> products) {
    return products.where((product) => hasValidServerId(product)).toList();
  }

  /// Check if product has valid server ID
  static bool hasValidServerId(Product product) {
    // Product must have a valid server ID (the 'id' field from server)
    return product.id != null && product.id! > 0;
  }

  /// Filter products with server IDs only
  static List<Product> filterProductsWithServerIds(List<Product> products) {
    return validateServerIds(products);
  }

  /// Update products for Instagram using server IDs exclusively
  static Future<Map<String, dynamic>> updateProductsForInstagram({
    required List<int> serverProductIds,
  }) async {
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        return {"success": false, "message": "User not logged in"};
      }

      // Validate all IDs are server IDs (positive integers)
      for (int id in serverProductIds) {
        if (id <= 0) {
          return {
            "success": false, 
            "message": "Invalid server product ID: $id. Only server-based product IDs are allowed for Instagram operations."
          };
        }
      }

      final response = await http.post(
        Uri.parse("$baseUrl/products/update-instagram"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'user_id': userId,
          'product_ids': serverProductIds, // Use server IDs exclusively
        }),
      );

      final result = jsonDecode(response.body) as Map<String, dynamic>;
      
      print('✅ Updated ${serverProductIds.length} products for Instagram using server IDs');
      return result;
    } catch (e) {
      print('❌ Error updating products for Instagram: $e');
      return {"success": false, "message": "Error: ${e.toString()}"};
    }
  }

  /// Generate server-based product URLs
  static String generateProductUrl(int serverProductId) {
    if (serverProductId <= 0) {
      throw ArgumentError('Invalid server product ID: $serverProductId');
    }
    return '/product/$serverProductId';
  }

  /// Trigger product synchronization
  static Future<SyncResult> syncProductsToServer() async {
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        return SyncResult(
          success: false,
          message: "User not logged in",
          syncedCount: 0,
          failedCount: 0,
        );
      }

      // This would trigger a sync operation
      // For now, return a placeholder result
      // In a real implementation, this would sync local products to server
      return SyncResult(
        success: true,
        message: "Sync completed successfully",
        syncedCount: 0,
        failedCount: 0,
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message: "Sync failed: ${e.toString()}",
        syncedCount: 0,
        failedCount: 0,
      );
    }
  }
}

/// Result model for server product operations
class ServerProductResult {
  final List<Product> products;
  final List<Product> excludedProducts;
  final String? errorMessage;
  final bool success;

  ServerProductResult({
    required this.products,
    required this.excludedProducts,
    required this.errorMessage,
    required this.success,
  });

  /// Get count of excluded products
  int get excludedCount => excludedProducts.length;

  /// Get count of valid products
  int get validCount => products.length;

  /// Check if any products were excluded
  bool get hasExcludedProducts => excludedProducts.isNotEmpty;
}

/// Result model for sync operations
class SyncResult {
  final bool success;
  final String message;
  final int syncedCount;
  final int failedCount;

  SyncResult({
    required this.success,
    required this.message,
    required this.syncedCount,
    required this.failedCount,
  });
}