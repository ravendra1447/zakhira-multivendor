import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

class CDNService {
  static final CDNService _instance = CDNService._internal();
  factory CDNService() => _instance;
  CDNService._internal();

  late BaseCacheManager _cacheManager;
  final Map<String, Uint8List> _memoryCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const int _maxMemoryCacheSize = 50 * 1024 * 1024; // 50MB
  static const Duration _cacheExpiry = Duration(hours: 24);
  int _currentCacheSize = 0;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final cacheDir = await getTemporaryDirectory();
      _cacheManager = DefaultCacheManager();
      _isInitialized = true;
      debugPrint('✅ CDNService initialized successfully');
    } catch (e) {
      debugPrint('❌ Error initializing CDNService: $e');
      // Fallback to basic cache manager
      _cacheManager = DefaultCacheManager();
      _isInitialized = true;
    }
  }

  // CDN Configuration
  static const String _cdnBaseUrl = 'https://bangkokmart.in';
  static const String _uploadsPath = '/uploads';
  static const String _apiUploadsPath = '/api/uploads';
  
  // Cloudflare-specific optimizations
  static const Map<String, String> _cdnParams = {
    'format': 'auto',     // Auto-convert to WebP/AVIF
    'quality': '85',      // Compress to 85% quality
    'fit': 'cover',       // Smart cropping
    'width': '800',       // Default width
    'height': '600',      // Default height
  };

  // Get optimized CDN URL
  String getOptimizedImageUrl(String originalUrl, {
    int? width,
    int? height,
    int quality = 85,
    String format = 'auto',
    bool enableCompression = true,
  }) {
    if (originalUrl.startsWith('http')) {
      // Already a full URL, add CDN parameters
      return _addCDNParameters(originalUrl, width, height, quality, format, enableCompression);
    } else {
      // Relative path, construct full CDN URL
      String baseUrl = _cdnBaseUrl;
      if (originalUrl.startsWith('/api/uploads')) {
        baseUrl += originalUrl;
      } else if (originalUrl.startsWith('uploads/')) {
        baseUrl += '/$originalUrl';
      } else {
        baseUrl += '$_apiUploadsPath/$originalUrl';
      }
      
      return _addCDNParameters(baseUrl, width, height, quality, format, enableCompression);
    }
  }

  String _addCDNParameters(
    String url,
    int? width,
    int? height,
    int quality,
    String format,
    bool enableCompression,
  ) {
    if (!enableCompression) return url;

    final uri = Uri.parse(url);
    final Map<String, String> params = Map.from(uri.queryParameters);
    
    // Add Cloudflare Image Resizing parameters
    if (width != null) params['width'] = width.toString();
    if (height != null) params['height'] = height.toString();
    params['quality'] = quality.toString();
    params['format'] = format;
    
    // Add Cloudflare-specific optimizations
    params['fit'] = 'cover';
    params['gravity'] = 'auto';  // Smart focal point detection
    
    return uri.replace(queryParameters: params).toString();
  }

  // Get thumbnail URL for grid views
  String getThumbnailUrl(String originalUrl, {int size = 200}) {
    return getOptimizedImageUrl(
      originalUrl,
      width: size,
      height: size,
      quality: 75, // Lower quality for thumbnails
      format: 'auto',
    );
  }

  // Get medium-sized URL for product cards
  String getMediumUrl(String originalUrl, {int width = 400, int height = 300}) {
    return getOptimizedImageUrl(
      originalUrl,
      width: width,
      height: height,
      quality: 80,
      format: 'auto',
    );
  }

  // Get full-size URL for detail views
  String getFullSizeUrl(String originalUrl) {
    return getOptimizedImageUrl(
      originalUrl,
      width: 1200,
      height: 900,
      quality: 90,
      format: 'auto',
    );
  }

  // Get WebP-specific URL for better compression
  String getWebPUrl(String originalUrl, {int? width, int? height}) {
    return getOptimizedImageUrl(
      originalUrl,
      width: width,
      height: height,
      quality: 85,
      format: 'webp',
    );
  }

  // Get AVIF URL for modern browsers (best compression)
  String getAVIFUrl(String originalUrl, {int? width, int? height}) {
    return getOptimizedImageUrl(
      originalUrl,
      width: width,
      height: height,
      quality: 85,
      format: 'avif',
    );
  }

  // Progressive image loading URLs
  List<String> getProgressiveUrls(String originalUrl) {
    return [
      getThumbnailUrl(originalUrl, size: 50),   // Tiny preview
      getThumbnailUrl(originalUrl, size: 200),  // Medium thumbnail
      getMediumUrl(originalUrl),                 // Full card size
      getFullSizeUrl(originalUrl),               // Full detail size
    ];
  }

  // Check if CDN is available
  Future<bool> isCDNAvailable() async {
    try {
      final response = await http.head(
        Uri.parse('$_cdnBaseUrl/health'),
      ).timeout(const Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('CDN availability check failed: $e');
      return false;
    }
  }

  // Get CDN statistics
  Future<Map<String, dynamic>> getCDNStats() async {
    try {
      final response = await http.get(
        Uri.parse('$_cdnBaseUrl/api/cdn-stats'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      debugPrint('Failed to get CDN stats: $e');
    }
    
    return {
      'status': 'unavailable',
      'cacheHitRate': 0,
      'bandwidthSaved': 0,
      'requestsServed': 0,
    };
  }

  // Clear CDN cache for specific image
  Future<bool> clearImageCache(String imageUrl) async {
    try {
      final response = await http.post(
        Uri.parse('$_cdnBaseUrl/api/cdn/purge'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'urls': [imageUrl]}),
      ).timeout(const Duration(seconds: 10));
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Failed to clear CDN cache: $e');
      return false;
    }
  }

  // Preload images on CDN
  Future<void> preloadImages(List<String> imageUrls) async {
    final futures = imageUrls.take(10).map((url) async {
      try {
        final optimizedUrl = getMediumUrl(url);
        await http.head(Uri.parse(optimizedUrl)).timeout(const Duration(seconds: 3));
      } catch (e) {
        debugPrint('Failed to preload image: $url - $e');
      }
    });
    
    await Future.wait(futures);
  }

  // Get best format based on device capabilities
  String getBestFormatForDevice() {
    if (kIsWeb) {
      return 'auto'; // Let browser decide
    }
    
    // For mobile, prefer WebP for better compression
    return 'webp';
  }

  // Adaptive image URL based on network conditions
  String getAdaptiveImageUrl(
    String originalUrl, {
    bool isSlowNetwork = false,
    bool isDataSaver = false,
  }) {
    int quality = 85;
    String format = getBestFormatForDevice();
    
    if (isSlowNetwork) {
      quality = 60; // Lower quality for slow networks
    }
    
    if (isDataSaver) {
      quality = 50; // Even lower for data saver mode
      format = 'webp'; // Force WebP for maximum compression
    }
    
    return getOptimizedImageUrl(
      originalUrl,
      quality: quality,
      format: format,
    );
  }
}

// Extension for easy CDN URL generation
extension CDNUrlExtension on String {
  String toCDNUrl({int? width, int? height}) {
    return CDNService().getOptimizedImageUrl(this, width: width, height: height);
  }
  
  String toThumbnailUrl({int size = 200}) {
    return CDNService().getThumbnailUrl(this, size: size);
  }
  
  String toMediumUrl({int width = 400, int height = 300}) {
    return CDNService().getMediumUrl(this, width: width, height: height);
  }
  
  String toFullSizeUrl() {
    return CDNService().getFullSizeUrl(this);
  }
  
  String toWebPUrl({int? width, int? height}) {
    return CDNService().getWebPUrl(this, width: width, height: height);
  }
}
