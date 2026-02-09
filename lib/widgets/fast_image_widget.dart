import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';

class FastImageWidget extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final bool enableCache;

  const FastImageWidget({
    Key? key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.enableCache = true,
  }) : super(key: key);

  @override
  State<FastImageWidget> createState() => _FastImageWidgetState();
}

class _FastImageWidgetState extends State<FastImageWidget> {
  @override
  Widget build(BuildContext context) {
    return Image.network(
      widget.imageUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      // High quality settings (like before)
      filterQuality: FilterQuality.high,  // High quality
      gaplessPlayback: true,
      // Smart caching with null safety
      cacheWidth: widget.width != null && widget.width != double.infinity 
          ? widget.width?.toInt() 
          : null,
      cacheHeight: widget.height != null && widget.height != double.infinity 
          ? widget.height?.toInt() 
          : null,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return widget.placeholder ?? _buildDefaultPlaceholder();
      },
      errorBuilder: (context, error, stackTrace) {
        return widget.errorWidget ?? _buildDefaultError();
      },
    );
  }

  Widget _buildDefaultPlaceholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[200],
      child: Center(
        child: Container(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[400]!),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultError() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[300],
      child: Icon(Icons.broken_image, color: Colors.grey[500]),
    );
  }
}

// Pre-cached image widget for repeated images
class PreCachedImageWidget extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;

  const PreCachedImageWidget({
    Key? key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  }) : super(key: key);

  @override
  State<PreCachedImageWidget> createState() => _PreCachedImageWidgetState();
}

class _PreCachedImageWidgetState extends State<PreCachedImageWidget> {
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
      );
    }

    // Fallback to fast loading
    return FastImageWidget(
      imageUrl: widget.imageUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
    );
  }
}
