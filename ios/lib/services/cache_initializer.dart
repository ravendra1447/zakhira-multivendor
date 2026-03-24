import 'package:flutter/foundation.dart';
import 'image_cache_service.dart';
import 'cdn_service.dart';
import 'cloudflare_image_service.dart';

class CacheInitializer {
  static bool _isInitialized = false;

  // Initialize all cache services
  static Future<void> initializeAll() async {
    if (_isInitialized) return;

    try {
      debugPrint('🚀 Initializing cache services...');

      // Initialize Image Cache Service
      await ImageCacheService().initialize();
      debugPrint('✅ ImageCacheService initialized');

      // Initialize CDN Service (if needed)
      await CDNService().initialize();
      debugPrint('✅ CDNService initialized');

      // Check CDN availability
      final cdnAvailable = await CDNService().isCDNAvailable();
      debugPrint('🌐 CDN Available: $cdnAvailable');

      // Initialize Cloudflare Image Service
      // Note: This doesn't need initialization but we can check availability
      final cloudflareAvailable = await CloudflareImageService.isCDNAvailable();
      debugPrint('☁️ Cloudflare CDN Available: $cloudflareAvailable');

      _isInitialized = true;
      debugPrint('🎉 All cache services initialized successfully!');

    } catch (e) {
      debugPrint('❌ Error initializing cache services: $e');
      // Don't rethrow, allow app to continue with fallbacks
    }
  }

  // Get initialization status
  static bool get isInitialized => _isInitialized;

  // Reset initialization (for testing)
  static void reset() {
    _isInitialized = false;
  }

  // Get cache statistics
  static Future<Map<String, dynamic>> getAllCacheStats() async {
    try {
      final imageCacheStats = ImageCacheService().getCacheStats();
      final cdnStats = await CDNService().getCDNStats();

      return {
        'imageCache': imageCacheStats,
        'cdn': cdnStats,
        'initialized': _isInitialized,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      debugPrint('Error getting cache stats: $e');
      return {
        'error': e.toString(),
        'initialized': _isInitialized,
      };
    }
  }

  // Clear all caches
  static Future<void> clearAllCaches() async {
    try {
      debugPrint('🧹 Clearing all caches...');

      // Clear image cache
      await ImageCacheService().clearCache();
      debugPrint('✅ Image cache cleared');

      // Clear CDN cache (if available)
      final cdnAvailable = await CDNService().isCDNAvailable();
      if (cdnAvailable) {
        // Note: CDN cache clearing would require API implementation
        debugPrint('ℹ️ CDN cache clearing requires server implementation');
      }

      debugPrint('🎉 All caches cleared successfully!');
    } catch (e) {
      debugPrint('❌ Error clearing caches: $e');
    }
  }

  // Cleanup expired items
  static void cleanupExpiredItems() {
    try {
      debugPrint('🧹 Cleaning up expired cache items...');

      // Clean up image cache expired items
      final imageCacheService = ImageCacheService();
      imageCacheService.cleanupExpiredItems();

      debugPrint('✅ Expired items cleanup completed');
    } catch (e) {
      debugPrint('❌ Error cleaning up expired items: $e');
    }
  }

  // Get memory usage summary
  static Map<String, dynamic> getMemoryUsageSummary() {
    try {
      final imageCacheService = ImageCacheService();
      final memoryUsage = imageCacheService.getMemoryUsage();

      return {
        'imageCache': memoryUsage,
        'totalMemoryUsage': memoryUsage['currentSize'],
        'totalMemoryLimit': memoryUsage['maxSize'],
        'usagePercentage': memoryUsage['usagePercentage'],
        'availableSpace': memoryUsage['availableSpace'],
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      debugPrint('Error getting memory usage: $e');
      return {
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  // Health check for all cache services
  static Future<Map<String, dynamic>> performHealthCheck() async {
    final results = <String, dynamic>{};

    try {
      // Check Image Cache Service
      final imageCacheService = ImageCacheService();
      final imageStats = imageCacheService.getCacheStats();
      results['imageCache'] = {
        'status': imageStats['isInitialized'] ? 'healthy' : 'not_initialized',
        'stats': imageStats,
      };

      // Check CDN Service
      final cdnAvailable = await CDNService().isCDNAvailable();
      results['cdn'] = {
        'status': cdnAvailable ? 'healthy' : 'unavailable',
        'available': cdnAvailable,
      };

      // Check Cloudflare CDN
      final cloudflareAvailable = await CloudflareImageService.isCDNAvailable();
      results['cloudflare'] = {
        'status': cloudflareAvailable ? 'healthy' : 'unavailable',
        'available': cloudflareAvailable,
      };

      // Overall status
      final overallHealthy = imageStats['isInitialized'] == true && cdnAvailable;
      results['overall'] = {
        'status': overallHealthy ? 'healthy' : 'degraded',
        'initialized': _isInitialized,
      };

    } catch (e) {
      debugPrint('Error in health check: $e');
      results['error'] = e.toString();
      results['overall'] = {'status': 'error'};
    }

    return results;
  }
}
