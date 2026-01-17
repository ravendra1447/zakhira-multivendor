import 'dart:io';
import 'dart:ui'; // Added for ImageFilter
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/product.dart';

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
  double _imageHeight = 0.4; // Initial image height as fraction of screen
  final Map<int, double> _imageAspectRatios = {}; // Cache aspect ratios for images
  final Map<String, int> _sizeQuantities = {}; // For variations sheet size quantities
  final Map<String, int> _variationQuantities = {}; // Track quantities per variation
  final Map<String, Map<String, int>> _variationSizeQuantities = {}; // Track sizes per variation: {variationName: {size: qty}}
  double _subtotal = 0.0;
  bool _isColorList = false;
  bool _hasOpenedVariationsFromSlide = false; // Track if variations was opened from slide
  Set<int> _viewedImageIndices = {}; // Track which images have been viewed
  Timer? _swipeTimer; // Timer to detect swipe beyond last image

  @override
  void initState() {
    super.initState();
    _currentVariation = widget.variation;
    _currentImageIndex = widget.initialImageIndex;
    final images = _getAllImages();
    _pageController = PageController(initialPage: _currentImageIndex);
    _scrollController.addListener(_onScroll);
    
    // Initialize viewed images with the starting image
    _viewedImageIndices.add(_currentImageIndex);
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
    _scrollController.dispose();
    _colorRowScrollController.dispose();
    _swipeTimer?.cancel();
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
            print('⚠️ allImages JSON malformed, applied fallback parsing');
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

      print('📸 Found ${images.length} images in variation ${_currentVariation['name']}');
    }

    // Fallback to single image if allImages not available
    if (images.isEmpty && _currentVariation['image'] != null) {
      final img = _currentVariation['image'];
      if (img is String && img.isNotEmpty) {
        images.add(img);
        print('📸 Using single image fallback');
      }
    }

    print('📸 Total images to display: ${images.length}');
    return images;
  }

  void _switchVariation(Map<String, dynamic> variation) {
    setState(() {
      _currentVariation = variation;
      _currentImageIndex = 0;
      _isGridView = false;
      _mediaTab = 'Photos';
      final images = _getAllImages();
      _pageController = PageController(initialPage: 0);
      if (images.isNotEmpty) {
        _setImageHeightFor(images[0], 0);
      }
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
      return Image.network(
        imagePath,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: Colors.grey.shade200,
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                    loadingProgress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey.shade300,
            child: const Icon(Icons.broken_image, color: Colors.grey, size: 20),
          );
        },
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
              color: Colors.grey.shade300,
              child: const Icon(Icons.broken_image, color: Colors.grey, size: 20),
            );
          },
        );
      }
    } catch (e) {
      print("Error checking file: $imagePath - $e");
    }
    return Container(
      color: Colors.grey.shade300,
      child: const Icon(Icons.broken_image, color: Colors.grey, size: 20),
    );
  }

  Widget _buildImageWidget(String imagePath, {bool isClickable = true}) {
    final bool isNetwork = imagePath.startsWith('http://') || imagePath.startsWith('https://');

    Widget buildImage({required BoxFit fit}) {
      if (isNetwork) {
        return Image.network(
          imagePath,
          fit: fit,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                    loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
              child: const Icon(Icons.broken_image, color: Colors.grey, size: 40),
            );
          },
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
                child: const Icon(Icons.broken_image, color: Colors.grey, size: 40),
              );
            },
          );
        }
      } catch (e) {}

      return const Icon(Icons.broken_image, color: Colors.grey);
    }

    Widget imageContent = Stack(
      fit: StackFit.expand,
      children: [
        // Background with blur
        if (isNetwork)
          Image.network(
            imagePath,
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) => Container(color: Colors.white),
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
                    errorBuilder: (c, e, s) => Container(color: Colors.white),
                  );
                }
              } catch (e) {}
              return Container(color: Colors.white);
            },
          ),

        // Blur Effect Overlay
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: Colors.white.withOpacity(0.6),
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
        final stream = NetworkImage(imagePath).resolve(const ImageConfiguration());
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
    if (_imageHeight == 0.4) {
      final screen = MediaQuery.of(context).size;
      _imageHeight = screen.height * 0.50;
      if (images.isNotEmpty) {
        // Kick off aspect resolution for initial image
        _setImageHeightFor(images[_currentImageIndex], _currentImageIndex);
      }
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const Icon(Icons.search, color: Colors.black),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.product.name,
                style: const TextStyle(
                  color: Colors.black,
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
              color: Colors.black,
            ),
            onPressed: () {
              setState(() {
                _isGridView = !_isGridView;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined, color: Colors.black),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Image Gallery Section - Collapsible on scroll
          AnimatedContainer(
            duration: const Duration(milliseconds: 50),
            curve: Curves.easeOut,
            height: _imageHeight,
            child: Stack(
              children: [
                _isGridView
                    ? _buildGridView(images)
                    : _buildPageView(images),
                // Photos/Video/Reviews/Variations tabs overlay
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildMediaTabs(images.length),
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
                                color: Colors.grey.shade800,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.keyboard_arrow_right,
                            color: Colors.grey.shade400,
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
                          const Text(
                            'Colors',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
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
                                                  ? const Color(0xFF25D366)
                                                  : Colors.transparent,
                                              width: 2,
                                            ),
                                          ),
                                          child: Container(
                                            width: 60,
                                            height: 60,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(6),
                                              color: Colors.white,
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
                                            color: isSelected ? Colors.black87 : Colors.grey.shade600,
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
                    const Divider(height: 1),
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
                              const Text(
                                'Simple Stock',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.green.shade200),
                                ),
                                child: Text(
                                  'Available: ${widget.product.availableQty}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
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
                                            color: Colors.grey.shade600,
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
                    const Divider(height: 1),
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
                                      color: Colors.grey.shade300,
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
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                  ],

                  // Product Description
                  if (widget.product.description.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Text(
                        widget.product.description,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
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
                          color: Colors.grey.shade300,
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
                    child: SizedBox(
                      height: 40,
                      child: OutlinedButton(
                        onPressed: () {},
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.black, width: 1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: const Text(
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
                        onPressed: () {},
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
              color: isSelected ? Colors.black : Colors.transparent,
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
            color: isSelected ? Colors.black : Colors.grey.shade600,
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
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Text(
                '5.0',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(width: 8),
              Row(
                children: [
                  Icon(Icons.star, color: Colors.orange, size: 20),
                  Icon(Icons.star, color: Colors.orange, size: 20),
                  Icon(Icons.star, color: Colors.orange, size: 20),
                  Icon(Icons.star, color: Colors.orange, size: 20),
                  Icon(Icons.star, color: Colors.orange, size: 20),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'No reviews yet',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
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
          const Text(
            'Product Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          if (widget.product.description.isNotEmpty) ...[
            Text(
              widget.product.description,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (widget.product.attributes.isNotEmpty) ...[
            const Text(
              'Attributes:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
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
                          color: Colors.grey.shade700,
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
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(
        child: Text(
          'Recommended products coming soon',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey,
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
                'Photos ${_currentImageIndex + 1}/$totalImages',
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
              _openVariationsSheet();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                'Variations',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageView(List<String> images) {
    return GestureDetector(
      onPanUpdate: (details) {
        // Detect left swipe (next image direction)
        if (details.delta.dx < -5) { // Swiping left
          _swipeTimer?.cancel();
          _swipeTimer = Timer(const Duration(milliseconds: 100), () {
            // This timer fires after swipe gesture ends
            if (_currentImageIndex == images.length - 1 && 
                _viewedImageIndices.length == images.length && 
                _mediaTab != 'Variations') {
              print('DEBUG: All images viewed and user tried to swipe beyond last. Opening Variations.');
              setState(() {
                _mediaTab = 'Variations';
              });
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted) {
                  _openVariationsSheet();
                }
              });
            }
          });
        }
      },
      onPanEnd: (details) {
        _swipeTimer?.cancel();
      },
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            final wasOnLastImage = _currentImageIndex == images.length - 1;
            _currentImageIndex = index;
            // Track this image as viewed
            _viewedImageIndices.add(index);
            print('DEBUG: Viewed image index $index. Current viewed images: ${_viewedImageIndices.length}/${images.length}');
            
            // If user swiped to a new image beyond the last one (when images.length is 2 and now 3)
            // or if they're on the last image and images just became 3 or more
            if (images.length >= 3 && index == images.length - 1 && wasOnLastImage && _mediaTab != 'Variations') {
              // Auto-slide to Variations tab after a brief delay
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted && _mediaTab != 'Variations') {
                  setState(() {
                    _mediaTab = 'Variations';
                  });
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (mounted) {
                      _openVariationsSheet();
                    }
                  });
                }
              });
            }
            
            if (index < images.length) {
              _setImageHeightFor(images[index], index);
            }
          });
        },
        itemCount: images.length,
        itemBuilder: (context, index) {
          return Container(
            color: Colors.white,
            width: double.infinity,
            height: double.infinity,
            child: Center(
              child: _buildImageWidget(images[index], isClickable: true),
            ),
          );
        },
      ),
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
                    ? Colors.blue
                    : Colors.grey.shade300,
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

  // Full-screen variations sheet similar to reference
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
        final currentVarName = _currentVariation['name']?.toString() ?? '';

        // Initialize variation size quantities if empty for ALL variations
        for (var variation in variations) {
          final varName = variation['name']?.toString() ?? '';
          if (!_variationSizeQuantities.containsKey(varName)) {
            _variationSizeQuantities[varName] = {};
            for (final s in sizes) {
              _variationSizeQuantities[varName]![s] = 0;
            }
          }
        }
        print('DEBUG: Opening variations sheet. All quantities: $_variationSizeQuantities');

        // Get current variation's size quantities - use currently selected variation
        Map<String, int> getCurrentSizeQuantities() {
          final selectedVarName = _currentVariation['name']?.toString() ?? '';
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
          final varSizes = _variationSizeQuantities[varName] ?? {};
          return varSizes.values.fold(0, (a, b) => a + b);
        }

        // Get available stock for a color-size combination
        int getAvailableStock(String colorName, String size) {
          // Always available mode - stock never runs out
          if (widget.product.stockMode == 'always_available') {
            return 999999; // Return a very large number to indicate unlimited
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
          // Always available mode - stock never runs out
          if (widget.product.stockMode == 'always_available') {
            return 999999; // Return a very large number to indicate unlimited
          }
          final available = getAvailableStock(colorName, size);
          final selected = _variationSizeQuantities[colorName]?[size] ?? 0;
          return (available - selected).clamp(0, available);
        }

        // Check if a color-size combination is out of stock
        bool isOutOfStock(String colorName, String size) {
          // Always available mode - never out of stock
          if (widget.product.stockMode == 'always_available') {
            return false;
          }
          return getRemainingStock(colorName, size) <= 0;
        }

        // Get total selected quantity across all variations and sizes (for simple stock)
        int getTotalSelectedQuantity() {
          int total = 0;
          for (var varName in _variationSizeQuantities.keys) {
            final sizes = _variationSizeQuantities[varName] ?? {};
            total += sizes.values.fold(0, (a, b) => a + b);
          }
          return total;
        }

        // Get remaining simple stock
        int getRemainingSimpleStock() {
          // Always available mode - stock never runs out
          if (widget.product.stockMode == 'always_available') {
            return 999999; // Return a very large number to indicate unlimited
          }
          if (widget.product.stockMode != 'simple') return 0;
          final totalAvailable = int.tryParse(widget.product.availableQty) ?? 0;
          final selected = getTotalSelectedQuantity();
          return (totalAvailable - selected).clamp(0, totalAvailable);
        }

        // Check if simple stock is out
        bool isSimpleStockOut() {
          // Always available mode - never out of stock
          if (widget.product.stockMode == 'always_available') {
            return false;
          }
          if (widget.product.stockMode != 'simple') return false;
          return getRemainingSimpleStock() <= 0;
        }

        // Get price based on total quantity
        Map<String, dynamic> getPriceForQuantity(int totalQty) {
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

        // Calculate subtotal for ALL variations (not just current)
        double calcSubtotal() {
          int totalQty = getTotalSelectedQuantity();
          final priceInfo = getPriceForQuantity(totalQty);
          return priceInfo['price'] * totalQty;
        }
        _subtotal = calcSubtotal();
        return StatefulBuilder(
          builder: (context, setModalState) {
            final currentSizes = getCurrentSizeQuantities();
            final totalPieces = currentSizes.values.fold(0, (a, b) => a + b);
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.92,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                // Scroll to selected color when sheet opens
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final selectedIndex = variations.indexWhere((v) =>
                  (v['name']?.toString() ?? '') == currentVarName
                  );
                  if (selectedIndex >= 0 && scrollController.hasClients) {
                    // Calculate approximate scroll position for selected color
                    // Assuming each color item is about 100px wide with spacing
                    final scrollPosition = (selectedIndex ~/ 3) * 120.0;
                    scrollController.animateTo(
                      scrollPosition.clamp(0.0, scrollController.position.maxScrollExtent),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                });

                return Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 8, bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Variations header - at top with X button on right
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.product.stockMode == 'color_size'
                                      ? 'Variations - Color Size Stock'
                                      : 'Variations',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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
                    // Selected quantities summary for all colors
                    Builder(
                      builder: (context) {
                        // Get all variations with quantities
                        final selectedVariations = <String, int>{};
                        for (var variation in variations) {
                          final varName = variation['name']?.toString() ?? '';
                          final qty = getVariationQty(varName);
                          if (qty > 0) {
                            selectedVariations[varName] = qty;
                          }
                        }
                        
                        if (selectedVariations.isNotEmpty) {
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.shopping_cart_outlined, size: 18, color: Colors.blue.shade700),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: selectedVariations.entries.map((entry) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.blue.shade300),
                                        ),
                                        child: Text(
                                          '${entry.key}: ${entry.value}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.blue.shade700,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    // Product image and price section - exactly like second image
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Product thumbnail image (larger, square)
                          Builder(
                            builder: (context) {
                              final currentImages = _getAllImages();
                              return Stack(
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
                                      child: currentImages.isNotEmpty
                                          ? _buildColorSwatchImage(currentImages[0])
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
                                ],
                              );
                            },
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
                              // Color grid - always show 6 colors
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
                              Builder(
                                builder: (context) {
                                  final count = variations.length;
                                  if (_isColorList) {
                                    return SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: variations.map((variation) {
                                          final vColorName = variation['name']?.toString() ?? '';
                                          final isSelected = vColorName == _currentVariation['name']?.toString();
                                          return GestureDetector(
                                            onTap: () {
                                              setModalState(() {
                                                _switchVariation(variation);
                                                _subtotal = calcSubtotal();
                                              });
                                            },
                                            child: Container(
                                              margin: const EdgeInsets.only(right: 8),
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: isSelected ? Colors.black : Colors.grey.shade300, width: isSelected ? 1.5 : 1),
                                                color: Colors.white,
                                              ),
                                              child: Text(
                                                vColorName,
                                                style: const TextStyle(fontSize: 12),
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
                                      crossAxisCount: 3,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 8,
                                      childAspectRatio: 0.85,
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
                                            child: Center(
                                              child: Text(
                                                'More',
                                                style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                      final variation = variations[index];
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
                                      final vColorName = variation['name']?.toString() ?? '';
                                      final isSelected = vColorName == _currentVariation['name']?.toString();
                                      // Get quantity for this specific color variation
                                      final selectedQty = getVariationQty(vColorName);
                                      return GestureDetector(
                                        onTap: () {
                                              setModalState(() {
                                                final oldVarName = _currentVariation['name']?.toString() ?? '';
                                                print('DEBUG: Switching from $oldVarName to ${variation['name']}');
                                                _switchVariation(variation);
                                                final newVarName = variation['name']?.toString() ?? '';
                                                if (!_variationSizeQuantities.containsKey(newVarName)) {
                                                  _variationSizeQuantities[newVarName] = {};
                                                  for (final s in sizes) {
                                                    _variationSizeQuantities[newVarName]![s] = 0;
                                                  }
                                                  print('DEBUG: Initialized new variation $newVarName with zero quantities');
                                                } else {
                                                  print('DEBUG: Existing quantities for $newVarName: ${_variationSizeQuantities[newVarName]}');
                                                }
                                                final newImages = _getAllImages();
                                                _subtotal = calcSubtotal();
                                              });
                                              // Update the summary by rebuilding
                                              setModalState(() {});
                                            },
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Stack(
                                              children: [
                                                Container(
                                                  width: 90,
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
                                                        ? Stack(
                                                      children: [
                                                        Positioned.fill(
                                                          child: _buildColorSwatchImage(variationImage),
                                                        ),
                                                        Positioned(
                                                          top: 2,
                                                          left: 2,
                                                          child: GestureDetector(
                                                            onTap: () {
                                                              _openImageViewer(variationImage!, vColorName, priceSlabs);
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
                                                            color: Colors.white.withOpacity(0.9),
                                                            child: Text(
                                                              vColorName,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
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
                                                        'x$selectedQty',
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
                              const SizedBox(height: 12),
                              // Size with steppers
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    widget.product.stockMode == 'color_size'
                                        ? 'Size (${sizes.length}) - Color Size Stock'
                                        : widget.product.stockMode == 'always_available'
                                        ? 'Size (${sizes.length}) - Always Available'
                                        : 'Size (${sizes.length})',
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Column(
                                children: sizes.map((s) {
                                  final currentSizes = getCurrentSizeQuantities();
                                  final qty = currentSizes[s] ?? 0;
                                  final availableStock = widget.product.stockMode == 'color_size'
                                      ? getAvailableStock(currentVarName, s)
                                      : null;
                                  final remainingStock = widget.product.stockMode == 'color_size'
                                      ? getRemainingStock(currentVarName, s)
                                      : getRemainingSimpleStock();
                                  final stockOut = widget.product.stockMode == 'always_available'
                                      ? false // Never out of stock for always_available
                                      : widget.product.stockMode == 'color_size'
                                      ? isOutOfStock(currentVarName, s)
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
                                                final cur = (currentSizes[s] ?? 0);
                                                if (cur > 0) {
                                                  print('DEBUG: Decreasing quantity for $currentVarName, size $s from $cur to ${cur - 1}');
                                                  _variationSizeQuantities[currentVarName]![s] = cur - 1;
                                                  _subtotal = calcSubtotal();
                                                  setModalState(() {
                                                    // Rebuild to update summary
                                                  });
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
                                                final cur = (currentSizes[s] ?? 0);
                                                // For always_available, allow unlimited quantity
                                                if (isAlwaysAvailable) {
                                                  print('DEBUG: Increasing quantity for $currentVarName, size $s from $cur to ${cur + 1}');
                                                  _variationSizeQuantities[currentVarName]![s] = cur + 1;
                                                  _subtotal = calcSubtotal();
                                                  setModalState(() {
                                                    // Rebuild to update summary
                                                  });
                                                } else {
                                                  final remaining = widget.product.stockMode == 'color_size'
                                                      ? getRemainingStock(currentVarName, s)
                                                      : getRemainingSimpleStock();
                                                  if (remaining > 0) {
                                                    print('DEBUG: Increasing quantity for $currentVarName, size $s from $cur to ${cur + 1}');
                                                    _variationSizeQuantities[currentVarName]![s] = cur + 1;
                                                    _subtotal = calcSubtotal();
                                                    setModalState(() {
                                                      // Rebuild to update summary
                                                    });
                                                  }
                                                }
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
                              Builder(
                                builder: (context) {
                                  final currentSizes = getCurrentSizeQuantities();
                                  return Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: sizes.where((s) => (currentSizes[s] ?? 0) > 0).map((s) {
                                      final q = currentSizes[s]!;
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: Colors.grey.shade300),
                                        ),
                                        child: Text('$s × $q'),
                                      );
                                    }).toList(),
                                  );
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
                              child: Text('Subtotal: ₹${_subtotal.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            ),
                            SizedBox(
                              height: 40,
                              child: OutlinedButton(
                                onPressed: () {},
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Add to cart'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 40,
                              child: ElevatedButton(
                                onPressed: () {},
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
