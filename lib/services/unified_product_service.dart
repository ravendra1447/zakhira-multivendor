import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';


class UnifiedProductService {
  
  // Admin API - shows ALL variants (for management)
  static Future<Map<String, dynamic>> getAdminProduct(String productId) async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/api/admin/products/$productId/variants'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data;
        }
      }
      
      return {'success': false, 'message': 'Failed to load admin product data'};
    } catch (e) {
      print('Error in getAdminProduct: $e');
      return {'success': false, 'message': 'Error: $e'};
    }
  }
  
  // Marketplace API - shows ONLY ACTIVE variants (for customers)
  static Future<Map<String, dynamic>> getMarketplaceProduct(String productId) async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/api/marketplace/products/$productId'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data;
        }
      }
      
      return {'success': false, 'message': 'Failed to load marketplace product data'};
    } catch (e) {
      print('Error in getMarketplaceProduct: $e');
      return {'success': false, 'message': 'Error: $e'};
    }
  }
  
  // Website API - shows ONLY ACTIVE variants (for customers)
  static Future<Map<String, dynamic>> getWebsiteProduct(String productId) async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/api/website/products/$productId'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data;
        }
      }
      
      return {'success': false, 'message': 'Failed to load website product data'};
    } catch (e) {
      print('Error in getWebsiteProduct: $e');
      return {'success': false, 'message': 'Error: $e'};
    }
  }
  
  // Toggle variant status (uses admin API)
  static Future<Map<String, dynamic>> toggleVariantStatus(
    String productId, 
    String variantId, 
    bool currentStatus
  ) async {
    try {
      final newStatus = !currentStatus;
      
      final response = await http.put(
        Uri.parse('${Config.baseNodeApiUrl}/api/admin/products/$productId/variant/$variantId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'is_active': newStatus,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return {
            'success': true,
            'message': 'Variant status updated successfully',
            'new_status': newStatus
          };
        }
      }
      
      return {'success': false, 'message': 'Failed to update variant status'};
    } catch (e) {
      print('Error in toggleVariantStatus: $e');
      return {'success': false, 'message': 'Error: $e'};
    }
  }
  
  // Toggle all variants status (uses admin API)
  static Future<Map<String, dynamic>> toggleAllVariantsStatus(
    String productId, 
    bool newStatus
  ) async {
    try {
      final response = await http.put(
        Uri.parse('${Config.baseNodeApiUrl}/api/admin/products/$productId/variants'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'is_active': newStatus,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return {
            'success': true,
            'message': 'All variants updated successfully',
            'new_status': newStatus
          };
        }
      }
      
      return {'success': false, 'message': 'Failed to update all variants'};
    } catch (e) {
      print('Error in toggleAllVariantsStatus: $e');
      return {'success': false, 'message': 'Error: $e'};
    }
  }
  
  // Get marketplace product list (for customer browsing)
  static Future<Map<String, dynamic>> getMarketplaceProducts() async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/api/marketplace/products'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data;
        }
      }
      
      return {'success': false, 'message': 'Failed to load marketplace products'};
    } catch (e) {
      print('Error in getMarketplaceProducts: $e');
      return {'success': false, 'message': 'Error: $e'};
    }
  }
  
  // Get website product list (for customer browsing)
  static Future<Map<String, dynamic>> getWebsiteProducts() async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/api/website/products'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data;
        }
      }
      
      return {'success': false, 'message': 'Failed to load website products'};
    } catch (e) {
      print('Error in getWebsiteProducts: $e');
      return {'success': false, 'message': 'Error: $e'};
    }
  }
  
  // Search marketplace products
  static Future<Map<String, dynamic>> searchMarketplaceProducts({
    String? query,
    String? category,
    double? minPrice,
    double? maxPrice,
  }) async {
    try {
      final uri = Uri.parse('${Config.baseNodeApiUrl}/api/marketplace/products').replace(
        query: 'q=$query&category=$category&min_price=$minPrice&max_price=$maxPrice',
      );
      
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data;
        }
      }
      
      return {'success': false, 'message': 'Failed to search marketplace products'};
    } catch (e) {
      print('Error in searchMarketplaceProducts: $e');
      return {'success': false, 'message': 'Error: $e'};
    }
  }
  
  // Search website products
  static Future<Map<String, dynamic>> searchWebsiteProducts({
    String? query,
    String? category,
    double? minPrice,
    double? maxPrice,
  }) async {
    try {
      final uri = Uri.parse('${Config.baseNodeApiUrl}/api/website/search/products').replace(
        query: 'q=$query&category=$category&min_price=$minPrice&max_price=$maxPrice',
      );
      
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data;
        }
      }
      
      return {'success': false, 'message': 'Failed to search website products'};
    } catch (e) {
      print('Error in searchWebsiteProducts: $e');
      return {'success': false, 'message': 'Error: $e'};
    }
  }
}
