import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._internal();
  factory ImageCacheService() => _instance;
  ImageCacheService._internal();

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
      debugPrint('✅ ImageCacheService initialized successfully');
    } catch (e) {
      debugPrint('❌ Error initializing ImageCacheService: $e');
      // Fallback to basic cache manager
      _cacheManager = DefaultCacheManager();
      _isInitialized = true;
    }
  }

  // Ensure initialization before operations
  void _ensureInitialized() {
    if (!_isInitialized) {
      throw Exception('ImageCacheService not initialized. Call initialize() first.');
    }
  }

  // Get optimized image URL with size parameters
  String getOptimizedImageUrl(String originalUrl, {int? width, int? height}) {
    try {
      if (originalUrl.contains('?')) {
        // Already has parameters, add size optimization
        final separator = originalUrl.contains('&') ? '&' : '?';
        var optimizedUrl = originalUrl;
        if (width != null) optimizedUrl += '${separator}w=$width';
        if (height != null) optimizedUrl += '&h=$height';
        return optimizedUrl;
      } else {
        // Add size parameters
        var params = [];
        if (width != null) params.add('w=$width');
        if (height != null) params.add('h=$height');
        return params.isEmpty ? originalUrl : '$originalUrl?${params.join('&')}';
      }
    } catch (e) {
      debugPrint('Error generating optimized URL: $e');
      return originalUrl; // Fallback to original URL
    }
  }

  // Preload multiple images with error handling
  Future<void> preloadImages(List<String> imageUrls, {int? width, int? height}) async {
    _ensureInitialized();
    
    final futures = imageUrls.take(10).map((url) async {
      try {
        if (url.isNotEmpty && (url.startsWith('http') || url.startsWith('/'))) {
          final optimizedUrl = getOptimizedImageUrl(url, width: width, height: height);
          await _cacheManager.getSingleFile(optimizedUrl);
        }
      } catch (e) {
        debugPrint('Error preloading image: $url - $e');
      }
    });
    
    try {
      await Future.wait(futures);
    } catch (e) {
      debugPrint('Error in preloadImages: $e');
    }
  }

  // Get image with memory caching and proper error handling
  Future<Uint8List?> getImageData(String imageUrl, {int? width, int? height}) async {
    _ensureInitialized();
    
    if (imageUrl.isEmpty) {
      debugPrint('❌ Empty image URL provided');
      return null;
    }
    
    final cacheKey = _generateCacheKey(imageUrl, width, height);
    
    // Check memory cache first
    if (_memoryCache.containsKey(cacheKey)) {
      final timestamp = _cacheTimestamps[cacheKey];
      if (timestamp != null && DateTime.now().difference(timestamp) < _cacheExpiry) {
        return _memoryCache[cacheKey];
      } else {
        // Remove expired cache
        _memoryCache.remove(cacheKey);
        _cacheTimestamps.remove(cacheKey);
        _updateCacheSize();
      }
    }

    try {
      final optimizedUrl = getOptimizedImageUrl(imageUrl, width: width, height: height);
      final file = await _cacheManager.getSingleFile(optimizedUrl).timeout(
        const Duration(seconds: 10),
      );
      
      final bytes = await file.readAsBytes();
      
      // Add to memory cache if not too large
      if (bytes.length < 1024 * 1024) { // 1MB limit per image
        _addToMemoryCache(cacheKey, bytes);
      }
      
      return bytes;
    } catch (e) {
      debugPrint('Error loading image: $imageUrl - $e');
      return null;
    }
  }

  void _addToMemoryCache(String key, Uint8List bytes) {
    try {
      // Remove old items if cache is full
      while (_currentCacheSize + bytes.length > _maxMemoryCacheSize && _memoryCache.isNotEmpty) {
        final oldestKey = _cacheTimestamps.entries
            .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
            .key;
        
        final removedBytes = _memoryCache.remove(oldestKey);
        _cacheTimestamps.remove(oldestKey);
        if (removedBytes != null) {
          _currentCacheSize -= removedBytes.length;
        }
      }
      
      _memoryCache[key] = bytes;
      _cacheTimestamps[key] = DateTime.now();
      _currentCacheSize += bytes.length;
    } catch (e) {
      debugPrint('Error adding to memory cache: $e');
    }
  }

  void _updateCacheSize() {
    _currentCacheSize = 0;
    for (final bytes in _memoryCache.values) {
      _currentCacheSize += bytes.length;
    }
  }

  String _generateCacheKey(String url, int? width, int? height) {
    try {
      final keyData = '$url-${width ?? 'auto'}-${height ?? 'auto'}';
      final bytes = utf8.encode(keyData);
      final digest = sha256.convert(bytes);
      return digest.toString();
    } catch (e) {
      debugPrint('Error generating cache key: $e');
      // Fallback to simple key
      return '${url.hashCode}_${width ?? 0}_${height ?? 0}';
    }
  }

  // Clear cache with error handling
  Future<void> clearCache() async {
    try {
      _ensureInitialized();
      await _cacheManager.emptyCache();
      _memoryCache.clear();
      _cacheTimestamps.clear();
      _currentCacheSize = 0;
      debugPrint('✅ Cache cleared successfully');
    } catch (e) {
      debugPrint('Error clearing cache: $e');
      // Clear memory cache at least
      _memoryCache.clear();
      _cacheTimestamps.clear();
      _currentCacheSize = 0;
    }
  }

  // Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'memoryCacheSize': _currentCacheSize,
      'memoryCacheItems': _memoryCache.length,
      'maxMemoryCacheSize': _maxMemoryCacheSize,
      'isInitialized': _isInitialized,
      'cacheUsagePercentage': _maxMemoryCacheSize > 0 
          ? ((_currentCacheSize / _maxMemoryCacheSize) * 100).toStringAsFixed(2) + '%'
          : '0%',
    };
  }

  // Compress image data with actual implementation
  Future<Uint8List?> compressImage(Uint8List imageBytes, {int quality = 85}) async {
    try {
      // Use flutter_image_compress for actual compression
      final result = await FlutterImageCompress.compressWithList(
        imageBytes,
        quality: quality,
        minWidth: 800,
        minHeight: 600,
      );
      
      if (result.isNotEmpty) {
        debugPrint('✅ Image compressed: ${imageBytes.length} -> ${result.length} bytes');
        return Uint8List.fromList(result);
      }
      
      return null;
    } catch (e) {
      debugPrint('Error compressing image: $e');
      // Fallback: return original bytes
      return imageBytes;
    }
  }

  // Generate thumbnail with actual implementation
  Future<Uint8List?> generateThumbnail(Uint8List imageBytes, {int size = 200}) async {
    try {
      // Use flutter_image_compress for thumbnail generation
      final result = await FlutterImageCompress.compressWithList(
        imageBytes,
        minWidth: size,
        minHeight: size,
        quality: 75,
      );
      
      if (result.isNotEmpty) {
        debugPrint('✅ Thumbnail generated: ${result.length} bytes');
        return Uint8List.fromList(result);
      }
      
      return null;
    } catch (e) {
      debugPrint('Error generating thumbnail: $e');
      // Fallback: return compressed original
      return await compressImage(imageBytes, quality: 60);
    }
  }

  // Check if image is cached
  bool isImageCached(String imageUrl, {int? width, int? height}) {
    try {
      final cacheKey = _generateCacheKey(imageUrl, width, height);
      return _memoryCache.containsKey(cacheKey);
    } catch (e) {
      debugPrint('Error checking if image is cached: $e');
      return false;
    }
  }

  // Remove specific image from cache
  void removeFromCache(String imageUrl, {int? width, int? height}) {
    try {
      final cacheKey = _generateCacheKey(imageUrl, width, height);
      final removedBytes = _memoryCache.remove(cacheKey);
      _cacheTimestamps.remove(cacheKey);
      if (removedBytes != null) {
        _currentCacheSize -= removedBytes.length;
      }
    } catch (e) {
      debugPrint('Error removing from cache: $e');
    }
  }

  // Get memory usage info
  Map<String, dynamic> getMemoryUsage() {
    return {
      'currentSize': _currentCacheSize,
      'maxSize': _maxMemoryCacheSize,
      'itemsCount': _memoryCache.length,
      'usagePercentage': _maxMemoryCacheSize > 0 
          ? ((_currentCacheSize / _maxMemoryCacheSize) * 100).toStringAsFixed(2)
          : '0',
      'availableSpace': _maxMemoryCacheSize - _currentCacheSize,
    };
  }

  // Cleanup expired items
  void cleanupExpiredItems() {
    try {
      final now = DateTime.now();
      final expiredKeys = <String>[];
      
      for (final entry in _cacheTimestamps.entries) {
        if (now.difference(entry.value) > _cacheExpiry) {
          expiredKeys.add(entry.key);
        }
      }
      
      for (final key in expiredKeys) {
        final removedBytes = _memoryCache.remove(key);
        _cacheTimestamps.remove(key);
        if (removedBytes != null) {
          _currentCacheSize -= removedBytes.length;
        }
      }
      
      if (expiredKeys.isNotEmpty) {
        debugPrint('✅ Cleaned up ${expiredKeys.length} expired cache items');
      }
    } catch (e) {
      debugPrint('Error cleaning up expired items: $e');
    }
  }
}

// Extension for easy access
extension ImageCacheExtension on String {
  String toOptimizedUrl({int? width, int? height}) {
    try {
      return ImageCacheService().getOptimizedImageUrl(this, width: width, height: height);
    } catch (e) {
      debugPrint('Error in toOptimizedUrl extension: $e');
      return this; // Fallback to original
    }
  }
}
