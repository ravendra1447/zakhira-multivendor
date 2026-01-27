import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'local_auth_service.dart';

class AdminDashboardService {
  // Check if user is admin for any website
  static Future<bool> isAdminUser() async {
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) return false;

      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/websites/user/$userId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final websites = data['data'] as List? ?? [];
        
        // Check if any website has admin role
        return websites.any((website) => 
          website['role']?.toString().toLowerCase() == 'admin'
        );
      }
      return false;
    } catch (e) {
      print('Error checking admin status: $e');
      return false;
    }
  }

  // Get admin dashboard data
  static Future<Map<String, dynamic>> getAdminDashboardData() async {
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/orders/admin/dashboard?userId=$userId'),
        headers: {
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      print('Admin Dashboard Response status: ${response.statusCode}');
      print('Admin Dashboard Response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] && responseData['data'] != null) {
          return responseData['data'];
        } else {
          throw Exception('API returned failure: ${responseData['message'] ?? 'Unknown error'}');
        }
      } else if (response.statusCode == 403) {
        throw Exception('User is not an admin for any website');
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      print('Admin Dashboard API Error: $e');
      throw Exception('Failed to load admin dashboard: $e');
    }
  }

  // Get admin websites
  static Future<List<Map<String, dynamic>>> getAdminWebsites() async {
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/websites/user/$userId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final websites = data['data'] as List? ?? [];
        
        // Filter only admin websites
        return websites.where((website) => 
          website['role']?.toString().toLowerCase() == 'admin'
        ).toList().cast<Map<String, dynamic>>();
      } else {
        throw Exception('Failed to fetch admin websites');
      }
    } catch (e) {
      print('Error fetching admin websites: $e');
      throw Exception('Failed to load admin websites: $e');
    }
  }

  // Get website-specific orders
  static Future<List<Map<String, dynamic>>> getWebsiteOrders(int websiteId) async {
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      // Verify admin access
      final adminWebsites = await getAdminWebsites();
      final hasAccess = adminWebsites.any((website) => 
        website['website_id'] == websiteId
      );

      if (!hasAccess) {
        throw Exception('Access denied: Not an admin for this website');
      }

      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/orders/website/$websiteId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final ordersList = data['orders'] as List? ?? [];
        return ordersList.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Failed to fetch website orders');
      }
    } catch (e) {
      print('Error fetching website orders: $e');
      throw Exception('Failed to load website orders: $e');
    }
  }

  // Get website-specific products
  static Future<List<Map<String, dynamic>>> getWebsiteProducts(int websiteId) async {
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      // Verify admin access
      final adminWebsites = await getAdminWebsites();
      final hasAccess = adminWebsites.any((website) => 
        website['website_id'] == websiteId
      );

      if (!hasAccess) {
        throw Exception('Access denied: Not an admin for this website');
      }

      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/products/website/$websiteId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final productsList = data['products'] as List? ?? [];
        return productsList.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Failed to fetch website products');
      }
    } catch (e) {
      print('Error fetching website products: $e');
      throw Exception('Failed to load website products: $e');
    }
  }
}
