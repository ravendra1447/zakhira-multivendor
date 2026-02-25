import 'package:flutter/material.dart';
import '../services/cdn_service.dart';
import 'optimized_image_widget.dart';

// CDN-Optimized Product Grid for Marketplace
class CDNOptimizedProductGrid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final Function(Map<String, dynamic>) onTap;
  final int crossAxisCount;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final EdgeInsets? padding;

  const CDNOptimizedProductGrid({
    super.key,
    required this.items,
    required this.onTap,
    this.crossAxisCount = 2,
    this.crossAxisSpacing = 8.0,
    this.mainAxisSpacing = 12.0,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final cdnService = CDNService();
    
    return Padding(
      padding: padding ?? const EdgeInsets.all(8.0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: crossAxisSpacing,
          mainAxisSpacing: mainAxisSpacing,
          childAspectRatio: 0.75,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final product = item['product'];
          final variation = item['variation'];
          final imageUrl = item['imageUrl'] as String;
          final allImages = item['allImages'] as List<String>;

          return _buildCDNOptimizedCard(
            product: product,
            variation: variation,
            imageUrl: imageUrl,
            allImages: allImages,
            onTap: () => onTap(item),
          );
        },
      ),
    );
  }

  Widget _buildCDNOptimizedCard({
    required dynamic product,
    required Map<String, dynamic> variation,
    required String imageUrl,
    required List<String> allImages,
    required VoidCallback onTap,
  }) {
    final cdnService = CDNService();
    
    // Calculate price and discount
    double? currentPrice;
    double? originalPrice;
    int discountPercent = 0;

    if (product.priceSlabs.isNotEmpty) {
      final firstSlab = product.priceSlabs.first;
      final priceStr = firstSlab['price']?.toString() ?? '';
      if (priceStr.isNotEmpty) {
        try {
          currentPrice = double.tryParse(priceStr);
          originalPrice = currentPrice != null ? currentPrice * 1.3 : null;
          if (originalPrice != null && currentPrice != null) {
            discountPercent = ((originalPrice - currentPrice) / originalPrice * 100).round();
          }
        } catch (e) {
          print('Error parsing price: $e');
        }
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // CDN-Optimized Product Image
            Expanded(
              flex: 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      color: Colors.grey.shade100,
                      child: OptimizedImageWidget(
                        imageUrl: imageUrl,
                        width: double.infinity,
                        height: double.infinity,
                        memCacheWidth: 400,
                        memCacheHeight: 400,
                        fadeInDuration: const Duration(milliseconds: 200),
                        placeholder: 'Product',
                      ),
                    ),
                  ),
                  // Image count badge
                  if (allImages.length > 1)
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
                              '${allImages.length}',
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
            ),

            // Product Details
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Product Name
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),

                  // Price Row
                  Row(
                    children: [
                      if (currentPrice != null) ...[
                        Flexible(
                          child: Text(
                            '₹${currentPrice.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (originalPrice != null) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '₹${originalPrice.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                decoration: TextDecoration.lineThrough,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// CDN-Optimized Profile Grid (3 columns)
class CDNOptimizedProfileGrid extends StatelessWidget {
  final List<Map<String, dynamic>> gridItems;
  final Function(Map<String, dynamic>) onTap;

  const CDNOptimizedProfileGrid({
    super.key,
    required this.gridItems,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cdnService = CDNService();
    
    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: gridItems.length,
        itemBuilder: (context, index) {
          final item = gridItems[index];
          final product = item['product'];
          final variation = item['variation'];
          final imageUrl = item['imageUrl'] as String;
          final allImages = item['allImages'] as List<String>;
          final totalImages = allImages.length;

          return GestureDetector(
            onTap: () => onTap(item),
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: Colors.grey.shade200,
                    child: OptimizedImageWidget(
                      imageUrl: imageUrl,
                      width: double.infinity,
                      height: double.infinity,
                      memCacheWidth: 300,
                      memCacheHeight: 300,
                      fadeInDuration: const Duration(milliseconds: 150),
                      placeholder: 'Product',
                    ),
                  ),
                  // Image count badge
                  if (totalImages > 1)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
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
                              '$totalImages',
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
            ),
          );
        },
      ),
    );
  }
}
