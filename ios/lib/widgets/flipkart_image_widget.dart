import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';

class FlipkartImageWidget extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool enablePreloading;

  const FlipkartImageWidget({
    Key? key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.enablePreloading = true,
  }) : super(key: key);

  @override
  State<FlipkartImageWidget> createState() => _FlipkartImageWidgetState();
}

class _FlipkartImageWidgetState extends State<FlipkartImageWidget> {
  ImageProvider? _cachedImage;
  bool _isPreloaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.enablePreloading) {
      _preloadImage();
    }
  }

  void _preloadImage() async {
    try {
      final imageProvider = NetworkImage(widget.imageUrl);
      // Preload in background for instant display
      await precacheImage(imageProvider, context);
      if (mounted) {
        setState(() {
          _cachedImage = imageProvider;
          _isPreloaded = true;
        });
      }
    } catch (e) {
      // Fallback to network loading
      if (mounted) {
        setState(() {
          _isPreloaded = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isPreloaded && _cachedImage != null) {
      // Use preloaded image for instant display
      return Image(
        image: _cachedImage!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium, // Balanced for speed
      );
    }

    // Fallback to network loading with optimization
    return Image.network(
      widget.imageUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      filterQuality: FilterQuality.medium, // Flipkart-like quality
      gaplessPlayback: true,
      // Minimal loading for smooth scrolling
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        
        // Show minimal placeholder for smooth UX
        return Container(
          width: widget.width,
          height: widget.height,
          color: Colors.grey[100],
          child: Container(
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: widget.width,
          height: widget.height,
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image, color: Colors.grey, size: 20),
        );
      },
    );
  }
}

// Grid image with smart preloading for marketplace
class FlipkartGridImage extends StatefulWidget {
  final String imageUrl;
  final double size;
  final bool preload;

  const FlipkartGridImage({
    Key? key,
    required this.imageUrl,
    this.size = 100,
    this.preload = true,
  }) : super(key: key);

  @override
  State<FlipkartGridImage> createState() => _FlipkartGridImageState();
}

class _FlipkartGridImageState extends State<FlipkartGridImage> {
  ImageProvider? _cachedImage;
  bool _isPreloaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.preload) {
      _preloadImage();
    }
  }

  void _preloadImage() async {
    try {
      final imageProvider = NetworkImage(widget.imageUrl);
      await precacheImage(imageProvider, context);
      if (mounted) {
        setState(() {
          _cachedImage = imageProvider;
          _isPreloaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPreloaded = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isPreloaded && _cachedImage != null) {
      return Image(
        image: _cachedImage!,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    }

    return Image.network(
      widget.imageUrl,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      cacheWidth: widget.size.toInt(),
      cacheHeight: widget.size.toInt(),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: widget.size,
          height: widget.size,
          color: Colors.grey[100],
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: widget.size,
          height: widget.size,
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image, color: Colors.grey, size: 16),
        );
      },
    );
  }
}

// Batch preloader for multiple images
class ImageBatchPreloader {
  static final Map<String, bool> _preloadedImages = {};
  
  static void preloadImages(BuildContext context, List<String> imageUrls) {
    for (final url in imageUrls) {
      if (!_preloadedImages.containsKey(url)) {
        _preloadedImages[url] = false;
        _preloadSingleImage(context, url);
      }
    }
  }

  static void _preloadSingleImage(BuildContext context, String url) async {
    try {
      final imageProvider = NetworkImage(url);
      await precacheImage(imageProvider, context);
      _preloadedImages[url] = true;
    } catch (e) {
      _preloadedImages[url] = false;
    }
  }

  static bool isImagePreloaded(String url) {
    return _preloadedImages[url] ?? false;
  }
}
