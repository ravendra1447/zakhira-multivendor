import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'cdn_service.dart';
import '../config.dart';

class CloudflareImageService {
  static final CloudflareImageService _instance = CloudflareImageService._internal();
  factory CloudflareImageService() => _instance;
  CloudflareImageService._internal();

  // Cloudflare Image Resizing API (if you have the paid feature)
  static const String _cloudflareApiUrl = 'https://api.cloudflare.com/client/v4/accounts';
  static String? _apiToken;
  static String? _accountId;

  // Initialize with Cloudflare credentials
  static void initialize({required String apiToken, required String accountId}) {
    _apiToken = apiToken;
    _accountId = accountId;
  }

  // Get optimized image URL using Cloudflare CDN
  static String getOptimizedImageUrl(
    String originalUrl, {
    int? width,
    int? height,
    int quality = 85,
    String format = 'auto',
    String fit = 'cover',
  }) {
    final cdnService = CDNService();
    return cdnService.getOptimizedImageUrl(
      originalUrl,
      width: width,
      height: height,
      quality: quality,
      format: format,
    );
  }

  // Generate multiple sizes for responsive images
  static Map<String, String> getResponsiveUrls(String originalUrl) {
    final cdnService = CDNService();
    
    return {
      'thumbnail': cdnService.getThumbnailUrl(originalUrl, size: 150),
      'small': cdnService.getOptimizedImageUrl(originalUrl, width: 300, height: 300),
      'medium': cdnService.getMediumUrl(originalUrl),
      'large': cdnService.getOptimizedImageUrl(originalUrl, width: 800, height: 600),
      'xlarge': cdnService.getFullSizeUrl(originalUrl),
    };
  }

  // Progressive image loading URLs
  static List<String> getProgressiveUrls(String originalUrl) {
    final cdnService = CDNService();
    return cdnService.getProgressiveUrls(originalUrl);
  }

  // Upload image to server and return optimized URLs
  static Future<Map<String, dynamic>> uploadImage({
    required File imageFile,
    required String uploadPath,
    Map<String, String>? additionalFields,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${Config.baseNodeApiUrl}/api/upload'),
      );

      // Add image file
      final imageBytes = await imageFile.readAsBytes();
      final multipartFile = http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: imageFile.path.split('/').last,
      );
      request.files.add(multipartFile);

      // Add additional fields
      if (additionalFields != null) {
        request.fields.addAll(additionalFields);
      }

      // Add upload path
      request.fields['upload_path'] = uploadPath;

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          final originalUrl = data['data']['url'] ?? '';
          
          // Generate optimized URLs
          final optimizedUrls = getResponsiveUrls(originalUrl);
          
          return {
            'success': true,
            'message': 'Image uploaded successfully',
            'data': {
              'original_url': originalUrl,
              'optimized_urls': optimizedUrls,
              'file_info': {
                'size': imageBytes.length,
                'name': imageFile.path.split('/').last,
                'type': 'image/${imageFile.path.split('.').last}',
              },
            },
          };
        } else {
          return {
            'success': false,
            'message': data['message'] ?? 'Upload failed',
          };
        }
      } else {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Upload error: $e',
      };
    }
  }

  // Delete image from server and CDN cache
  static Future<Map<String, dynamic>> deleteImage({
    required String imageUrl,
    required String imagePath,
  }) async {
    try {
      // Delete from server
      final response = await http.post(
        Uri.parse('${Config.baseNodeApiUrl}/api/delete-image'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'image_url': imageUrl,
          'image_path': imagePath,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Clear CDN cache
        await _clearCDNCache(imageUrl);
        
        return {
          'success': data['success'] ?? false,
          'message': data['message'] ?? 'Image deleted successfully',
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
        'message': 'Delete error: $e',
      };
    }
  }

  // Clear Cloudflare CDN cache for specific image
  static Future<bool> _clearCDNCache(String imageUrl) async {
    try {
      final cdnService = CDNService();
      return await cdnService.clearImageCache(imageUrl);
    } catch (e) {
      debugPrint('Failed to clear CDN cache: $e');
      return false;
    }
  }

  // Get image info from CDN
  static Future<Map<String, dynamic>> getImageInfo(String imageUrl) async {
    try {
      final response = await http.head(Uri.parse(imageUrl));
      
      return {
        'success': true,
        'data': {
          'content_length': response.contentLength,
          'content_type': response.headers['content-type'],
          'cache_control': response.headers['cache-control'],
          'last_modified': response.headers['last-modified'],
          'etag': response.headers['etag'],
        },
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to get image info: $e',
      };
    }
  }

  // Preload multiple images on CDN
  static Future<void> preloadImages(List<String> imageUrls) async {
    final cdnService = CDNService();
    await cdnService.preloadImages(imageUrls);
  }

  // Check if CDN is available and responsive
  static Future<bool> isCDNAvailable() async {
    final cdnService = CDNService();
    return await cdnService.isCDNAvailable();
  }

  // Get CDN performance statistics
  static Future<Map<String, dynamic>> getCDNStats() async {
    final cdnService = CDNService();
    return await cdnService.getCDNStats();
  }

  // Adaptive image URL based on network conditions
  static String getAdaptiveImageUrl(
    String originalUrl, {
    bool isSlowNetwork = false,
    bool isDataSaver = false,
    bool isWiFi = false,
  }) {
    final cdnService = CDNService();
    return cdnService.getAdaptiveImageUrl(
      originalUrl,
      isSlowNetwork: isSlowNetwork,
      isDataSaver: isDataSaver,
    );
  }

  // Get best format for current platform
  static String getBestFormatForPlatform() {
    final cdnService = CDNService();
    return cdnService.getBestFormatForDevice();
  }

  // Validate image URL format
  static bool isValidImageUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  // Extract image ID from URL
  static String? extractImageId(String imageUrl) {
    try {
      final uri = Uri.parse(imageUrl);
      final pathSegments = uri.pathSegments;
      
      // Look for common patterns
      for (int i = 0; i < pathSegments.length; i++) {
        final segment = pathSegments[i];
        if (segment.contains('uploads') && i + 1 < pathSegments.length) {
          return pathSegments[i + 1];
        }
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }
}

// Extension for easy Cloudflare image operations
extension CloudflareImageExtension on String {
  String toCloudflareUrl({int? width, int? height}) {
    return CloudflareImageService.getOptimizedImageUrl(
      this,
      width: width,
      height: height,
    );
  }
  
  Map<String, String> toResponsiveUrls() {
    return CloudflareImageService.getResponsiveUrls(this);
  }
  
  String toThumbnailUrl({int size = 200}) {
    return CloudflareImageService.getOptimizedImageUrl(
      this,
      width: size,
      height: size,
    );
  }
  
  bool isValidImageUrl() {
    return CloudflareImageService.isValidImageUrl(this);
  }
}
