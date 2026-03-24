// CDN Configuration for Cloudflare Integration
class CDNConfig {
  // Cloudflare CDN Settings
  static const String cdnBaseUrl = 'https://bangkokmart.in';
  static const String uploadsPath = '/uploads';
  static const String apiUploadsPath = '/api/uploads';
  
  // Cloudflare Image Resizing Parameters
  static const Map<String, String> defaultParams = {
    'format': 'auto',     // Auto-convert to WebP/AVIF
    'quality': '85',      // Compress to 85% quality
    'fit': 'cover',       // Smart cropping
  };
  
  // Image size presets for different use cases
  static const Map<String, Map<String, int>> sizePresets = {
    'thumbnail': {'width': 200, 'height': 200},
    'card': {'width': 400, 'height': 300},
    'detail': {'width': 800, 'height': 600},
    'full': {'width': 1200, 'height': 900},
  };
  
  // Quality settings for different network conditions
  static const Map<String, int> qualitySettings = {
    'slow': 60,      // Slow network
    'normal': 85,    // Normal network
    'fast': 90,      // Fast network
    'data_saver': 50, // Data saver mode
  };
  
  // Format preferences
  static const Map<String, String> formatPreferences = {
    'webp': 'webp',     // WebP format
    'avif': 'avif',     // AVIF format (best compression)
    'auto': 'auto',     // Auto-detect best format
    'jpg': 'jpg',       // Fallback JPEG
  };
}

// CDN URL Builder Helper
class CDNUrlBuilder {
  static String buildUrl(
    String originalUrl, {
    int? width,
    int? height,
    int? quality,
    String? format,
    String? fit,
  }) {
    if (originalUrl.startsWith('http')) {
      return _addParameters(originalUrl, width, height, quality, format, fit);
    } else {
      String baseUrl = CDNConfig.cdnBaseUrl;
      if (originalUrl.startsWith('/api/uploads')) {
        baseUrl += originalUrl;
      } else if (originalUrl.startsWith('uploads/')) {
        baseUrl += '/$originalUrl';
      } else {
        baseUrl += '${CDNConfig.apiUploadsPath}/$originalUrl';
      }
      return _addParameters(baseUrl, width, height, quality, format, fit);
    }
  }
  
  static String _addParameters(
    String url,
    int? width,
    int? height,
    int? quality,
    String? format,
    String? fit,
  ) {
    final uri = Uri.parse(url);
    final Map<String, String> params = Map.from(uri.queryParameters);
    
    if (width != null) params['width'] = width.toString();
    if (height != null) params['height'] = height.toString();
    if (quality != null) params['quality'] = quality.toString();
    if (format != null) params['format'] = format;
    if (fit != null) params['fit'] = fit;
    
    // Add Cloudflare-specific optimizations
    params['gravity'] = 'auto';  // Smart focal point detection
    
    return uri.replace(queryParameters: params).toString();
  }
}
