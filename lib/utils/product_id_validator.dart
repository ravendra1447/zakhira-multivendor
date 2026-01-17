import '../models/product.dart';
import '../services/product_service.dart';

/// Utility class for validating and managing product ID consistency
/// Ensures Instagram operations use server product IDs exclusively
class ProductIdValidator {
  /// Check if product has valid server ID
  static bool hasValidServerId(Product product) {
    // Product must have a valid server ID (the 'id' field from server)
    // Server IDs are positive integers assigned by the backend
    return product.id != null && product.id! > 0;
  }

  /// Filter products with server IDs only
  static List<Product> filterProductsWithServerIds(List<Product> products) {
    return products.where((product) => hasValidServerId(product)).toList();
  }

  /// Map local IDs to server IDs where possible
  /// This is used during migration from local-based to server-based references
  static Future<Map<int, int>> mapLocalToServerIds(List<int> localIds) async {
    final Map<int, int> mapping = {};
    
    try {
      // In a real implementation, this would query the database to find
      // products with matching local IDs and return their server IDs
      // For now, we return an empty mapping since we're moving to server-first
      
      print('🔄 Attempting to map ${localIds.length} local IDs to server IDs');
      
      // This would be implemented based on your database schema
      // Example logic:
      // 1. Query local database for products with localIds
      // 2. For each product, check if it has a server ID
      // 3. Build mapping of localId -> serverId
      
      print('✅ Mapped ${mapping.length} local IDs to server IDs');
      return mapping;
    } catch (e) {
      print('❌ Error mapping local to server IDs: $e');
      return {};
    }
  }

  /// Validate server ID availability for Instagram operations
  static ValidationResult validateForInstagram(List<Product> products) {
    final List<Product> validProducts = [];
    final List<Product> invalidProducts = [];
    final List<String> errorMessages = [];

    for (var product in products) {
      if (hasValidServerId(product)) {
        validProducts.add(product);
      } else {
        invalidProducts.add(product);
        
        String errorMessage;
        if (product.id == null) {
          errorMessage = 'Product "${product.name}" has no server ID';
        } else if (product.id! <= 0) {
          errorMessage = 'Product "${product.name}" has invalid server ID: ${product.id}';
        } else {
          errorMessage = 'Product "${product.name}" failed server ID validation';
        }
        
        errorMessages.add(errorMessage);
      }
    }

    return ValidationResult(
      validProducts: validProducts,
      invalidProducts: invalidProducts,
      errorMessages: errorMessages,
    );
  }

  /// Validate a single product for Instagram operations
  static bool validateSingleProduct(Product product) {
    return hasValidServerId(product);
  }

  /// Get validation error message for a product
  static String? getValidationError(Product product) {
    if (hasValidServerId(product)) {
      return null;
    }

    if (product.id == null) {
      return 'Product has no server ID. Please sync with server first.';
    } else if (product.id! <= 0) {
      return 'Product has invalid server ID: ${product.id}. Only server-synced products can be used for Instagram.';
    } else {
      return 'Product failed server ID validation.';
    }
  }

  /// Check if a list of product IDs are all valid server IDs
  static bool areAllServerIds(List<int> productIds) {
    return productIds.every((id) => id > 0);
  }

  /// Filter out invalid server IDs from a list
  static List<int> filterValidServerIds(List<int> productIds) {
    return productIds.where((id) => id > 0).toList();
  }

  /// Get count of products that need synchronization
  static int getUnsyncedCount(List<Product> products) {
    return products.where((product) => !hasValidServerId(product)).length;
  }

  /// Get products that need synchronization
  static List<Product> getUnsyncedProducts(List<Product> products) {
    return products.where((product) => !hasValidServerId(product)).toList();
  }

  /// Generate user-friendly message about product validation
  static String generateValidationMessage(ValidationResult result) {
    final validCount = result.validProducts.length;
    final invalidCount = result.invalidProducts.length;
    final totalCount = validCount + invalidCount;

    if (invalidCount == 0) {
      return 'All $totalCount products are ready for Instagram';
    } else if (validCount == 0) {
      return 'No products are ready for Instagram. Please sync your products with the server first.';
    } else {
      return '$validCount of $totalCount products are ready for Instagram. $invalidCount products need to be synced with the server.';
    }
  }
}

/// Result model for product validation operations
class ValidationResult {
  final List<Product> validProducts;
  final List<Product> invalidProducts;
  final List<String> errorMessages;

  ValidationResult({
    required this.validProducts,
    required this.invalidProducts,
    required this.errorMessages,
  });

  /// Check if validation passed (all products are valid)
  bool get isValid => invalidProducts.isEmpty;

  /// Check if validation failed (some products are invalid)
  bool get hasErrors => invalidProducts.isNotEmpty;

  /// Get count of valid products
  int get validCount => validProducts.length;

  /// Get count of invalid products
  int get invalidCount => invalidProducts.length;

  /// Get total count of products validated
  int get totalCount => validCount + invalidCount;

  /// Get success rate as percentage
  double get successRate {
    if (totalCount == 0) return 0.0;
    return (validCount / totalCount) * 100;
  }
}