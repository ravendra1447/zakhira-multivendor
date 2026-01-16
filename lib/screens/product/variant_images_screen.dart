import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:ui' as ui;
import 'package:whatsappchat/theme/app_colors.dart';

// Orientation-aware image widget that auto-adjusts based on image dimensions
class OrientationAwareImage extends StatefulWidget {
  final File imageFile;
  final BoxFit? fit;
  final double? width;
  final double? height;

  const OrientationAwareImage({
    Key? key,
    required this.imageFile,
    this.fit,
    this.width,
    this.height,
  }) : super(key: key);

  @override
  State<OrientationAwareImage> createState() => _OrientationAwareImageState();
}

class _OrientationAwareImageState extends State<OrientationAwareImage> {
  BoxFit _fit = BoxFit.cover;
  bool _resolved = false;
  double? _aspectRatio;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  Future<void> _resolveImage() async {
    try {
      final bytes = await widget.imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      
      final w = image.width.toDouble();
      final h = image.height.toDouble();
      final aspectRatio = w / h;
      
      BoxFit f;
      if (w > h) {
        // Horizontal image - fit height to show full width
        f = BoxFit.fitHeight;
      } else if (h > w) {
        // Vertical image - fit width to show full height
        f = BoxFit.fitWidth;
      } else {
        // Square image - contain to fit
        f = BoxFit.contain;
      }
      
      image.dispose();
      
      if (mounted) {
        setState(() {
          _fit = f;
          _aspectRatio = aspectRatio;
          _resolved = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fit = widget.fit ?? BoxFit.cover;
          _resolved = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_resolved) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: AppColors.surface(context),
        child: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary(context),
          ),
        ),
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Image.file(
        widget.imageFile,
        fit: widget.fit ?? _fit,
      ),
    );
  }
}

class VariantImagesScreen extends StatefulWidget {
  final List<File> variantImages;

  const VariantImagesScreen({
    super.key,
    required this.variantImages,
  });

  @override
  State<VariantImagesScreen> createState() => _VariantImagesScreenState();
}

class _VariantImagesScreenState extends State<VariantImagesScreen> {
  late List<File> _images;
  int _currentIndex = 0;
  bool _isGridView = true;
  final ImagePicker _picker = ImagePicker();
  final ScrollController _topScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _images = List<File>.from(widget.variantImages);
  }

  @override
  void dispose() {
    _topScrollController.dispose();
    super.dispose();
  }

  Future<void> _addImages() async {
    try {
      final List<XFile>? pickedFiles = await _picker.pickMultiImage(
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 75,
      );

      if (pickedFiles != null && pickedFiles.isNotEmpty) {
        final imageFiles = pickedFiles.map((file) => File(file.path)).toList();
        setState(() {
          _images.addAll(imageFiles);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding images: $e')),
        );
      }
    }
  }

  Widget _buildTopImageSection() {
    if (_images.isEmpty) {
      return Container(
        height: 150,
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: GestureDetector(
            onTap: _addImages,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border(context), width: 2),
              ),
              child: Icon(Icons.add, size: 40, color: AppColors.textSecondary(context)),
            ),
          ),
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final padding = 16.0;
    final spacing = 8.0;
    final availableWidth = screenWidth - (padding * 2);
    // Calculate width for 2.5 images (2 full + 0.5 half)
    final imageWidth = (availableWidth - spacing) / 2.5;
    final imageHeight = 150.0;
    
    return Container(
      height: imageHeight + 16,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        controller: _topScrollController,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: padding),
        child: Row(
          children: [
            // First image (full)
            if (_images.length >= 1)
              Container(
                width: imageWidth,
                height: imageHeight,
                margin: EdgeInsets.only(right: spacing),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    color: AppColors.surface(context),
                    child: OrientationAwareImage(
                      imageFile: _images[0],
                      width: imageWidth,
                      height: imageHeight,
                    ),
                  ),
                ),
              ),
            
            // Second image (full)
            if (_images.length >= 2)
              Container(
                width: imageWidth,
                height: imageHeight,
                margin: EdgeInsets.only(right: spacing),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    color: AppColors.surface(context),
                    child: OrientationAwareImage(
                      imageFile: _images[1],
                      width: imageWidth,
                      height: imageHeight,
                    ),
                  ),
                ),
              ),
            
            // Third image (half visible) with + button overlay
            if (_images.length >= 3)
              Container(
                width: imageWidth * 0.5,
                height: imageHeight,
                margin: EdgeInsets.only(right: spacing),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        color: AppColors.surface(context),
                        child: ClipRect(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            widthFactor: 0.5,
                            child: SizedBox(
                              width: imageWidth,
                              height: imageHeight,
                              child: OrientationAwareImage(
                                imageFile: _images[2],
                                width: imageWidth,
                                height: imageHeight,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // + button overlay on the half-visible part
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: _addImages,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (_images.length == 2)
              // Show + button if only 2 images
              Container(
                width: imageWidth * 0.5,
                height: imageHeight,
                margin: EdgeInsets.only(right: spacing),
                child: GestureDetector(
                  onTap: _addImages,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface(context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border(context), width: 2),
                    ),
                    child: Icon(
                      Icons.add,
                      size: 40,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ),
              )
            else if (_images.length == 1)
              // Show + button if only 1 image
              Container(
                width: imageWidth * 0.5,
                height: imageHeight,
                margin: EdgeInsets.only(right: spacing),
                child: GestureDetector(
                  onTap: _addImages,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface(context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border(context), width: 2),
                    ),
                    child: Icon(
                      Icons.add,
                      size: 40,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    print('VariantImagesScreen: Received ${_images.length} images');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFF1F1F1F),
        elevation: 0,
        shadowColor: Colors.black.withOpacity(0.3),
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context, _images),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF25D366).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.photo_library,
                color: Color(0xFF25D366),
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Variations (${_images.length})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: IconButton(
              icon: Icon(
                _isGridView ? Icons.list : Icons.grid_view,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  _isGridView = !_isGridView;
                });
              },
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  const Color(0xFF25D366).withOpacity(0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Top section with 2.5 images
          _buildTopImageSection(),
          
          // Divider
          const Divider(height: 1),
          
          // Main content area
          Expanded(
            child: _isGridView
                ? GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 0.75,
                    ),
                    itemCount: _images.length,
                    itemBuilder: (context, index) {
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _currentIndex = index;
                            _isGridView = false;
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _currentIndex == index
                                  ? AppColors.primary(context)
                                  : AppColors.border(context),
                              width: _currentIndex == index ? 2 : 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: OrientationAwareImage(
                              imageFile: _images[index],
                            ),
                          ),
                        ),
                      );
                    },
                  )
                : PageView.builder(
                    controller: PageController(initialPage: _currentIndex),
                    itemCount: _images.length + 1, // +1 for add button slide
                    onPageChanged: (index) {
                      setState(() {
                        _currentIndex = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      if (index < _images.length) {
                        final isLast = index == _images.length - 1;
                        return Stack(
                          children: [
                            Center(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  return OrientationAwareImage(
                                    imageFile: _images[index],
                                    width: constraints.maxWidth,
                                    height: constraints.maxHeight,
                                  );
                                },
                              ),
                            ),
                            // Show + button on the last image slide
                            if (isLast)
                              Positioned(
                                bottom: 80,
                                right: 20,
                                child: FloatingActionButton(
                                  onPressed: _addImages,
                                  backgroundColor: const Color(0xFF25D366),
                                  child: const Icon(Icons.add, color: Colors.white),
                                ),
                              ),
                          ],
                        );
                      } else {
                        // Add button slide (after last image)
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: _addImages,
                                child: Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    color: AppColors.surface(context),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: AppColors.border(context),
                                      width: 3,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.add,
                                    size: 60,
                                    color: AppColors.textSecondary(context),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Add More Images',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary(context),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: !_isGridView
          ? Container(
              padding: const EdgeInsets.all(16),
              color: AppColors.card(context),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.grid_view, color: AppColors.textPrimary(context)),
                    onPressed: () {
                      setState(() {
                        _isGridView = true;
                      });
                    },
                  ),
                  Text(
                    _currentIndex < _images.length
                        ? '${_currentIndex + 1} / ${_images.length}'
                        : '${_images.length + 1} / ${_images.length + 1}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(width: 48), // Balance the grid icon
                ],
              ),
            )
          : null,
    );
  }
}
