import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'dart:io';

class UltraFastImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;

  const UltraFastImage({
    Key? key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  }) : super(key: key);

  @override
  State<UltraFastImage> createState() => _UltraFastImageState();
}

class _UltraFastImageState extends State<UltraFastImage> {
  @override
  Widget build(BuildContext context) {
    return Image.network(
      widget.imageUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      // Fast settings for marketplace (Flipkart-like)
      filterQuality: FilterQuality.medium,  // Balanced quality
      gaplessPlayback: true,
      // Minimal loading for instant display
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: widget.width,
          height: widget.height,
          color: Colors.grey[100],
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: widget.width,
          height: widget.height,
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image, color: Colors.grey),
        );
      },
    );
  }
}

// Preloaded network image for instant display
class PreloadedNetworkImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;

  const PreloadedNetworkImage({
    Key? key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  }) : super(key: key);

  @override
  State<PreloadedNetworkImage> createState() => _PreloadedNetworkImageState();
}

class _PreloadedNetworkImageState extends State<PreloadedNetworkImage> {
  ImageProvider? _imageProvider;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _preloadImage();
  }

  void _preloadImage() async {
    try {
      final provider = NetworkImage(widget.imageUrl);
      // Preload in background
      await precacheImage(provider, context);
      if (mounted) {
        setState(() {
          _imageProvider = provider;
          _isLoaded = true;
        });
      }
    } catch (e) {
      // Fallback to direct loading
      if (mounted) {
        setState(() {
          _isLoaded = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoaded && _imageProvider != null) {
      return Image(
        image: _imageProvider!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
      );
    }

    // Fallback to ultra-fast loading
    return UltraFastImage(
      imageUrl: widget.imageUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
    );
  }
}

// Grid optimized image for marketplace
class MarketplaceGridImage extends StatelessWidget {
  final String imageUrl;
  final double size;

  const MarketplaceGridImage({
    Key? key,
    required this.imageUrl,
    this.size = 100,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Image.network(
      imageUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      // Balanced optimization - good quality with speed
      filterQuality: FilterQuality.medium,  // Better quality
      gaplessPlayback: true,
      // Safe cache dimensions
      cacheWidth: size > 0 && size != double.infinity ? size.toInt() : null,
      cacheHeight: size > 0 && size != double.infinity ? size.toInt() : null,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: size,
          height: size,
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image, color: Colors.grey, size: 20),
        );
      },
    );
  }
}
