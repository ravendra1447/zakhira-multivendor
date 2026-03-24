import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'dart:io';
import '../services/cdn_service.dart';

class OptimizedImageWidget extends StatefulWidget {
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
  final int memCacheWidth;
  final int memCacheHeight;
  final bool useBlurHash;
  final String? blurHash;

  const OptimizedImageWidget({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.customPlaceholder,
    this.customErrorWidget,
    this.enableFadeIn = true,
    this.fadeInDuration = const Duration(milliseconds: 300),
    this.enablePreloading = true,
    this.memCacheWidth = 800,
    this.memCacheHeight = 600,
    this.useBlurHash = false,
    this.blurHash,
  });

  @override
  State<OptimizedImageWidget> createState() => _OptimizedImageWidgetState();
}

class _OptimizedImageWidgetState extends State<OptimizedImageWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

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
      _animationController.forward();
    }

    // Preload nearby images for better performance
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

  void _preloadNearbyImages() {
    // This can be expanded to preload next/previous images in a list
    // For now, we'll just preload the current image with higher priority
    if (widget.imageUrl.startsWith('http')) {
      // Use CDN service for optimized preloading
      final cdnService = CDNService();
      final optimizedUrl = cdnService.getMediumUrl(widget.imageUrl);
      
      precacheImage(
        CachedNetworkImageProvider(
          optimizedUrl,
          cacheKey: _getCacheKey(),
        ),
        context,
      );
    }
  }

  String _getCacheKey() {
    // Create a unique cache key based on image dimensions
    return '${widget.imageUrl}_${widget.memCacheWidth}x${widget.memCacheHeight}';
  }  Widget _buildPlaceholder() {
    if (widget.customPlaceholder != null) {
      return widget.customPlaceholder!;
    }

    final double? pWidth = (widget.width?.isInfinite ?? true) ? null : widget.width;
    final double? pHeight = (widget.height?.isInfinite ?? true) ? null : widget.height;

    return Container(
      width: pWidth,
      height: pHeight,
      color: Colors.grey[200],
      child: widget.useBlurHash && widget.blurHash != null
          ? BlurHash(
              hash: widget.blurHash!,
              imageFit: widget.fit ?? BoxFit.cover,
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.image_outlined,
                    color: Colors.grey[400],
                    size: (pWidth ?? 40) * 0.4,
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
  }  Widget _buildNetworkImage() {
    String optimizedUrl = widget.imageUrl;
    if (optimizedUrl.contains('184.168.126.71:3000')) {
      optimizedUrl = optimizedUrl.replaceAll('184.168.126.71:3000', 'bangkokmart.in');
    }

    return CachedNetworkImage(
      imageUrl: optimizedUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit ?? BoxFit.cover,
      memCacheWidth: widget.memCacheWidth,
      memCacheHeight: widget.memCacheHeight,
      fadeInDuration: widget.enableFadeIn ? widget.fadeInDuration : Duration.zero,
      placeholder: (context, url) => _buildPlaceholder(),
      errorWidget: (context, url, error) {
        debugPrint('❌ Image load error: $optimizedUrl - $error');
        return _buildErrorWidget();
      },
    );
  }

  Widget _buildFileImage() {
    try {
      final file = File(widget.imageUrl);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          cacheWidth: widget.memCacheWidth,
          cacheHeight: widget.memCacheHeight,
          frameBuilder: widget.enableFadeIn
              ? (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded) return child;
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: widget.fadeInDuration,
                    curve: Curves.easeInOut,
                    child: child,
                  );
                }
              : null,
          errorBuilder: (context, error, stackTrace) => _buildErrorWidget(),
        );
      }
    } catch (e) {
      debugPrint('Error loading file image: $e');
    }
    return _buildErrorWidget();
  }

  @override
  Widget build(BuildContext context) {
    // Handle network images
    if (widget.imageUrl.startsWith('http://') || widget.imageUrl.startsWith('https://')) {
      return _buildNetworkImage();
    }

    // Handle local files
    return _buildFileImage();
  }
}

// Preloader widget for batch image preloading
class ImagePreloader extends StatefulWidget {
  final List<String> imageUrls;
  final Widget child;
  final int maxConcurrent;

  const ImagePreloader({
    super.key,
    required this.imageUrls,
    required this.child,
    this.maxConcurrent = 3,
  });

  @override
  State<ImagePreloader> createState() => _ImagePreloaderState();
}

class _ImagePreloaderState extends State<ImagePreloader> {
  bool _isPreloading = true;

  @override
  void initState() {
    super.initState();
    _preloadImages();
  }

  Future<void> _preloadImages() async {
    final networkUrls = widget.imageUrls
        .where((url) => url.startsWith('http'))
        .take(widget.maxConcurrent)
        .toList();

    if (networkUrls.isEmpty) {
      setState(() => _isPreloading = false);
      return;
    }

    try {
      await Future.wait(
        networkUrls.map((url) => precacheImage(
          CachedNetworkImageProvider(url),
          context,
        )),
      );
    } catch (e) {
      debugPrint('Error preloading images: $e');
    }

    if (mounted) {
      setState(() => _isPreloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

// Grid-specific optimized image widget with CDN integration
class GridOptimizedImage extends StatelessWidget {
  final String imageUrl;
  final double size;
  final VoidCallback? onTap;
  final int imageCount;
  final String? blurHash;

  const GridOptimizedImage({
    super.key,
    required this.imageUrl,
    this.size = 120,
    this.onTap,
    this.imageCount = 1,
    this.blurHash,
  });

  @override
  Widget build(BuildContext context) {
    final cdnService = CDNService();
    
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          OptimizedImageWidget(
            imageUrl: imageUrl,
            width: size,
            height: size,
            memCacheWidth: (size * 2).toInt(),
            memCacheHeight: (size * 2).toInt(),
            useBlurHash: blurHash != null,
            blurHash: blurHash,
            fadeInDuration: const Duration(milliseconds: 200),
          ),
          if (imageCount > 1)
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.photo_library,
                      color: Colors.white,
                      size: 12,
                    ),
                    const SizedBox(width: 2),
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
