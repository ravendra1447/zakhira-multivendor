import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class WebsiteService {
  // Fetch all available websites
  static Future<List<dynamic>> getAvailableWebsites() async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/websites/available'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'] ?? [];
      } else {
        throw Exception('Failed to fetch available websites');
      }
    } catch (e) {
      throw Exception('Error fetching available websites: $e');
    }
  }

  // Fetch user's linked websites
  static Future<List<dynamic>> getUserWebsites(int userId) async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/websites/user/$userId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'] ?? [];
      } else {
        throw Exception('Failed to fetch user websites');
      }
    } catch (e) {
      throw Exception('Error fetching user websites: $e');
    }
  }

  // Link user to website
  static Future<bool> linkUserToWebsite({
    required int userId,
    required int websiteId,
    String role = 'user',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${Config.baseNodeApiUrl}/websites/link'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'userId': userId,
          'websiteId': websiteId,
          'role': role,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] ?? false;
      } else {
        throw Exception('Failed to link website');
      }
    } catch (e) {
      throw Exception('Error linking website: $e');
    }
  }

  // Update website link status
  static Future<bool> updateWebsiteLinkStatus({
    required int userId,
    required int websiteId,
    required String status,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('${Config.baseNodeApiUrl}/websites/update-status'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'userId': userId,
          'websiteId': websiteId,
          'status': status,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] ?? false;
      } else {
        throw Exception('Failed to update website status');
      }
    } catch (e) {
      throw Exception('Error updating website status: $e');
    }
  }

  // Fetch products for a specific website
  static Future<Map<String, dynamic>> getWebsiteProducts({
    required int websiteId,
    required int userId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/websites/products/$websiteId/$userId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'data': data['data'] ?? []
        };
      } else {
        throw Exception('Failed to fetch website products');
      }
    } catch (e) {
      throw Exception('Error fetching website products: $e');
    }
  }

  // Fetch products published to a specific website (for Website Products List)
  static Future<Map<String, dynamic>> getPublishedWebsiteProducts(int websiteId) async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/product-domain-visibility/products/website/$websiteId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['success'] ?? false,
          'products': data['products'] ?? []
        };
      } else {
        throw Exception('Failed to fetch published website products');
      }
    } catch (e) {
      throw Exception('Error fetching published website products: $e');
    }
  }

  // Fetch websites with published products for a user
  static Future<Map<String, dynamic>> getWebsitesWithProducts(int userId) async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/product-domain-visibility/websites/with-products/$userId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['success'] ?? false,
          'websites': data['websites'] ?? []
        };
      } else {
        throw Exception('Failed to fetch websites with products');
      }
    } catch (e) {
      throw Exception('Error fetching websites with products: $e');
    }
  }
}
