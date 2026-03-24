// TODO Implement this library.import 'dart:io';
import 'dart:io';
import 'dart:ui'; // Added for ImageFilter
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hive/hive.dart';
import '../../../models/product.dart';
import '../../cart/cart_screen.dart';
import '../../checkout/checkout_screen.dart';
import '../../marketplace/marketplace_tab.dart'; // For marketplace products
import '../../marketplace/marketplace_chat_screen.dart';
import '../../../services/marketplace/marketplace_chat_service.dart';
import '../../../models/marketplace/marketplace_chat_room.dart';
import '../../chat_screen.dart'; // Import main chat screen

import '../../../services/cart_service.dart';

class ProductDetailScreen extends StatefulWidget {
  final Product product;
  final Map<String, dynamic> variation; // The color variation that was clicked
  final int initialImageIndex; // Which image to show initially

  const ProductDetailScreen({
    super.key,
    required this.product,
    required this.variation,
    this.initialImageIndex = 0,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late PageController _pageController;
  late int _currentImageIndex;
  bool _isGridView = false;
  late Map<String, dynamic> _currentVariation;
  String _selectedTab = 'Overview'; // Overview, Details, Recommended
  String _mediaTab = 'Photos'; // Photos, Video, Reviews, Variations
  final ScrollController _scrollController = ScrollController();
  final ScrollController _colorRowScrollController = ScrollController(); // For color row scrolling
  double _imageHeight = 0.6; // Increased initial height to prevent "pop"
  final Map<int, double> _imageAspectRatios = {}; // Cache aspect ratios for images
  final Map<String, int> _sizeQuantities = {}; // For variations sheet size quantities
  final Map<String, int> _variationQuantities = {}; // Track quantities per variation
  final Map<String, Map<String, int>> _variationSizeQuantities = {}; // Track sizes per variation: {variationName: {size: qty}}
  double _subtotal = 0.0;
  bool _isColorList = false;
  String? _activeVariationForSheet; // Track which variation is active in the sheet
  Map<String, bool> _colorSelectionMode = {}; // Track which colors are being edited
  Set<int> _viewedImageIndices = {}; // Track which images have been viewed
  int _swipeAttemptCount = 0; // Simple counter for swipe attempts
  Timer? _swipeTimer; // Timer to detect swipe attempts
  late PageController _variationsPageController; // Controller for variations swipe navigation

  // Chat related variables
  final MarketplaceChatService _chatService = MarketplaceChatService();
  bool _isLoadingChat = false;
  int? _currentUserId; // This should come from your auth service
  bool _showChatButton = true;

  @override
  void initState() {
    super.initState();
    _currentVariation = widget.variation;
    _activeVariationForSheet = widget.variation['name']?.toString() ?? '';
    _currentImageIndex = widget.initialImageIndex;
    final images = _getAllImages();
    _pageController = PageController(initialPage: _currentImageIndex);
    
    // Initialize variations PageController with current variation index
    final currentVariationIndex = widget.product.variations.indexWhere(
      (v) => (v['name']?.toString() ?? '') == (_currentVariation['name']?.toString() ?? '')
    );
    _variationsPageController = PageController(initialPage: currentVariationIndex >= 0 ? currentVariationIndex : 0);
    
    _scrollController.addListener(_onScroll);

    // Initialize viewed images with the starting image
    _viewedImageIndices.add(_currentImageIndex);
    // Initialize swipe counter - if starting on last image (single image), set to 1
    if (images.length == 1) {
      _swipeAttemptCount = 1; // Already on last image for single image case
    } else {
      _swipeAttemptCount = 0;
    }

    // Initialize color selection mode
    for (var variation in widget.product.variations) {
      final varName = variation['name']?.toString() ?? '';
      _colorSelectionMode[varName] = false;
    }

    // Preload variation images in background
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadAllVariationImages();
      // Set initial height for first image so it doesn't look "halka"
      if (images.isNotEmpty) {
        _setImageHeightFor(images[_currentImageIndex], _currentImageIndex);
      }
    });
  }

  void _preloadAllVariationImages() {
    for (var variation in widget.product.variations) {
      if (variation['allImages'] != null) {
        dynamic allImagesData = variation['allImages'];
        List<String> images = [];
        if (allImagesData is List) {
          images = allImagesData.map((e) => e.toString()).toList();
        } else if (allImagesData is String) {
          try {
            final decoded = jsonDecode(allImagesData);
            if (decoded is List) images = decoded.map((e) => e.toString()).toList();
          } catch (_) {}
        }
        for (var url in images) {
          if (url.startsWith('http')) {
            precacheImage(CachedNetworkImageProvider(url), context);
          }
        }
      } else if (variation['image'] != null) {
        final url = variation['image'].toString();
        if (url.startsWith('http')) {
          precacheImage(CachedNetworkImageProvider(url), context);
        }
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final scrollOffset = _scrollController.offset;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxImageHeight = screenHeight * 0.4;

    // Calculate new image height based on scroll
    // As user scrolls up, image height decreases
    final newHeight = (maxImageHeight - scrollOffset * 0.5).clamp(0.0, maxImageHeight);

    if ((_imageHeight - newHeight).abs() > 0.5) {
      setState(() {
        _imageHeight = newHeight;
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _variationsPageController.dispose();
    _scrollController.dispose();
    _colorRowScrollController.dispose();
    _swipeTimer?.cancel();
    _chatService.dispose();
    super.dispose();
  }

  List<String> _getAllImages() {
    final List<String> images = [];

    // Get all images from the current variation
    if (_currentVariation['allImages'] != null) {
      dynamic allImagesData = _currentVariation['allImages'];

      // Handle if allImages is a JSON string
      if (allImagesData is String) {
        try {
          final decoded = jsonDecode(allImagesData);
          if (decoded is List) {
            allImagesData = decoded;
          }
        } catch (e) {
          // Fallback parsing for malformed JSON strings
          final s = allImagesData.trim();
          // Try to auto-fix simple missing bracket
          dynamic fallbackList;
          try {
            final fixed = (s.startsWith('[') && !s.endsWith(']')) ? '$s]' : s;
            final decodedFixed = jsonDecode(fixed);
            if (decodedFixed is List) {
              fallbackList = decodedFixed;
            }
          } catch (_) {
            // If still failing, attempt CSV-style split
            final cleaned = s
                .replaceAll('[', '')
                .replaceAll(']', '')
                .replaceAll('"', '')
                .replaceAll("'", '');
            final parts = cleaned
                .split(RegExp(r'[,\s]+'))
                .where((p) => p.isNotEmpty)
                .toList();
            if (parts.isNotEmpty) {
              fallbackList = parts;
            }
          }
          if (fallbackList is List) {
            allImagesData = fallbackList;
            print('?? allImages JSON malformed, applied fallback parsing');
          } else {
            print('Error decoding allImages JSON: $e');
          }
        }
      }

      // Process as List
      if (allImagesData is List) {
        for (var img in allImagesData) {
          if (img is String && img.isNotEmpty) {
            images.add(img);
          } else if (img != null) {
            images.add(img.toString());
          }
        }
      }

      print('?? Found ${images.length} images in variation ${_currentVariation['name']}');
    }

    // Fallback to single image if allImages not available
    if (images.isEmpty && _currentVariation['image'] != null) {
      final img = _currentVariation['image'];
      if (img is String && img.isNotEmpty) {
        images.add(img);
        print('?? Using single image fallback');
      }
    }

    print(' Total images to display: ${images.length}');
    return images;
  }

  void _switchToNextVariation() {
    final currentIndex = widget.product.variations.indexWhere(
      (v) => (v['name']?.toString() ?? '') == (_currentVariation['name']?.toString() ?? '')
    );
    
    if (currentIndex >= 0 && currentIndex < widget.product.variations.length - 1) {
      // Switch to next variation
      final nextVariation = widget.product.variations[currentIndex + 1];
      _switchVariation(nextVariation);
      
      // Update variations PageController to show new variation
      if (_variationsPageController.hasClients) {
        _variationsPageController.animateToPage(
          currentIndex + 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
      
      print('DEBUG: Switched to next variation: ${nextVariation['name']}');
    } else if (currentIndex == widget.product.variations.length - 1) {
      // Already on last variation, go to variations gallery
      setState(() {
        _mediaTab = 'Variations';
      });
      print('DEBUG: Already on last variation, showing variations gallery');
    }
  }

  void _switchToPreviousVariation() {
    final currentIndex = widget.product.variations.indexWhere(
      (v) => (v['name']?.toString() ?? '') == (_currentVariation['name']?.toString() ?? '')
    );
    
    if (currentIndex > 0) {
      // Switch to previous variation
      final previousVariation = widget.product.variations[currentIndex - 1];
      _switchVariation(previousVariation);
      
      // Update variations PageController to show new variation
      if (_variationsPageController.hasClients) {
        _variationsPageController.animateToPage(
          currentIndex - 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  void _switchVariation(Map<String, dynamic> variation, {bool resetToPhotos = true}) {
    setState(() {
      _currentVariation = variation;
      _currentImageIndex = 0;
      _isGridView = false;
      // Only reset to Photos tab if explicitly requested (e.g., when clicking a color)
      // Don't reset when swiping in Variations tab
      if (resetToPhotos) {
        _mediaTab = 'Photos';
      }
      // Reset viewed images and swipe counter when switching variations
      _viewedImageIndices.clear();
      _viewedImageIndices.add(0); // Add the first image as viewed
      _swipeAttemptCount = 0; // Reset swipe counter when switching variations
      final images = _getAllImages();
      // Use existing controller to jump to page 0, don't create new one
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      if (images.isNotEmpty) {
        _setImageHeightFor(images[0], 0);
      }
      // IMPORTANT: Don't reset quantities when switching variations
      // This preserves selections across different colors
    });
  }

  Color _getColorFromName(String colorName) {
    final name = colorName.toLowerCase();
    switch (name) {
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'black':
        return Colors.black;
      case 'white':
        return Colors.white;
      case 'yellow':
        return Colors.yellow;
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purple;
      case 'pink':
        return Colors.pink;
      case 'brown':
        return Colors.brown;
      case 'grey':
      case 'gray':
        return Colors.grey;
      default:
        return Colors.grey.shade400;
    }
  }

  Widget _buildColorSwatchImage(String imagePath, {double size = 60}) {
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: imagePath,
        fit: BoxFit.cover,
        width: size,
        height: size,
        placeholder: (context, url) => Container(
          color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
          child: Icon(Icons.broken_image, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), size: 20),
        ),
      );
    }
    try {
      final file = File(imagePath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
              child: Icon(Icons.broken_image, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), size: 20),
            );
          },
        );
      }
    } catch (e) {
      print("Error checking file: $imagePath - $e");
    }
    return Container(
      color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
      child: Icon(Icons.broken_image, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), size: 20),
    );
  }

  Widget _buildImageWidget(String imagePath, {bool isClickable = true}) {
    final bool isNetwork = imagePath.startsWith('http://') || imagePath.startsWith('https://');

    Widget buildImage({required BoxFit fit}) {
      if (isNetwork) {
        return CachedNetworkImage(
          imageUrl: imagePath,
          fit: fit,
          fadeInDuration: const Duration(milliseconds: 150),
          placeholder: (context, url) => Center(
            child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
          ),
          errorWidget: (context, url, error) => Container(
            child: Icon(Icons.broken_image, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), size: 40),
          ),
        );
      }

      try {
        final file = File(imagePath);
        if (file.existsSync()) {
          return Image.file(
            file,
            fit: fit,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                child: Icon(Icons.broken_image, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), size: 40),
              );
            },
          );
        }
      } catch (e) {}

      return Icon(Icons.broken_image, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5));
    }

    Widget imageContent = Stack(
      fit: StackFit.expand,
      children: [
        // Background with blur
        if (isNetwork)
          Image.network(
            imagePath,
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) => Container(color: Theme.of(context).colorScheme.surface),
          )
        else
          Builder(
            builder: (context) {
              try {
                final file = File(imagePath);
                if (file.existsSync()) {
                  return Image.file(
                    file,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Container(color: Theme.of(context).colorScheme.surface),
                  );
                }
              } catch (e) {}
              return Container(color: Theme.of(context).colorScheme.surface);
            },
          ),

        // Blur Effect Overlay
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.6),
            ),
          ),
        ),

        // Main Image with proper fit (fill width, allow vertical crop)
        Positioned.fill(child: buildImage(fit: BoxFit.fitWidth)),
      ],
    );

    if (isClickable) {
      return GestureDetector(
        onTap: () {
          _openFullScreenImage(imagePath);
        },
        child: imageContent,
      );
    }

    return imageContent;
  }

  void _openFullScreenImage(String imagePath) {
    final images = _getAllImages();
    final initialIndex = images.indexOf(imagePath);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _FullScreenImageViewer(
          images: images,
          initialIndex: initialIndex >= 0 ? initialIndex : 0,
        ),
      ),
    );
  }

  // Resolve aspect ratio and adjust top image height so orientation matches (horizontal/vertical/square)
  Future<void> _setImageHeightFor(String imagePath, int index) async {
    try {
      double? ratio;
      if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
        final provider = CachedNetworkImageProvider(imagePath);
        final stream = provider.resolve(const ImageConfiguration());
        final completer = Completer<double>();
        ImageStreamListener? listener;
        listener = ImageStreamListener((info, _) {
          ratio = info.image.width.toDouble() / info.image.height.toDouble();
          completer.complete(ratio!);
          stream.removeListener(listener!);
        }, onError: (error, stack) {
          if (!completer.isCompleted) completer.complete(1.0);
          stream.removeListener(listener!);
        });
        stream.addListener(listener);
        ratio = await completer.future;
      } else {
        final file = File(imagePath);
        if (file.existsSync()) {
          final bytes = await file.readAsBytes();
          final codec = await instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          final img = frame.image;
          ratio = img.width.toDouble() / img.height.toDouble();
          img.dispose();
        }
      }
      if (ratio == null) ratio = 1.0;
      _imageAspectRatios[index] = ratio!;
      final screen = MediaQuery.of(context).size;
      // Desired height so that the image box matches orientation: height = width / ratio
      double desired = screen.width / ratio!;
      // Clamp to sensible range
      final minH = screen.height * 0.30;
      final maxH = screen.height * 0.62;
      desired = desired.clamp(minH, maxH);
      if (mounted) {
        setState(() {
          _imageHeight = desired;
        });
      }
    } catch (_) {
      final screen = MediaQuery.of(context).size;
      if (mounted) {
        setState(() {
          _imageHeight = screen.height * 0.5;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = _getAllImages();
    final colorName = _currentVariation['name'] as String? ?? 'Unknown';
    final color = _getColorFromName(colorName);

    // Initialize image height on first build
    final screen = MediaQuery.of(context).size;
    if (_imageHeight == 0.6) {
      _imageHeight = screen.height * 0.60; // Start larger to match Marketplace style
      if (images.isNotEmpty) {
        // Kick off aspect resolution for initial image
        _setImageHeightFor(images[_currentImageIndex], _currentImageIndex);
      }
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const Icon(Icons.search),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.product.name,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isGridView ? Icons.view_carousel : Icons.grid_view,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: () {
              setState(() {
                _isGridView = !_isGridView;
              });
            },
          ),
          Stack(
            children: [
              IconButton(
                icon: Icon(Icons.shopping_cart_outlined, color: Theme.of(context).colorScheme.onSurface),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CartScreen(),
                    ),
                  );
                },
              ),
              if (CartService.totalItems > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '${CartService.totalItems}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: Icon(Icons.more_vert, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Image Gallery Section - Collapsible on scroll
          AnimatedContainer(
            duration: const Duration(milliseconds: 300), // Smoother transition
            curve: Curves.easeInOut,
            height: _imageHeight,
            child: Stack(
              children: [
                _mediaTab == 'Variations'
                    ? _buildVariationsGallery()
                    : _isGridView
                        ? _buildGridView(images)
                        : _buildPageView(images),
                // Photos/Video/Reviews/Variations tabs overlay
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildMediaTabs(_mediaTab == 'Variations' ? widget.product.variations.length : images.length),
                ),
              ],
            ),
          ),

          // Product Details Section
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: 80), // Space for fixed buttons
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product Name above Colors
                  if (widget.product.variations.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              widget.product.name,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.keyboard_arrow_right,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Color Swatches
                  if (widget.product.variations.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Colors',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            controller: _colorRowScrollController,
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: widget.product.variations.asMap().entries.map((entry) {
                                final index = entry.key;
                                final variation = entry.value;
                                final vColorName = variation['name'] as String? ?? '';
                                final vColor = _getColorFromName(vColorName);
                                final isSelected = vColorName == colorName;

                                // Get first image for this variation
                                String? variationImage;
                                if (variation['allImages'] != null) {
                                  final allImages = variation['allImages'] as List;
                                  if (allImages.isNotEmpty) {
                                    variationImage = allImages.first.toString();
                                  }
                                }
                                if (variationImage == null && variation['image'] != null) {
                                  variationImage = variation['image'].toString();
                                }

                                return GestureDetector(
                                  onTap: () {
                                    _switchVariation(variation);
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 12),
                                    child: Column(
                                      children: [
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 200),
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: isSelected
                                                  ? Theme.of(context).colorScheme.primary
                                                  : Colors.transparent,
                                              width: 2,
                                            ),
                                          ),
                                          child: Container(
                                            width: 60,
                                            height: 60,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(6),
                                              color: Theme.of(context).colorScheme.surface,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.05),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(6),
                                              child: variationImage != null
                                                  ? _buildColorSwatchImage(variationImage)
                                                  : Container(
                                                color: vColor,
                                                child: Center(
                                                  child: Text(
                                                    vColorName.isNotEmpty
                                                        ? vColorName.substring(0, 1).toUpperCase()
                                                        : '?',
                                                    style: TextStyle(
                                                      color: vColor.computeLuminance() > 0.5
                                                          ? Colors.black87
                                                          : Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${index + 1}. $vColorName',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                            color: isSelected ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: Theme.of(context).colorScheme.outline.withOpacity(0.2)),
                  ],

                  // Simple Stock Display (when stockMode is 'simple')
                  if (widget.product.stockMode == 'simple') ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Simple Stock',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.3)),
                                ),
                                child: Text(
                                  'Available: ${widget.product.availableQty}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: Theme.of(context).colorScheme.outline.withOpacity(0.2)),
                  ],

                  // Pricing Tiers
                  if (widget.product.priceSlabs.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pricing',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...widget.product.priceSlabs.map((slab) {
                            final price = slab['price']?.toString() ?? '';
                            final moq = slab['moq'];
                            final moqStr = moq != null ? moq.toString() : '';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '₹$price',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (moqStr.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Min. order: $moqStr pieces',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: Theme.of(context).colorScheme.outline.withOpacity(0.2)),
                  ],

                  // Size Selection
                  if (widget.product.sizes.isNotEmpty) ...[
                    GestureDetector(
                      onTap: () {
                        _openVariationsSheet();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Size (${widget.product.sizes.length})',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Icon(Icons.arrow_forward_ios, size: 16),
                              ],  
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: widget.product.sizes.take(9).map((size) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    size,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            if (widget.product.sizes.length > 9)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '+${widget.product.sizes.length - 9}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Divider(height: 1, color: Theme.of(context).colorScheme.outline.withOpacity(0.2)),
                  ],

                  // Product Description
                  if (widget.product.description.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Text(
                        widget.product.description,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                        ),
                      ),
                    ),
                  ],

                  // Customization
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Customization: Logo/graphic design, Packaging...',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, size: 16),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // Overview/Details/Recommended Tabs
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildTabButton('Overview', _selectedTab == 'Overview'),
                        ),
                        Expanded(
                          child: _buildTabButton('Details', _selectedTab == 'Details'),
                        ),
                        Expanded(
                          child: _buildTabButton('Recommended', _selectedTab == 'Recommended'),
                        ),
                      ],
                    ),
                  ),

                  // Tab Content
                  _buildTabContent(),
                ],
              ),
            ),
          ),

          // Fixed Action Buttons at Bottom
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(/*  */
                      height: 40,
                      child: OutlinedButton(
                        onPressed: _isLoadingChat ? null : _startChat,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.black, width: 1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: _isLoadingChat
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                ),
                              )
                            : const Text(
                                'Chat now',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: ElevatedButton(
                        onPressed: () {
                          _openVariationsSheet();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          elevation: 1,
                        ),
                        child: const Text(
                          'Start Order',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
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

  Widget _buildTabButton(String label, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTab = label;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 'Overview':
        return _buildOverviewTab();
      case 'Details':
        return _buildDetailsTab();
      case 'Recommended':
        return _buildRecommendedTab();
      default:
        return _buildOverviewTab();
    }
  }

  Widget _buildOverviewTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reviews Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Reviews',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios, size: 16),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.black,
                      width: 2,
                    ),
                  ),
                ),
                child: const Text(
                  'Product reviews (0)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Store reviews (0)',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                '5.0',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(width: 8),
              Row(
                children: [
                  Icon(Icons.star, color: Theme.of(context).colorScheme.primary, size: 20),
                  Icon(Icons.star, color: Theme.of(context).colorScheme.primary, size: 20),
                  Icon(Icons.star, color: Theme.of(context).colorScheme.primary, size: 20),
                  Icon(Icons.star, color: Theme.of(context).colorScheme.primary, size: 20),
                  Icon(Icons.star, color: Theme.of(context).colorScheme.primary, size: 20),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'No reviews yet',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Product Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          if (widget.product.description.isNotEmpty) ...[
            Text(
              widget.product.description,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (widget.product.attributes.isNotEmpty) ...[
            Text(
              'Attributes:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            ...widget.product.attributes.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry.key}: ',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        entry.value.join(', '),
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ],
      ),
    );
  }

  Widget _buildRecommendedTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text(
          'Recommended products coming soon',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaTabs(int totalImages) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Photos tab
          GestureDetector(
            onTap: () {
              setState(() {
                _mediaTab = 'Photos';
                _isGridView = false;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _mediaTab == 'Photos' ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _mediaTab == 'Variations' 
                    ? 'Variations ${widget.product.variations.length}'
                    : 'Photos ${_currentImageIndex + 1}/$totalImages',
                style: TextStyle(
                  color: _mediaTab == 'Photos' ? Colors.black : Colors.white,
                  fontSize: 12,
                  fontWeight: _mediaTab == 'Photos' ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Variations tab
          GestureDetector(
            onTap: () {
              setState(() {
                _mediaTab = 'Variations';
              });
              // Scroll color row to show selected color
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final selectedIndex = widget.product.variations.indexWhere((v) =>
                (v['name']?.toString() ?? '') == _currentVariation['name']?.toString()
                );
                if (selectedIndex >= 0 && _colorRowScrollController.hasClients) {
                  // Calculate scroll position: each color item is about 84px wide (60 + 12 margin + 12 padding)
                  final scrollPosition = selectedIndex * 84.0;
                  _colorRowScrollController.animateTo(
                    scrollPosition.clamp(0.0, _colorRowScrollController.position.maxScrollExtent),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              });
              // Don't open the sheet - just show the variations gallery
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _mediaTab == 'Variations' ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'Variations',
                style: TextStyle(
                  color: _mediaTab == 'Variations' ? Colors.black : Colors.white,
                  fontSize: 12,
                  fontWeight: _mediaTab == 'Variations' ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageView(List<String> images) {
    return PageView.builder(
      controller: _pageController,
      onPageChanged: (index) {
        setState(() {
          _currentImageIndex = index;
          print('DEBUG: Page changed to index $index. Total images: ${images.length}');
          
          if (index < images.length) {
            _setImageHeightFor(images[index], index);
          }
        });
      },
      itemCount: images.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onPanEnd: (details) {
            // Detect left swipe (negative dx) when on last image - go to next variation
            if (details.velocity.pixelsPerSecond.dx < -100 && index == images.length - 1) {
              print('DEBUG: User tried to swipe beyond last image. Switching to next variation.');
              _switchToNextVariation();
            }
            // Detect right swipe (positive dx) when on first image - go to previous variation
            if (details.velocity.pixelsPerSecond.dx > 100 && index == 0) {
              print('DEBUG: User tried to swipe before first image. Switching to previous variation.');
              _switchToPreviousVariation();
            }
          },
          child: Container(
            color: Colors.white,
            width: double.infinity,
            height: double.infinity,
            child: _buildImageWidget(images[index], isClickable: true),
          ),
        );
      },
    );
  }

  Widget _buildVariationsPageView() {
    return PageView.builder(
      controller: _variationsPageController,
      onPageChanged: (index) {
        // Switch to variation when swiped
        if (index < widget.product.variations.length) {
          _switchVariation(widget.product.variations[index]);
        }
      },
      itemCount: widget.product.variations.length,
      itemBuilder: (context, index) {
        final variation = widget.product.variations[index];
        final colorName = variation['name'] as String? ?? 'Unknown';
        final color = _getColorFromName(colorName);
        
        // Get all images for this variation
        final variationImages = <String>[];
        if (variation['allImages'] != null) {
          final allImages = variation['allImages'] as List;
          for (var img in allImages) {
            if (img is String && img.isNotEmpty) {
              variationImages.add(img);
            }
          }
        }
        if (variationImages.isEmpty && variation['image'] != null) {
          variationImages.add(variation['image'].toString());
        }
        
        return Column(
          children: [
            // Show current variation's images at top - full screen
            if (variationImages.isNotEmpty) ...[
              Expanded(
                child: GestureDetector(
                  onPanEnd: (details) {
                    // Detect left swipe (negative dx) when on last image - go to next product
                    if (details.velocity.pixelsPerSecond.dx < -100) {
                      print('DEBUG: User tried to swipe beyond last variation. Going to next product.');
                      // Go to next product (not just variation)
                      Navigator.pop(context); // Close current product
                      // You can add navigation to next product here
                    }
                    // Detect right swipe (positive dx) when on first image - go to previous product
                    if (details.velocity.pixelsPerSecond.dx > 100) {
                      print('DEBUG: User tried to swipe before first variation. Going to previous product.');
                      // Go to previous product (not just variation)
                      Navigator.pop(context); // Close current product
                      // You can add navigation to previous product here
                    }
                  },
                  child: Container(
                    color: Colors.white,
                    child: PageView.builder(
                      onPageChanged: (imgIndex) {
                        setState(() {
                          _currentImageIndex = imgIndex;
                        });
                      },
                      itemCount: variationImages.length,
                      itemBuilder: (context, imgIndex) {
                        return Container(
                          color: Colors.white,
                          width: double.infinity,
                          height: double.infinity,
                          child: _buildImageWidget(variationImages[imgIndex], isClickable: false),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildVariationsGallery() {
    return PageView.builder(
      controller: _variationsPageController,
      onPageChanged: (index) {
        // Switch to variation when swiped
        if (index < widget.product.variations.length) {
          _switchVariation(widget.product.variations[index]);
        }
      },
      itemCount: widget.product.variations.length,
      itemBuilder: (context, index) {
        final variation = widget.product.variations[index];
        final colorName = variation['name'] as String? ?? 'Unknown';
        final color = _getColorFromName(colorName);
        
        // Get all images for this variation
        final variationImages = <String>[];
        if (variation['allImages'] != null) {
          final allImages = variation['allImages'] as List;
          for (var img in allImages) {
            if (img is String && img.isNotEmpty) {
              variationImages.add(img);
            }
          }
        }
        if (variationImages.isEmpty && variation['image'] != null) {
          variationImages.add(variation['image'].toString());
        }
        
        return Column(
          children: [
            // Show current variation's images at top - full screen
            if (variationImages.isNotEmpty) ...[
              Expanded(
                child: GestureDetector(
                  onPanEnd: (details) {
                    // Detect left swipe (negative dx) when on last image - go to next product
                    if (details.velocity.pixelsPerSecond.dx < -100) {
                      print('DEBUG: User tried to swipe beyond last variation. Going to next product.');
                      // Go to next product (not just variation)
                      Navigator.pop(context); // Close current product
                      // You can add navigation to next product here
                    }
                    // Detect right swipe (positive dx) when on first image - go to previous product
                    if (details.velocity.pixelsPerSecond.dx > 100) {
                      print('DEBUG: User tried to swipe before first variation. Going to previous product.');
                      // Go to previous product (not just variation)
                      Navigator.pop(context); // Close current product
                      // You can add navigation to previous product here
                    }
                  },
                  child: Container(
                    color: Colors.white,
                    child: PageView.builder(
                      onPageChanged: (imgIndex) {
                        setState(() {
                          _currentImageIndex = imgIndex;
                        });
                      },
                      itemCount: variationImages.length,
                      itemBuilder: (context, imgIndex) {
                        return Container(
                          color: Colors.white,
                          width: double.infinity,
                          height: double.infinity,
                          child: _buildImageWidget(variationImages[imgIndex], isClickable: false),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildGridView(List<String> images) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () {
            setState(() {
              _currentImageIndex = index;
              _isGridView = false;
              _pageController.jumpToPage(index);
            });
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _currentImageIndex == index
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline.withOpacity(0.3),
                width: _currentImageIndex == index ? 2 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: _buildImageWidget(images[index], isClickable: false),
            ),
          ),
        );
      },
    );
  }

  Future<void> _addToCart() async {
    // Get all variations with quantities
    final selectedItems = <Map<String, dynamic>>[];

    if (widget.product.sizes.isNotEmpty) {
      // When sizes exist, process size-based quantities
      for (var entry in _variationSizeQuantities.entries) {
        final colorName = entry.key;
        final sizeQuantities = entry.value;

        for (var sizeEntry in sizeQuantities.entries) {
          final size = sizeEntry.key;
          final quantity = sizeEntry.value;

          if (quantity > 0) {
            // Find variation object
            final variation = widget.product.variations.firstWhere(
                  (v) => (v['name']?.toString() ?? '') == colorName,
              orElse: () => {},
            );

            // Calculate price for this item
            final priceInfo = _getPriceForQuantity(quantity);
            final pricePerItem = priceInfo['price']?.toDouble() ?? 0.0;

            selectedItems.add({
              'variation': variation,
              'size': size,
              'quantity': quantity,
              'price': pricePerItem,
            });
          }
        }
      }
    } else {
      // When no sizes, process color-based quantities
      for (var entry in _variationQuantities.entries) {
        final colorName = entry.key;
        final quantity = entry.value;

        if (quantity > 0) {
          // Find variation object
          final variation = widget.product.variations.firstWhere(
                (v) => (v['name']?.toString() ?? '') == colorName,
            orElse: () => {},
          );

          // Calculate price for this item
          final priceInfo = _getPriceForQuantity(quantity);
          final pricePerItem = priceInfo['price']?.toDouble() ?? 0.0;

          selectedItems.add({
            'variation': variation,
            'size': 'N/A', // No size when only color variations
            'quantity': quantity,
            'price': pricePerItem,
          });
        }
      }
    }

    if (selectedItems.isEmpty) {
      // Show error dialog for better visibility
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.orange, size: 24),
              SizedBox(width: 8),
              Text(
                'Selection Required',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Please select at least one product before adding to cart.',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 12),
              Text(
                'Choose a color and size to continue.',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'OK',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    // Add all items to cart
    for (var item in selectedItems) {
      await CartService.addToCart(
        product: widget.product,
        variation: item['variation'] as Map<String, dynamic>,
        size: item['size'] as String,
        quantity: item['quantity'] as int,
        price: item['price'] as double,
      );
    }

    final totalItems = selectedItems.fold(0, (sum, item) => sum + (item['quantity'] as int));

    // Show immediate confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text('Added $totalItems items to cart'),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'View Cart',
          textColor: Colors.white,
          onPressed: () {
            Navigator.pop(context); // Close variations sheet
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CartScreen(),
              ),
            );
          },
        ),
      ),
    );

    // Auto-close variations sheet after a short delay
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    });

    // Trigger cart count update (if there's a listener)
    setState(() {});
  }

  Map<String, dynamic> _getPriceForQuantity(int totalQty) {
    final priceSlabs = widget.product.priceSlabs;

    if (priceSlabs.isEmpty) {
      return {'price': 0.0, 'moq': 0};
    }

    // Sort price slabs by MOQ (ascending)
    final sortedSlabs = List<Map<String, dynamic>>.from(priceSlabs);
    sortedSlabs.sort((a, b) {
      final moqA = (a['moq'] as num?)?.toInt() ?? 0;
      final moqB = (b['moq'] as num?)?.toInt() ?? 0;
      return moqA.compareTo(moqB);
    });

    // Find the appropriate price slab based on quantity
    Map<String, dynamic>? selectedSlab;
    for (var slab in sortedSlabs.reversed) {
      final moq = (slab['moq'] as num?)?.toInt() ?? 0;
      if (totalQty >= moq) {
        selectedSlab = slab;
        break;
      }
    }

    // If no slab matches, use the first one
    selectedSlab ??= sortedSlabs.first;

    return {
      'price': (selectedSlab['price'] as num?)?.toDouble() ?? 0.0,
      'moq': (selectedSlab['moq'] as num?)?.toInt() ?? 0,
    };
  }

  void _openVariationsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final priceSlabs = widget.product.priceSlabs;
        final sizes = widget.product.sizes;
        final variations = widget.product.variations;

        // Set initial active variation if not set
        if (_activeVariationForSheet == null) {
          _activeVariationForSheet = _currentVariation['name']?.toString() ?? '';
        }

        // Initialize variation size quantities if empty for ALL variations
        for (var variation in variations) {
          final varName = variation['name']?.toString() ?? '';
          if (!_variationSizeQuantities.containsKey(varName)) {
            _variationSizeQuantities[varName] = {};
            // Only initialize sizes if they exist
            if (sizes.isNotEmpty) {
              for (final s in sizes) {
                _variationSizeQuantities[varName]![s] = 0;
              }
            } else {
              // When no sizes, store quantity directly under the variation
              _variationQuantities[varName] = 0;
            }
          }
        }

        print('DEBUG: Opening variations sheet. All quantities: $_variationSizeQuantities');
        print('DEBUG: Active variation in sheet: $_activeVariationForSheet');

        // Helper function to get images for a variation
        List<String> getImagesForVariation(Map<String, dynamic> variation) {
          final List<String> images = [];

          if (variation['allImages'] != null) {
            dynamic allImagesData = variation['allImages'];

            if (allImagesData is String) {
              try {
                final decoded = jsonDecode(allImagesData);
                if (decoded is List) {
                  allImagesData = decoded;
                }
              } catch (e) {
                final s = allImagesData.trim();
                dynamic fallbackList;
                try {
                  final fixed = (s.startsWith('[') && !s.endsWith(']')) ? '$s]' : s;
                  final decodedFixed = jsonDecode(fixed);
                  if (decodedFixed is List) {
                    fallbackList = decodedFixed;
                  }
                } catch (_) {
                  final cleaned = s
                      .replaceAll('[', '')
                      .replaceAll(']', '')
                      .replaceAll('"', '')
                      .replaceAll("'", '');
                  final parts = cleaned
                      .split(RegExp(r'[,\s]+'))
                      .where((p) => p.isNotEmpty)
                      .toList();
                  if (parts.isNotEmpty) {
                    fallbackList = parts;
                  }
                }
                if (fallbackList is List) {
                  allImagesData = fallbackList;
                }
              }
            }

            if (allImagesData is List) {
              for (var img in allImagesData) {
                if (img is String && img.isNotEmpty) {
                  images.add(img);
                } else if (img != null) {
                  images.add(img.toString());
                }
              }
            }
          }

          if (images.isEmpty && variation['image'] != null) {
            final img = variation['image'];
            if (img is String && img.isNotEmpty) {
              images.add(img);
            }
          }

          return images;
        }

        // Get active variation's size quantities
        Map<String, int> getActiveSizeQuantities() {
          final selectedVarName = _activeVariationForSheet ?? '';
          if (!_variationSizeQuantities.containsKey(selectedVarName)) {
            _variationSizeQuantities[selectedVarName] = {};
            for (final s in sizes) {
              _variationSizeQuantities[selectedVarName]![s] = 0;
            }
          }
          return _variationSizeQuantities[selectedVarName] ?? {};
        }

        // Function to get quantity for a variation
        int getVariationQty(String varName) {
          if (sizes.isNotEmpty) {
            // When sizes exist, sum up all size quantities for this variation
            final varSizes = _variationSizeQuantities[varName] ?? {};
            return varSizes.values.fold(0, (a, b) => a + b);
          } else {
            // When no sizes, get direct variation quantity
            return _variationQuantities[varName] ?? 0;
          }
        }

        // Get available stock for a color-size combination
        int getAvailableStock(String colorName, String size) {
          if (widget.product.stockMode == 'always_available') {
            return 999999;
          }
          if (widget.product.stockMode != 'color_size' || widget.product.stockByColorSize == null) {
            return 0;
          }
          final colorStock = widget.product.stockByColorSize![colorName];
          if (colorStock == null) return 0;
          return colorStock[size] ?? 0;
        }

        // Get remaining available stock after subtracting selected quantities
        int getRemainingStock(String colorName, String size) {
          if (widget.product.stockMode == 'always_available') {
            return 999999;
          }
          final available = getAvailableStock(colorName, size);
          final selected = _variationSizeQuantities[colorName]?[size] ?? 0;
          return (available - selected).clamp(0, available).toInt();
        }

        // Check if a color-size combination is out of stock
        bool isOutOfStock(String colorName, String size) {
          if (widget.product.stockMode == 'always_available') {
            return false;
          }
          return getRemainingStock(colorName, size) <= 0;
        }

        // Get available stock for a color-only variation
        int getAvailableStockForColor(String colorName) {
          if (widget.product.stockMode == 'always_available') {
            return 999999;
          }
          if (widget.product.stockMode == 'simple') {
            return int.tryParse(widget.product.availableQty) ?? 0;
          }
          if (widget.product.stockMode != 'color_size' || widget.product.stockByColorSize == null) {
            return 0;
          }
          final colorStock = widget.product.stockByColorSize![colorName];
          if (colorStock == null) return 0;
          // Sum all sizes for this color
          return colorStock.values.fold(0, (a, b) => (a as int) + (b as int));
        }

        // Get remaining available stock for a color-only variation
        int getRemainingStockForColor(String colorName) {
          if (widget.product.stockMode == 'always_available') {
            return 999999;
          }
          final available = getAvailableStockForColor(colorName);
          final selected = _variationQuantities[colorName] ?? 0;
          return (available - selected).clamp(0, available).toInt();
        }

        // Check if a color-only variation is out of stock
        bool isColorOutOfStock(String colorName) {
          if (widget.product.stockMode == 'always_available') {
            return false;
          }
          return getRemainingStockForColor(colorName) <= 0;
        }

        // Get total selected quantity across all variations and sizes
        int getTotalSelectedQuantity() {
          int total = 0;
          if (sizes.isNotEmpty) {
            // When sizes exist, sum all size quantities
            for (var varName in _variationSizeQuantities.keys) {
              final sizes = _variationSizeQuantities[varName] ?? {};
              total += sizes.values.fold<int>(0, (a, b) => a + (b as int));
            }
          } else {
            // When no sizes, sum all variation quantities
            for (var varName in _variationQuantities.keys) {
              total += _variationQuantities[varName] ?? 0;
            }
          }
          return total;
        }

        // Get remaining simple stock
        int getRemainingSimpleStock() {
          if (widget.product.stockMode == 'always_available') {
            return 999999;
          }
          if (widget.product.stockMode != 'simple') return 0;
          final totalAvailable = int.tryParse(widget.product.availableQty) ?? 0;
          final selected = getTotalSelectedQuantity();
          return (totalAvailable - selected).clamp(0, totalAvailable);
        }

        // Check if simple stock is out
        bool isSimpleStockOut() {
          if (widget.product.stockMode == 'always_available') {
            return false;
          }
          if (widget.product.stockMode != 'simple') return false;
          return getRemainingSimpleStock() <= 0;
        }

        // Get price based on total quantity
        Map<String, dynamic> getPriceForQuantity(int totalQty) {
          return _getPriceForQuantity(totalQty);
        }

        // Calculate subtotal for ALL variations
        double calcSubtotal() {
          int totalQty = getTotalSelectedQuantity();
          final priceInfo = getPriceForQuantity(totalQty);
          return priceInfo['price'] * totalQty;
        }

        _subtotal = calcSubtotal();

        return StatefulBuilder(
          builder: (context, setModalState) {
            // Get active variation size quantities
            Map<String, int> getActiveSizeQuantitiesLocal() {
              final selectedVarName = _activeVariationForSheet ?? '';
              if (!_variationSizeQuantities.containsKey(selectedVarName)) {
                _variationSizeQuantities[selectedVarName] = {};
                for (final s in sizes) {
                  _variationSizeQuantities[selectedVarName]![s] = 0;
                }
              }
              return _variationSizeQuantities[selectedVarName] ?? {};
            }

            final activeSizes = getActiveSizeQuantitiesLocal();
            final totalPieces = activeSizes.values.fold(0, (a, b) => a + b);

            // Get active variation object
            final activeVariationObj = variations.firstWhere(
                  (v) => (v['name']?.toString() ?? '') == _activeVariationForSheet,
              orElse: () => _currentVariation,
            );

            // Get images for active variation
            final activeVariationImages = getImagesForVariation(activeVariationObj);

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.75,
              maxChildSize: 0.85,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    // Compact header
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 8, bottom: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // Compact header with X button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Product name and price
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.product.stockMode == 'color_size'
                                      ? 'Variations - Color Size Stock'
                                      : 'Variations',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
                                ),
                                if (widget.product.stockMode == 'color_size') ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Available stock shown for each size',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 24),
                            onPressed: () => Navigator.pop(context),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    // Product image and price section - WITH ACTIVE VARIATION IMAGE
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Product thumbnail image (based on active variation)
                          GestureDetector(
                            onTap: () {
                              if (activeVariationImages.isNotEmpty) {
                                _openImageViewer(activeVariationImages[0], _activeVariationForSheet ?? '', priceSlabs);
                              }
                            },
                            child: Stack(
                              children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: activeVariationImages.isNotEmpty
                                        ? _buildColorSwatchImage(activeVariationImages[0])
                                        : Container(color: Colors.grey.shade200),
                                  ),
                                ),
                                // Expand icon on top left
                                Positioned(
                                  top: 4,
                                  left: 4,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.8),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.open_in_full,
                                      size: 14,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                // Variation name at bottom
                                if (_activeVariationForSheet != null && _activeVariationForSheet!.isNotEmpty)
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.6),
                                        borderRadius: const BorderRadius.only(
                                          bottomLeft: Radius.circular(8),
                                          bottomRight: Radius.circular(8),
                                        ),
                                      ),
                                      child: Text(
                                        _activeVariationForSheet!,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Pricing tiers on right - slidable
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: priceSlabs.asMap().entries.map((entry) {
                                  final idx = entry.key;
                                  final slab = entry.value;
                                  final price = slab['price']?.toString() ?? '';
                                  final moq = slab['moq'];
                                  final moqNum = (moq as num?)?.toInt() ?? 0;
                                  final isActive = totalPieces >= moqNum && moqNum > 0;
                                  final label = moqNum > 0
                                      ? (idx == 0 ? 'Min. order:$moqNum pieces' : '${moqNum}+ pieces')
                                      : 'Min. order';
                                  return Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: isActive ? Colors.orange : Colors.grey.shade300,
                                        width: isActive ? 1.5 : 1,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '₹${double.tryParse(price)?.toStringAsFixed(2) ?? price}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: isActive ? Colors.orange : Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          label,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isActive ? Colors.orange.shade700 : Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Color grid header
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.product.stockMode == 'color_size'
                                              ? 'Color (${variations.length}) - Color Size Stock'
                                              : 'Color (${variations.length})',
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                        ),
                                        if (widget.product.stockMode == 'color_size') ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'Stock available for each color-size combination',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () {
                                          setModalState(() {
                                            _isColorList = true;
                                          });
                                        },
                                        icon: const Icon(Icons.view_list, size: 18),
                                        label: const Text('List'),
                                      ),
                                      TextButton.icon(
                                        onPressed: () {
                                          setModalState(() {
                                            _isColorList = false;
                                          });
                                        },
                                        icon: const Icon(Icons.photo_library_outlined, size: 18),
                                        label: const Text('Gallery'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Color selection grid
                              Builder(
                                builder: (context) {
                                  final count = variations.length;
                                  if (_isColorList) {
                                    return SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: variations.map((variation) {
                                          final vColorName = variation['name']?.toString() ?? '';
                                          final isSelected = vColorName == _activeVariationForSheet;
                                          final selectedQty = getVariationQty(vColorName);

                                          return GestureDetector(
                                            onTap: () {
                                              setModalState(() {
                                                _activeVariationForSheet = vColorName;
                                                _subtotal = calcSubtotal();
                                              });
                                            },
                                            child: Container(
                                              margin: const EdgeInsets.only(right: 8),
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: isSelected ? Colors.orange : Colors.grey.shade300,
                                                  width: isSelected ? 2 : 1,
                                                ),
                                                color: Colors.white,
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    vColorName,
                                                    style: const TextStyle(fontSize: 12),
                                                  ),
                                                  if (selectedQty > 0) ...[
                                                    const SizedBox(width: 4),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.red,
                                                        borderRadius: BorderRadius.circular(10),
                                                      ),
                                                      child: Text(
                                                        '$selectedQty',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    );
                                  }

                                  final gridCount = count > 6 ? 7 : count;
                                  return GridView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 4,
                                      crossAxisSpacing: 4,
                                      mainAxisSpacing: 8,
                                      childAspectRatio: 0.75,
                                    ),
                                    itemCount: gridCount,
                                    itemBuilder: (context, index) {
                                      final isMoreTile = count > 6 && index == 6;
                                      if (isMoreTile) {
                                        return GestureDetector(
                                          onTap: () {
                                            setModalState(() {
                                              _isColorList = true;
                                            });
                                          },
                                          child: Container(
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.grey.shade300),
                                            ),
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.add,
                                                  size: 32,
                                                  color: Colors.grey.shade600,
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  '${count - 6} more',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade600,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }

                                      final variation = variations[index];
                                      final vColorName = variation['name']?.toString() ?? '';
                                      final isSelected = vColorName == _activeVariationForSheet;
                                      final selectedQty = getVariationQty(vColorName);

                                      // Get image for this variation
                                      final variationImages = getImagesForVariation(variation);
                                      String? variationImage;
                                      if (variationImages.isNotEmpty) {
                                        variationImage = variationImages[0];
                                      } else if (variation['image'] != null) {
                                        variationImage = variation['image'].toString();
                                      }

                                      return GestureDetector(
                                        onTap: () {
                                          setModalState(() {
                                            _activeVariationForSheet = vColorName;
                                            _subtotal = calcSubtotal();
                                          });
                                        },
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Stack(
                                              children: [
                                                Container(
                                                  width: double.infinity,
                                                  height: 90,
                                                  decoration: BoxDecoration(
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: isSelected ? Colors.orange : Colors.grey.shade300,
                                                      width: isSelected ? 2 : 1,
                                                    ),
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: variationImage != null
                                                        ? GestureDetector(
                                                            onDoubleTap: () {
                                                              if (variationImage != null) {
                                                                _openImageViewer(variationImage!, vColorName, priceSlabs);
                                                              }
                                                            },
                                                            child: Stack(
                                                              children: [
                                                                Positioned.fill(
                                                                  child: _buildColorSwatchImage(variationImage!),
                                                                ),
                                                                Positioned(
                                                                  top: 2,
                                                                  left: 2,
                                                                  child: GestureDetector(
                                                                    onTap: () {
                                                                      if (variationImage != null) {
                                                                        _openImageViewer(variationImage!, vColorName, priceSlabs);
                                                                      }
                                                                    },
                                                                    child: Container(
                                                                      padding: const EdgeInsets.all(2),
                                                                      decoration: BoxDecoration(
                                                                        color: Colors.white.withOpacity(0.7),
                                                                        shape: BoxShape.circle,
                                                                      ),
                                                                      child: const Icon(
                                                                        Icons.open_in_full,
                                                                        size: 10,
                                                                        color: Colors.black87,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                                Positioned(
                                                                  bottom: 0,
                                                                  left: 0,
                                                                  right: 0,
                                                                  child: Container(
                                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                                                    decoration: BoxDecoration(
                                                                      color: Colors.black.withOpacity(0.6),
                                                                      borderRadius: const BorderRadius.only(
                                                                        bottomLeft: Radius.circular(7),
                                                                        bottomRight: Radius.circular(7),
                                                                      ),
                                                                    ),
                                                                    child: Text(
                                                                      vColorName,
                                                                      textAlign: TextAlign.center,
                                                                      overflow: TextOverflow.ellipsis,
                                                                      style: const TextStyle(
                                                                        fontSize: 11,
                                                                        fontWeight: FontWeight.w600,
                                                                        color: Colors.white,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          )
                                                        : Container(color: Colors.grey.shade200),
                                                  ),
                                                ),
                                                if (selectedQty > 0)
                                                  Positioned(
                                                    top: 4,
                                                    right: 4,
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.red,
                                                        borderRadius: BorderRadius.circular(10),
                                                      ),
                                                      child: Text(
                                                        '$selectedQty',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                              const SizedBox(height: 2),
                              // Size selection header - Show different text when no sizes
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    sizes.isEmpty
                                        ? 'Quantity Selection'
                                        : widget.product.stockMode == 'color_size'
                                        ? 'Size (${sizes.length}) - Color Size Stock'
                                        : widget.product.stockMode == 'always_available'
                                        ? 'Size (${sizes.length}) - Always Available'
                                        : 'Size (${sizes.length})',
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Size selection with steppers OR color-based quantity selection
                              sizes.isEmpty
                                  ? // When no sizes, show quantity selector for active color
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: isColorOutOfStock(_activeVariationForSheet!)
                                        ? Colors.red.shade300
                                        : widget.product.stockMode == 'always_available'
                                        ? Colors.green.shade300
                                        : Colors.grey.shade300,
                                    width: isColorOutOfStock(_activeVariationForSheet!) ? 2 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  color: isColorOutOfStock(_activeVariationForSheet!)
                                      ? Colors.red.shade50
                                      : widget.product.stockMode == 'always_available'
                                      ? Colors.green.shade50
                                      : Colors.grey.shade50,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _activeVariationForSheet ?? 'Selected Color',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: isColorOutOfStock(_activeVariationForSheet!)
                                                  ? Colors.red.shade700
                                                  : Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          if (widget.product.stockMode == 'simple' || 
                                              widget.product.stockMode == 'color_size' || 
                                              widget.product.stockMode == 'always_available') ...[
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: widget.product.stockMode == 'always_available'
                                                      ? Row(
                                                    children: [
                                                      Icon(
                                                        Icons.check_circle,
                                                        size: 14,
                                                        color: Colors.green.shade700,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        'Always Available',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.green.shade700,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  )
                                                      : Text(
                                                    widget.product.stockMode == 'simple'
                                                        ? 'Available: ${getRemainingStockForColor(_activeVariationForSheet!)} (Simple Stock)'
                                                        : 'Available: ${getRemainingStockForColor(_activeVariationForSheet!)}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: isColorOutOfStock(_activeVariationForSheet!)
                                                          ? Colors.red.shade700
                                                          : Colors.green.shade700,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (isColorOutOfStock(_activeVariationForSheet!) && 
                                                    widget.product.stockMode != 'always_available') ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.red.shade700,
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: const Text(
                                                      'Out of Stock',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        IconButton(
                                          onPressed: () {
                                            final currentQty = _variationQuantities[_activeVariationForSheet] ?? 0;
                                            if (currentQty > 0) {
                                              setModalState(() {
                                                _variationQuantities[_activeVariationForSheet!] = currentQty - 1;
                                                _subtotal = calcSubtotal();
                                              });
                                              setState(() {}); // Update cart count in real-time
                                            }
                                          },
                                          icon: const Icon(Icons.remove_circle_outline),
                                        ),
                                        Text(
                                          '${_variationQuantities[_activeVariationForSheet] ?? 0}',
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                        IconButton(
                                          onPressed: isColorOutOfStock(_activeVariationForSheet!) ||
                                                  widget.product.stockMode != 'always_available' &&
                                                  getRemainingStockForColor(_activeVariationForSheet!) <= 0
                                              ? null
                                              : () {
                                                final currentQty = _variationQuantities[_activeVariationForSheet] ?? 0;
                                                setModalState(() {
                                                  _variationQuantities[_activeVariationForSheet!] = currentQty + 1;
                                                  _subtotal = calcSubtotal();
                                                });
                                                setState(() {}); // Update cart count in real-time
                                              },
                                          icon: Icon(
                                            Icons.add_circle_outline,
                                            color: isColorOutOfStock(_activeVariationForSheet!) ||
                                                    widget.product.stockMode != 'always_available' &&
                                                    getRemainingStockForColor(_activeVariationForSheet!) <= 0
                                                ? Colors.grey.shade400
                                                : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              )
                                  : // When sizes exist, show original size selection
                              Column(
                                children: sizes.map((s) {
                                  final qty = activeSizes[s] ?? 0;
                                  final availableStock = widget.product.stockMode == 'color_size'
                                      ? getAvailableStock(_activeVariationForSheet!, s)
                                      : null;
                                  final remainingStock = widget.product.stockMode == 'color_size'
                                      ? getRemainingStock(_activeVariationForSheet!, s)
                                      : getRemainingSimpleStock();
                                  final stockOut = widget.product.stockMode == 'always_available'
                                      ? false
                                      : widget.product.stockMode == 'color_size'
                                      ? isOutOfStock(_activeVariationForSheet!, s)
                                      : isSimpleStockOut();
                                  final isAlwaysAvailable = widget.product.stockMode == 'always_available';
                                  final effectiveStockOut = isAlwaysAvailable ? false : stockOut;

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: effectiveStockOut
                                            ? Colors.red.shade300
                                            : isAlwaysAvailable
                                            ? Colors.green.shade300
                                            : Colors.grey.shade300,
                                        width: effectiveStockOut ? 2 : 1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      color: effectiveStockOut
                                          ? Colors.red.shade50
                                          : isAlwaysAvailable
                                          ? Colors.green.shade50
                                          : Colors.transparent,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                s,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: effectiveStockOut
                                                      ? Colors.red.shade700
                                                      : Colors.black87,
                                                ),
                                              ),
                                              if (widget.product.stockMode == 'simple' || availableStock != null || isAlwaysAvailable) ...[
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: isAlwaysAvailable
                                                          ? Row(
                                                        children: [
                                                          Icon(
                                                            Icons.check_circle,
                                                            size: 14,
                                                            color: Colors.green.shade700,
                                                          ),
                                                          const SizedBox(width: 4),
                                                          Text(
                                                            'Always Available',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: Colors.green.shade700,
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                          ),
                                                        ],
                                                      )
                                                          : Text(
                                                        widget.product.stockMode == 'simple'
                                                            ? 'Available: $remainingStock (Simple Stock)'
                                                            : 'Available: $remainingStock',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: stockOut
                                                              ? Colors.red.shade700
                                                              : Colors.green.shade700,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    if (stockOut && !isAlwaysAvailable) ...[
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: Colors.red.shade700,
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: const Text(
                                                          'Out of Stock',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: Colors.white,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            IconButton(
                                              onPressed: () {
                                                if (qty > 0) {
                                                  setModalState(() {
                                                    _variationSizeQuantities[_activeVariationForSheet!]![s] = qty - 1;
                                                    _subtotal = calcSubtotal();
                                                  });
                                                  setState(() {}); // Update cart count in real-time
                                                }
                                              },
                                              icon: const Icon(Icons.remove_circle_outline),
                                            ),
                                            Text(
                                              '$qty',
                                              style: const TextStyle(fontWeight: FontWeight.w600),
                                            ),
                                            IconButton(
                                              onPressed: effectiveStockOut
                                                  ? null
                                                  : () {
                                                if (isAlwaysAvailable) {
                                                  setModalState(() {
                                                    _variationSizeQuantities[_activeVariationForSheet!]![s] = qty + 1;
                                                    _subtotal = calcSubtotal();
                                                  });
                                                } else {
                                                  final remaining = widget.product.stockMode == 'color_size'
                                                      ? getRemainingStock(_activeVariationForSheet!, s)
                                                      : getRemainingSimpleStock();
                                                  if (remaining > 0) {
                                                    setModalState(() {
                                                      _variationSizeQuantities[_activeVariationForSheet!]![s] = qty + 1;
                                                      _subtotal = calcSubtotal();
                                                    });
                                                  }
                                                }
                                                setState(() {}); // Update cart count in real-time
                                              },
                                              icon: Icon(
                                                Icons.add_circle_outline,
                                                color: effectiveStockOut
                                                    ? Colors.grey.shade400
                                                    : null,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),

                              const SizedBox(height: 8),

                              // Selected sizes summary for active variation
                              Builder(
                                builder: (context) {
                                  if (sizes.isEmpty) {
                                    // When no sizes, show color quantity summary
                                    final selectedQty = _variationQuantities[_activeVariationForSheet] ?? 0;
                                    if (selectedQty > 0) {
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Selected for $_activeVariationForSheet:',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade50,
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(color: Colors.blue.shade300),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text('Quantity: $selectedQty'),
                                                const SizedBox(width: 4),
                                                GestureDetector(
                                                  onTap: () {
                                                    setModalState(() {
                                                      _variationQuantities[_activeVariationForSheet!] = 0;
                                                      _subtotal = calcSubtotal();
                                                    });
                                                    setState(() {}); // Update cart count in real-time
                                                  },
                                                  child: Icon(
                                                    Icons.clear,
                                                    size: 16,
                                                    color: Colors.red.shade600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      );
                                    }
                                  } else {
                                    // When sizes exist, show size-based summary
                                    final selectedSizes = sizes.where((s) => (activeSizes[s] ?? 0) > 0).toList();
                                    if (selectedSizes.isNotEmpty) {
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Selected for $_activeVariationForSheet:',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: selectedSizes.map((s) {
                                              final q = activeSizes[s]!;
                                              return Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.shade50,
                                                  borderRadius: BorderRadius.circular(20),
                                                  border: Border.all(color: Colors.blue.shade300),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text('$s � $q'),
                                                    const SizedBox(width: 4),
                                                    GestureDetector(
                                                      onTap: () {
                                                        setModalState(() {
                                                          _variationSizeQuantities[_activeVariationForSheet!]![s] = 0;
                                                          _subtotal = calcSubtotal();
                                                        });
                                                        setState(() {}); // Update cart count in real-time
                                                      },
                                                      child: Icon(
                                                        Icons.clear,
                                                        size: 16,
                                                        color: Colors.red.shade600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ],
                                      );
                                    }
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Bottom subtotal and actions
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, -2)),
                        ],
                      ),
                      child: SafeArea(
                        top: false,
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Subtotal: ₹${_subtotal.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Total items: ${getTotalSelectedQuantity()}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 40,
                              child: OutlinedButton(
                                onPressed: () async {
                                  await _addToCart();
                                },
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  side: const BorderSide(color: Colors.blue),
                                ),
                                child: const Text('Add to cart', style: TextStyle(color: Colors.blue)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 40,
                              child: ElevatedButton(
                                onPressed: () {
                                  // Check if any product is selected before proceeding
                                  final totalSelected = getTotalSelectedQuantity();
                                  
                                  if (totalSelected == 0) {
                                    // Show validation dialog
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: Row(
                                          children: [
                                            Icon(Icons.warning, color: Colors.orange, size: 24),
                                            SizedBox(width: 8),
                                            Text(
                                              'No Products Selected',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.red,
                                              ),
                                            ),
                                          ],
                                        ),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Please select at least one product before starting order.',
                                              style: TextStyle(fontSize: 16),
                                            ),
                                            SizedBox(height: 12),
                                            Text(
                                              'Choose color and size to continue.',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context),
                                            child: Text(
                                              'OK',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                    return; // Don't proceed to checkout
                                  }
                                  
                                  final sizes = widget.product.sizes;
                                  
                                  if (sizes.isNotEmpty) {
                                    // With sizes - pass variationSizeQuantities
                                    final Map<String, Map<String, int>> variationSizeQuantities = {};
                                    final Map<String, String> variationImages = {};
                                    
                                    for (final variation in variations) {
                                      final varName = variation['name']?.toString() ?? '';
                                      final varSizes = _variationSizeQuantities[varName] ?? {};
                                      
                                      // Only include variations with quantity > 0
                                      final hasQuantity = varSizes.values.any((q) => q > 0);
                                      if (hasQuantity) {
                                        variationSizeQuantities[varName] = Map<String, int>.from(varSizes);
                                        // Get image for this variation
                                        final varImages = getImagesForVariation(variation);
                                        if (varImages.isNotEmpty) {
                                          variationImages[varName] = varImages[0];
                                        } else if (variation['image'] != null) {
                                          variationImages[varName] = variation['image'].toString();
                                        }
                                      }
                                    }
                                    
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => CheckoutScreen(
                                          product: widget.product,
                                          variationSizeQuantities: variationSizeQuantities,
                                          variationImages: variationImages,
                                          availableSizes: sizes,
                                          totalPrice: _subtotal,
                                        ),
                                      ),
                                    );
                                  } else {
                                    // Without sizes - pass selectedVariations (original behavior)
                                    final Map<String, int> selectedVariations = {};
                                    final Map<String, String> variationImages = {};
                                    
                                    for (final variation in variations) {
                                      final varName = variation['name']?.toString() ?? '';
                                      final qty = getVariationQty(varName);
                                      if (qty > 0) {
                                        selectedVariations[varName] = qty;
                                        // Get image for this variation
                                        final varImages = getImagesForVariation(variation);
                                        if (varImages.isNotEmpty) {
                                          variationImages[varName] = varImages[0];
                                        } else if (variation['image'] != null) {
                                          variationImages[varName] = variation['image'].toString();
                                        }
                                      }
                                    }
                                    
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => CheckoutScreen(
                                          product: widget.product,
                                          selectedVariations: selectedVariations,
                                          variationImages: variationImages,
                                          totalPrice: _subtotal,
                                        ),
                                      ),
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Start order'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _openImageViewer(String imageUrl, String colorName, List<Map<String, dynamic>> priceSlabs) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            color: Colors.black,
            child: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: imageUrl.startsWith('http')
                        ? Image.network(imageUrl, fit: BoxFit.contain)
                        : Image.file(File(imageUrl), fit: BoxFit.contain),
                  ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Positioned(
                    bottom: 24,
                    left: 16,
                    right: 16,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          colorName,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: priceSlabs.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final slab = entry.value;
                              final price = slab['price']?.toString() ?? '';
                              final moqNum = (slab['moq'] as num?)?.toInt() ?? 0;
                              final label = moqNum > 0
                                  ? (idx == 0 ? 'Min. order:$moqNum pieces' : '${moqNum}+ pieces')
                                  : 'Min. order';
                              return Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '₹${double.tryParse(price)?.toStringAsFixed(2) ?? price}',
                                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      label,
                                      style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Check if current user is the seller of this product
  bool _isCurrentUserSeller() {
    // Get current user ID from auth service (Hive box)
    final authBox = Hive.box('authBox');
    final currentUserId = authBox.get('userId');
    
    // If current user is the one who published this product, hide chat button
    if (currentUserId == widget.product.userId) {
      return true; // Current user is seller
    }
    
    return false; // Current user is not seller (buyer)
  }

  // Start chat with seller
  void _startChat() async {
    if (_isLoadingChat) return;

    setState(() {
      _isLoadingChat = true;
    });

    try {
      // Create or get chat room for this product
      final chatService = MarketplaceChatService();
      
      // Get current user ID from auth service (Hive box)
      final authBox = Hive.box('authBox');
      final currentUserId = authBox.get('userId') ?? 1; // Fallback to 1 if not found
      
      // Get seller ID from product (userId is the seller/creator)
      final sellerId = widget.product.userId;
      
      // Check if current user is trying to chat with themselves (seller chatting with seller)
      if (currentUserId == sellerId) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You cannot chat with yourself - you are the seller of this product'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      
      print('Starting chat - User ID: $currentUserId, Seller ID: $sellerId, Product ID: ${widget.product.id}');
      
      // Initialize socket connection
      await chatService.initializeSocket(currentUserId);
      
      // Create chat room for this product
      final chatRoom = await chatService.createOrGetChatRoom(
        productId: widget.product.id!,
        buyerId: currentUserId,
        sellerId: sellerId,
      );
      
      if (chatRoom != null && mounted) {
        // Navigate to main chat screen with marketplace chat integration
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              chatId: chatRoom.id,
              otherUserId: widget.product.userId == currentUserId 
                  ? chatRoom.buyerId 
                  : chatRoom.sellerId,
              otherUserName: widget.product.userId == currentUserId 
                  ? "Buyer" 
                  : "Seller",
              isMarketplaceChat: true, // ✅ Enable marketplace chat
              marketplaceChatRoom: chatRoom, // ✅ Pass chat room data
              product: widget.product, // ✅ Pass product info
            ),
          ),
        );
      }
    } catch (e) {
      print('Error starting chat: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error starting chat: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingChat = false;
        });
      }
    }
  }
}

// Full Screen Image Viewer
class _FullScreenImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _FullScreenImageViewer({
    required this.images,
    required this.initialIndex,
  });

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildImage(String imagePath) {
    final bool isNetwork = imagePath.startsWith('http://') || imagePath.startsWith('https://');

    ImageProvider imageProvider;
    if (isNetwork) {
      imageProvider = CachedNetworkImageProvider(imagePath);
    } else {
      imageProvider = FileImage(File(imagePath));
    }

    return PhotoView(
      imageProvider: imageProvider,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      minScale: PhotoViewComputedScale.contained * 0.8,
      maxScale: PhotoViewComputedScale.covered * 4.0,
      initialScale: PhotoViewComputedScale.contained,
      loadingBuilder: (context, event) {
        if (event == null) {
          return Container(color: Colors.black);
        }
        final progress = event.cumulativeBytesLoaded / (event.expectedTotalBytes ?? 1);
        return Stack(
          children: [
            Container(color: Colors.black),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      errorBuilder: (context, error, stackTrace) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 50),
            const SizedBox(height: 16),
            const Text(
              'Failed to load image',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return _buildImage(widget.images[index]);
            },
          ),
          // Close button
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),
          ),
          // Image counter
          if (widget.images.length > 1)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_currentIndex + 1}/${widget.images.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Left arrow for previous
          if (widget.images.length > 1 && _currentIndex > 0)
            SafeArea(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          // Right arrow for next
          if (widget.images.length > 1 && _currentIndex < widget.images.length - 1)
            SafeArea(
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_forward, color: Colors.white),
                      onPressed: () {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
