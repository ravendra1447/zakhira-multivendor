import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/website_service.dart';
import '../services/local_auth_service.dart';
import '../models/product.dart';
import 'product/detail/product_detail_screen.dart';

class WebsiteProductsScreen extends StatefulWidget {
  final int websiteId;
  final String websiteName;

  const WebsiteProductsScreen({
    super.key,
    required this.websiteId,
    required this.websiteName,
  });

  @override
  State<WebsiteProductsScreen> createState() => _WebsiteProductsScreenState();
}

class _WebsiteProductsScreenState extends State<WebsiteProductsScreen> {
  List<dynamic> products = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
  }

  Future<void> _fetchProducts() async {
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      final result = await WebsiteService.getWebsiteProducts(
        websiteId: widget.websiteId,
        userId: userId,
      );

      if (result['success'] == true && result['data'] != null) {
        final fetchedProducts = result['data'];
        
        if (mounted) {
          setState(() {
            products = fetchedProducts;
            isLoading = false;
          });
        }
      } else {
        throw Exception('Failed to load website products');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.websiteName} Products'),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchProducts,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchProducts,
              child: products.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No products available',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Products from ${widget.websiteName} will appear here',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.68,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final product = products[index];
                        final images = product['images'] as List<dynamic>? ?? [];
                        final imageUrl = images.isNotEmpty ? images[0] : null;

                        return Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: InkWell(
                            onTap: () {
                              // Create Product object from API data (matching products table structure)
                              final productData = Product(
                                id: product['id'],
                                userId: product['user_id'] ?? 1,
                                name: product['name'] ?? 'Unknown Product',
                                category: product['category']?.toString(),
                                subcategory: product['subcategory']?.toString(),
                                availableQty: product['available_qty']?.toString() ?? '0',
                                description: product['description'] ?? '',
                                status: product['status'] ?? 'publish',
                                priceSlabs: product['price_slabs'] is String && product['price_slabs'].isNotEmpty
                                    ? List<Map<String, dynamic>>.from(jsonDecode(product['price_slabs']))
                                    : [],
                                attributes: product['attributes'] is String && product['attributes'].isNotEmpty
                                    ? Map<String, List<String>>.from(jsonDecode(product['attributes']))
                                    : {},
                                selectedAttributeValues: product['selected_attribute_values'] is String && product['selected_attribute_values'].isNotEmpty
                                    ? Map<String, String>.from(jsonDecode(product['selected_attribute_values']))
                                    : {},
                                variations: product['variations'] is String && product['variations'].isNotEmpty
                                    ? List<Map<String, dynamic>>.from(jsonDecode(product['variations']))
                                    : [],
                                sizes: product['sizes'] is String && product['sizes'].isNotEmpty
                                    ? List<String>.from(jsonDecode(product['sizes']))
                                    : [],
                                images: product['images'] is List
                                    ? List<String>.from(product['images'].map((img) => img.toString()))
                                    : [],
                                marketplaceEnabled: product['marketplace_enabled'] == 1 || product['marketplace_enabled'] == true,
                                stockMode: product['stock_mode'] ?? 'simple',
                                stockByColorSize: product['stock_by_color_size'] is Map
                                    ? Map<String, Map<String, int>>.from(product['stock_by_color_size'])
                                    : null,
                                instagramUrl: product['product_insta_url'],
                                createdAt: product['created_at'] != null 
                                    ? DateTime.tryParse(product['created_at'])
                                    : null,
                                updatedAt: product['updated_at'] != null
                                    ? DateTime.tryParse(product['updated_at'])
                                    : null,
                              );

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ProductDetailScreen(
                                    product: productData,
                                    variation: {}, // Empty variation for now
                                  ),
                                ),
                              );
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(12),
                                      ),
                                      color: Colors.grey[100],
                                    ),
                                    child: imageUrl != null
                                        ? Image.network(
                                            imageUrl.startsWith('http') 
                                                ? imageUrl 
                                                : 'https://bangkokmart.in/$imageUrl',
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) {
                                              return Icon(
                                                Icons.image,
                                                size: 48,
                                                color: Colors.grey[400],
                                              );
                                            },
                                          )
                                        : Icon(
                                            Icons.image,
                                            size: 48,
                                            color: Colors.grey[400],
                                          ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product['name'] ?? 'Unknown Product',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        if (product['price'] != null)
                                          Text(
                                            '₹${product['price']}',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF25D366),
                                            ),
                                          ),
                                        const Spacer(),
                                        if (product['available_qty'] != null)
                                          Text(
                                            'Stock: ${product['available_qty']}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
    );
  }
}
