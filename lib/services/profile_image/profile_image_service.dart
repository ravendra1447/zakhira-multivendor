import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../config.dart';
import '../cloudflare_image_service.dart';
import 'dart:io';

class ProfileImageService {
  // Edit profile image API with CDN optimization
  static Future<Map<String, dynamic>> editProfileImage({
    required int userId,
    required String imageId,
    required String newImageUrl,
  }) async {
    try {
      // Validate image URL
      if (!CloudflareImageService.isValidImageUrl(newImageUrl)) {
        return {
          'success': false,
          'message': 'Invalid image URL format',
        };
      }

      // If it's a local file, upload it first
      String finalImageUrl = newImageUrl;
      if (newImageUrl.startsWith('/') || !newImageUrl.startsWith('http')) {
        final uploadResult = await CloudflareImageService.uploadImage(
          imageFile: File(newImageUrl),
          uploadPath: 'profile_images',
          additionalFields: {
            'user_id': userId.toString(),
            'image_id': imageId,
          },
        );
        
        if (uploadResult['success'] == true) {
          finalImageUrl = uploadResult['data']['original_url'];
        } else {
          return uploadResult;
        }
      }

      final response = await http.post(
        Uri.parse('${Config.baseNodeApiUrl}/api/profile/edit_image'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'user_id': userId,
          'image_id': imageId,
          'new_image_url': finalImageUrl,
          'cdn_optimized': true,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Clear CDN cache for old image if exists
        if (data['data']?['old_image_url'] != null) {
          await CloudflareImageService.deleteImage(
            imageUrl: data['data']['old_image_url'],
            imagePath: 'profile_images/$imageId',
          );
        }
        
        return {
          'success': data['success'] ?? false,
          'message': data['message'] ?? 'Image updated successfully',
          'data': {
            ...?data['data'],
            'optimized_urls': CloudflareImageService.getResponsiveUrls(finalImageUrl),
          },
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

  // Delete profile image API with CDN cleanup
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
        
        // Clear CDN cache if image URL exists
        if (data['data']?['image_url'] != null) {
          await CloudflareImageService.deleteImage(
            imageUrl: data['data']['image_url'],
            imagePath: 'profile_images/$imageId',
          );
        }
        
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

  // Update product variation image API with CDN optimization
  static Future<Map<String, dynamic>> editProductImage({
    required int userId,
    required int productId,
    required String newImageUrl,
  }) async {
    try {
      // Validate image URL
      if (!CloudflareImageService.isValidImageUrl(newImageUrl)) {
        return {
          'success': false,
          'message': 'Invalid image URL format',
        };
      }

      // If it's a local file, upload it first
      String finalImageUrl = newImageUrl;
      if (newImageUrl.startsWith('/') || !newImageUrl.startsWith('http')) {
        final uploadResult = await CloudflareImageService.uploadImage(
          imageFile: File(newImageUrl),
          uploadPath: 'products',
          additionalFields: {
            'user_id': userId.toString(),
            'product_id': productId.toString(),
          },
        );
        
        if (uploadResult['success'] == true) {
          finalImageUrl = uploadResult['data']['original_url'];
        } else {
          return uploadResult;
        }
      }

      final response = await http.post(
        Uri.parse('${Config.baseNodeApiUrl}/api/product/edit_image'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'user_id': userId,
          'product_id': productId,
          'new_image_url': finalImageUrl,
          'cdn_optimized': true,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Clear CDN cache for old image if exists
        if (data['data']?['old_image_url'] != null) {
          await CloudflareImageService.deleteImage(
            imageUrl: data['data']['old_image_url'],
            imagePath: 'products/$productId',
          );
        }
        
        return {
          'success': data['success'] ?? false,
          'message': data['message'] ?? 'Product image updated successfully',
          'data': {
            ...?data['data'],
            'optimized_urls': CloudflareImageService.getResponsiveUrls(finalImageUrl),
          },
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

  // Delete product variation image API with CDN cleanup
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
        
        // Clear CDN cache if image URL exists
        if (data['data']?['image_url'] != null) {
          await CloudflareImageService.deleteImage(
            imageUrl: data['data']['image_url'],
            imagePath: 'products/$productId',
          );
        }
        
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

  // Upload multiple images with CDN optimization
  static Future<Map<String, dynamic>> uploadMultipleImages({
    required List<File> imageFiles,
    required String uploadPath,
    Map<String, String>? additionalFields,
  }) async {
    try {
      final results = [];
      
      for (int i = 0; i < imageFiles.length; i++) {
        final file = imageFiles[i];
        final uploadResult = await CloudflareImageService.uploadImage(
          imageFile: file,
          uploadPath: '$uploadPath/image_$i',
          additionalFields: additionalFields,
        );
        
        results.add(uploadResult);
      }
      
      final successCount = results.where((r) => r['success'] == true).length;
      
      return {
        'success': successCount > 0,
        'message': '$successCount/${imageFiles.length} images uploaded successfully',
        'data': {
          'results': results,
          'success_count': successCount,
          'total_count': imageFiles.length,
        },
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Batch upload error: $e',
      };
    }
  }

  // Get optimized image URL for display
  static String getOptimizedImageUrl(
    String imageUrl, {
    int? width,
    int? height,
    String size = 'medium', // thumbnail, small, medium, large, xlarge
  }) {
    return CloudflareImageService.getOptimizedImageUrl(
      imageUrl,
      width: width,
      height: height,
    );
  }

  // Preload images for better performance
  static Future<void> preloadImages(List<String> imageUrls) async {
    await CloudflareImageService.preloadImages(imageUrls);
  }
}
