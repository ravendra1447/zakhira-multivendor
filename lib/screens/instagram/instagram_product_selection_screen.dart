import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/product.dart';
import '../../services/product_database_service.dart';
import '../../services/product_service.dart';
import '../../services/local_auth_service.dart';

class InstagramProductSelectionScreen extends StatefulWidget {
  const InstagramProductSelectionScreen({super.key});

  @override
  State<InstagramProductSelectionScreen> createState() => _InstagramProductSelectionScreenState();
}

class _InstagramProductSelectionScreenState extends State<InstagramProductSelectionScreen> {
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  Set<int> _selectedProducts = {};
  bool _loading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPublishedProductsFromServer();
    _searchController.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPublishedProductsFromServer() async {
    setState(() => _loading = true);

    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        print("❌ User ID not found");
        setState(() {
          _allProducts = [];
          _filteredProducts = [];
          _loading = false;
        });
        return;
      }

      print("🔄 Loading published products from SERVER for user: $userId");

      // ✅ ProductService.getProducts() use karo
      final result = await ProductService.getProducts(
        user_id: userId,      // ✅ User ID pass karo
        status: 'publish',    // Sirf published products
        marketplace: false,   // Sirf user ke apne products
        limit: 200,           // Max products
      );

      List<Product> serverProducts = [];

      if (result['success'] == true && result['data'] != null) {
        final productsData = result['data'] as List<dynamic>;
        print("✅ Server se aaye published products: ${productsData.length}");

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
        _allProducts = serverProducts;
        _filteredProducts = serverProducts;
        _loading = false;
      });

      print("🎯 Total products loaded from server: ${serverProducts.length}");

    } catch (e) {
      print("❌ Error loading products from SERVER: $e");
      setState(() {
        _allProducts = [];
        _filteredProducts = [];
        _loading = false;
      });
    }
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredProducts = _allProducts;
      });
    } else {
      setState(() {
        _filteredProducts = _allProducts
            .where((p) => p.name.toLowerCase().contains(query) ||
                (p.category?.toLowerCase().contains(query) ?? false) ||
                (p.subcategory?.toLowerCase().contains(query) ?? false))
            .toList();
      });
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
        title: const Text(
          'Select Products',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
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
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _filteredProducts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No products found',
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
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
      floatingActionButton: _selectedProducts.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () async {
                // Show loading
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(
                    child: CircularProgressIndicator(),
                  ),
                );

                try {
                  // Call API to update products for Instagram
                  final result = await ProductService.updateProductsForInstagram(
                    productIds: _selectedProducts.toList(),
                  );

                  Navigator.pop(context); // Close loading dialog

                  if (result['success'] == true) {
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
              },
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

