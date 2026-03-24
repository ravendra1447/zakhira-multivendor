import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../config.dart';

class BannerService {
  static Future<List<dynamic>> getActiveBanners() async {
    try {
      // Prioritize live server since it's working
      final urls = [
        'https://node-api.bangkokmart.in/banners/active',  // Live server (working)
        'https://node-api.bangkokmart.in/api/banners/active', // Live server (backup)
        'http://10.0.2.2:3000/banners/active',       // Android emulator
        'http://10.0.2.2:3000/api/banners/active',    // Android emulator
        'http://localhost:3000/banners/active',        // iOS simulator
        'http://localhost:3000/api/banners/active',     // iOS simulator
      ];
      
      for (String url in urls) {
        try {
          print('🌐 Trying: $url');
          
          // Add timeout to prevent infinite loading
          final response = await http.get(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
          ).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              print('⏰ Timeout for $url');
              throw TimeoutException('Request timeout', const Duration(seconds: 5));
            },
          );

          print('🌐 Response from $url: ${response.statusCode}');
          
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data['success'] == true) {
              print('✅ Success with $url');
              print('🎯 Banners found: ${data['data'].length}');
              return data['data'] as List<dynamic>;
            }
          }
        } catch (e) {
          print('❌ Failed with $url: $e');
          // Continue to next URL
        }
      }
      
      print('🎯 All URLs failed, returning empty to trigger fallback');
      return [];
    } catch (e) {
      print('❌ Error fetching banners: $e');
      return [];
    }
  }

  static Future<List<dynamic>> getAllBanners() async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/banners'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'] as List<dynamic>;
        }
      }
      return [];
    } catch (e) {
      print('Error fetching all banners: $e');
      return [];
    }
  }

  static Future<bool> createBanner({
    required String title,
    String? subtitle,
    String? description,
    required String imageUrl,
    String? backgroundColor,
    String? textColor,
    String? buttonText,
    String? buttonUrl,
    int? displayOrder,
    bool? isActive,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${Config.baseNodeApiUrl}/banners'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': title,
          'subtitle': subtitle,
          'description': description,
          'image_url': imageUrl,
          'background_color': backgroundColor ?? '#FF6B35',
          'text_color': textColor ?? '#FFFFFF',
          'button_text': buttonText,
          'button_url': buttonUrl,
          'display_order': displayOrder ?? 0,
          'is_active': isActive ?? true,
          'start_date': startDate,
          'end_date': endDate,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('Error creating banner: $e');
      return false;
    }
  }

  static Future<bool> updateBanner({
    required int id,
    required String title,
    String? subtitle,
    String? description,
    required String imageUrl,
    String? backgroundColor,
    String? textColor,
    String? buttonText,
    String? buttonUrl,
    int? displayOrder,
    bool? isActive,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('${Config.baseNodeApiUrl}/banners/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': title,
          'subtitle': subtitle,
          'description': description,
          'image_url': imageUrl,
          'background_color': backgroundColor ?? '#FF6B35',
          'text_color': textColor ?? '#FFFFFF',
          'button_text': buttonText,
          'button_url': buttonUrl,
          'display_order': displayOrder ?? 0,
          'is_active': isActive ?? true,
          'start_date': startDate,
          'end_date': endDate,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('Error updating banner: $e');
      return false;
    }
  }

  static Future<bool> deleteBanner(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('${Config.baseNodeApiUrl}/banners/$id'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('Error deleting banner: $e');
      return false;
    }
  }
}
