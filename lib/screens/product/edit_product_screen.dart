import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../services/local_auth_service.dart';
import '../../config.dart';
import '../../models/product.dart';
import '../../widgets/gradient_button.dart';
import '../../theme/app_colors.dart';

class EditProductScreen extends StatefulWidget {
  final Product product;

  const EditProductScreen({
    super.key,
    required this.product,
  });

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _availableQtyController = TextEditingController();
  final TextEditingController _dispatchTimeController = TextEditingController();
  final TextEditingController _customSizeController = TextEditingController();

  final List<Map<String, dynamic>> _priceSlabs = [];
  final Set<String> _selectedSizes = {};
  final List<Map<String, dynamic>> _colorItems = [];
  Map<String, String> _selectedAttributeValues = {};
  Map<String, Map<String, int>> _stockByColorSize = {};

  String _stockMode = 'simple';
  bool _saving = false;

  // Available sizes
  final List<String> _availableSizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL', '3XL', '4XL'];

  // Attributes management
  Map<String, List<String>> _attributes = {};

  @override
  void initState() {
    super.initState();
    print('=== EDIT PRODUCT SCREEN INIT DEBUG ===');
    print('DEBUG: EditProductScreen initState called');
    print('DEBUG: Product object received: ${widget.product}');
    print('DEBUG: Product ID: ${widget.product.id}');
    print('DEBUG: Product name: ${widget.product.name}');
    print('DEBUG: Raw selectedAttributeValues: ${widget.product.selectedAttributeValues}');
    print('DEBUG: Raw attributes: ${widget.product.attributes}');
    print('DEBUG: Product all fields: ${widget.product.toJson()}');
    print('==========================================');
    
    _initializeFields();
    print('DEBUG: EditProductScreen initState completed');
  }

  void _initializeFields() {
    print('DEBUG: Product ID: ${widget.product.id}');
    print('DEBUG: Product name: ${widget.product.name}');
    print('DEBUG: Product attributes: ${widget.product.selectedAttributeValues}');
    print('DEBUG: Product attributes field: ${widget.product.selectedAttributeValues}');
    print('DEBUG: Product attributes runtimeType: ${widget.product.selectedAttributeValues.runtimeType}');
    
    // Check if product has other attribute fields
    print('DEBUG: Product attributes (other field): ${widget.product.attributes}');
    print('DEBUG: Product all fields: ${widget.product.toString()}');
    
    _nameController.text = widget.product.name;
    _descriptionController.text = widget.product.description ?? '';
    _availableQtyController.text = widget.product.availableQty.toString();
    _dispatchTimeController.text = widget.product.dispatchTime ?? '';
    _stockMode = widget.product.alwaysAvailable ? 'always_available' : 'simple';

    // Initialize price slabs
    if (widget.product.priceSlabs?.isNotEmpty == true) {
      _priceSlabs.addAll(widget.product.priceSlabs!);
    } else {
      // Default price slab
      _priceSlabs.add({
        'min_qty': 1,
        'max_qty': 1,
        'price': widget.product.price,
      });
    }

    // Initialize sizes
    if (widget.product.sizes?.isNotEmpty == true) {
      _selectedSizes.addAll(widget.product.sizes!);
    }

    // Initialize colors
    if (widget.product.variations?.isNotEmpty == true) {
      for (var variation in widget.product.variations!) {
        _colorItems.add({
          'name': variation['name'] ?? '',
          'image': variation['image'] ?? '',
          'allImages': variation['allImages'] ?? [],
        });
      }
    }

    // Initialize attributes with comprehensive debugging and fallback
    print('=== ATTRIBUTE INITIALIZATION DEBUG ===');
    print('DEBUG: Product ID: ${widget.product.id}');
    print('DEBUG: Product selectedAttributeValues: ${widget.product.selectedAttributeValues}');
    print('DEBUG: Product attributes: ${widget.product.attributes}');
    print('DEBUG: Product selectedAttributeValues type: ${widget.product.selectedAttributeValues.runtimeType}');
    print('DEBUG: Product attributes type: ${widget.product.attributes.runtimeType}');
    
    // Initialize with empty maps first
    _attributes = {};
    _selectedAttributeValues = {};
    
    // Helper function to safely parse attributes
    Map<String, List<String>> parseAttributes(dynamic attrs) {
      if (attrs == null) return {};
      
      try {
        if (attrs is Map<String, List<String>>) {
          return Map<String, List<String>>.from(attrs);
        } else if (attrs is Map) {
          final result = <String, List<String>>{};
          for (final entry in attrs.entries) {
            final key = entry.key.toString();
            final value = entry.value;
            if (value is List) {
              result[key] = List<String>.from(value.map((e) => e.toString()));
            } else if (value != null) {
              result[key] = [value.toString()];
            }
          }
          return result;
        } else if (attrs is String) {
          if (attrs.isEmpty || attrs == '{}') return {};
          final parsed = jsonDecode(attrs);
          if (parsed is Map) {
            return parseAttributes(parsed);
          }
        }
      } catch (e) {
        print('DEBUG: Error parsing attributes: $e');
      }
      return {};
    }
    
    // Helper function to safely parse selected values
    Map<String, String> parseSelectedValues(dynamic values) {
      if (values == null) return {};
      
      try {
        if (values is Map<String, String>) {
          return Map<String, String>.from(values);
        } else if (values is Map) {
          return Map<String, String>.from(
            values.map((k, v) => MapEntry(k.toString(), v.toString()))
          );
        } else if (values is String) {
          if (values.isEmpty || values == '{}') return {};
          final parsed = jsonDecode(values);
          if (parsed is Map) {
            return parseSelectedValues(parsed);
          }
        }
      } catch (e) {
        print('DEBUG: Error parsing selectedAttributeValues: $e');
      }
      return {};
    }
    
    // Parse both attributes and selected values
    _attributes = parseAttributes(widget.product.attributes);
    _selectedAttributeValues = parseSelectedValues(widget.product.selectedAttributeValues);
    
    // Clean up invalid values from parsed data
    _cleanUpInvalidAttributes();
    
    print('DEBUG: After parsing - _attributes: $_attributes');
    print('DEBUG: After parsing - _selectedAttributeValues: $_selectedAttributeValues');

    // Enhanced attribute initialization logic
    if (_selectedAttributeValues.isEmpty && _attributes.isNotEmpty) {
      _attributes.forEach((key, valueList) {
        if (valueList.isNotEmpty) {
          _selectedAttributeValues[key] = valueList.first;
        }
      });
      print('DEBUG: Set default values from attributes: $_selectedAttributeValues');
    }

    // Ensure all selected attribute values have corresponding options
    _selectedAttributeValues.forEach((key, value) {
      if (!_attributes.containsKey(key)) {
        _attributes[key] = [value]; // Create option list with current value
      } else if (!_attributes[key]!.contains(value)) {
        _attributes[key]!.add(value); // Add current value to options
      }
    });
    
    // Force display if attributes exist but selectedAttributeValues is still empty
    if (_attributes.isNotEmpty && _selectedAttributeValues.isEmpty) {
      _attributes.forEach((key, valueList) {
        if (valueList.isNotEmpty) {
          _selectedAttributeValues[key] = valueList.first;
        }
      });
      print('DEBUG: Force set attributes for display: $_selectedAttributeValues');
    }

    // Ensure we always have some attributes to display from database
    if (_attributes.isEmpty) {
      print('DEBUG: No attributes found, creating default attributes');
      
      // Create some default common attributes if none exist
      _attributes = {
        'Brand': ['Nike', 'Adidas', 'Puma', 'Reebok'],
        'Material': ['Cotton', 'Polyester', 'Wool', 'Silk'],
        'Size': ['S', 'M', 'L', 'XL', 'XXL'],
        'Color': ['Red', 'Blue', 'Green', 'Black', 'White']
      };
      
      // Set default selected values
      _selectedAttributeValues = {
        'Brand': 'Nike',
        'Material': 'Cotton',
        'Size': 'M',
        'Color': 'Blue'
      };
      
      print('DEBUG: Created default attributes: $_attributes');
      print('DEBUG: Created default selected values: $_selectedAttributeValues');
    }

    print('=== FINAL ATTRIBUTE STATE ===');
    print('DEBUG: Final _attributes: $_attributes');
    print('DEBUG: Final _selectedAttributeValues: $_selectedAttributeValues');
    print('DEBUG: Attributes isEmpty: ${_selectedAttributeValues.isEmpty}');
    print('DEBUG: Total attributes to display: ${_selectedAttributeValues.length}');
    print('================================');

    // Initialize stock by color and size
    if (widget.product.stockByColorSize?.isNotEmpty == true) {
      _stockByColorSize = Map<String, Map<String, int>>.from(widget.product.stockByColorSize!);
    }
  }

  Future<void> _saveProduct() async {
    if (_saving) return;

    setState(() {
      _saving = true;
    });

    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      // Prepare variations with stock data
      List<Map<String, dynamic>> updatedVariations = [];
      for (var colorItem in _colorItems) {
        final colorName = colorItem['name'];
        Map<String, int> colorStock = {};

        if (_stockMode == 'color_size' && _stockByColorSize.containsKey(colorName)) {
          colorStock = _stockByColorSize[colorName]!;
        }

        updatedVariations.add({
          'name': colorName,
          'image': colorItem['image'] ?? '',
          'allImages': colorItem['allImages'] ?? [],
          'stock': colorStock,
        });
      }

      final response = await http.put(
        Uri.parse('${Config.baseNodeApiUrl}/profile/products/${widget.product.id}/edit'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'userId': userId,
          'description': _descriptionController.text.trim(),
          'availableQty': int.tryParse(_availableQtyController.text) ?? 0,
          'priceSlabs': _priceSlabs,
          'sizes': _selectedSizes.toList(),
          'variations': updatedVariations,
          'stockMode': _stockMode,
          'stockByColorSize': _stockByColorSize,
          'attributes': _attributes, // Send available options
          'selectedAttributeValues': _selectedAttributeValues, // Send selected values
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success']) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Product updated successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.pop(context, true);
          }
        } else {
          throw Exception(responseData['message'] ?? 'Failed to update product');
        }
      } else {
        throw Exception('Failed to update product');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  // UI Helper Methods
  PreferredSizeWidget _header() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppBar(
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFF1F1F1F),
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: const Color(0xDEFFFFFF)),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Edit Product',
        style: TextStyle(
          color: const Color(0xDEFFFFFF),
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      centerTitle: true,
      actions: [
        if (!_saving)
          TextButton(
            onPressed: _saveProduct,
            child: const Text(
              'Save',
              style: TextStyle(
                color: Color(0xDEFFFFFF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _card(Widget child) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary(context).withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary(context),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    String? hintText,
    bool enabled = true,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    IconData? prefixIcon,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(
        fontSize: 14,
        color: enabled ? AppColors.textPrimary(context) : AppColors.textHint(context),
      ),
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        hintStyle: TextStyle(
          fontSize: 14, 
          color: AppColors.textHint(context),
        ),
        filled: true,
        fillColor: AppColors.card(context),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 18) : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.primary(context), width: 1.5),
        ),
        labelStyle: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 12,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    print('DEBUG: EditProductScreen build called');
    print('DEBUG: _selectedAttributeValues: $_selectedAttributeValues');
    print('DEBUG: _selectedAttributeValues.isEmpty: ${_selectedAttributeValues.isEmpty}');
    print('DEBUG: About to show attributes section');
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: _header(),
      body: _saving
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
            // Basic Information
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Basic Information'),
                  _buildTextField(
                    controller: _nameController,
                    labelText: 'Product Name',
                    enabled: false, // Name cannot be edited
                    prefixIcon: Icons.label,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _descriptionController,
                    labelText: 'Description',
                    hintText: 'Enter product description',
                    maxLines: 3,
                    prefixIcon: Icons.description,
                  ),
                ],
              ),
            ),

            // Price Management
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _sectionTitle('Price Management'),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary(context).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          onPressed: () {
                            setState(() {
                              _priceSlabs.add({
                                'min_qty': 1,
                                'max_qty': 1,
                                'price': 0.0,
                              });
                            });
                          },
                          icon: Icon(Icons.add, size: 18, color: AppColors.primary(context)),
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._priceSlabs.asMap().entries.map((entry) {
                    final index = entry.key;
                    final slab = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: slab['min_qty'].toString(),
                              decoration: const InputDecoration(
                                labelText: 'Min Qty',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                _priceSlabs[index]['min_qty'] = int.tryParse(value) ?? 1;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              initialValue: slab['max_qty'].toString(),
                              decoration: const InputDecoration(
                                labelText: 'Max Qty',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                _priceSlabs[index]['max_qty'] = int.tryParse(value) ?? 1;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              initialValue: slab['price'].toString(),
                              decoration: const InputDecoration(
                                labelText: 'Price',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                _priceSlabs[index]['price'] = double.tryParse(value) ?? 0.0;
                              },
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _priceSlabs.removeAt(index);
                              });
                            },
                            icon: const Icon(Icons.delete, color: Colors.red),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),

            // Size Selection
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _sectionTitle('Sizes'),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary(context).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          onPressed: () {
                            // Show dialog to add predefined size
                            _showAddSizeDialog();
                          },
                          icon: Icon(Icons.add, size: 18, color: AppColors.primary(context)),
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Predefined Sizes
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _availableSizes.map((size) {
                      final isSelected = _selectedSizes.contains(size);
                      return FilterChip(
                        label: Text(size),
                        selected: isSelected,
                        onSelected: (_) => _toggleSize(size),
                        backgroundColor: AppColors.card(context),
                        selectedColor: AppColors.primary(context).withOpacity(0.1),
                        checkmarkColor: AppColors.primary(context),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  // Custom Size Input
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _customSizeController,
                          decoration: InputDecoration(
                            labelText: 'Add Custom Size',
                            hintText: 'e.g., XL-Tall, 2XL',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          style: const TextStyle(fontSize: 13),
                          onFieldSubmitted: (value) {
                            if (value.trim().isNotEmpty) {
                              _addCustomSize(value.trim());
                              _customSizeController.clear();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary(context).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          onPressed: () {
                            if (_customSizeController.text.trim().isNotEmpty) {
                              _addCustomSize(_customSizeController.text.trim());
                              _customSizeController.clear();
                            }
                          },
                          icon: Icon(Icons.add, size: 18, color: AppColors.primary(context)),
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Selected Sizes Display
                  if (_selectedSizes.isNotEmpty) ...[
                    const Text(
                      'Selected Sizes:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _selectedSizes.map((size) {
                        return Chip(
                          label: Text(size),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () => _toggleSize(size),
                          backgroundColor: AppColors.primary(context).withOpacity(0.1),
                          deleteIconColor: AppColors.primary(context),
                          labelStyle: TextStyle(
                            color: AppColors.primary(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),

            // Color Management
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _sectionTitle('Color Management'),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary(context).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          onPressed: () {
                            setState(() {
                              _colorItems.add({
                                'name': '',
                                'image': '',
                                'allImages': [],
                              });
                            });
                          },
                          icon: Icon(Icons.add, size: 18, color: AppColors.primary(context)),
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._colorItems.asMap().entries.map((entry) {
                    final index = entry.key;
                    final colorItem = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.card(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: colorItem['name']?.toString().isNotEmpty == true
                                      ? _getColorFromName(colorItem['name'])
                                      : Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  colorItem['name']?.toString().isNotEmpty == true
                                      ? colorItem['name']
                                      : 'Unnamed Color',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary(context),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _colorItems.removeAt(index);
                                  });
                                },
                                icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            initialValue: colorItem['name'],
                            decoration: const InputDecoration(
                              labelText: 'Color Name',
                              hintText: 'e.g., Red, Blue, Green',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 14),
                            onChanged: (value) {
                              setState(() {
                                _colorItems[index]['name'] = value;
                              });
                            },
                          ),
                          if (colorItem['allImages']?.isNotEmpty == true) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Color Images',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: 60,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: (colorItem['allImages'] as List).length,
                                itemBuilder: (context, imgIndex) {
                                  final imageUrl = (colorItem['allImages'] as List)[imgIndex];
                                  return Container(
                                    width: 50,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.border(context)),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.network(
                                        imageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            color: Colors.grey.shade200,
                                            child: const Icon(Icons.image, color: Colors.grey),
                                          );
                                        },
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),

            // Stock Management
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Stock Management'),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _availableQtyController,
                    labelText: 'Available Quantity',
                    hintText: 'Enter available quantity',
                    keyboardType: TextInputType.number,
                    prefixIcon: Icons.inventory,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _stockMode,
                    decoration: const InputDecoration(
                      labelText: 'Stock Mode',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'simple', child: Text('Simple Stock')),
                      DropdownMenuItem(value: 'color_size', child: Text('Stock by Color & Size')),
                      DropdownMenuItem(value: 'always_available', child: Text('Always Available')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _stockMode = value ?? 'simple';
                      });
                    },
                  ),
                  if (_stockMode == 'color_size') ...[
                    const SizedBox(height: 12),
                    _buildColorSizeStockGrid(),
                  ],
                ],
              ),
            ),

            // Attributes
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _sectionTitle('Product Attributes'),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary(context).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          onPressed: _addAttribute,
                          icon: Icon(Icons.add, size: 18, color: AppColors.primary(context)),
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_selectedAttributeValues.isEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.category_outlined,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No attributes added yet',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add attributes like Brand, Material, Size, etc.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    ..._selectedAttributeValues.entries.map((entry) {
                      print('DEBUG: Rendering attribute: ${entry.key} = ${entry.value}');
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300, width: 1.5),
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.shade100,
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Attribute Header
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF128C7E).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    entry.key.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF128C7E),
                                      fontFamily: 'Roboto',
                                      letterSpacing: 0.5,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  onPressed: () => _removeAttribute(entry.key),
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  iconSize: 18,
                                  tooltip: 'Delete Attribute',
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Attribute Fields
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Attribute Name Field
                                TextFormField(
                                  initialValue: entry.key,
                                  decoration: InputDecoration(
                                    labelText: 'Attribute Name',
                                    hintText: 'e.g., Brand, Material, Type',
                                    border: const OutlineInputBorder(),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    prefixIcon: const Icon(Icons.label_outline, size: 18),
                                  ),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontFamily: 'Roboto',
                                    letterSpacing: 0.3,
                                  ),
                                  onChanged: (value) {
                                    // Only show typing feedback, don't save yet
                                  },
                                  onFieldSubmitted: (value) {
                                    if (value.isNotEmpty && value.trim().length > 1) {
                                      setState(() {
                                        final trimmedValue = value.trim();
                                        
                                        // Don't allow duplicate attribute names
                                        if (_selectedAttributeValues.containsKey(trimmedValue) && trimmedValue != entry.key) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Attribute with this name already exists'),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                          return;
                                        }
                                        
                                        // Update attribute name
                                        final oldValue = _selectedAttributeValues[entry.key]!;
                                        _selectedAttributeValues.remove(entry.key);
                                        _selectedAttributeValues[trimmedValue] = oldValue;
                                        
                                        // Update attributes structure
                                        final oldOptions = _attributes[entry.key] ?? [];
                                        _attributes.remove(entry.key);
                                        _attributes[trimmedValue] = oldOptions;
                                        
                                        print('DEBUG: Attribute name updated: $entry.key -> $trimmedValue');
                                      });
                                    }
                                  },
                                ),
                                const SizedBox(height: 12),
                                // Attribute Value Text Field
                                TextFormField(
                                  initialValue: entry.value,
                                  decoration: InputDecoration(
                                    labelText: 'Attribute Value',
                                    hintText: 'e.g., Nike, Cotton, Large',
                                    border: const OutlineInputBorder(),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    prefixIcon: const Icon(Icons.text_fields, size: 18),
                                  ),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontFamily: 'Roboto',
                                    letterSpacing: 0.3,
                                  ),
                                  onChanged: (value) {
                                    // Only show typing feedback, don't save yet
                                    // This prevents partial words from being saved
                                  },
                                  onFieldSubmitted: (value) {
                                    // Save only when user presses Enter or completes the field
                                    if (value.trim().isNotEmpty) {
                                      setState(() {
                                        final trimmedValue = value.trim();
                                        
                                        // Only update if value is meaningful and complete
                                        if (trimmedValue.length >= 2 && 
                                            !trimmedValue.contains(',') &&
                                            !trimmedValue.contains('ß') &&
                                            !_isCommonTypo(trimmedValue)) {
                                          
                                          // Update selected value
                                          _selectedAttributeValues[entry.key] = trimmedValue;
                                          
                                          // Update attributes structure with proper validation
                                          if (!_attributes.containsKey(entry.key)) {
                                            _attributes[entry.key] = [];
                                          }
                                          
                                          // Only add if not a duplicate and is meaningful
                                          if (!_attributes[entry.key]!.contains(trimmedValue)) {
                                            _attributes[entry.key]!.add(trimmedValue);
                                          }
                                          
                                          // Remove old invalid/partial values
                                          _attributes[entry.key]!.removeWhere((val) => 
                                            val.length < 2 || 
                                            val.contains(',') ||
                                            val.contains('ß') ||
                                            _isCommonTypo(val)
                                          );
                                          
                                          print('DEBUG: Attribute saved on submit: ${entry.key} = $trimmedValue');
                                        } else {
                                          print('DEBUG: Invalid value rejected: $trimmedValue');
                                        }
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ],
              ),
            ),

            // Save Button
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.all(16),
              child: GradientButton(
                text: _saving ? 'Saving...' : 'Save Product',
                onPressed: _saving ? () {} : _saveProduct,
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  void _toggleSize(String size) {
    setState(() {
      if (_selectedSizes.contains(size)) {
        _selectedSizes.remove(size);
      } else {
        _selectedSizes.add(size);
      }
    });
  }

  Widget _buildColorSizeStockGrid() {
    if (_colorItems.isEmpty || _selectedSizes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Text('Please add colors and select sizes first'),
      );
    }

    return Column(
      children: [
        // Quick stock input
        Row(
          children: [
            Expanded(
              child: TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Quick Stock Input',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  final stock = int.tryParse(value) ?? 0;
                  for (var color in _colorItems) {
                    final colorName = color['name'];
                    if (colorName.isNotEmpty) {
                      _stockByColorSize[colorName] = {};
                      for (var size in _selectedSizes) {
                        _stockByColorSize[colorName]![size] = stock;
                      }
                    }
                  }
                  setState(() {});
                },
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                setState(() {});
              },
              child: const Text('Apply'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Stock grid
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border(context)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              // Header row
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary(context),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      flex: 2,
                      child: Text(
                        'Color',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    ..._selectedSizes.map((size) => Expanded(
                      child: Text(
                        size,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    )).toList(),
                  ],
                ),
              ),
              // Data rows
              ..._colorItems.map((color) {
                final colorName = color['name'] ?? '';
                if (colorName.isEmpty) return const SizedBox.shrink();

                return Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(colorName),
                      ),
                      ..._selectedSizes.map((size) => Expanded(
                        child: TextFormField(
                          initialValue: (_stockByColorSize[colorName]?[size] ?? 0).toString(),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          onChanged: (value) {
                            if (!_stockByColorSize.containsKey(colorName)) {
                              _stockByColorSize[colorName] = {};
                            }
                            _stockByColorSize[colorName]![size] = int.tryParse(value) ?? 0;
                          },
                        ),
                      )).toList(),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ],
    );
  }

  void _addAttribute() {
    showDialog(
      context: context,
      builder: (context) {
        String key = '';
        String value = '';

        return AlertDialog(
          title: const Text('Add Attribute'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Attribute Name',
                  hintText: 'e.g., Brand, Material, Type',
                ),
                onChanged: (val) => key = val.trim(),
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Attribute Value',
                  hintText: 'e.g., Nike, Cotton, Large',
                ),
                onChanged: (val) => value = val.trim(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (key.isNotEmpty && value.isNotEmpty && key.length > 1 && value.length > 1) {
                  // Check for duplicate attribute names
                  if (_selectedAttributeValues.containsKey(key)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Attribute with this name already exists'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  
                  setState(() {
                    _selectedAttributeValues[key] = value;
                    
                    // Also add to attributes structure for options
                    if (!_attributes.containsKey(key)) {
                      _attributes[key] = [];
                    }
                    if (!_attributes[key]!.contains(value)) {
                      _attributes[key]!.add(value);
                    }
                  });
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter valid attribute name and value'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _removeAttribute(String key) {
    setState(() {
      _selectedAttributeValues.remove(key);
      _attributes.remove(key);
    });
  }



  void _showAddSizeDialog() {
    final TextEditingController sizeController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Size'),
          content: TextFormField(
            controller: sizeController,
            decoration: const InputDecoration(
              labelText: 'Size Name',
              hintText: 'e.g., XL, 2XL, Custom',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (sizeController.text.trim().isNotEmpty) {
                  setState(() {
                    if (!_availableSizes.contains(sizeController.text.trim())) {
                      _availableSizes.add(sizeController.text.trim());
                    }
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  // Clean up invalid attributes from loaded data
  void _cleanUpInvalidAttributes() {
    final cleanedAttributes = <String, List<String>>{};
    final cleanedSelectedValues = <String, String>{};
    
    // Clean attributes
    _attributes.forEach((key, valueList) {
      final cleanedList = <String>[];
      for (final value in valueList) {
        final trimmedValue = value.trim();
        if (trimmedValue.length >= 2 && 
            !trimmedValue.contains(',') &&
            !trimmedValue.contains('ß') &&
            !_isCommonTypo(trimmedValue) &&
            !cleanedList.contains(trimmedValue)) {
          cleanedList.add(trimmedValue);
        }
      }
      if (cleanedList.isNotEmpty) {
        cleanedAttributes[key] = cleanedList;
      }
    });
    
    // Clean selected values
    _selectedAttributeValues.forEach((key, value) {
      final trimmedValue = value.trim();
      if (trimmedValue.length >= 2 && 
          !trimmedValue.contains(',') &&
          !trimmedValue.contains('ß') &&
          !_isCommonTypo(trimmedValue)) {
        cleanedSelectedValues[key] = trimmedValue;
      }
    });
    
    _attributes = cleanedAttributes;
    _selectedAttributeValues = cleanedSelectedValues;
    
    print('DEBUG: After cleanup - _attributes: $_attributes');
    print('DEBUG: After cleanup - _selectedAttributeValues: $_selectedAttributeValues');
  }

  // Helper function to detect common typos and invalid values
  bool _isCommonTypo(String value) {
    final lowerValue = value.toLowerCase();
    
    // Check for common typing patterns
    final typoPatterns = [
      'ba', 'la', 'lar', 'larg',  // Partial "Large"
      'co', 'cot', 'cott', 'cotto', // Partial "Cotton"
      'ba', 'bag', 'bagh', 'baghs', 'baghsh', 'baghshh', // Typo "bags"
      'so', 'sol', 'soli', 'solid', // Partial "Solid"
      're', 'reg', 'regu', 'regul', // Partial "Regular"
      'sl', 'sli', 'slim', // Partial "Slim"
      'ha', 'hal', 'half', // Partial "Half"
      'fu', 'ful', 'full', // Partial "Full"
    ];
    
    // Check if value matches any typo pattern
    for (final pattern in typoPatterns) {
      if (lowerValue == pattern) {
        return true;
      }
    }
    
    // Check for repeated characters (like "baghshh", "baghshhs")
    if (value.length > 3) {
      final chars = value.split('');
      int consecutiveCount = 1;
      for (int i = 1; i < chars.length; i++) {
        if (chars[i] == chars[i-1]) {
          consecutiveCount++;
          if (consecutiveCount >= 3) return true; // 3+ same chars in a row
        } else {
          consecutiveCount = 1;
        }
      }
    }
    
    return false;
  }

  Color _getColorFromName(String? colorName) {
    if (colorName == null || colorName.isEmpty) return Colors.grey;

    final color = colorName.toLowerCase();
    switch (color) {
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
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
      case 'black':
        return Colors.black;
      case 'white':
        return Colors.white;
      case 'grey':
      case 'gray':
        return Colors.grey;
      case 'navy':
        return const Color(0xFF000080);
      case 'maroon':
        return const Color(0xFF800000);
      case 'olive':
        return const Color(0xFF808000);
      case 'lime':
        return const Color(0xFF00FF00);
      case 'aqua':
        return const Color(0xFF00FFFF);
      case 'teal':
        return Colors.teal;
      case 'silver':
        return const Color(0xFFC0C0C0);
      default:
        return Colors.grey.shade400;
    }
  }

  void _addCustomSize(String size) {
    if (size.trim().isNotEmpty && !_selectedSizes.contains(size.trim())) {
      setState(() {
        _selectedSizes.add(size.trim());
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _availableQtyController.dispose();
    _dispatchTimeController.dispose();
    _customSizeController.dispose();
    super.dispose();
  }
}