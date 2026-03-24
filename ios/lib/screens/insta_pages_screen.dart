import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whatsappchat/screens/product/detail/product_detail_screen.dart';
import 'instagram/instagram_product_selection_screen.dart';
import 'instagram/instagram_category_selection_screen.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import '../services/product_database_service.dart';
import '../services/catalog_service.dart';
import '../services/local_auth_service.dart';
import 'catalog/catalog_detail_screen.dart';

class InstaPagesScreen extends StatefulWidget {
  const InstaPagesScreen({super.key});

  @override
  State<InstaPagesScreen> createState() => _InstaPagesScreenState();
}

class _InstaPagesScreenState extends State<InstaPagesScreen> {
  List<Map<String, dynamic>> _catalogs = [];
  List<Product> _instaProducts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadInstagramProducts();
  }

  Future<void> _loadInstagramProducts() async {
    setState(() => _loading = true);
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        print("❌ User ID not found");
        setState(() {
          _catalogs = [];
          _instaProducts = [];
          _loading = false;
        });
        return;
      }

      // Load catalogs first
      final catalogsResult = await CatalogService.getCatalogs(userId);
      List<Map<String, dynamic>> catalogs = [];
      
      if (catalogsResult['success'] == true && catalogsResult['catalogs'] != null) {
        catalogs = List<Map<String, dynamic>>.from(catalogsResult['catalogs']);
      }

      // Also load individual Instagram products (for backward compatibility)
      final localProducts = await ProductDatabaseService().getInstagramProducts();
      final apiResponse = await ProductService.getInstagramProducts();

      List<Product> individualProducts = [];
      if (apiResponse['success'] == true && apiResponse['products'] != null) {
        individualProducts = (apiResponse['products'] as List)
            .map((p) => Product.fromMap(p))
            .toList();
      }

      // Merge local and API products (avoid duplicates)
      final allProductsMap = <int, Product>{};
      for (var p in localProducts) {
        if (p.id != null) {
          allProductsMap[p.id!] = p;
        }
      }
      for (var p in individualProducts) {
        if (p.id != null && !allProductsMap.containsKey(p.id!)) {
          allProductsMap[p.id!] = p;
        }
      }

      setState(() {
        _catalogs = catalogs;
        _instaProducts = allProductsMap.values.toList();
        _loading = false;
      });

      print("✅ Loaded ${catalogs.length} catalogs and ${allProductsMap.length} individual products");
    } catch (e) {
      print('Error loading Instagram products: $e');
      // Fallback to local database only
      final localProducts = await ProductDatabaseService().getInstagramProducts();
      setState(() {
        _catalogs = [];
        _instaProducts = localProducts;
        _loading = false;
      });
    }
  }

  String? _getProductImage(Product product) {
    // Get first available image from variations or images
    if (product.variations.isNotEmpty) {
      for (var variation in product.variations) {
        if (variation['images'] != null && variation['images'].isNotEmpty) {
          return variation['images'][0];
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

  Widget _buildProductImage(String imageData) {
    try {
      List<String> images = [];
      if (imageData.startsWith('[')) {
        // JSON array format
        images = List<String>.from(json.decode(imageData));
      } else {
        // Comma separated or single image
        images = imageData.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
      
      if (images.isNotEmpty) {
        final firstImage = images[0];
        return CachedNetworkImage(
          imageUrl: firstImage.startsWith('http') 
              ? firstImage 
              : 'https://bangkokmart.in/admin/uploads/$firstImage',
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            color: Colors.grey[200],
            child: const Center(
              child: CircularProgressIndicator(color: Color(0xFF128C7E)),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            color: Colors.grey[200],
            child: const Icon(Icons.image_not_supported, color: Colors.grey),
          ),
        );
      }
    } catch (e) {
      print('Error parsing product image: $e');
    }
    
    // Fallback to catalog icon
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF128C7E), const Color(0xFF25D366)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Icon(
        Icons.folder,
        color: Colors.white,
        size: 30,
      ),
    );
  }

  Future<void> _copyProductWithImage(Product product) async {
    try {
      final instagramUrl = product.instagramUrl!;
      
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      String shareContent = instagramUrl; // Only copy the URL for rich preview

      Navigator.pop(context); // Close loading dialog
      
      await Clipboard.setData(ClipboardData(text: shareContent));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text('Product URL copied!'),
              ],
            ),
            backgroundColor: const Color(0xFF25D366),
            duration: const Duration(seconds: 2),
          ),
        );
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
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Instagram Pages',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8.0),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.add, color: Colors.black, size: 18),
              onPressed: () {
                _showSelectionOptions();
              },
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _catalogs.isEmpty && _instaProducts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No Instagram catalogs or products yet',
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to add products and create catalogs',
                        style: TextStyle(color: Colors.grey[500], fontSize: 14),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _catalogs.length + _instaProducts.length,
                  itemBuilder: (context, index) {
                    // Show catalogs first, then individual products
                    if (index < _catalogs.length) {
                      return _buildCatalogCard(_catalogs[index]);
                    } else {
                      final productIndex = index - _catalogs.length;
                      final product = _instaProducts[productIndex];
                      return _buildProductCard(product);
                    }
                  },
                ),
    );
  }

  Widget _buildCatalogCard(Map<String, dynamic> catalog) {
    final catalogId = catalog['id'];
    final catalogName = catalog['catalog_name'] ?? 'Unnamed Catalog';
    final catalogCode = catalog['catalog_code'] ?? '';
    final productCount = catalog['product_count'] ?? 0;
    final catalogUrl = 'https://bangkokmart.in/catalog/$catalogId';
    final firstProductImage = catalog['first_product_image'];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [const Color(0xFF128C7E).withOpacity(0.05), Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.all(12),
          leading: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: firstProductImage != null && firstProductImage.isNotEmpty
                  ? _buildProductImage(firstProductImage)
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [const Color(0xFF128C7E), const Color(0xFF25D366)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Icon(
                        Icons.folder,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
            ),
          ),
          title: Text(
            catalogName,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF128C7E).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      catalogCode,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF128C7E),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$productCount products',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF128C7E).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF128C7E).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.link,
                          size: 16,
                          color: Color(0xFF128C7E),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Catalog URL:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Color(0xFF128C7E),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () async {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CatalogDetailScreen(
                              catalogId: catalogId,
                              catalogName: catalogName,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                catalogUrl,
                                style: const TextStyle(
                                  color: Color(0xFF128C7E),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(
                              Icons.open_in_new,
                              size: 14,
                              color: Color(0xFF128C7E),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          trailing: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF25D366).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: catalogUrl));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text('Catalog URL copied: $catalogName'),
                        ],
                      ),
                      backgroundColor: const Color(0xFF25D366),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              icon: const Icon(
                Icons.copy,
                color: Color(0xFF25D366),
                size: 20,
              ),
              tooltip: 'Copy Catalog URL',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductCard(Product product) {
    final imageUrl = _getProductImage(product);
    final instagramUrl = product.instagramUrl ?? 'No URL available';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [Colors.white, Colors.grey[50]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.all(12),
          leading: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: imageUrl != null
                  ? CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey[200],
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[200],
                  child: const Icon(Icons.image_not_supported, color: Colors.grey),
                ),
              )
                  : Container(
                color: Colors.grey[200],
                child: const Icon(Icons.image_not_supported, color: Colors.grey),
              ),
            ),
          ),
          title: Text(
            product.name,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF128C7E).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF128C7E).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.link,
                          size: 16,
                          color: Color(0xFF128C7E),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Instagram URL:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Color(0xFF128C7E),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () async {
                        if (product.instagramUrl != null && product.instagramUrl!.isNotEmpty) {
                          // Get first variation for navigation
                          Map<String, dynamic> firstVariation = {};
                          if (product.variations.isNotEmpty) {
                            firstVariation = product.variations.first;
                          } else {
                            firstVariation = {
                              'name': 'Default',
                              'image': product.images.isNotEmpty ? product.images.first : '',
                              'allImages': product.images,
                            };
                          }
                          
                          // Navigate to product detail page
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ProductDetailScreen(
                                product: product,
                                variation: firstVariation,
                              ),
                            ),
                          );
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('No URL available for this product'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                instagramUrl,
                                style: const TextStyle(
                                  color: Color(0xFF128C7E),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(
                              Icons.open_in_new,
                              size: 14,
                              color: Color(0xFF128C7E),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          trailing: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF25D366).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              onPressed: () async {
                if (product.instagramUrl != null && product.instagramUrl!.isNotEmpty) {
                  await _copyProductWithImage(product);
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No URL to copy'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(
                Icons.copy,
                color: Color(0xFF25D366),
                size: 20,
              ),
              tooltip: 'Copy Product Details',
            ),
          ),
        ),
      ),
    );
  }

  void _showSelectionOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'Select Option',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Product Wise Option
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.shopping_bag,
                  color: Color(0xFF25D366),
                ),
              ),
              title: const Text(
                'Product Wise',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'Create page based on products',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              onTap: () async {
                Navigator.pop(context);
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const InstagramProductSelectionScreen(),
                  ),
                );
                if (result != null && mounted) {
                  // Refresh Instagram products after selection
                  _loadInstagramProducts();
                }
              },
            ),
            const Divider(height: 1),
            // Category Wise Option
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF128C7E).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.category,
                  color: Color(0xFF128C7E),
                ),
              ),
              title: const Text(
                'Category Wise',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'Create page based on categories',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              onTap: () async {
                Navigator.pop(context);
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const InstagramCategorySelectionScreen(),
                  ),
                );
                if (result != null && mounted) {
                  // Refresh Instagram products after selection
                  _loadInstagramProducts();
                }
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

