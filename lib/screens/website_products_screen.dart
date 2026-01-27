import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/website_service.dart';
import '../services/local_auth_service.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/app_spacing.dart';
import '../widgets/modern_card.dart';
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final product = products[index];
                        final images = product['images'] as List<dynamic>? ?? [];
                        final imageUrl = images.isNotEmpty ? images[0] : null;

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
                              ? Map<String, List<String>>.from(
                                  (jsonDecode(product['attributes']) as Map).map((k, v) => 
                                    MapEntry(k.toString(), List<String>.from((v as List).map((e) => e.toString())))))
                              : (product['attributes'] != null && product['attributes'] is Map)
                                  ? Map<String, List<String>>.from(
                                      (product['attributes'] as Map).map((k, v) => 
                                        MapEntry(k.toString(), List<String>.from((v as List).map((e) => e.toString())))))
                                  : {},
                          selectedAttributeValues: product['selected_attribute_values'] is String && product['selected_attribute_values'].isNotEmpty
                              ? Map<String, String>.from(
                                  (jsonDecode(product['selected_attribute_values']) as Map).map((k, v) => 
                                    MapEntry(k.toString(), v.toString())))
                              : (product['selected_attribute_values'] != null && product['selected_attribute_values'] is Map)
                                  ? Map<String, String>.from(
                                      (product['selected_attribute_values'] as Map).map((k, v) => 
                                        MapEntry(k.toString(), v.toString())))
                                  : {},
                          variations: product['variations'] is String && product['variations'].isNotEmpty
                              ? List<Map<String, dynamic>>.from(
                                  (jsonDecode(product['variations']) as List).map((e) => 
                                    e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{}))
                              : (product['variations'] != null && product['variations'] is List)
                                  ? List<Map<String, dynamic>>.from(
                                      (product['variations'] as List).map((e) => 
                                        e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{}))
                              : [],
                          sizes: product['sizes'] is String && product['sizes'].isNotEmpty
                              ? List<String>.from(
                                  (jsonDecode(product['sizes']) as List).map((e) => e.toString()))
                              : (product['sizes'] != null && product['sizes'] is List)
                                  ? List<String>.from(
                                      (product['sizes'] as List).map((e) => e.toString()))
                              : [],
                          images: product['images'] is List
                              ? List<String>.from(
                                  (product['images'] as List).map((img) => img.toString()))
                              : (product['images'] is String && product['images'].isNotEmpty)
                                  ? List<String>.from(
                                      (jsonDecode(product['images']) as List).map((e) => e.toString()))
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

                        return _buildProductCard(
                          product: productData,
                          imageUrl: imageUrl,
                          images: images,
                        );
                      },
                    ),
        ),
    );
  }

  Widget _buildProductCard({
    required Product product,
    required String? imageUrl,
    required List<dynamic> images,
  }) {
    // Calculate price and discount
    double? currentPrice;
    double? originalPrice;
    int discountPercent = 0;

    if (product.priceSlabs.isNotEmpty) {
      final firstSlab = product.priceSlabs.first;
      final priceStr = firstSlab['price']?.toString() ?? '';
      if (priceStr.isNotEmpty) {
        try {
          currentPrice = double.tryParse(priceStr);
          originalPrice = currentPrice != null ? currentPrice * 1.3 : null;
          if (originalPrice != null && currentPrice != null) {
            discountPercent = ((originalPrice - currentPrice) / originalPrice * 100).round();
          }
        } catch (e) {
          print('Error parsing price: $e');
        }
      }
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailScreen(
              product: product,
              variation: {}, // Empty variation for now
            ),
          ),
        );
      },
      child: ModernCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Product Image
            Expanded(
              flex: 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      color: AppColors.surface(context),
                      child: _buildImageWidget(imageUrl),
                    ),
                  ),
                  // Discount badge
                  if (discountPercent > 0)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$discountPercent% OFF',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  // Image count badge
                  if (images.length > 1)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.photo_library,
                              color: Colors.white,
                              size: 10,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${images.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Product Details
            Padding(
              padding: AppSpacing.paddingSM,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Product Name
                  Text(
                    product.name,
                    style: AppTypography.bodyMedium(context).copyWith(
                      fontWeight: AppTypography.semibold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),

                  // Rating stars (placeholder)
                  Row(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(5, (index) {
                          return Icon(
                            index < 4 ? Icons.star : Icons.star_border,
                            color: Colors.amber,
                            size: 12,
                          );
                        }),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(24)',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Price Row
                  Row(
                    children: [
                      if (currentPrice != null) ...[
                        Flexible(
                          child: Text(
                            '₹${currentPrice.toStringAsFixed(0)}',
                            style: AppTypography.price(context).copyWith(fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (originalPrice != null) ...[
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '₹${originalPrice.toStringAsFixed(0)}',
                              style: AppTypography.discount(context).copyWith(fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),

                  // Stock info
                  if (product.availableQty != null && product.availableQty!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Stock: ${product.availableQty}',
                        style: TextStyle(
                          fontSize: 10,
                          color: int.tryParse(product.availableQty!) != null && 
                                 int.parse(product.availableQty!) > 0 
                              ? Colors.green[600]
                              : Colors.red[600],
                          fontWeight: FontWeight.w500,
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

  Widget _buildImageWidget(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(
        color: Colors.grey.shade200,
        child: const Icon(
          Icons.image,
          color: Colors.grey,
          size: 48,
        ),
      );
    }

    final fullImageUrl = imageUrl.startsWith('http') 
        ? imageUrl 
        : 'https://bangkokmart.in/$imageUrl';

    return CachedNetworkImage(
      imageUrl: fullImageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (context, url) => Container(
        color: Colors.grey.shade200,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: Colors.grey.shade300,
        child: const Icon(Icons.broken_image, color: Colors.grey),
      ),
    );
  }
}
