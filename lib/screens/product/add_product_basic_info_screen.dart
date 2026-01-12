import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../camera_interface_screen.dart';
import 'category_selection_screen.dart';
import 'attributes_management_screen.dart';
import '../../services/product_service.dart';
import '../chat_home.dart';

class AddProductBasicInfoScreen extends StatefulWidget {
  final List<File> images;
  final Map<String, List<File>>? colorImagesMap; // Color name -> List of images
  const AddProductBasicInfoScreen({
    super.key,
    required this.images,
    this.colorImagesMap,
  });
  @override
  State<AddProductBasicInfoScreen> createState() =>
      _AddProductBasicInfoScreenState();
}

class _AddProductBasicInfoScreenState extends State<AddProductBasicInfoScreen> {
  final TextEditingController _nameController = TextEditingController();
  String? _category;
  final TextEditingController _availableQtyController = TextEditingController();
  final FocusNode _availableQtyFocusNode = FocusNode();
  final List<Map<String, dynamic>> _priceSlabs = [];
  final Set<String> _selectedSizes = {};
  final List<Map<String, dynamic>> _colorItems = [];
  Map<String, List<String>> _attributes = {
    'Fabric': ['Cotton', 'Silk', 'Wool', 'Polyester', 'Linen'],
    'Fit': ['Regular', 'Slim', 'Loose', 'Tight'],
    'Sleeve': ['Half Sleeve', 'Full Sleeve', 'Sleeveless', 'Short Sleeve'],
    'Pattern': ['Solid', 'Striped', 'Printed', 'Checked', 'Floral'],
  };
  Map<String, String> _selectedAttributeValues = {};
  final TextEditingController _descController = TextEditingController();
  bool _attributesExpanded = false;
  final Map<String, bool> _expandedAttributeItems = {};
  final List<String> _sizes = ['S', 'M', 'L', 'XL', 'XXL'];
  final TextEditingController _tempNameController = TextEditingController();
  final TextEditingController _tempValueController = TextEditingController();
  bool _showAddAttributeFields = false;
  bool _marketplaceEnabled = true; // Marketplace toggle
  // Stock management
  String _stockMode = 'simple'; // 'simple', 'color_size', or 'always_available'
  String? _selectedColorForStock;
  final Map<String, Map<String, int>> _stockByColorSize = {}; // {color: {size: qty}}
  final TextEditingController _quickStockController = TextEditingController();
  bool _applyQuickToAllColors = false;
  // Always Available / On Demand fields
  final TextEditingController _dispatchTimeController = TextEditingController();
  bool _showMadeOnOrderBadge = false;

  // Recently selected items
  List<String> _recentCategories = [];
  List<String> _recentSizes = [];
  List<String> _recentColors = [];

  @override
  void initState() {
    super.initState();
    _loadRecentlySelectedItems();
    // Initialize color items from colorImagesMap if available
    if (widget.colorImagesMap != null && widget.colorImagesMap!.isNotEmpty) {
      // Use color names from map - store all images for each color
      widget.colorImagesMap!.forEach((colorName, images) {
        if (images.isNotEmpty) {
          // Store all images for each color
          _colorItems.add({
            'name': colorName,
            'image': images.first, // First image for display
            'allImages': images, // All images for this color
          });
        }
      });
    } else if (widget.images.isNotEmpty) {
      // Fallback: Initialize color items from images (default names)
      for (int i = 0; i < widget.images.length; i++) {
        _colorItems.add({
          'name': 'Color ${i + 1}',
          'image': widget.images[i],
          'allImages': [widget.images[i]],
        });
      }
    }
  }

  // Load recently selected items from SharedPreferences
  Future<void> _loadRecentlySelectedItems() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _recentCategories = prefs.getStringList('recent_categories') ?? [];
      _recentSizes = prefs.getStringList('recent_sizes') ?? [];
      _recentColors = prefs.getStringList('recent_colors') ?? [];
    });
  }

  // Save recently selected category
  Future<void> _saveRecentCategory(String category) async {
    final prefs = await SharedPreferences.getInstance();
    _recentCategories.remove(category); // Remove if exists
    _recentCategories.insert(0, category); // Add to beginning
    if (_recentCategories.length > 10) {
      _recentCategories = _recentCategories.take(10).toList(); // Keep only 10
    }
    await prefs.setStringList('recent_categories', _recentCategories);
    setState(() {});
  }

  // Save recently selected size
  Future<void> _saveRecentSize(String size) async {
    final prefs = await SharedPreferences.getInstance();
    _recentSizes.remove(size); // Remove if exists
    _recentSizes.insert(0, size); // Add to beginning
    if (_recentSizes.length > 10) {
      _recentSizes = _recentSizes.take(10).toList(); // Keep only 10
    }
    await prefs.setStringList('recent_sizes', _recentSizes);
    setState(() {});
  }

  // Save recently added color
  Future<void> _saveRecentColor(String color) async {
    final prefs = await SharedPreferences.getInstance();
    _recentColors.remove(color); // Remove if exists
    _recentColors.insert(0, color); // Add to beginning
    if (_recentColors.length > 20) {
      _recentColors = _recentColors.take(20).toList(); // Keep only 20
    }
    await prefs.setStringList('recent_colors', _recentColors);
    setState(() {});
  }

  void _selectRecentColor(String colorName) {
    // Create a new color item with the selected recent color
    final newColorItem = {
      'name': colorName,
      'image': null, // No image initially
      'allImages': <File>[],
    };

    setState(() {
      _colorItems.add(newColorItem);
    });

    // Optionally, save this new color to recent colors again
    _saveRecentColor(colorName);
  }

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

  // Helper function to get text color for background
  Color _getTextColorForBackground(Color backgroundColor) {
    // Calculate luminance to determine if text should be white or black
    double luminance = (0.299 * backgroundColor.red +
        0.587 * backgroundColor.green +
        0.114 * backgroundColor.blue) / 255;
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _availableQtyController.dispose();
    _availableQtyFocusNode.dispose();
    _descController.dispose();
    _tempNameController.dispose();
    _tempValueController.dispose();
    _dispatchTimeController.dispose();
    super.dispose();
  }

  Future<void> _addPriceSlab() async {
    final priceCtrl = TextEditingController();
    final moqCtrl = TextEditingController();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title and close button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Add Price Slab',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.grey),
                            onPressed: () => Navigator.pop(ctx),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Price input field
                      TextField(
                        controller: priceCtrl,
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          prefixText: '₹ ',
                          prefixStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          hintText: 'Price (per piece)',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFF25D366),
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // MOQ field with label
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Minimum Order Quantity (MOQ):',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: moqCtrl,
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 14),
                                  decoration: InputDecoration(
                                    suffixText: 'PCS',
                                    suffixStyle: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.black87,
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF25D366),
                                        width: 2,
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Recommendation text
                      Row(
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Colors.orange.shade700,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.help_outline,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Add button
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: ElevatedButton(
                          onPressed: () {
                            final p = double.tryParse(priceCtrl.text.trim());
                            final m = int.tryParse(moqCtrl.text.trim());
                            if (p != null && m != null && m > 0) {
                              Navigator.pop(ctx, {
                                'price': p,
                                'moq': m,
                                'sizes': [],
                              });
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade700,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Add',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (result != null) {
      setState(() {
        _priceSlabs.add(result);
      });
    }
  }

  Future<void> _showSizeSelectionModal() async {
    final Set<String> tempSelectedSizes = Set<String>.from(_selectedSizes);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title and + button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Select Sizes',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          GestureDetector(
                            onTap: () async {
                              // Open Add New Size modal
                              final newSizes = await _showAddNewSizeModal(ctx);
                              if (newSizes != null && newSizes.isNotEmpty) {
                                setState(() {
                                  // Combine all sizes with comma and add as single item
                                  final combinedSize = newSizes.join(', ');
                                  _sizes.add(combinedSize);
                                });
                                setModalState(() {});
                              }
                            },
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: const Color(0xFF25D366),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.add,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Select Sizes',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Recently selected sizes section
                      if (_recentSizes.isNotEmpty) ...[
                        const Text(
                          'Recently Selected',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ..._recentSizes.map((s) {
                          final selected = tempSelectedSizes.contains(s);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: GestureDetector(
                              onTap: () {
                                setModalState(() {
                                  if (selected) {
                                    tempSelectedSizes.remove(s);
                                  } else {
                                    tempSelectedSizes.add(s);
                                  }
                                });
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: selected
                                        ? const Color(0xFF25D366).withOpacity(0.6)
                                        : Colors.grey.shade200,
                                    width: selected ? 1.5 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                  color: selected
                                      ? const Color(0xFF25D366).withOpacity(0.08)
                                      : Colors.white,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? const Color(
                                          0xFF25D366,
                                        ).withOpacity(0.8)
                                            : Colors.transparent,
                                        border: Border.all(
                                          color: selected
                                              ? const Color(
                                            0xFF25D366,
                                          ).withOpacity(0.6)
                                              : Colors.grey.shade300,
                                          width: 1.5,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: selected
                                          ? const Icon(
                                        Icons.check,
                                        size: 10,
                                        color: Colors.white,
                                      )
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      s,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: selected
                                            ? const Color(
                                          0xFF25D366,
                                        ).withOpacity(0.8)
                                            : Colors.black87,
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Recent',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.blue.shade700,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                        const SizedBox(height: 12),
                        const Text(
                          'All Sizes',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      // Size checkboxes - one per line
                      ..._sizes.map((s) {
                        final selected = tempSelectedSizes.contains(s);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: GestureDetector(
                            onTap: () {
                              setModalState(() {
                                if (selected) {
                                  tempSelectedSizes.remove(s);
                                } else {
                                  tempSelectedSizes.add(s);
                                }
                              });
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: selected
                                      ? const Color(0xFF25D366).withOpacity(0.6)
                                      : Colors.grey.shade200,
                                  width: selected ? 1.5 : 1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                                color: selected
                                    ? const Color(0xFF25D366).withOpacity(0.08)
                                    : Colors.white,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? const Color(
                                        0xFF25D366,
                                      ).withOpacity(0.8)
                                          : Colors.transparent,
                                      border: Border.all(
                                        color: selected
                                            ? const Color(
                                          0xFF25D366,
                                        ).withOpacity(0.6)
                                            : Colors.grey.shade300,
                                        width: 1.5,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: selected
                                        ? const Icon(
                                      Icons.check,
                                      size: 10,
                                      color: Colors.white,
                                    )
                                        : null,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    s,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: selected
                                          ? const Color(
                                        0xFF25D366,
                                      ).withOpacity(0.8)
                                          : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                      const SizedBox(height: 12),
                      // Done button
                      SizedBox(
                        width: double.infinity,
                        height: 36,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _selectedSizes.clear();
                              _selectedSizes.addAll(tempSelectedSizes);
                            });
                            // Save recently selected sizes
                            for (final size in tempSelectedSizes) {
                              _saveRecentSize(size);
                            }
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          child: const Text(
                            'Done',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAddAttributeModal() async {
    final nameController = TextEditingController();
    final valueController = TextEditingController();
    final List<String> valueOptions = [];

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title and close button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Add Attribute',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.grey,
                              size: 18,
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Show existing attributes
                      ..._attributes.entries.map((e) {
                        final selectedValue =
                            _selectedAttributeValues[e.key] ??
                                (e.value.isNotEmpty ? e.value.first : '');
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  e.key,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      selectedValue,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.keyboard_arrow_down,
                                      size: 14,
                                      color: Colors.grey.shade400,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      const SizedBox(height: 8),
                      // Add Custom Attribute section
                      const Text(
                        '+ Add Custom Attribute',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // + button above Name and Value
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          GestureDetector(
                            onTap: () {
                              final value = valueController.text.trim();
                              if (value.isNotEmpty) {
                                setModalState(() {
                                  valueOptions.add(value);
                                  valueController.clear();
                                });
                              }
                            },
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: const Color(0xFF25D366),
                                borderRadius: BorderRadius.circular(6),
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
                      const SizedBox(height: 6),
                      // Name and Value in same line
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: nameController,
                              style: const TextStyle(fontSize: 12),
                              decoration: InputDecoration(
                                hintText: 'Name',
                                hintStyle: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: valueController,
                              style: const TextStyle(fontSize: 12),
                              decoration: InputDecoration(
                                hintText: 'Value',
                                hintStyle: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                suffixIcon: valueOptions.isEmpty
                                    ? Icon(
                                  Icons.keyboard_arrow_down,
                                  color: Colors.grey.shade400,
                                  size: 16,
                                )
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Show added value options
                      if (valueOptions.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: valueOptions.map((value) {
                            return Chip(
                              label: Text(
                                value,
                                style: const TextStyle(fontSize: 11),
                              ),
                              onDeleted: () {
                                setModalState(() {
                                  valueOptions.remove(value);
                                });
                              },
                              deleteIcon: const Icon(Icons.close, size: 12),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 12),
                      // Save button
                      SizedBox(
                        width: double.infinity,
                        height: 32,
                        child: ElevatedButton(
                          onPressed: () {
                            final name = nameController.text.trim();
                            final value = valueOptions.isNotEmpty
                                ? valueOptions.first
                                : valueController.text.trim();
                            if (name.isNotEmpty && value.isNotEmpty) {
                              setState(() {
                                _attributes[name] = [value];
                                _selectedAttributeValues[name] = value;
                              });
                              Navigator.pop(ctx);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          child: const Text(
                            'Save',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAddValueToAttribute(String attributeName) async {
    final valueController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Add Value to $attributeName',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => Navigator.pop(ctx),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: valueController,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Enter value',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 32,
                      child: ElevatedButton(
                        onPressed: () {
                          final value = valueController.text.trim();
                          if (value.isNotEmpty) {
                            setState(() {
                              if (!_attributes[attributeName]!.contains(
                                value,
                              )) {
                                _attributes[attributeName]!.add(value);
                              }
                            });
                            Navigator.pop(ctx);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                        ),
                        child: const Text(
                          'Add',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showValueDropdown(
      String attributeName,
      List<String> values,
      ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select $attributeName',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...values.map((value) {
                  return ListTile(
                    title: Text(value, style: const TextStyle(fontSize: 12)),
                    onTap: () {
                      setState(() {
                        _selectedAttributeValues[attributeName] = value;
                      });
                      Navigator.pop(ctx);
                    },
                  );
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditAttributeAndValue(
      String attributeName,
      String currentValue,
      ) async {
    final nameController = TextEditingController(text: attributeName);
    final valueController = TextEditingController(text: currentValue);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Edit Attribute',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Attribute Name',
                    hintText: 'Enter attribute name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: valueController,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Attribute Value',
                    hintText: 'Enter attribute value',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: ElevatedButton(
                    onPressed: () {
                      final newName = nameController.text.trim();
                      final newValue = valueController.text.trim();
                      if (newName.isNotEmpty && newValue.isNotEmpty) {
                        setState(() {
                          // Update attribute name if changed
                          if (newName != attributeName) {
                            final values = _attributes[attributeName]!;
                            final selectedValue =
                            _selectedAttributeValues[attributeName];
                            _attributes.remove(attributeName);
                            _attributes[newName] = values;
                            if (selectedValue != null) {
                              _selectedAttributeValues.remove(attributeName);
                              _selectedAttributeValues[newName] = selectedValue;
                            }
                            attributeName = newName;
                          }
                          // Update the current value
                          final index = _attributes[attributeName]!.indexOf(
                            currentValue,
                          );
                          if (index != -1) {
                            _attributes[attributeName]![index] = newValue;
                            if (_selectedAttributeValues[attributeName] ==
                                currentValue) {
                              _selectedAttributeValues[attributeName] =
                                  newValue;
                            }
                          }
                        });
                        Navigator.pop(ctx);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                    ),
                    child: const Text('Save', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditAttribute(String attributeName) async {
    final nameController = TextEditingController(text: attributeName);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Edit Attribute',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Attribute name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: ElevatedButton(
                    onPressed: () {
                      final newName = nameController.text.trim();
                      if (newName.isNotEmpty && newName != attributeName) {
                        setState(() {
                          final values = _attributes[attributeName]!;
                          final selectedValue =
                          _selectedAttributeValues[attributeName];
                          _attributes.remove(attributeName);
                          _attributes[newName] = values;
                          if (selectedValue != null) {
                            _selectedAttributeValues.remove(attributeName);
                            _selectedAttributeValues[newName] = selectedValue;
                          }
                        });
                        Navigator.pop(ctx);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                    ),
                    child: const Text('Save', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _deleteAttribute(String attributeName) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Delete Attribute'),
          content: Text('Are you sure you want to delete "$attributeName"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _attributes.remove(attributeName);
                  _selectedAttributeValues.remove(attributeName);
                });
                Navigator.pop(ctx);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEditAttributeValue(
      String attributeName,
      String currentValue,
      ) async {
    final valueController = TextEditingController(text: currentValue);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Edit Value for $attributeName',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: valueController,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Enter value',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: ElevatedButton(
                    onPressed: () {
                      final newValue = valueController.text.trim();
                      if (newValue.isNotEmpty && newValue != currentValue) {
                        setState(() {
                          final index = _attributes[attributeName]!.indexOf(
                            currentValue,
                          );
                          if (index != -1) {
                            _attributes[attributeName]![index] = newValue;
                            if (_selectedAttributeValues[attributeName] ==
                                currentValue) {
                              _selectedAttributeValues[attributeName] =
                                  newValue;
                            }
                          }
                        });
                        Navigator.pop(ctx);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                    ),
                    child: const Text('Save', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _deleteAttributeValue(String attributeName, String value) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Delete Value'),
          content: Text(
            'Are you sure you want to delete "$value" from "$attributeName"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _attributes[attributeName]!.remove(value);
                  if (_selectedAttributeValues[attributeName] == value) {
                    if (_attributes[attributeName]!.isNotEmpty) {
                      _selectedAttributeValues[attributeName] =
                          _attributes[attributeName]!.first;
                    } else {
                      _selectedAttributeValues.remove(attributeName);
                    }
                  }
                });
                Navigator.pop(ctx);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Future<List<String>?> _showAddNewSizeModal(BuildContext parentContext) async {
    final sizeNameController = TextEditingController();
    final List<String> tempSizes = [];

    return await showDialog<List<String>>(
      context: parentContext,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title and close button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Add New Size',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.grey,
                              size: 18,
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Size Name label
                      const Text(
                        'Size Name',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Size Name input with tick circle
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: sizeNameController,
                              textCapitalization: TextCapitalization.characters,
                              style: const TextStyle(fontSize: 12),
                              decoration: InputDecoration(
                                hintText: 'e.g. Free Size, 3XL, 500g',
                                hintStyle: const TextStyle(fontSize: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                              onSubmitted: (value) {
                                final sizeName = value.trim();
                                if (sizeName.isNotEmpty) {
                                  setModalState(() {
                                    tempSizes.add(sizeName);
                                    sizeNameController.clear();
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Tick circle button
                          GestureDetector(
                            onTap: () {
                              final sizeName = sizeNameController.text.trim();
                              if (sizeName.isNotEmpty) {
                                setModalState(() {
                                  tempSizes.add(sizeName);
                                  sizeNameController.clear();
                                });
                              }
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFF25D366),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Display added sizes in one line
                      if (tempSizes.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: tempSizes.map((size) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Chip(
                                  label: Text(
                                    size,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  onDeleted: () {
                                    setModalState(() {
                                      tempSizes.remove(size);
                                    });
                                  },
                                  deleteIcon: const Icon(Icons.close, size: 14),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  labelPadding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      // Save Size button
                      SizedBox(
                        width: double.infinity,
                        height: 36,
                        child: ElevatedButton(
                          onPressed: () {
                            if (tempSizes.isNotEmpty) {
                              // Return the list of sizes to be combined
                              Navigator.pop(ctx, tempSizes);
                            } else {
                              Navigator.pop(ctx);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          child: const Text(
                            'Save Size',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _addNewColor() async {
    final result = await Navigator.push<List<File>>(
      context,
      MaterialPageRoute(
        builder: (context) =>
        const CameraInterfaceScreen(returnImagesDirectly: true),
      ),
    );
    File? picked;
    if (result != null && result.isNotEmpty) {
      picked = result.first;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Add Color'),
          content: TextField(
            controller: ctrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Enter color name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    if (name != null && name.isNotEmpty) {
      // Check for duplicate colors (case-insensitive)
      final isDuplicate = _colorItems.any((item) =>
      item['name'].toString().toLowerCase() == name.toLowerCase());

      if (!isDuplicate) {
        setState(() {
          _colorItems.add({'name': name, 'image': picked});
        });
        _saveRecentColor(name); // Save to recent colors
      } else {
        // Show error message for duplicate color
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Color "$name" already exists!'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveProduct(String type) async {
    try {
      // Show loading
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
          const Center(child: CircularProgressIndicator()),
        );
      }

      // Convert _colorItems to JSON-serializable format (File objects to paths)
      final variations = _colorItems.map((item) {
        final colorName = item['name'] as String;
        final Map<String, dynamic> variation = {
          'name': colorName,
        };

        // Convert File to path string
        if (item['image'] != null) {
          final image = item['image'];
          if (image is File) {
            variation['image'] = image.path;
          } else {
            variation['image'] = image.toString();
          }
        }

        // Convert allImages List<File> to List<String>
        if (item['allImages'] != null) {
          final allImages = item['allImages'] as List;
          variation['allImages'] = allImages.map((img) {
            if (img is File) {
              return img.path;
            }
            return img.toString();
          }).toList();
        }

        // If stock mode is color_size, include stock data for this color
        if (_stockMode == 'color_size' && _stockByColorSize.containsKey(colorName)) {
          variation['stock'] = Map<String, int>.from(_stockByColorSize[colorName]!);
          // Calculate total stock for this color
          final totalStock = _stockByColorSize[colorName]!.values.fold<int>(0, (a, b) => a + b);
          variation['totalStock'] = totalStock;
        }

        return variation;
      }).toList();

      // Prepare product data
      final productData = {
        'name': _nameController.text.trim(),
        'category': _category ?? '',
        // For simple stock, use availableQty. For color_size, calculate total from all colors. For always_available, set to empty or special value
        'availableQty': _stockMode == 'simple'
            ? _availableQtyController.text.trim()
            : _stockMode == 'color_size'
            ? _stockByColorSize.values
            .expand((sizeMap) => sizeMap.values)
            .fold<int>(0, (a, b) => a + b)
            .toString()
            : '0', // For always_available, set to 0 or empty
        'stockMode': _stockMode, // 'simple', 'color_size', or 'always_available'
        'priceSlabs': _priceSlabs,
        'variations': variations,
        'attributes': _attributes,
        'selectedAttributeValues': _selectedAttributeValues,
        'description': _descController.text.trim(),
        'sizes': _selectedSizes, // Keep as Set<String> - ProductService expects Set<String>?
        'marketplaceEnabled': _marketplaceEnabled,
        // Include full stock data for color_size mode
        'stockByColorSize': _stockMode == 'color_size'
            ? _stockByColorSize.map((color, sizeMap) =>
            MapEntry(color, Map<String, int>.from(sizeMap)))
            : null,
        // Always Available / On Demand fields
        'dispatchTime': _stockMode == 'always_available' ? _dispatchTimeController.text.trim() : null,
        'showMadeOnOrderBadge': _stockMode == 'always_available' ? _showMadeOnOrderBadge : false,
      };

      // Save to database using ProductService
      final result = await ProductService.saveProduct(
        productData: productData,
        images: widget.images,
        status: type, // 'draft' or 'publish'
      );

      // Close loading dialog
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
      }

      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                type == 'draft'
                    ? 'Product saved as draft successfully'
                    : 'Product published successfully',
              ),
              backgroundColor: Colors.green,
            ),
          );

          // If published, navigate to profile tab
          if (type == 'publish') {
            // Pop all screens and navigate to ChatHomePage with profile tab
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) => const ChatHomePage(initialTabIndex: 2),
              ),
                  (route) => false,
            );
          } else {
            Navigator.pop(context); // Go back for draft
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Error saving product'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog if open
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving product: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  PreferredSizeWidget _header() {
    return AppBar(
      backgroundColor: const Color(0xFF1F1F1F),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'Add Product',
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      centerTitle: true,
    );
  }

  Widget _sectionTitle(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _card(Widget child) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5);
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final borderColor = isDark ? Colors.grey.shade700 : Colors.grey.shade300;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: _header(),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Product Name'),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    style: TextStyle(fontSize: 14, color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Enter product name',
                      hintStyle: TextStyle(fontSize: 14, color: hintColor),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF2E2E2E) : Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        borderSide: BorderSide(
                          color: Color(0xFF25D366),
                          width: 2,
                        ),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _sectionTitle('Category'),
                  InkWell(
                    onTap: () async {
                      final picked = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CategorySelectionScreen(),
                        ),
                      );
                      if (picked != null) {
                        setState(() => _category = picked);
                        _saveRecentCategory(picked); // Save to recent categories
                        Future.delayed(const Duration(milliseconds: 300), () {
                          _availableQtyFocusNode.requestFocus();
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2E2E2E) : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _category ?? 'Select category',
                              style: TextStyle(
                                color: (_category == null)
                                    ? hintColor
                                    : textColor,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right, color: hintColor),
                        ],
                      ),
                    ),
                  ),
                  // Recently selected categories
                  if (_recentCategories.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.green.shade900.withOpacity(0.3) : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? Colors.green.shade700 : Colors.green.shade200,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recently Selected Categories',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.green.shade300 : Colors.green.shade700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: _recentCategories.take(5).map((category) {
                              return GestureDetector(
                                onTap: () {
                                  setState(() => _category = category);
                                  _saveRecentCategory(category);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF2E2E2E) : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isDark ? Colors.green.shade600 : Colors.green.shade300,
                                    ),
                                  ),
                                  child: Text(
                                    category,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? Colors.green.shade300 : Colors.green.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Available Quantity'),
                  const SizedBox(height: 12),
                  // Modern segmented control
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _stockMode = 'color_size';
                                if (_selectedColorForStock == null &&
                                    _colorItems.isNotEmpty) {
                                  _selectedColorForStock =
                                  _colorItems.first['name'] as String;
                                }
                              });
                            },
                            child: Container(
                              height: 40,
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: _stockMode == 'color_size'
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: _stockMode == 'color_size'
                                    ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  'Color & Size',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _stockMode == 'color_size'
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: _stockMode == 'color_size'
                                        ? const Color(0xFF25D366)
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _stockMode = 'simple';
                              });
                            },
                            child: Container(
                              height: 40,
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: _stockMode == 'simple'
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: _stockMode == 'simple'
                                    ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  'Simple',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _stockMode == 'simple'
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: _stockMode == 'simple'
                                        ? const Color(0xFF25D366)
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _stockMode = 'always_available';
                              });
                            },
                            child: Container(
                              height: 40,
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: _stockMode == 'always_available'
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: _stockMode == 'always_available'
                                    ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  'Unlimited',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _stockMode == 'always_available'
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: _stockMode == 'always_available'
                                        ? const Color(0xFF25D366)
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_stockMode == 'simple') ...[
                    Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _availableQtyController,
                        focusNode: _availableQtyFocusNode,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: '0',
                          hintStyle: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade400,
                          ),
                          suffixIcon: Container(
                            margin: const EdgeInsets.all(8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade200,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'PCS',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                      ),
                    ),
                  ] else if (_stockMode == 'always_available') ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.inventory_2_outlined,
                                  color: Colors.green.shade700,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Unlimited Stock',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Accept orders without tracking inventory',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Show Made on Order badge checkbox
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: _showMadeOnOrderBadge,
                                  onChanged: (value) {
                                    setState(() {
                                      _showMadeOnOrderBadge = value ?? false;
                                    });
                                  },
                                  activeColor: const Color(0xFF25D366),
                                ),
                                const Expanded(
                                  child: Text(
                                    'Show "Made on Order" badge',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_showMadeOnOrderBadge) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'This label will highlight that the product is manufactured after order confirmation.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Dispatch Time',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _dispatchTimeController,
                              keyboardType: TextInputType.text,
                              style: const TextStyle(fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Enter dispatch time (e.g., 5-7 days)',
                                hintStyle: const TextStyle(fontSize: 14),
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                                ),
                                focusedBorder: const OutlineInputBorder(
                                  borderRadius:
                                  BorderRadius.all(Radius.circular(8)),
                                  borderSide: BorderSide(
                                    color: Color(0xFF25D366),
                                    width: 2,
                                  ),
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Price & MoQ'),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ..._priceSlabs.asMap().entries.map((entry) {
                            final index = entry.key;
                            final slab = entry.value;
                            final sizes = slab['sizes'] as List<dynamic>? ?? [];
                            final sizesText = sizes.isNotEmpty ? sizes.join(' ') : '';
                            return Container(
                              margin: const EdgeInsets.only(right: 10),
                              child: SizedBox(
                                width: 140,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        color: Colors.grey.shade100,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Price slab ${index + 1}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade700,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '₹ ${slab['price']}/pc',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            'Min. order: ${slab['moq']} pcs',
                                            style: TextStyle(
                                              color: Colors.grey.shade700,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (sizesText.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Size $sizesText',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black87,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                          // Add price slab box
                          Container(
                            margin: const EdgeInsets.only(right: 10),
                            child: GestureDetector(
                              onTap: _addPriceSlab,
                              child: SizedBox(
                                width: 140,
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                      style: BorderStyle.solid,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                    color: Colors.grey.shade50,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add,
                                        color: Colors.grey.shade600,
                                        size: 24,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Add price slab',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
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
            ),
            // Separate card for Add New Size
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFF25D366),
                        width: 1.5,
                        style: BorderStyle.solid,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.grey.shade50,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: _showSizeSelectionModal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add,
                                color: const Color(0xFF25D366),
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Add Size',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: const Color(0xFF25D366),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (_selectedSizes.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.check_circle,
                                  color: const Color(0xFF25D366),
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '(${_selectedSizes.join(', ')})',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ] else ...[
                                const SizedBox(width: 8),
                                Text(
                                  '(S, M, L, XL, XXL)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (_selectedSizes.isNotEmpty) ...[
                          const Spacer(),
                          GestureDetector(
                            onTap: _showSizeSelectionModal,
                            child: Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.orange,
                              size: 16,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Recently selected sizes
                  if (_recentSizes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.blue.shade900.withOpacity(0.3) : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? Colors.blue.shade700 : Colors.blue.shade200,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recently Selected Sizes',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: _recentSizes.take(8).map((size) {
                              final isSelected = _selectedSizes.contains(size);
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (!_selectedSizes.contains(size)) {
                                      _selectedSizes.add(size);
                                      _saveRecentSize(size);
                                    }
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? (isDark ? Colors.blue.shade700 : Colors.blue.shade100)
                                        : (isDark ? const Color(0xFF2E2E2E) : Colors.white),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? (isDark ? Colors.blue.shade400 : Colors.blue.shade400)
                                          : (isDark ? Colors.blue.shade600 : Colors.blue.shade300),
                                    ),
                                  ),
                                  child: Text(
                                    size,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? (isSelected ? Colors.white : Colors.blue.shade300)
                                          : Colors.blue.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Variation label and Add New Color button row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Variation label - left side
                      const Text(
                        'Variation',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      // Add New Color button - right side (smaller and thinner)
                      OutlinedButton.icon(
                        onPressed: _addNewColor,
                        icon: const Icon(
                          Icons.add,
                          color: Color(0xFF25D366),
                          size: 18,
                        ),
                        label: const Text(
                          'Add New Color',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black87,
                          side: const BorderSide(
                            color: Color(0xFF25D366),
                            width: 1,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          minimumSize: const Size(0, 36),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Color tab - selected (orange/yellow)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Color',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Recently added colors - show before variation items if no colors added yet
                  if (_recentColors.isNotEmpty && _colorItems.isEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.purple.shade900.withOpacity(0.3) : Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? Colors.purple.shade700 : Colors.purple.shade200,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.history,
                                size: 14,
                                color: isDark ? Colors.purple.shade300 : Colors.purple.shade700,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Recent Colors (Tap to add)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.purple.shade300 : Colors.purple.shade700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _recentColors.take(10).map((color) {
                              final isAdded = _colorItems.any((item) =>
                              item['name'].toString().toLowerCase() == color.toLowerCase());
                              return GestureDetector(
                                onTap: isAdded ? null : () {
                                  setState(() {
                                    _colorItems.add({'name': color, 'image': null});
                                    _saveRecentColor(color);
                                  });
                                },
                                child: Opacity(
                                  opacity: isAdded ? 0.5 : 1.0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: _getColorFromName(color),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isDark ? Colors.grey.shade600 : Colors.grey.shade300,
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isAdded) ...[
                                          const Icon(Icons.check, size: 14, color: Colors.white),
                                          const SizedBox(width: 4),
                                        ],
                                        Text(
                                          color,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: _getTextColorForBackground(_getColorFromName(color)),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ..._colorItems.map((item) {
                          final File? f = item['image'] as File?;
                          final colorName = item['name'] as String;
                          final color = _getColorFromName(colorName);
                          final isSelected = colorName == _selectedColorForStock;
                          final isRecentColor = _recentColors.contains(colorName);
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedColorForStock = colorName;
                              });
                            },
                            child: Container(
                              width: 100,
                              margin: const EdgeInsets.only(right: 12),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.black
                                      : (isRecentColor ? Colors.purple.shade400 : (isDark ? Colors.grey.shade700 : Colors.grey.shade300)),
                                  width: isSelected ? 1.5 : (isRecentColor ? 1.5 : 1),
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Header with color name and units badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(11),
                                        topRight: Radius.circular(11),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (isRecentColor) ...[
                                                const Icon(
                                                  Icons.history,
                                                  size: 12,
                                                  color: Colors.white,
                                                ),
                                                const SizedBox(width: 4),
                                              ],
                                              Flexible(
                                                child: Text(
                                                  colorName,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Builder(
                                          builder: (context) {
                                            final totalUnits = (_stockByColorSize[
                                            colorName] ??
                                                {})
                                                .values
                                                .fold<int>(0, (a, b) => a + b);
                                            if (totalUnits > 0) {
                                              return Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: Colors.green,
                                                  borderRadius:
                                                  BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  '+$totalUnits',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              );
                                            }
                                            return const SizedBox.shrink();
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  ClipRRect(
                                    borderRadius: const BorderRadius.only(
                                      bottomLeft: Radius.circular(11),
                                      bottomRight: Radius.circular(11),
                                    ),
                                    child: SizedBox(
                                      width: 100,
                                      height: 100,
                                      child: f != null
                                          ? Image.file(f, fit: BoxFit.cover)
                                          : Container(
                                        color: color,
                                        child: Center(
                                          child: Text(
                                            colorName.substring(0, 1).toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                              color: _getTextColorForBackground(color),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                  // Recently added colors
                  if (_recentColors.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.purple.shade900.withOpacity(0.3) : Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? Colors.purple.shade700 : Colors.purple.shade200,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recently Added Colors (Last 20)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.purple.shade300 : Colors.purple.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: _recentColors.take(20).map((color) {
                              final isDuplicate = _colorItems.any((item) =>
                              item['name'].toString().toLowerCase() == color.toLowerCase());

                              return GestureDetector(
                                onTap: isDuplicate ? null : () {
                                  // Add color from recent list
                                  setState(() {
                                    _colorItems.add({'name': color, 'image': null});
                                  });
                                },
                                child: Opacity(
                                  opacity: isDuplicate ? 0.5 : 1.0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: _getColorFromName(color),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isDark ? Colors.grey.shade600 : Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Text(
                                      color,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: _getTextColorForBackground(_getColorFromName(color)),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_stockMode == 'color_size') ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text(
                          'Quick Stock Entry',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _quickStockController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Enter Qty',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                BorderSide(color: Colors.grey.shade300),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () {
                            final q = int.tryParse(
                                _quickStockController.text.trim()) ??
                                0;
                            final color = _selectedColorForStock;
                            if (q > 0 && color != null) {
                              setState(() {
                                _stockByColorSize.putIfAbsent(
                                    color, () => {});
                                for (final s in (_selectedSizes.isNotEmpty
                                    ? _selectedSizes
                                    : _sizes)) {
                                  _stockByColorSize[color]![s] = q;
                                }
                              });
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            side: const BorderSide(color: Color(0xFF25D366)),
                            foregroundColor: const Color(0xFF25D366),
                            textStyle: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          child: const Text('Apply to all sizes'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Checkbox(
                          value: _applyQuickToAllColors,
                          onChanged: (v) {
                            setState(() {
                              _applyQuickToAllColors = v ?? false;
                              final q = int.tryParse(
                                  _quickStockController.text.trim()) ??
                                  0;
                              if (_applyQuickToAllColors && q > 0) {
                                for (final item in _colorItems) {
                                  final color = item['name'] as String;
                                  _stockByColorSize.putIfAbsent(
                                      color, () => {});
                                  for (final s in (_selectedSizes.isNotEmpty
                                      ? _selectedSizes
                                      : _sizes)) {
                                    _stockByColorSize[color]![s] = q;
                                  }
                                }
                              } else {
                                // Remove auto-applied stock from all colors except currently selected color
                                for (final item in _colorItems) {
                                  final color = item['name'] as String;
                                  if (color != _selectedColorForStock) {
                                    _stockByColorSize.remove(color);
                                  }
                                }
                              }
                            });
                          },
                        ),
                        const Text('Apply this stock to all colors'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (_selectedColorForStock != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Stock for: ${_selectedColorForStock!}',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${(_stockByColorSize[_selectedColorForStock!] ?? {}).values.fold<int>(0, (a, b) => a + b)} Units',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Column(
                        children:
                        (_selectedSizes.isNotEmpty ? _selectedSizes : _sizes)
                            .map((s) {
                          final cs = _stockByColorSize.putIfAbsent(
                              _selectedColorForStock!, () => {});
                          final qty = cs[s] ?? 0;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                    child:
                                    Text(s, style: const TextStyle(fontSize: 13))),
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: () {
                                        setState(() {
                                          final cur = cs[s] ?? 0;
                                          if (cur > 0) cs[s] = cur - 1;
                                        });
                                      },
                                      icon:
                                      const Icon(Icons.remove_circle_outline),
                                    ),
                                    Text('$qty',
                                        style:
                                        const TextStyle(fontWeight: FontWeight.w600)),
                                    IconButton(
                                      onPressed: () {
                                        setState(() {
                                          final cur = cs[s] ?? 0;
                                          cs[s] = cur + 1;
                                        });
                                      },
                                      icon: const Icon(Icons.add_circle_outline),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Attributes header with expand/collapse
                  InkWell(
                    onTap: () {
                      setState(() {
                        _attributesExpanded = !_attributesExpanded;
                      });
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _sectionTitle('Attributes'),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () async {
                                final result = await Navigator.push<
                                    Map<String, dynamic>>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        AttributesManagementScreen(
                                          attributes: _attributes,
                                          selectedAttributeValues:
                                          _selectedAttributeValues,
                                        ),
                                  ),
                                );
                                if (result != null) {
                                  setState(() {
                                    _attributes.clear();
                                    _attributes.addAll(
                                      Map<String, List<String>>.from(
                                        result['attributes'],
                                      ),
                                    );
                                    _selectedAttributeValues.clear();
                                    _selectedAttributeValues.addAll(
                                      Map<String, String>.from(
                                        result['selectedValues'],
                                      ),
                                    );
                                  });
                                }
                              },
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF25D366),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.add,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              _attributesExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.chevron_right,
                              color: Colors.grey,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_attributesExpanded) ...[
                    const SizedBox(height: 6),
                    ..._attributes.entries.map((e) {
                      final values = e.value;
                      final selectedValue = _selectedAttributeValues[e.key] ?? '';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.key,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Fixed width value box
                            GestureDetector(
                              onTap: () => _showValueDropdown(e.key, values),
                              child: Container(
                                width: 120,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        selectedValue,
                                        style: const TextStyle(fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.keyboard_arrow_down,
                                      size: 16,
                                      color: Colors.grey,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Expand/Collapse arrow
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _expandedAttributeItems[e.key] =
                                  !(_expandedAttributeItems[e.key] ?? false);
                                });
                              },
                              child: Icon(
                                (_expandedAttributeItems[e.key] ?? false)
                                    ? Icons.keyboard_arrow_up
                                    : Icons.chevron_right,
                                color: Colors.grey,
                                size: 20,
                              ),
                            ),
                            // Show buttons only when expanded
                            if (_expandedAttributeItems[e.key] ?? false) ...[
                              const SizedBox(width: 4),
                              // + button
                              GestureDetector(
                                onTap: () =>
                                    _showAddValueToAttribute(e.key),
                                child: Container(
                                  width: 24,
                                  height: 24,
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
                              const SizedBox(width: 4),
                              // Edit button
                              GestureDetector(
                                onTap: () => _showEditAttributeAndValue(
                                  e.key,
                                  selectedValue,
                                ),
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.edit,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              // Delete button
                              GestureDetector(
                                onTap: () => _deleteAttribute(e.key),
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.delete,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ],
              ),
            ),
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          _sectionTitle('Product Description'),
                          const Text(' *', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                      Text(
                        '${_descController.text.length} / 500 chars',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _descController,
                    maxLines: 6,
                    maxLength: 500,
                    style: const TextStyle(fontSize: 14),
                    onChanged: (value) {
                      setState(() {});
                    },
                    decoration: InputDecoration(
                      hintText: 'Enter product description',
                      hintStyle: const TextStyle(fontSize: 14),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        borderSide: BorderSide(
                          color: Color(0xFF25D366),
                          width: 2,
                        ),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Marketplace Toggle
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.store,
                                color: Color(0xFF25D366), size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Marketplace',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        Switch(
                          value: _marketplaceEnabled,
                          onChanged: (value) {
                            setState(() {
                              _marketplaceEnabled = value;
                            });
                          },
                          activeColor: const Color(0xFF25D366),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _saveProduct('draft'),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade400),
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: const Text(
                        'Save as Draft',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _saveProduct('publish'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: const Text(
                        'Publish',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
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

class AddProductPriceMoqScreen extends StatefulWidget {
  final List<File> images;
  final String? name;
  final String? category;
  final String sellingUnit;
  final bool varSize;
  final bool varColor;
  final double price;
  final int stock;
  final int moq;

  const AddProductPriceMoqScreen({
    super.key,
    required this.images,
    this.name,
    this.category,
    required this.sellingUnit,
    required this.varSize,
    required this.varColor,
    required this.price,
    required this.stock,
    required this.moq,
  });

  @override
  State<AddProductPriceMoqScreen> createState() =>
      _AddProductPriceMoqScreenState();
}

class _AddProductPriceMoqScreenState extends State<AddProductPriceMoqScreen> {
  bool _autoCalc = true;
  int _availableQty = 126;
  final List<Map<String, dynamic>> _priceSlabs = [
    {'price': 6.45, 'moq': 2},
    {'price': 6.09, 'moq': 150},
  ];
  final List<String> _colors = [
    'Blue',
    'Gray',
    'Brown',
    'Black',
    'Pink',
    'Dark Blue',
  ];
  final Map<String, String> _attributes = {
    'Fabric': 'Cotton',
    'Fit': 'Regular',
    'Sleeve': 'Half Sleeve',
    'Pattern': 'Solid',
  };
  final TextEditingController _descController = TextEditingController();
  final List<Map<String, dynamic>> _colorItems = [];
  List<String> _recentColors = []; // Add recent colors list

  @override
  void initState() {
    super.initState();
    _loadRecentlySelectedItems(); // Load recent colors
    for (int i = 0; i < _colors.length; i++) {
      _colorItems.add({
        'name': _colors[i],
        'image': i < widget.images.length ? widget.images[i] : null,
      });
    }
  }

  // Load recently selected items from SharedPreferences
  Future<void> _loadRecentlySelectedItems() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _recentColors = prefs.getStringList('recent_colors') ?? [];
    });
  }

  // Save recently added color
  Future<void> _saveRecentColor(String color) async {
    final prefs = await SharedPreferences.getInstance();
    _recentColors.remove(color); // Remove if exists
    _recentColors.insert(0, color); // Add to beginning
    if (_recentColors.length > 20) {
      _recentColors = _recentColors.take(20).toList(); // Keep only 20
    }
    await prefs.setStringList('recent_colors', _recentColors);
    setState(() {});
  }

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

  // Helper function to get text color for background
  Color _getTextColorForBackground(Color backgroundColor) {
    // Calculate luminance to determine if text should be white or black
    double luminance = (0.299 * backgroundColor.red +
        0.587 * backgroundColor.green +
        0.114 * backgroundColor.blue) / 255;
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  Widget _buildImageStrip() {
    if (widget.images.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 70,
              height: 70,
              color: Colors.grey.shade200,
              child: Image.file(widget.images[index], fit: BoxFit.cover),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Widget _pill(String text, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (color ?? Colors.grey.shade200),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(text),
    );
  }

  Future<void> _addPriceSlab() async {
    final priceCtrl = TextEditingController();
    final moqCtrl = TextEditingController();
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add Price Slab',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    prefixText: '₹ ',
                    hintText: 'Price per piece',
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: moqCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Minimum order quantity',
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () {
                      final p = double.tryParse(priceCtrl.text.trim());
                      final m = int.tryParse(moqCtrl.text.trim());
                      if (p != null && m != null) {
                        Navigator.pop(ctx, {'price': p, 'moq': m});
                      } else {
                        Navigator.pop(ctx);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Add'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (result != null) {
      setState(() {
        _priceSlabs.add(result);
      });
    }
  }

  Future<void> _saveToFile(String type) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/product_${type}_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      final data = {
        'name': widget.name,
        'category': widget.category,
        'sellingUnit': widget.sellingUnit,
        'varSize': widget.varSize,
        'varColor': widget.varColor,
        'price': widget.price,
        'stock': widget.stock,
        'moq': widget.moq,
        'availableQty': _availableQty,
        'autoCalc': _autoCalc,
        'priceSlabs': _priceSlabs,
        'attributes': _attributes,
        'description': _descController.text,
        'images': widget.images.map((f) => f.path).toList(),
      };
      await file.writeAsString(jsonEncode(data));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              type == 'draft' ? 'Saved as draft' : 'Product published',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    }
  }

  Future<void> _addNewColor() async {
    final result = await Navigator.push<List<File>>(
      context,
      MaterialPageRoute(
        builder: (context) =>
        const CameraInterfaceScreen(returnImagesDirectly: true),
      ),
    );
    File? picked;
    if (result != null && result.isNotEmpty) {
      picked = result.first;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Add Color'),
          content: TextField(
            controller: ctrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Enter color name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    if (name != null && name.isNotEmpty) {
      // Check for duplicate colors (case-insensitive)
      final isDuplicate = _colorItems.any((item) =>
      item['name'].toString().toLowerCase() == name.toLowerCase());

      if (!isDuplicate) {
        setState(() {
          _colors.add(name);
          _colorItems.add({'name': name, 'image': picked});
        });
        _saveRecentColor(name); // Save to recent colors
      } else {
        // Show error message for duplicate color
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Color "$name" already exists!'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F1F1F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Add Product Details',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildImageStrip(),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Basic Info',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.name ?? 'No name',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _pill(
                        widget.category ?? 'Category',
                        color: Colors.grey.shade100,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (widget.varSize)
                        _pill('Size', color: Colors.blue.shade100),
                      if (widget.varSize && widget.varColor)
                        const SizedBox(width: 4),
                      if (widget.varColor)
                        _pill('Color', color: Colors.purple.shade100),
                      const SizedBox(width: 4),
                      _pill(
                        '${widget.sellingUnit}',
                        color: Colors.green.shade100,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Available Quantity',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Text('Total Available'),
                              const Spacer(),
                              Text(
                                '$_availableQty PCS',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _pill('Auto'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: _autoCalc,
                        onChanged: (v) => setState(() => _autoCalc = v ?? true),
                        activeColor: const Color(0xFF25D366),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Auto calculate from variations',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Price & MOQ',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _priceSlabs
                        .map(
                          (slab) => Container(
                        width: 150,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.orange.shade300),
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.orange.shade50,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '₹ ${slab['price']}/pc',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Min. order: ${slab['moq']} pcs',
                              style: TextStyle(
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: _addPriceSlab,
                      child: _pill(
                        '+ Add More Price Slab',
                        color: Colors.orange.shade100,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                AddProductMoqSetScreen(images: widget.images),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.orange.shade400),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Minimum Order Quantity (PCS/SET)'),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Variations',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Color',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('Size'),
                      ),
                      const Spacer(),
                      const Icon(Icons.keyboard_arrow_up, color: Colors.grey),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ..._colorItems.map((item) {
                          final File? f = item['image'] as File?;
                          return Container(
                            width: 90,
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                ClipOval(
                                  child: Container(
                                    width: 60,
                                    height: 60,
                                    color: Colors.grey.shade200,
                                    child: f != null
                                        ? Image.file(f, fit: BoxFit.cover)
                                        : const SizedBox(),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(item['name'] as String),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _addNewColor,
                      icon: const Icon(Icons.add, color: Colors.orange),
                      label: const Text('Add New Color'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black87,
                        side: BorderSide(color: Colors.orange.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Attributes',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _showAddAttributeModal(),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFF25D366),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._attributes.entries
                      .map(
                        (e) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(e.key)),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(e.value),
                                const Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                      .toList(),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Product Description',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Enter description',
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        _saveToFile('draft');
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade400),
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Save as Draft'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        _saveToFile('publish');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Publish Product'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddAttributeModal() async {
    final nameController = TextEditingController();
    final valueController = TextEditingController();
    final List<String> valueOptions = [];

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title and close button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Add Attribute',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.grey,
                              size: 18,
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Show existing attributes
                      ..._attributes.entries.map((e) {
                        final selectedValue = e.value.toString();
                        return Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  e.key,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      selectedValue,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.keyboard_arrow_down,
                                      size: 14,
                                      color: Colors.grey.shade400,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      const SizedBox(height: 8),
                      // Add Custom Attribute section
                      const Text(
                        '+ Add Custom Attribute',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // + button above Name and Value
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          GestureDetector(
                            onTap: () {
                              final value = valueController.text.trim();
                              if (value.isNotEmpty) {
                                setModalState(() {
                                  valueOptions.add(value);
                                  valueController.clear();
                                });
                              }
                            },
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: const Color(0xFF25D366),
                                borderRadius: BorderRadius.circular(6),
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
                      const SizedBox(height: 6),
                      // Name and Value in same line
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: nameController,
                              style: const TextStyle(fontSize: 12),
                              decoration: InputDecoration(
                                hintText: 'Name',
                                hintStyle: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: valueController,
                              style: const TextStyle(fontSize: 12),
                              decoration: InputDecoration(
                                hintText: 'Value',
                                hintStyle: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                suffixIcon: valueOptions.isEmpty
                                    ? Icon(
                                  Icons.keyboard_arrow_down,
                                  color: Colors.grey.shade400,
                                  size: 16,
                                )
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Show added value options
                      if (valueOptions.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: valueOptions.map((value) {
                            return Chip(
                              label: Text(
                                value,
                                style: const TextStyle(fontSize: 11),
                              ),
                              onDeleted: () {
                                setModalState(() {
                                  valueOptions.remove(value);
                                });
                              },
                              deleteIcon: const Icon(Icons.close, size: 12),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 12),
                      // Save button
                      SizedBox(
                        width: double.infinity,
                        height: 32,
                        child: ElevatedButton(
                          onPressed: () {
                            final name = nameController.text.trim();
                            final value = valueOptions.isNotEmpty
                                ? valueOptions.join(', ')
                                : valueController.text.trim();
                            if (name.isNotEmpty && value.isNotEmpty) {
                              setState(() {
                                _attributes[name] = value;
                              });
                              Navigator.pop(ctx);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          child: const Text(
                            'Save',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class AddProductMoqSetScreen extends StatefulWidget {
  final List<File> images;
  const AddProductMoqSetScreen({super.key, required this.images});
  @override
  State<AddProductMoqSetScreen> createState() => _AddProductMoqSetScreenState();
}

class _AddProductMoqSetScreenState extends State<AddProductMoqSetScreen> {
  String _mode = 'PCS';
  final List<String> _sizes = ['S', 'M', 'L', 'XL', 'XXL'];
  final Set<String> _selectedSizes = {'M', 'L'};
  final TextEditingController _pcsController = TextEditingController(text: '3');
  final TextEditingController _setCountController = TextEditingController(
    text: '1',
  );

  @override
  void dispose() {
    _pcsController.dispose();
    _setCountController.dispose();
    super.dispose();
  }

  Widget _buildImageStrip() {
    if (widget.images.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 70,
              height: 70,
              color: Colors.grey.shade200,
              child: Image.file(widget.images[index], fit: BoxFit.cover),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F1F1F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Minimum Order Quantity',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildImageStrip(),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Type',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _mode = 'PCS'),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _mode == 'PCS'
                                    ? const Color(0xFF25D366)
                                    : Colors.grey.shade300,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              color: _mode == 'PCS'
                                  ? const Color(0xFF25D366).withOpacity(0.08)
                                  : Colors.white,
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF25D366),
                                ),
                                SizedBox(width: 8),
                                Text('PCS'),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _mode = 'SET'),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _mode == 'SET'
                                    ? const Color(0xFF25D366)
                                    : Colors.grey.shade300,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              color: _mode == 'SET'
                                  ? const Color(0xFF25D366).withOpacity(0.08)
                                  : Colors.white,
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  color: Color(0xFF25D366),
                                ),
                                SizedBox(width: 8),
                                Text('SET'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_mode == 'PCS') ...[
                    const Text(
                      'Minimum Order (PCS)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _pcsController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        suffixText: 'PCS',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'Define Set',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _sizes.map((s) {
                        final selected = _selectedSizes.contains(s);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (selected) {
                                _selectedSizes.remove(s);
                              } else {
                                _selectedSizes.add(s);
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFF25D366)
                                    : Colors.grey.shade300,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              color: selected
                                  ? const Color(0xFF25D366).withOpacity(0.08)
                                  : Colors.white,
                            ),
                            child: Text(s),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _setCountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'Pieces per set',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade400),
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final result = {
                          'mode': _mode,
                          'pcs': int.tryParse(_pcsController.text) ?? 3,
                          'selectedSizes': _selectedSizes.toList(),
                          'setCount':
                          int.tryParse(_setCountController.text) ?? 1,
                        };
                        Navigator.pop(context, result);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Save'),
                    ),
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
