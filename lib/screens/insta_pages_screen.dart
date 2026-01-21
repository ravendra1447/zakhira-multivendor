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

class InstaPagesScreen extends StatefulWidget {
  const InstaPagesScreen({super.key});

  @override
  State<InstaPagesScreen> createState() => _InstaPagesScreenState();
}

class _InstaPagesScreenState extends State<InstaPagesScreen> {
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
      // Try loading from local database first
      final localProducts = await ProductDatabaseService().getInstagramProducts();

      // Also try to fetch from API
      final apiResponse = await ProductService.getInstagramProducts();

      if (apiResponse['success'] == true && apiResponse['products'] != null) {
        final apiProducts = (apiResponse['products'] as List)
            .map((p) => Product.fromMap(p))
            .toList();

        // Merge local and API products (avoid duplicates)
        final allProductsMap = <int, Product>{};
        for (var p in localProducts) {
          if (p.id != null) {
            allProductsMap[p.id!] = p;
          }
        }
        for (var p in apiProducts) {
          if (p.id != null && !allProductsMap.containsKey(p.id!)) {
            allProductsMap[p.id!] = p;
          }
        }

        setState(() {
          _instaProducts = allProductsMap.values.toList();
        });
      } else {
        // Use local products if API fails
        setState(() {
          _instaProducts = localProducts;
        });
      }
    } catch (e) {
      print('Error loading Instagram products: $e');
      // Fallback to local database only
      final localProducts = await ProductDatabaseService().getInstagramProducts();
      setState(() {
        _instaProducts = localProducts;
      });
    } finally {
      setState(() => _loading = false);
    }
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

  Future<void> _copyProductWithImage(Product product) async {
    try {
      final imageUrl = _getProductImage(product);
      final productName = product.name;
      final instagramUrl = product.instagramUrl!;
      
      // Convert IP address URLs to bangkokmart.in domain
      String? fixedImageUrl = imageUrl;
      if (imageUrl != null && imageUrl.isNotEmpty) {
        fixedImageUrl = imageUrl.replaceAll(
          RegExp(r'http://184\.168\.126\.71:3000'),
          'https://bangkokmart.in'
        );
      }

      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      String shareContent = '';
      
      if (fixedImageUrl != null && fixedImageUrl.isNotEmpty) {
        try {
          // Download image
          final dio = Dio();
          final response = await dio.get(
            fixedImageUrl,
            options: Options(responseType: ResponseType.bytes),
          );
          
          // Get temporary directory
          final tempDir = await getTemporaryDirectory();
          final imagePath = '${tempDir.path}/product_${product.id}.jpg';
          
          // Save image to temporary file
          final imageFile = File(imagePath);
          await imageFile.writeAsBytes(response.data);
          
          // Copy image file to clipboard (if supported)
          // Note: Direct image copying to clipboard is limited on mobile
          // We'll use the file path approach
          
          shareContent = '$productName\n';
          shareContent += '$instagramUrl\n\n';
          shareContent += 'Image: $fixedImageUrl';
          
        } catch (e) {
          print('Error downloading image: $e');
          // Fallback to URL only
          shareContent = '$fixedImageUrl\n\n';
          shareContent += '$productName\n';
          shareContent += '$instagramUrl';
        }
      } else {
        shareContent = '$productName\n';
        shareContent += '$instagramUrl';
      }

      Navigator.pop(context); // Close loading dialog
      
      await Clipboard.setData(ClipboardData(text: shareContent));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text('Product details copied!'),
              ],
            ),
            backgroundColor: const Color(0xFF25D366),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Close loading dialog if open
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
          : _instaProducts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No Instagram products yet',
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to add products',
                        style: TextStyle(color: Colors.grey[500], fontSize: 14),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _instaProducts.length,
                  itemBuilder: (context, index) {
                    final product = _instaProducts[index];
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
                  },
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

