import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/cdn_service.dart';
import '../services/cloudflare_image_service.dart';

// Cloudflare-Optimized Image Widget with Fast Loading
class CloudflareOptimizedImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final String? placeholder;
  final Widget? customPlaceholder;
  final Widget? customErrorWidget;
  final bool enableFadeIn;
  final Duration fadeInDuration;
  final bool enablePreloading;
  final String sizeCategory; // thumbnail, small, medium, large, xlarge
  final bool useProgressiveLoading;

  const CloudflareOptimizedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.customPlaceholder,
    this.customErrorWidget,
    this.enableFadeIn = true,
    this.fadeInDuration = const Duration(milliseconds: 200),
    this.enablePreloading = true,
    this.sizeCategory = 'medium',
    this.useProgressiveLoading = true,
  });

  @override
  State<CloudflareOptimizedImage> createState() => _CloudflareOptimizedImageState();
}

class _CloudflareOptimizedImageState extends State<CloudflareOptimizedImage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  String? _optimizedUrl;
  bool _isLoading = true;
  String? _currentLoadingUrl;

  @override
  void initState() {
    super.initState();
    if (widget.enableFadeIn) {
      _animationController = AnimationController(
        duration: widget.fadeInDuration,
        vsync: this,
      );
      _fadeAnimation = CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      );
    }

    _loadOptimizedImage();
    
    if (widget.enablePreloading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _preloadNearbyImages();
      });
    }
  }

  @override
  void dispose() {
    if (widget.enableFadeIn) {
      _animationController.dispose();
    }
    super.dispose();
  }

  Future<void> _loadOptimizedImage() async {
    try {
      // Initialize CDN service if not already done
      final cdnService = CDNService();
      await cdnService.initialize();
      
      // Get optimized URL based on size category using CDN service directly
      String optimizedUrl;
      switch (widget.sizeCategory) {
        case 'thumbnail':
          optimizedUrl = cdnService.getThumbnailUrl(widget.imageUrl, size: 150);
          break;
        case 'small':
          optimizedUrl = cdnService.getOptimizedImageUrl(widget.imageUrl, width: 300, height: 300);
          break;
        case 'medium':
          optimizedUrl = cdnService.getMediumUrl(widget.imageUrl);
          break;
        case 'large':
          optimizedUrl = cdnService.getOptimizedImageUrl(widget.imageUrl, width: 800, height: 600);
          break;
        case 'xlarge':
          optimizedUrl = cdnService.getOptimizedImageUrl(widget.imageUrl, width: 1200, height: 900);
          break;
        default:
          optimizedUrl = cdnService.getMediumUrl(widget.imageUrl);
      }
      
      _optimizedUrl = optimizedUrl;
      
      if (widget.useProgressiveLoading) {
        _currentLoadingUrl = cdnService.getThumbnailUrl(widget.imageUrl, size: 150); // Load thumbnail first
      } else {
        _currentLoadingUrl = _optimizedUrl;
      }
      
      setState(() {
        _isLoading = false;
      });

      // If progressive loading, switch to full image after thumbnail loads
      if (widget.useProgressiveLoading && _currentLoadingUrl != _optimizedUrl) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            setState(() {
              _currentLoadingUrl = _optimizedUrl;
            });
          }
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading optimized image: $e');
      debugPrint('❌ Image URL: ${widget.imageUrl}');
      debugPrint('❌ Size category: ${widget.sizeCategory}');
      // Fallback to original URL
      setState(() {
        _optimizedUrl = widget.imageUrl;
        _currentLoadingUrl = widget.imageUrl;
        _isLoading = false;
      });
    }
  }

  void _preloadNearbyImages() {
    // Preload using CDN service for better performance
    final cdnService = CDNService();
    final urlsToPreload = [
      cdnService.getThumbnailUrl(widget.imageUrl, size: 150),
      cdnService.getOptimizedImageUrl(widget.imageUrl, width: 300, height: 300),
      cdnService.getMediumUrl(widget.imageUrl),
    ];
    
    for (final url in urlsToPreload) {
      if (url != null && url.isNotEmpty) {
        precacheImage(NetworkImage(url), context);
      }
    }
  }

  Widget _buildPlaceholder() {
    if (widget.customPlaceholder != null) {
      return widget.customPlaceholder!;
    }

    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[200],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_outlined,
              color: Colors.grey[400],
              size: (widget.width ?? 40) * 0.4,
            ),
            if (widget.placeholder != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.placeholder!,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    if (widget.customErrorWidget != null) {
      return widget.customErrorWidget!;
    }

    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[300],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_outlined,
            color: Colors.grey[500],
            size: (widget.width ?? 40) * 0.4,
          ),
          const SizedBox(height: 8),
          Text(
            'Failed to load',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkImage() {
    // Use original URL directly for fastest loading
    String optimizedUrl = widget.imageUrl;
    
    // Only convert IP to domain, keep original protocol
    if (optimizedUrl.contains('184.168.126.71:3000')) {
      optimizedUrl = optimizedUrl.replaceAll('184.168.126.71:3000', 'bangkokmart.in');
    }
    
    // Debug: Print the URL
    debugPrint('🌩️ Fast loading image: $optimizedUrl');
    
    return Image.network(
      optimizedUrl,
      width: widget.width,
      height: widget.height,
      fit: BoxFit.cover,
      // Remove all processing for fastest load
      cacheWidth: _getMemCacheWidth(),
      cacheHeight: _getMemCacheHeight(),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: widget.width,
          height: widget.height,
          color: Colors.grey[200],
          child: Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                  : null,
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).primaryColor,
              ),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        debugPrint('❌ Cloudflare image load error: $optimizedUrl - $error');
        
        // Try fallback to original URL
        if (optimizedUrl != widget.imageUrl) {
          debugPrint('🔄 Trying original URL: ${widget.imageUrl}');
          return Image.network(
            widget.imageUrl,
            width: widget.width,
            height: widget.height,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('❌ Original also failed: ${widget.imageUrl} - $error');
              return _buildErrorWidget();
            },
          );
        }
        
        return _buildErrorWidget();
      },
      frameBuilder: widget.enableFadeIn
          ? (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return FadeTransition(
                opacity: _fadeAnimation,
                child: child,
              );
            }
          : (context, child, frame, wasSynchronouslyLoaded) => child,
    );
  }

  String _getCacheKey() {
    return widget.imageUrl;
  }

  int _getMemCacheWidth() {
    switch (widget.sizeCategory) {
      case 'thumbnail':
        return 150;
      case 'small':
        return 300;
      case 'medium':
        return 400;
      case 'large':
        return 600;
      case 'xlarge':
        return 800;
      default:
        return 400;
    }
  }

  int _getMemCacheHeight() {
    switch (widget.sizeCategory) {
      case 'thumbnail':
        return 150;
      case 'small':
        return 300;
      case 'medium':
        return 300;
      case 'large':
        return 450;
      case 'xlarge':
        return 600;
      default:
        return 300;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildPlaceholder();
    }

    return _buildNetworkImage();
  }
}

// Specialized Cloudflare-optimized product card image
class CloudflareProductImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final int imageCount;
  final bool showImageCount;

  const CloudflareProductImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.onTap,
    this.imageCount = 1,
    this.showImageCount = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          CloudflareOptimizedImage(
            imageUrl: imageUrl,
            width: width,
            height: height,
            sizeCategory: 'medium',
            useProgressiveLoading: true,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: 'Product',
          ),
          if (showImageCount && imageCount > 1)
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.photo_library,
                      color: Colors.white,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$imageCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Cloudflare-optimized profile grid image
class CloudflareProfileImage extends StatelessWidget {
  final String imageUrl;
  final double size;
  final VoidCallback? onTap;

  const CloudflareProfileImage({
    super.key,
    required this.imageUrl,
    this.size = 120,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CloudflareOptimizedImage(
        imageUrl: imageUrl,
        width: size,
        height: size,
        sizeCategory: 'small',
        useProgressiveLoading: true,
        fadeInDuration: const Duration(milliseconds: 100),
        placeholder: 'Photo',
      ),
    );
  }
}

// Cloudflare-optimized marketplace hero image
class CloudflareHeroImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  const CloudflareHeroImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CloudflareOptimizedImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        sizeCategory: 'large',
        useProgressiveLoading: true,
        fadeInDuration: const Duration(milliseconds: 300),
        placeholder: 'Loading...',
      ),
    );
  }
}
