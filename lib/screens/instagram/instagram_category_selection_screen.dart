import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/product.dart';
import '../../services/product_database_service.dart';
import '../../services/product_service.dart';
import '../../services/local_auth_service.dart';
import '../../services/catalog_service.dart';
import 'instagram_category_product_detail_screen.dart';

class InstagramCategorySelectionScreen extends StatefulWidget {
  final Function(List<int>)? onProductsSelected;

  const InstagramCategorySelectionScreen({
    super.key,
    this.onProductsSelected,
  });

  @override
  State<InstagramCategorySelectionScreen> createState() => _InstagramCategorySelectionScreenState();
}

class _InstagramCategorySelectionScreenState extends State<InstagramCategorySelectionScreen> {
  List<Product> _allProducts = [];
  Map<String, List<Product>> _productsByCategory = {};
  bool _loading = true;

  final List<Map<String, String>> _categories = [
    {'name': 'Popular', 'icon': '⭐'},
    {'name': 'Kurti, Saree & Lehenga', 'icon': '👗'},
    {'name': 'Women Western', 'icon': '👚'},
    {'name': 'Lingerie', 'icon': '👙'},
    {'name': 'Men', 'icon': '👔'},
    {'name': 'Kids & Toys', 'icon': '🧸'},
    {'name': 'Home & Kitchen', 'icon': '🏠'},
    {'name': 'Electronics', 'icon': '📱'},
    {'name': 'Beauty & Personal Care', 'icon': '💄'},
    {'name': 'Footwear', 'icon': '👠'},
  ];

  @override
  void initState() {
    super.initState();
    _loadPublishedProductsFromServer(); // ✅ Server se hi load karo
  }

  // ✅ Server se sirf published products load karne ka function
  Future<void> _loadPublishedProductsFromServer() async {
    setState(() => _loading = true);

    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        print("❌ User ID not found");
        setState(() {
          _allProducts = [];
          _productsByCategory = {};
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

      // Group products by category
      _groupProductsByCategory(serverProducts);

      setState(() {
        _allProducts = serverProducts;
        _loading = false;
      });

      print("🎯 Total products loaded from server: ${serverProducts.length}");

    } catch (e) {
      print("❌ Error loading products from SERVER: $e");
      setState(() {
        _allProducts = [];
        _productsByCategory = {};
        _loading = false;
      });
    }
  }

  // ✅ Helper function: Products ko category me group karega
  void _groupProductsByCategory(List<Product> products) {
    final productsByCat = <String, List<Product>>{};

    for (var product in products) {
      if (product.category != null && product.category!.isNotEmpty) {
        productsByCat.putIfAbsent(product.category!, () => []).add(product);
      }
    }

    _productsByCategory = productsByCat;
  }

  // ✅ Refresh method
  Future<void> _refreshProducts() async {
    await _loadPublishedProductsFromServer();
  }

  List<Map<String, dynamic>> _getCategoriesWithProducts() {
    final List<Map<String, dynamic>> categoriesWithProducts = [];

    for (var category in _categories) {
      final categoryName = category['name']!;
      final products = _productsByCategory[categoryName] ?? [];

      // Only show categories that have products
      if (products.isNotEmpty) {
        categoriesWithProducts.add({
          'name': categoryName,
          'icon': category['icon']!,
          'products': products,
        });
      }
    }

    return categoriesWithProducts;
  }

  String? _getCategoryImage(String category) {
    // Get first product image from this category as category image
    final products = _productsByCategory[category] ?? [];
    if (products.isEmpty) return null;

    final product = products.first;

    // Get first available image
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

  void _handleCategoryTap(BuildContext context, String categoryName, List<Product> products) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InstagramCategoryProductDetailScreen(
          categoryName: categoryName,
          products: products, // ✅ Server se aaye products hi bhejo
          loadFromServer: false, // ❌ false rakho kyunki products already server se aaye hain
        ),
      ),
    );

    // Handle the result when coming back from detail screen
    if (result != null && mounted) {
      if (result is List<int>) {
        // If you need to pass selected product IDs back
        if (widget.onProductsSelected != null) {
          widget.onProductsSelected!(result);
        }
        // Also pop this screen with the result
        Navigator.pop(context, result);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesWithProducts = _getCategoriesWithProducts();

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
          'Select Categories',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refreshProducts,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshProducts,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : categoriesWithProducts.isEmpty
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.category_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No categories with products found',
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
            : ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: categoriesWithProducts.length,
          itemBuilder: (context, index) {
            final categoryData = categoriesWithProducts[index];
            final categoryName = categoryData['name'] as String;
            final icon = categoryData['icon'] as String;
            final products = categoryData['products'] as List<Product>;
            final productCount = products.length;
            final categoryImage = _getCategoryImage(categoryName);

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey[200],
                  ),
                  child: categoryImage != null
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: categoryImage,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Center(
                        child: Text(icon, style: const TextStyle(fontSize: 24)),
                      ),
                      errorWidget: (context, url, error) => Center(
                        child: Text(icon, style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                  )
                      : Center(
                    child: Text(icon, style: const TextStyle(fontSize: 24)),
                  ),
                ),
                title: Text(
                  categoryName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text('$productCount ${productCount == 1 ? 'product' : 'products'}'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _handleCategoryTap(context, categoryName, products),
              ),
            );
          },
        ),
      ),
    );
  }
}