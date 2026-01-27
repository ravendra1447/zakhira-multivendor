import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../config.dart';
import 'dart:convert';


class ProfileImageService {
  // Edit profile image API
  static Future<Map<String, dynamic>> editProfileImage({
    required int userId,
    required String imageId,
    required String newImageUrl,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${Config.baseNodeApiUrl}/api/profile/edit_image'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'user_id': userId,
          'image_id': imageId,
          'new_image_url': newImageUrl,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['success'] ?? false,
          'message': data['message'] ?? 'Image updated successfully',
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }

  // Delete profile image API
  static Future<Map<String, dynamic>> deleteProfileImage({
    required int userId,
    required String imageId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${Config.baseNodeApiUrl}/api/profile/delete_image'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'user_id': userId,
          'image_id': imageId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['success'] ?? false,
          'message': data['message'] ?? 'Image deleted successfully',
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }

  // Update product variation image API
  static Future<Map<String, dynamic>> editProductImage({
    required int userId,
    required int productId,
    required String newImageUrl,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${Config.baseNodeApiUrl}/api/product/edit_image'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'user_id': userId,
          'product_id': productId,
          'new_image_url': newImageUrl,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['success'] ?? false,
          'message': data['message'] ?? 'Product image updated successfully',
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }

  // Delete product variation image API
  static Future<Map<String, dynamic>> deleteProductImage({
    required int userId,
    required int productId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${Config.baseNodeApiUrl}/api/product/delete_image'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'user_id': userId,
          'product_id': productId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['success'] ?? false,
          'message': data['message'] ?? 'Product image deleted successfully',
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }
}
