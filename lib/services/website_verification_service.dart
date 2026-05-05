import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class WebsiteVerificationService {
  static const String baseUrl = Config.apiBaseUrl;

  // Verify and link website
  static Future<Map<String, dynamic>> verifyAndLinkWebsite({
    required String domain,
    required int userId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/verify-app'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'domain': domain,
          'user_id': userId,
        }),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success']) {
        return {
          'success': true,
          'data': responseData['data'],
          'message': responseData['message'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Verification failed',
          'requires_admin': responseData['requires_admin'] ?? false,
          'admin_last4': responseData['admin_last4'] ?? '',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Check website linking status
  static Future<Map<String, dynamic>> checkWebsiteStatus({
    required int userId,
    required String domain,
  }) async {
    try {
      final cleanDomain = domain
          .replaceFirst(RegExp(r'^https?://'), '')
          .replaceFirst(RegExp(r'^www\.'), '')
          .toLowerCase();

      final response = await http.get(
        Uri.parse('$baseUrl/api/status/$userId/$cleanDomain'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success']) {
        return {
          'success': true,
          'linked': responseData['linked'] ?? false,
          'data': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Status check failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Get user's linked websites
  static Future<Map<String, dynamic>> getUserWebsites(int userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/websites/user/$userId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success']) {
        return {
          'success': true,
          'websites': responseData['data'] ?? [],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to fetch websites',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Get available websites
  static Future<Map<String, dynamic>> getAvailableWebsites() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/websites/available'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        return responseData;
      } else {
        throw Exception('Failed to load available websites: ${response.statusCode}');
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Unlink website
  static Future<Map<String, dynamic>> unlinkWebsite({
    required String domain,
    required int userId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/unlink-website'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'domain': domain,
          'user_id': userId,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        return responseData;
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to unlink website');
      }
    } catch (e) {
      throw Exception('Error unlinking website: $e');
    }
  }
}
