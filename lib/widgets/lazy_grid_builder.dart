import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

class LazyGridBuilder extends StatefulWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final SliverGridDelegate gridDelegate;
  final EdgeInsets? padding;
  final ScrollController? controller;
  final int preloadThreshold; // How many items to preload before visible
  final bool enableAutoPreloading;

  const LazyGridBuilder({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.gridDelegate,
    this.padding,
    this.controller,
    this.preloadThreshold = 3,
    this.enableAutoPreloading = true,
  });

  @override
  State<LazyGridBuilder> createState() => _LazyGridBuilderState();
}

class _LazyGridBuilderState extends State<LazyGridBuilder> {
  final Set<int> _visibleItems = <int>{};
  final Set<int> _loadedItems = <int>{};
  final Map<int, Widget> _itemCache = {};
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.controller ?? ScrollController();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _scrollController.dispose();
    } else {
      _scrollController.removeListener(_handleScroll);
    }
    super.dispose();
  }

  void _handleScroll() {
    if (!widget.enableAutoPreloading) return;

    // Calculate visible range based on scroll position
    final viewport = _scrollController.position.viewportDimension;
    final scrollOffset = _scrollController.offset;
    
    // Estimate which items should be visible
    final estimatedVisibleStart = (scrollOffset / (viewport / widget.gridDelegate.crossAxisCount)).floor();
    final estimatedVisibleEnd = estimatedVisibleStart + (widget.gridDelegate.crossAxisCount * 3); // Load 3 rows worth

    // Update visible items
    final newVisibleItems = <int>{};
    for (int i = estimatedVisibleStart.clamp(0, widget.itemCount - 1); 
         i <= estimatedVisibleEnd.clamp(0, widget.itemCount - 1); 
         i++) {
      newVisibleItems.add(i);
    }

    if (newVisibleItems != _visibleItems) {
      setState(() {
        _visibleItems = newVisibleItems;
        // Mark items as loaded (keep some cache)
        _loadedItems.addAll(_visibleItems);
        
        // Limit cache size to prevent memory issues
        if (_loadedItems.length > widget.gridDelegate.crossAxisCount * 10) {
          final itemsToRemove = _loadedItems.difference(_visibleItems).take(widget.gridDelegate.crossAxisCount * 5);
          _loadedItems.removeAll(itemsToRemove);
          _itemCache.removeWhere((key, value) => itemsToRemove.contains(key));
        }
      });
    }
  }

  Widget _buildLazyItem(int index) {
    if (_loadedItems.contains(index)) {
      // Return cached item if available
      if (_itemCache.containsKey(index)) {
        return _itemCache[index]!;
      }
      
      // Build and cache the item
      final item = widget.itemBuilder(context, index);
      _itemCache[index] = item;
      return item;
    }

    // Return placeholder for items not yet loaded
    return Container(
      color: Colors.grey[100],
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: _scrollController,
      padding: widget.padding,
      gridDelegate: widget.gridDelegate,
      itemCount: widget.itemCount,
      itemBuilder: (context, index) {
        return VisibilityDetector(
          key: Key('grid_item_$index'),
          onVisibilityChanged: (visibilityInfo) {
            if (!widget.enableAutoPreloading) return;
            
            final isVisible = visibilityInfo.visibleFraction > 0.1;
            if (isVisible && !_loadedItems.contains(index)) {
              setState(() {
                _loadedItems.add(index);
              });
            }
          },
          child: _buildLazyItem(index),
        );
      },
    );
  }
}

// Optimized grid view for product images with smart caching
class OptimizedProductGrid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final Function(Map<String, dynamic>) onTap;
  final int crossAxisCount;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final EdgeInsets? padding;

  const OptimizedProductGrid({
    super.key,
    required this.items,
    required this.onTap,
    this.crossAxisCount = 3,
    this.crossAxisSpacing = 2.0,
    this.mainAxisSpacing = 2.0,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return LazyGridBuilder(
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing,
      ),
      padding: padding,
      preloadThreshold: crossAxisCount * 2, // Preload 2 rows
      itemBuilder: (context, index) {
        final item = items[index];
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
                  child: _buildOptimizedImage(imageUrl),
                ),
                if (totalImages > 1)
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
    );
  }

  Widget _buildOptimizedImage(String imageUrl) {
    // Import here to avoid circular dependency
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: 300,
      memCacheHeight: 300,
      cacheWidth: 300,
      cacheHeight: 300,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
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
          color: Colors.grey[300],
          child: const Icon(
            Icons.broken_image,
            color: Colors.grey,
            size: 24,
          ),
        );
      },
    );
  }
}
