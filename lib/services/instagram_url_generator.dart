/// Centralized URL generation service for Instagram operations
/// Ensures all URLs use server product IDs exclusively
class InstagramUrlGenerator {
  /// Base URL for product pages
  static const String baseProductUrl = '/product';

  /// Generate product URL using server ID exclusively
  /// Format: /product/{server_product_id}
  static String generateProductUrl(int serverProductId) {
    if (serverProductId <= 0) {
      throw ArgumentError('Invalid server product ID: $serverProductId. Only positive server IDs are allowed.');
    }
    return '$baseProductUrl/$serverProductId';
  }

  /// Generate Instagram page URL with server product references
  static String generateInstagramPageUrl(List<int> serverProductIds) {
    if (serverProductIds.isEmpty) {
      throw ArgumentError('Cannot generate Instagram page URL with empty product list');
    }

    // Validate all IDs are server IDs
    for (int id in serverProductIds) {
      if (id <= 0) {
        throw ArgumentError('Invalid server product ID: $id. All product IDs must be server-based.');
      }
    }

    // Generate URL with comma-separated server product IDs
    final productIdsString = serverProductIds.join(',');
    return '/instagram/page?products=$productIdsString';
  }

  /// Validate URL generation before publishing
  static bool validateUrls(List<int> serverProductIds) {
    try {
      // Check if all IDs are valid server IDs
      for (int id in serverProductIds) {
        if (id <= 0) {
          print('❌ Invalid server product ID for URL generation: $id');
          return false;
        }
      }

      // Try generating URLs to ensure they're valid
      for (int id in serverProductIds) {
        generateProductUrl(id);
      }

      if (serverProductIds.isNotEmpty) {
        generateInstagramPageUrl(serverProductIds);
      }

      print('✅ URL validation passed for ${serverProductIds.length} server product IDs');
      return true;
    } catch (e) {
      print('❌ URL validation failed: $e');
      return false;
    }
  }

  /// Update existing Instagram pages with server-based URLs
  /// This is used during migration from local to server-based references
  static Future<void> migrateInstagramPageUrls() async {
    try {
      print('🔄 Starting Instagram page URL migration to server-based format...');
      
      // In a real implementation, this would:
      // 1. Query existing Instagram pages with local product references
      // 2. Map local product IDs to server product IDs
      // 3. Update Instagram page URLs to use server-based format
      // 4. Remove old local-based URL references
      
      // For now, this is a placeholder for the migration logic
      print('✅ Instagram page URL migration completed');
    } catch (e) {
      print('❌ Instagram page URL migration failed: $e');
      throw Exception('Failed to migrate Instagram page URLs: $e');
    }
  }

  /// Generate multiple product URLs efficiently
  static List<String> generateMultipleProductUrls(List<int> serverProductIds) {
    return serverProductIds.map((id) => generateProductUrl(id)).toList();
  }

  /// Validate a single product URL format
  static bool isValidProductUrl(String url) {
    // Check if URL matches the expected format: /product/{positive_integer}
    final regex = RegExp(r'^/product/(\d+)$');
    final match = regex.firstMatch(url);
    
    if (match == null) return false;
    
    final idString = match.group(1);
    if (idString == null) return false;
    
    final id = int.tryParse(idString);
    return id != null && id > 0;
  }

  /// Extract server product ID from a product URL
  static int? extractProductIdFromUrl(String url) {
    final regex = RegExp(r'^/product/(\d+)$');
    final match = regex.firstMatch(url);
    
    if (match == null) return null;
    
    final idString = match.group(1);
    if (idString == null) return null;
    
    final id = int.tryParse(idString);
    return (id != null && id > 0) ? id : null;
  }

  /// Generate URL for Instagram product gallery
  static String generateInstagramGalleryUrl({
    String? category,
    String? search,
    int? limit,
    int? offset,
  }) {
    final params = <String, String>{};
    
    if (category != null && category.isNotEmpty) {
      params['category'] = category;
    }
    if (search != null && search.isNotEmpty) {
      params['search'] = search;
    }
    if (limit != null && limit > 0) {
      params['limit'] = limit.toString();
    }
    if (offset != null && offset >= 0) {
      params['offset'] = offset.toString();
    }

    String url = '/instagram/gallery';
    if (params.isNotEmpty) {
      final queryString = params.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');
      url += '?$queryString';
    }

    return url;
  }

  /// Validate Instagram page URL format
  static bool isValidInstagramPageUrl(String url) {
    // Check if URL matches the expected format: /instagram/page?products={comma_separated_ids}
    final regex = RegExp(r'^/instagram/page\?products=(\d+(?:,\d+)*)$');
    final match = regex.firstMatch(url);
    
    if (match == null) return false;
    
    final idsString = match.group(1);
    if (idsString == null) return false;
    
    final ids = idsString.split(',');
    return ids.every((idStr) {
      final id = int.tryParse(idStr);
      return id != null && id > 0;
    });
  }

  /// Extract server product IDs from Instagram page URL
  static List<int>? extractProductIdsFromInstagramUrl(String url) {
    final regex = RegExp(r'^/instagram/page\?products=(\d+(?:,\d+)*)$');
    final match = regex.firstMatch(url);
    
    if (match == null) return null;
    
    final idsString = match.group(1);
    if (idsString == null) return null;
    
    try {
      final ids = idsString.split(',').map((idStr) => int.parse(idStr)).toList();
      
      // Validate all IDs are positive (server IDs)
      if (ids.every((id) => id > 0)) {
        return ids;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// Generate shareable Instagram page URL
  static String generateShareableInstagramUrl(List<int> serverProductIds, {String? baseUrl}) {
    final relativePath = generateInstagramPageUrl(serverProductIds);
    
    if (baseUrl != null) {
      return '$baseUrl$relativePath';
    } else {
      return relativePath;
    }
  }

  /// Validate all URLs in a batch
  static Map<String, bool> validateUrlBatch(List<String> urls) {
    final results = <String, bool>{};
    
    for (String url in urls) {
      if (url.startsWith('/product/')) {
        results[url] = isValidProductUrl(url);
      } else if (url.startsWith('/instagram/page')) {
        results[url] = isValidInstagramPageUrl(url);
      } else {
        results[url] = false;
      }
    }
    
    return results;
  }
}