import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class ProductWebsiteService {
  
  /// Save product-website associations when product is published
  static Future<void> saveProductWebsites({
    required int productId,
    required List<int> websiteIds,
  }) async {
    try {
      if (websiteIds.isEmpty) {
        print('🌐 No websites selected for product $productId');
        return;
      }

      print('🌐 Saving product-website associations...');
      print('🌐 Product ID: $productId');
      print('🌐 Website IDs: $websiteIds');

      final response = await http.post(
        Uri.parse('${Config.baseNodeApiUrl}/product-domain-visibility/save'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'productId': productId,
          'selectedWebsiteIds': websiteIds,
        }),
      );

      print('🌐 Save response status: ${response.statusCode}');
      print('🌐 Save response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          print('✅ Product-website associations saved successfully');
        } else {
          print('❌ Failed to save associations: ${data['message']}');
        }
      } else {
        print('❌ HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error saving product-website associations: $e');
    }
  }

  /// Get products for a specific website
  static Future<Map<String, dynamic>> getWebsiteProducts(int websiteId) async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/product-domain-visibility/products/website/$websiteId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load website products');
      }
    } catch (e) {
      print('Error loading website products: $e');
      return {'success': false, 'products': []};
    }
  }

  /// Get websites with products for user
  static Future<Map<String, dynamic>> getWebsitesWithProducts(int userId) async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/product-domain-visibility/websites/with-products/$userId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load websites with products');
      }
    } catch (e) {
      print('Error loading websites with products: $e');
      return {'success': false, 'websites': []};
    }
  }
}
