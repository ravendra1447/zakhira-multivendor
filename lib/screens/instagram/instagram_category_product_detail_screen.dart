import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../services/local_auth_service.dart';

class InstagramCategoryProductDetailScreen extends StatefulWidget {
  final String categoryName;
  final List<Product> products;
  final bool loadFromServer; // ✅ New parameter for server loading

  const InstagramCategoryProductDetailScreen({
    super.key,
    required this.categoryName,
    required this.products,
    this.loadFromServer = false, // ✅ Default false
  });

  @override
  State<InstagramCategoryProductDetailScreen> createState() => _InstagramCategoryProductDetailScreenState();
}

class _InstagramCategoryProductDetailScreenState extends State<InstagramCategoryProductDetailScreen> {
  Set<int> _selectedProducts = {};
  final TextEditingController _searchController = TextEditingController();
  List<Product> _filteredProducts = [];
  bool _loading = false;
  List<Product> _serverProducts = [];

  @override
  void initState() {
    super.initState();

    if (widget.loadFromServer) {
      // ✅ Server se products load karo
      _loadProductsFromServer();
    } else {
      // ✅ Agar server se load nahi karna hai to direct use karo
      _filteredProducts = widget.products;
    }

    _searchController.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ✅ Server se products load karne ka function
  Future<void> _loadProductsFromServer() async {
    setState(() => _loading = true);

    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        print("❌ User ID not found");
        setState(() {
          _loading = false;
          _filteredProducts = [];
        });
        return;
      }

      print("🔄 Loading published products from SERVER for category: ${widget.categoryName}");

      // ✅ Server se products load karo
      final result = await ProductService.getProducts(
        user_id: userId,
        status: 'publish',
        marketplace: false,
        limit: 200,
      );

      List<Product> serverProducts = [];

      if (result['success'] == true && result['data'] != null) {
        final productsData = result['data'] as List<dynamic>;
        print("✅ Server se aaye products: ${productsData.length}");

        // Parse products
        serverProducts = productsData.map((p) {
          try {
            final productMap = Map<String, dynamic>.from(p);

            if (productMap['marketplace_enabled'] != null) {
              productMap['marketplace_enabled'] = productMap['marketplace_enabled'] == 1 ||
                  productMap['marketplace_enabled'] == '1' ||
                  productMap['marketplace_enabled'] == true;
            }

            return Product.fromMap(productMap);
          } catch (e) {
            print('❌ Error parsing product: $e');
            return null;
          }
        }).whereType<Product>().toList();

        // ✅ Filter products by selected category
        serverProducts = serverProducts
            .where((p) => p.category == widget.categoryName)
            .toList();

        print("✅ Category '${widget.categoryName}' ke products: ${serverProducts.length}");
      } else {
        print("❌ Server error: ${result['message']}");
      }

      // Sort by updated_at DESC
      serverProducts.sort((a, b) {
        if (a.updatedAt == null && b.updatedAt == null) return 0;
        if (a.updatedAt == null) return 1;
        if (b.updatedAt == null) return -1;
        return b.updatedAt!.compareTo(a.updatedAt!);
      });

      setState(() {
        _serverProducts = serverProducts;
        _filteredProducts = serverProducts;
        _loading = false;
      });

    } catch (e) {
      print("❌ Error loading products from SERVER: $e");
      setState(() {
        _filteredProducts = [];
        _loading = false;
      });
    }
  }

  // ✅ Refresh function for server loading
  Future<void> _refreshProducts() async {
    if (widget.loadFromServer) {
      await _loadProductsFromServer();
    } else {
      setState(() {
        _filteredProducts = widget.products;
      });
    }
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();

    if (widget.loadFromServer) {
      // ✅ Server products filter karo
      if (query.isEmpty) {
        setState(() {
          _filteredProducts = _serverProducts;
        });
      } else {
        setState(() {
          _filteredProducts = _serverProducts
              .where((p) => p.name.toLowerCase().contains(query) ||
              (p.subcategory?.toLowerCase().contains(query) ?? false))
              .toList();
        });
      }
    } else {
      // ✅ Local products filter karo
      if (query.isEmpty) {
        setState(() {
          _filteredProducts = widget.products;
        });
      } else {
        setState(() {
          _filteredProducts = widget.products
              .where((p) => p.name.toLowerCase().contains(query) ||
              (p.subcategory?.toLowerCase().contains(query) ?? false))
              .toList();
        });
      }
    }
  }

  void _toggleProductSelection(int productId) {
    setState(() {
      if (_selectedProducts.contains(productId)) {
        _selectedProducts.remove(productId);
      } else {
        _selectedProducts.add(productId);
      }
    });
  }

  String? _getProductImage(Product product) {
    // Get first available image from variations or images
    if (product.variations.isNotEmpty) {
      for (var variation in product.variations) {
        if (variation['allImages'] != null) {
          dynamic allImagesData = variation['allImages'];
          if (allImagesData is String) {
            try {
              final decoded = jsonDecode(allImagesData);
              if (decoded is List && decoded.isNotEmpty) {
                return decoded.first;
              }
            } catch (e) {
              // Ignore
            }
          } else if (allImagesData is List && allImagesData.isNotEmpty) {
            return allImagesData.first;
          }
        }
        if (variation['image'] != null && variation['image'].toString().isNotEmpty) {
          return variation['image'].toString();
        }
      }
    }
    if (product.images.isNotEmpty) {
      return product.images.first;
    }
    return null;
  }

  // ✅ Updated: API call for Instagram update
  Future<void> _updateProductsForInstagram() async {
    if (_selectedProducts.isEmpty) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // ✅ Updated API call
      final result = await ProductService.updateProductsForInstagram(
        productIds: _selectedProducts.toList(),
      );

      Navigator.pop(context); // Close loading dialog

      if (result['success'] == true) {
        // ✅ Success: Return to previous screen with selected IDs
        Navigator.pop(context, _selectedProducts.toList());

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${_selectedProducts.length} products added to Instagram'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Failed to update products'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF128C7E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.loadFromServer ? 'My Products' : 'Category Products',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Container(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Text(
                  widget.categoryName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search products...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _refreshProducts,
        child: _filteredProducts.isEmpty
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                widget.loadFromServer
                    ? 'No published products found'
                    : 'No products found in this category',
                style: TextStyle(color: Colors.grey[600], fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _refreshProducts,
                child: const Text('Refresh'),
              ),
            ],
          ),
        )
            : GridView.builder(
          padding: const EdgeInsets.all(2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemCount: _filteredProducts.length,
          itemBuilder: (context, index) {
            final product = _filteredProducts[index];
            final isSelected = product.id != null && _selectedProducts.contains(product.id);
            final imageUrl = _getProductImage(product);

            return GestureDetector(
              onTap: () {
                if (product.id != null) {
                  _toggleProductSelection(product.id!);
                }
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: Colors.grey[200],
                    child: imageUrl != null
                        ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      errorWidget: (context, url, error) => const Icon(Icons.image_not_supported),
                    )
                        : const Icon(Icons.image_not_supported, color: Colors.grey),
                  ),
                  if (isSelected)
                    Container(
                      color: Colors.black.withOpacity(0.3),
                      child: const Center(
                        child: Icon(
                          Icons.check_circle,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: _selectedProducts.isNotEmpty
          ? FloatingActionButton.extended(
        onPressed: _updateProductsForInstagram,
        backgroundColor: const Color(0xFF25D366),
        icon: const Icon(Icons.done, color: Colors.white),
        label: Text(
          'Done (${_selectedProducts.length})',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      )
          : null,
    );
  }
}