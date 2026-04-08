import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import '../../config.dart';

class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  bool isLoading = true;
  List<Map<String, dynamic>> productVariants = [];
  String? errorMessage;
  
  @override
  void initState() {
    super.initState();
    _loadProductVariants();
  }

  Future<void> _loadProductVariants() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // Fetch real variants from database
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/admin/products/${widget.product['id']}/variants'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('=== API Response for Product Variants ===');
        print('Product ID: ${widget.product['id']}');
        print('Response data: ${data}');
        print('Success: ${data['success']}');
        print('Stock mode: ${data['stock_mode']}');
        print('Stock info: ${data['stock_info']}');
        print('==========================================');
        
        if (data['success']) {
          // Convert color groups to flat list for display
          final List<Map<String, dynamic>> variants = [];
          final colorGroups = data['stock_info']['color_groups'] as List?;
          
          print('Color groups: $colorGroups');
          
          if (colorGroups != null) {
            print('Processing ${colorGroups.length} color groups...');
            for (final colorGroup in colorGroups) {
              final colorVariants = colorGroup['variants'] as List?;
              if (colorVariants != null) {
                print('Processing ${colorVariants.length} variants for color ${colorGroup['color']}');
                for (final variant in colorVariants) {
                  variants.add({
                    'id': variant['id'],
                    'color': variant['color'],
                    'color_code': variant['color_code'],
                    'size': variant['size'],
                    'stock': variant['stock'],
                    'price': variant['price'],
                    'is_active': variant['status'] == 1, // Use status field instead of stock
                  });
                }
              }
            }
          } else {
            print('Color groups is null!');
          }
          
          print('Final variants count: ${variants.length}');
          
          setState(() {
            productVariants = variants;
            isLoading = false;
          });
        } else {
          throw Exception(data['message'] ?? 'Failed to load variants');
        }
      } else {
        print('API Error - Status code: ${response.statusCode}');
        print('API Error - Response body: ${response.body}');
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      print('=== Error Loading Product Variants ===');
      print('Error: $e');
      print('Product ID: ${widget.product['id']}');
      print('=====================================');
      setState(() {
        errorMessage = 'Failed to load product variants: $e';
        isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _createMockVariants() {
    // Create mock variants if no data exists
    final colors = ['Red', 'Blue', 'Green', 'Black', 'White'];
    final sizes = ['S', 'M', 'L', 'XL'];
    final variants = <Map<String, dynamic>>[];
    
    for (int i = 0; i < colors.length; i++) {
      for (int j = 0; j < sizes.length; j++) {
        variants.add({
          'id': '${widget.product['id']}_${colors[i]}_${sizes[j]}',
          'color': colors[i],
          'size': sizes[j],
          'stock': (i + j) % 5 + 1, // Random stock between 1-5
          'is_active': true,
          'price': widget.product['price'] ?? 0,
        });
      }
    }
    
    return variants;
  }

  Future<void> _toggleVariantStatus(String variantId, bool currentStatus) async {
    try {
      final newStatus = !currentStatus;
      
      // Update local state immediately for better UX
      setState(() {
        final index = productVariants.indexWhere((v) => v['id'] == variantId);
        if (index != -1) {
          productVariants[index]['is_active'] = newStatus;
        }
      });

      // Call API to update status
      final response = await http.put(
        Uri.parse('${Config.baseNodeApiUrl}/admin/products/${widget.product['id']}/variant/${variantId}'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'is_active': newStatus,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (!data['success']) {
          // Revert change if API call failed
          setState(() {
            final index = productVariants.indexWhere((v) => v['id'] == variantId);
            if (index != -1) {
              productVariants[index]['is_active'] = currentStatus;
            }
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to update variant: ${data['message']}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Variant status updated successfully'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      // Revert change on error
      setState(() {
        final index = productVariants.indexWhere((v) => v['id'] == variantId);
        if (index != -1) {
          productVariants[index]['is_active'] = currentStatus;
        }
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleAllVariantsStatus(bool newStatus) async {
    try {
      // Update local state immediately
      setState(() {
        for (var variant in productVariants) {
          variant['is_active'] = newStatus;
        }
      });

      // Call API to update all variants
      final response = await http.put(
        Uri.parse('${Config.baseNodeApiUrl}/admin/products/${widget.product['id']}/variants'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'is_active': newStatus,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('All variants ${newStatus ? 'enabled' : 'disabled'} successfully'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          throw Exception(data['message'] ?? 'Failed to update variants');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      // Revert changes on error
      await _loadProductVariants();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.product['images'] != null 
        ? List<String>.from(json.decode(widget.product['images'] ?? '[]'))
        : <String>[];
    final imageUrl = images.isNotEmpty ? images[0] : null;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          widget.product['name'] ?? 'Product Details',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 2,
        centerTitle: true,
        iconTheme: const IconThemeData(
          color: Colors.black,
        ),
        actions: [
          // Enable All button
          IconButton(
            icon: const Icon(Icons.check_circle_outline, color: Colors.green),
            onPressed: () => _toggleAllVariantsStatus(true),
            tooltip: 'Enable All Variants',
          ),
          // Disable All button
          IconButton(
            icon: const Icon(Icons.cancel_outlined, color: Colors.red),
            onPressed: () => _toggleAllVariantsStatus(false),
            tooltip: 'Disable All Variants',
          ),
        ],
      ),
      body: Column(
        children: [
          // Product Header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product Image
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey[100],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            errorWidget: (context, url, error) => Icon(
                              Icons.image_not_supported,
                              color: Colors.grey[400],
                            ),
                          )
                        : Icon(
                            Icons.image,
                            color: Colors.grey[400],
                            size: 50,
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                // Product Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.product['name'] ?? 'Unknown Product',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      if (widget.product['category'] != null)
                        Text(
                          'Category: ${widget.product['category']}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      if (widget.product['brand'] != null)
                        Text(
                          'Brand: ${widget.product['brand']}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      if (widget.product['price'] != null)
                        Text(
                          'Price: ₹${widget.product['price']}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.green[700],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Variants List
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage != null
                    ? _buildErrorView()
                    : productVariants.isEmpty
                        ? _buildEmptyView()
                        : _buildVariantsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 80,
            color: Colors.red[400],
          ),
          const SizedBox(height: 20),
          Text(
            errorMessage ?? 'Something went wrong',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loadProductVariants,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.colorize_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 20),
          Text(
            'No variants found',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This product has no color/size variants',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantsList() {
    // Group variants by color
    final Map<String, List<Map<String, dynamic>>> groupedVariants = {};
    for (final variant in productVariants) {
      final color = variant['color']?.toString() ?? 'Unknown';
      if (!groupedVariants.containsKey(color)) {
        groupedVariants[color] = [];
      }
      groupedVariants[color]!.add(variant);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groupedVariants.keys.length,
      itemBuilder: (context, index) {
        final color = groupedVariants.keys.elementAt(index);
        final variants = groupedVariants[color]!;
        return _buildColorGroup(color, variants);
      },
    );
  }

  Widget _buildColorGroup(String color, List<Map<String, dynamic>> variants) {
    final allActive = variants.every((v) => v['is_active'] == true);
    final anyActive = variants.any((v) => v['is_active'] == true);
    final colorCode = variants.isNotEmpty ? variants[0]['color_code'] : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
        children: [
          // Color Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: anyActive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                // Color indicator
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _getColorForName(color, colorCode),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                ),
                const SizedBox(width: 12),
                // Color name and status
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        color,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: anyActive ? Colors.green : Colors.red,
                        ),
                      ),
                      Text(
                        '${variants.length} size(s) - ${allActive ? "All Active" : anyActive ? "Partially Active" : "All Inactive"}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                // Toggle all button for this color
                GestureDetector(
                  onTap: () {
                    for (final variant in variants) {
                      _toggleVariantStatus(variant['id'], variant['is_active']);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: anyActive ? Colors.red : Colors.green,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      anyActive ? 'Disable All' : 'Enable All',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Size variants
          ...variants.map((variant) => _buildSizeVariant(variant)).toList(),
        ],
      ),
    );
  }

  Widget _buildSizeVariant(Map<String, dynamic> variant) {
    final isActive = variant['is_active'] == true;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          // Size label
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isActive ? Colors.blue.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActive ? Colors.blue : Colors.grey[300]!,
              ),
            ),
            child: Center(
              child: Text(
                variant['size']?.toString() ?? 'N/A',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isActive ? Colors.blue : Colors.grey[600],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Stock info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stock: ${variant['stock'] ?? 0}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                if (variant['price'] != null)
                  Text(
                    'Price: ₹${variant['price']}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
          // Status toggle
          GestureDetector(
            onTap: () => _toggleVariantStatus(variant['id'], isActive),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isActive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive ? Colors.green : Colors.red,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isActive ? Icons.check_circle : Icons.cancel,
                    size: 16,
                    color: isActive ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isActive ? 'Active' : 'Inactive',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isActive ? Colors.green : Colors.red,
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

  Color _getColorForName(String colorName, [String? colorCode]) {
    // If color code is provided, use it
    if (colorCode != null && colorCode.isNotEmpty) {
      try {
        // Handle hex color codes
        if (colorCode.startsWith('#')) {
          return Color(int.parse(colorCode.substring(1), radix: 16) + 0xFF000000);
        }
        // Handle RGB format if needed
        if (colorCode.startsWith('rgb')) {
          // Parse RGB format - simplified for now
          return Colors.blue;
        }
      } catch (e) {
        print('Error parsing color code $colorCode: $e');
      }
    }
  
    // Fallback to color name mapping
    switch (colorName.toLowerCase()) {
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
      case 'gray':
      case 'grey':
        return Colors.grey;
      default:
        return Colors.grey[400]!;
    }
  }
}
