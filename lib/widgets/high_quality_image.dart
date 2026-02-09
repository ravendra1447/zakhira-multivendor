import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';

class HighQualityImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;

  const HighQualityImage({
    Key? key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  }) : super(key: key);

  @override
  State<HighQualityImage> createState() => _HighQualityImageState();
}

class _HighQualityImageState extends State<HighQualityImage> {
  @override
  Widget build(BuildContext context) {
    return Image.network(
      widget.imageUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      // High quality settings
      filterQuality: FilterQuality.high,  // Best quality
      gaplessPlayback: true,
      // Better cache for quality
      cacheWidth: widget.width?.toInt(),
      cacheHeight: widget.height?.toInt(),
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
              valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[400]!),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: widget.width,
          height: widget.height,
          color: Colors.grey[300],
          child: const Icon(Icons.broken_image, color: Colors.grey),
        );
      },
    );
  }
}

// Profile optimized image - balance of quality and speed
class ProfileOptimizedImage extends StatelessWidget {
  final String imageUrl;
  final double size;

  const ProfileOptimizedImage({
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
      // Profile optimization - good quality, decent speed
      filterQuality: FilterQuality.high,  // High quality for profile
      gaplessPlayback: true,
      // Safe cache dimensions with validation
      cacheWidth: size > 0 && size != double.infinity ? (size * 2).toInt() : null,
      cacheHeight: size > 0 && size != double.infinity ? (size * 2).toInt() : null,
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
