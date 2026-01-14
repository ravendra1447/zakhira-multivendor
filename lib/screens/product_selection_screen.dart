import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:whatsappchat/screens/product/add_product_basic_info_screen.dart';
import 'dart:ui' as ui;
import 'camera_interface_screen.dart';

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

      BoxFit f = BoxFit.cover; // Always cover to fill the box without white space

      image.dispose();

      if (mounted) {
        setState(() {
          _fit = f;
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
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey.shade800
            : Colors.grey.shade300,
        child: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.grey.shade700,
          ),
        ),
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Image.file(widget.imageFile, fit: widget.fit ?? _fit),
    );
  }
}

class ProductSelectionScreen extends StatefulWidget {
  final List<File> selectedImages;

  const ProductSelectionScreen({super.key, required this.selectedImages});

  @override
  State<ProductSelectionScreen> createState() => _ProductSelectionScreenState();
}

class _ProductSelectionScreenState extends State<ProductSelectionScreen> {
  late List<File> _selectedImages; // Make images mutable
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _colorController = TextEditingController();
  int _currentIndex = 0;
  String? _selectedVariant; // Combined selection for Color/Model
  bool _showVariantDropdown = false; // Control dropdown visibility
  String _selectedTab = 'Color'; // Default selected tab
  bool _isAddButtonDisabled = false; // Track if Add button is disabled
  String _selectedVariantType = 'Color'; // Selected variant type: Color or Size

  final List<String> _colors = [
    'Red',
    'Blue',
    'Green',
    'Black',
    'White',
    'Yellow',
  ];

  // Map to store color images: color name -> list of image files (max 5 per color)
  Map<String, List<File>> _colorImages = {};
  static const int _maxImagesPerColor = 5;

  // List to track recently added colors (last 20)
  List<String> _recentColors = [];

  // Theme colors for light and dark mode
  Color get _backgroundColor => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF121212)
      : const Color(0xFFF5F5F5);

  Color get _cardColor => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF1E1E1E)
      : Colors.white;

  Color get _textColor => Theme.of(context).brightness == Brightness.dark
      ? Colors.white
      : Colors.black87;

  Color get _hintTextColor => Theme.of(context).brightness == Brightness.dark
      ? Colors.grey.shade400
      : Colors.grey.shade600;

  Color get _borderColor => Theme.of(context).brightness == Brightness.dark
      ? Colors.grey.shade700
      : Colors.grey.shade300;

  Color get _disabledButtonColor => Theme.of(context).brightness == Brightness.dark
      ? Colors.grey.shade700
      : Colors.grey.shade400;

  Color get _placeholderColor => Theme.of(context).brightness == Brightness.dark
      ? Colors.grey.shade800
      : Colors.grey.shade200;

  // Helper function to get color from color name
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
        return Theme.of(context).brightness == Brightness.dark
            ? Colors.grey.shade900
            : Colors.black;
      case 'white':
        return Theme.of(context).brightness == Brightness.dark
            ? Colors.grey.shade300
            : Colors.white;
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
        return Theme.of(context).brightness == Brightness.dark
            ? Colors.grey.shade600
            : Colors.grey.shade400;
    }
  }

  // Helper function to get text color based on background color
  Color _getTextColorForBackground(Color backgroundColor) {
    // Calculate luminance to determine if background is light or dark
    final luminance = backgroundColor.computeLuminance();
    return luminance > 0.5 ? Colors.black87 : Colors.white;
  }

  // Function to remove a color variant
  void _removeColorVariant(String colorName) {
    setState(() {
      _colorImages.remove(colorName);
      _recentColors.remove(colorName);
    });
  }

  // Function to remove an image
  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      if (_currentIndex >= _selectedImages.length) {
        _currentIndex = _selectedImages.isEmpty ? 0 : _selectedImages.length - 1;
      }
    });
  }

  // Function to add images to a specific color variant
  Future<void> _addImagesToColorVariant(String colorName) async {
    try {
      final List<XFile>? pickedFiles = await _picker.pickMultiImage(
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 75,
      );

      if (pickedFiles != null && pickedFiles.isNotEmpty) {
        final colorDir = await _getColorFolder(colorName);
        if (!_colorImages.containsKey(colorName)) {
          _colorImages[colorName] = [];
        }

        for (var pickedFile in pickedFiles) {
          if (_colorImages[colorName]!.length >= _maxImagesPerColor) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Maximum $_maxImagesPerColor images allowed for $colorName',
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black87,
                  ),
                ),
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade800
                    : Colors.white,
              ),
            );
            break;
          }

          final imageFile = File(pickedFile.path);
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final ext = path.extension(imageFile.path);
          final fileName = '${colorName}_${timestamp}$ext';
          final destFile = File(path.join(colorDir.path, fileName));
          final copiedFile = await imageFile.copy(destFile.path);

          setState(() {
            _colorImages[colorName]!.add(copiedFile);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error adding images: $e',
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black87,
              ),
            ),
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey.shade800
                : Colors.white,
          ),
        );
      }
    }
  }

  // Get variant images directory
  Future<Directory> _getVariantImagesDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final variantDir = Directory(path.join(appDir.path, 'variant_images'));
    if (!await variantDir.exists()) {
      await variantDir.create(recursive: true);
    }
    return variantDir;
  }

  // Get color folder directory
  Future<Directory> _getColorFolder(String colorName) async {
    final variantDir = await _getVariantImagesDirectory();
    final colorDir = Directory(path.join(variantDir.path, colorName));
    if (!await colorDir.exists()) {
      await colorDir.create(recursive: true);
    }
    return colorDir;
  }

  @override
  void initState() {
    super.initState();
    _selectedImages = List<File>.from(widget.selectedImages);

    // Initialize recent colors from existing color images
    // This ensures previously added colors show in the recently added section
    _recentColors = _colorImages.keys.toList();

    // Listen to text field changes to update display image and enable Add button
    _colorController.addListener(() {
      setState(() {
        // Re-enable Add button when text changes
        if (_colorController.text.trim().isNotEmpty) {
          _isAddButtonDisabled = false;
        } else {
          _isAddButtonDisabled = true;
        }
      });
    });
  }

  @override
  void dispose() {
    _colorController.dispose();
    super.dispose();
  }

  Future<void> _addMoreImages() async {
    try {
      final List<XFile>? pickedFiles = await _picker.pickMultiImage(
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 75,
      );

      if (pickedFiles != null && pickedFiles.isNotEmpty) {
        final imageFiles = pickedFiles.map((file) => File(file.path)).toList();
        setState(() {
          _selectedImages.addAll(imageFiles);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              'Error adding images: $e',
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black87,
              ),
            ),
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey.shade800
                : Colors.white,
          ),
        );
      }
    }
  }

  Future<void> _openCameraToAddImages({bool retainSelection = false}) async {
    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CameraInterfaceScreen(
            returnImagesDirectly: true,
            initialSelectedImages: retainSelection ? List<File>.from(_selectedImages) : [],
          ),
        ),
      );
      if (result != null && result is List<File>) {
        setState(() {
          _selectedImages = List<File>.from(result);
          if (_currentIndex >= _selectedImages.length) {
            _currentIndex = _selectedImages.isEmpty
                ? 0
                : _selectedImages.length - 1;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              'Error opening camera: $e',
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black87,
              ),
            ),
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey.shade800
                : Colors.white,
          ),
        );
      }
    }
  }

  Widget _buildTopImageSection() {
    final screenWidth = MediaQuery.of(context).size.width;
    final padding = 16.0;
    final spacing = 8.0;
    final availableWidth = screenWidth - (padding * 2);
    final imageWidth = (availableWidth - spacing) / 2.5;
    final imageHeight = 180.0;

    // If no images, show placeholder with add button
    if (_selectedImages.isEmpty) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black.withOpacity(0.3)
                  : Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          children: [
            // Product Image header with count
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Product Image',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _textColor,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: const Color(0xFF25D366),
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_selectedImages.length}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF25D366),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 180,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: Theme.of(context).brightness == Brightness.dark
                      ? [Colors.grey.shade900, Colors.black]
                      : [Colors.black, Colors.grey.shade900],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: GestureDetector(
                  onTap: _addMoreImages,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.add, size: 40, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final controller = PageController(viewportFraction: 1 / 2.5);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          // Product Image header with count
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Product Image',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _textColor,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade800
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: const Color(0xFF25D366),
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_selectedImages.length}/5',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: imageHeight + 16,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 0),
              child: PageView.builder(
                controller: controller,
                itemCount: _selectedImages.length + 1,
                padEnds: false,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  final isAddSlide = index == _selectedImages.length;
                  if (isAddSlide) {
                    return Center(
                      child: GestureDetector(
                        onTap: () => _openCameraToAddImages(retainSelection: true),
                        child: Container(
                          width: imageWidth,
                          height: imageHeight,
                          decoration: BoxDecoration(
                            color: _cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _borderColor, width: 1),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.add,
                              size: 28,
                              color: const Color(0xFF25D366),
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  return Container(
                    margin: EdgeInsets.only(right: spacing, top: 8, bottom: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _borderColor, width: 1),
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: OrientationAwareImage(
                            imageFile: _selectedImages[index],
                            width: imageWidth,
                            height: imageHeight,
                          ),
                        ),
                        // X button to remove image - top left
                        Positioned(
                          top: 4,
                          left: 4,
                          child: GestureDetector(
                            onTap: () {
                              _removeImage(index);
                            },
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        // Number badge on top right
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.grey.shade800
                                  : Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          // Add Images button below images - small, right side
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '(Max 5 | JPG/PNG)',
                style: TextStyle(
                  color: _hintTextColor,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF25D366), Color(0xFF128C7E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _openCameraToAddImages(retainSelection: false),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Add Color',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Get all variant images (flatten all color images)
  List<File> get _allVariantImages {
    final List<File> allImages = [];
    _colorImages.forEach((colorName, images) {
      for (var img in images) {
        if (img.existsSync()) {
          allImages.add(img);
        }
      }
    });
    return allImages;
  }

  void _navigateToVariantImages() {
    final allImages = _allVariantImages;
    if (allImages.isEmpty && _selectedImages.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            'Please add images first',
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black87,
            ),
          ),
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey.shade800
              : Colors.white,
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddProductBasicInfoScreen(
          images: allImages.isNotEmpty ? allImages : _selectedImages,
          colorImagesMap: _colorImages.isNotEmpty ? _colorImages : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1A1A1A)
            : const Color(0xFF1F1F1F),
        elevation: 0,
        shadowColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.black.withOpacity(0.5)
            : Colors.black.withOpacity(0.3),
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context, _selectedImages),
          ),
        ),
        title: const Text(
          'Select Products',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        centerTitle: true,
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

          // Scrollable content area
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 4),

                  // Variant Type section - Combined
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.black.withOpacity(0.3)
                              : Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Variant Type with radio buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Variant Type',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _textColor,
                              ),
                            ),
                            Row(
                              children: [
                                // Color radio button
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedVariantType = 'Color';
                                    });
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 18,
                                        height: 18,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: _selectedVariantType == 'Color'
                                                ? const Color(0xFF25D366)
                                                : _borderColor,
                                            width: 2,
                                          ),
                                        ),
                                        child: _selectedVariantType == 'Color'
                                            ? const Center(
                                          child: Icon(
                                            Icons.circle,
                                            size: 10,
                                            color: Color(0xFF25D366),
                                          ),
                                        )
                                            : null,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Color',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: _textColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Color input field with + Add button
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _colorController,
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(
                                  hintText: 'Enter color name',
                                  hintStyle: TextStyle(
                                    color: _hintTextColor,
                                    fontSize: 14,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: _borderColor,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: _borderColor,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF25D366),
                                      width: 2,
                                    ),
                                  ),
                                  fillColor: Theme.of(context).brightness == Brightness.dark
                                      ? Colors.grey.shade900
                                      : Colors.grey.shade50,
                                  filled: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: _textColor,
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    if (value.trim().isNotEmpty) {
                                      _isAddButtonDisabled = false;
                                    } else {
                                      _isAddButtonDisabled = true;
                                    }
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              decoration: BoxDecoration(
                                gradient: _isAddButtonDisabled
                                    ? LinearGradient(
                                  colors: [
                                    _disabledButtonColor,
                                    _disabledButtonColor.withOpacity(0.8),
                                  ],
                                )
                                    : const LinearGradient(
                                  colors: [
                                    Color(0xFF25D366),
                                    Color(0xFF128C7E),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _isAddButtonDisabled
                                      ? null
                                      : () async {
                                    FocusScope.of(context).unfocus();
                                    final colorName = _colorController.text.trim();

                                    // DUPLICATE CHECK - YEH CODE ADD KIYA HAI
                                    final existingColor = _colorImages.keys.firstWhere(
                                          (key) => key.toLowerCase() == colorName.toLowerCase(),
                                      orElse: () => '',
                                    );

                                    if (existingColor.isNotEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '$colorName already exists',
                                            style: TextStyle(
                                              color: Theme.of(context).brightness == Brightness.dark
                                                  ? Colors.white
                                                  : Colors.black87,
                                            ),
                                          ),
                                          backgroundColor: Theme.of(context).brightness == Brightness.dark
                                              ? Colors.grey.shade800
                                              : Colors.white,
                                        ),
                                      );
                                      return;
                                    }
                                    // DUPLICATE CHECK END

                                    if (colorName.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Please enter a color name',
                                            style: TextStyle(
                                              color: Theme.of(context).brightness == Brightness.dark
                                                  ? Colors.white
                                                  : Colors.black87,
                                            ),
                                          ),
                                          backgroundColor: Theme.of(context).brightness == Brightness.dark
                                              ? Colors.grey.shade800
                                              : Colors.white,
                                        ),
                                      );
                                      return;
                                    }

                                    if (_selectedImages.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Please add an image first',
                                            style: TextStyle(
                                              color: Theme.of(context).brightness == Brightness.dark
                                                  ? Colors.white
                                                  : Colors.black87,
                                            ),
                                          ),
                                          backgroundColor: Theme.of(context).brightness == Brightness.dark
                                              ? Colors.grey.shade800
                                              : Colors.white,
                                        ),
                                      );
                                      return;
                                    }

                                    try {
                                      final colorDir = await _getColorFolder(colorName);
                                      if (!_colorImages.containsKey(colorName)) {
                                        _colorImages[colorName] = [];
                                      }

                                      // Add ALL selected images to this color variant
                                      int addedCount = 0;
                                      for (var image in _selectedImages) {
                                        if (_colorImages[colorName]!.length >= _maxImagesPerColor) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Maximum $_maxImagesPerColor images allowed for $colorName. Added $addedCount images.',
                                                style: TextStyle(
                                                  color: Theme.of(context).brightness == Brightness.dark
                                                      ? Colors.white
                                                      : Colors.black87,
                                                ),
                                              ),
                                              backgroundColor: Theme.of(context).brightness == Brightness.dark
                                                  ? Colors.grey.shade800
                                                  : Colors.white,
                                            ),
                                          );
                                          break;
                                        }
                                        final timestamp = DateTime.now().millisecondsSinceEpoch;
                                        final ext = path.extension(image.path);
                                        final fileName = '${colorName}_${timestamp}_${addedCount}$ext';
                                        final destFile = File(path.join(colorDir.path, fileName));
                                        final copiedFile = await image.copy(destFile.path);
                                        _colorImages[colorName]!.add(copiedFile);
                                        addedCount++;
                                      }

                                      setState(() {
                                        // Remove if already exists and add to top
                                        _recentColors.remove(colorName);
                                        _recentColors.insert(0, colorName);
                                        if (_recentColors.length > 20) {
                                          _recentColors = _recentColors.take(20).toList();
                                        }
                                        _colorController.clear();
                                        _isAddButtonDisabled = true;
                                      });

                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Added $addedCount image(s) to $colorName variation',
                                            style: TextStyle(
                                              color: Theme.of(context).brightness == Brightness.dark
                                                  ? Colors.white
                                                  : Colors.black87,
                                            ),
                                          ),
                                          backgroundColor: Theme.of(context).brightness == Brightness.dark
                                              ? Colors.grey.shade800
                                              : Colors.white,
                                        ),
                                      );
                                    } catch (e) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Error adding color: $e',
                                            style: TextStyle(
                                              color: Theme.of(context).brightness == Brightness.dark
                                                  ? Colors.white
                                                  : Colors.black87,
                                            ),
                                          ),
                                          backgroundColor: Theme.of(context).brightness == Brightness.dark
                                              ? Colors.grey.shade800
                                              : Colors.white,
                                        ),
                                      );
                                    }
                                  },  // <-- YEH SIRF EK COMMA HAI
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.add,
                                          color: _isAddButtonDisabled
                                              ? Colors.grey.shade300
                                              : Colors.white,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Add',
                                          style: TextStyle(
                                            color: _isAddButtonDisabled
                                                ? Colors.grey.shade300
                                                : Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Recently Added Colors section
                        if (_recentColors.isNotEmpty) ...[
                          Text(
                            'Recently Added Colors (Last 20)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _textColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _recentColors.take(20).map((colorName) {
                                final isSelected = _colorController.text.trim().toLowerCase() == colorName.toLowerCase();
                                final color = _getColorFromName(colorName);
                                return Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _colorController.text = colorName;
                                        _isAddButtonDisabled = false;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: isSelected
                                              ? const Color(0xFF25D366)
                                              : Colors.transparent,
                                          width: isSelected ? 2 : 0,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isSelected) ...[
                                            Icon(
                                              Icons.check_circle,
                                              color: _getTextColorForBackground(color),
                                              size: 16,
                                            ),
                                            const SizedBox(width: 4),
                                          ],
                                          Text(
                                            colorName,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: _getTextColorForBackground(color),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        // Variant cards section
                        if (_colorImages.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                ..._colorImages.entries.map((entry) {
                                  final colorName = entry.key;
                                  final images = entry.value;
                                  final firstImage = images.isNotEmpty
                                      ? images.first
                                      : null;
                                  final color = _getColorFromName(colorName);
                                  return Container(
                                    width: 100,
                                    margin: const EdgeInsets.only(right: 12),
                                    decoration: BoxDecoration(
                                      color: _cardColor,
                                      border: Border.all(
                                        color: _borderColor,
                                        width: 1,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Colored header with color name and X button
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: color,
                                            borderRadius: const BorderRadius.only(
                                              topLeft: Radius.circular(11),
                                              topRight: Radius.circular(11),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  colorName,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: _getTextColorForBackground(color),
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              GestureDetector(
                                                onTap: () {
                                                  _removeColorVariant(colorName);
                                                },
                                                child: Container(
                                                  width: 16,
                                                  height: 16,
                                                  decoration: BoxDecoration(
                                                    color: _getTextColorForBackground(color).withOpacity(0.3),
                                                    borderRadius: BorderRadius.circular(3),
                                                  ),
                                                  child: Icon(
                                                    Icons.close,
                                                    size: 12,
                                                    color: _getTextColorForBackground(color),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Square Image section - fills the space with tap to add more images
                                        GestureDetector(
                                          onTap: () {
                                            _addImagesToColorVariant(colorName);
                                          },
                                          child: Stack(
                                            children: [
                                              ClipRRect(
                                                borderRadius: const BorderRadius.only(
                                                  bottomLeft: Radius.circular(11),
                                                  bottomRight: Radius.circular(11),
                                                ),
                                                child: SizedBox(
                                                  width: 100,
                                                  height: 100,
                                                  child: firstImage != null
                                                      ? Image.file(
                                                    firstImage,
                                                    fit: BoxFit.cover,
                                                  )
                                                      : Container(
                                                    color: _placeholderColor,
                                                  ),
                                                ),
                                              ),
                                              // Image count badge
                                              if (images.length > 1)
                                                Positioned(
                                                  top: 4,
                                                  right: 4,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black.withOpacity(0.7),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      '${images.length}',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              // Add more icon overlay
                                              Positioned(
                                                bottom: 4,
                                                right: 4,
                                                child: Container(
                                                  padding: const EdgeInsets.all(4),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF25D366),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(
                                                    Icons.add,
                                                    color: Colors.white,
                                                    size: 14,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Next button - centered
                  Container(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: Container(
                        width: double.infinity,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF25D366), Color(0xFF128C7E)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF25D366).withOpacity(0.4),
                              blurRadius: 15,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _navigateToVariantImages,
                            borderRadius: BorderRadius.circular(16),
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    'Save and Continue',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${_allVariantImages.length}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.arrow_forward,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
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
}