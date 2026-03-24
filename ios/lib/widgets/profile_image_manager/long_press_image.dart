import 'package:flutter/material.dart';
import 'image_options_modal.dart';

class LongPressImage extends StatefulWidget {
  final Widget child;
  final String imageUrl;
  final String? imageId;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const LongPressImage({
    super.key,
    required this.child,
    required this.imageUrl,
    this.imageId,
    this.width,
    this.height,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<LongPressImage> createState() => _LongPressImageState();
}

class _LongPressImageState extends State<LongPressImage> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Handle normal tap (existing functionality)
        // This will be handled by the parent widget's onTap
      },
      onLongPress: () {
        // Show the modal with edit/delete options
        _showImageOptions(context);
      },
      child: widget.child,
    );
  }

  void _showImageOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ImageOptionsModal(
        imageUrl: widget.imageUrl,
        imageId: 'profile', // Default for profile images
        productId: null,
        variationId: null,
        onRefresh: () {
          Navigator.pop(context);
          // Call onRefresh if available
          if (widget.onLongPress != null) {
            widget.onLongPress!();
          }
        },
      ),
    );
  }
}
