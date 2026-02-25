import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../product/detail/product_detail_screen.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../services/website_service.dart';
import 'package:whatsappchat/theme/app_theme.dart';
import 'package:whatsappchat/theme/app_colors.dart';
import 'package:whatsappchat/theme/app_typography.dart';
import 'package:whatsappchat/theme/app_spacing.dart';
import 'package:whatsappchat/widgets/modern_card.dart';

class WebsiteProductsListScreen extends StatefulWidget {
  final int websiteId;
  final String websiteName;
  final String domain;

  const WebsiteProductsListScreen({
    super.key,
    required this.websiteId,
    required this.websiteName,
    required this.domain,
  });

  @override
  State<WebsiteProductsListScreen> createState() => WebsiteProductsListScreenState();
}

class WebsiteProductsListScreenState extends State<WebsiteProductsListScreen> {
  List<dynamic> _products = [];
  List<dynamic> _filteredProducts = [];
  bool _loadingProducts = false;
  final TextEditingController _searchController = TextEditingController();
  String? _selectedCategory;
  String? _sortOption;

  final List<String> _sortOptions = [
    'Price: Low to High',
    'Price: High to Low',
    'Newest First',
    'Oldest First',
  ];

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    _searchController.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchProducts() async {
    setState(() {
      _loadingProducts = true;
    });

    try {
      print('🔍 Fetching products for website: ${widget.websiteId}');
      final result = await WebsiteService.getPublishedWebsiteProducts(widget.websiteId);
      
      if (result['success'] == true) {
        setState(() {
          _products = List<dynamic>.from(result['products']);
          _filteredProducts = _products;
        });
        print('✅ Successfully loaded ${_products.length} products');
      } else {
        print('❌ Failed to load products');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load products'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error fetching products: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _loadingProducts = false;
      });
    }
  }

  void _filterProducts() {
    setState(() {
      _filteredProducts = _products.where((product) {
        final matchesSearch = product['name'].toString().toLowerCase()
            .contains(_searchController.text.toLowerCase()) ||
            product['description'].toString().toLowerCase()
                .contains(_searchController.text.toLowerCase());
        
        final matchesCategory = _selectedCategory == null || 
            product['category'] == _selectedCategory;
        
        return matchesSearch && matchesCategory;
      }).toList();
    });

    if (_sortOption != null) {
      _sortProducts();
    }
  }

  void _sortProducts() {
    setState(() {
      switch (_sortOption) {
        case 'Price: Low to High':
          _filteredProducts.sort((a, b) {
            final priceA = double.tryParse(a['price']?.toString() ?? '0') ?? 0;
            final priceB = double.tryParse(b['price']?.toString() ?? '0') ?? 0;
            return priceA.compareTo(priceB);
          });
          break;
        case 'Price: High to Low':
          _filteredProducts.sort((a, b) {
            final priceA = double.tryParse(a['price']?.toString() ?? '0') ?? 0;
            final priceB = double.tryParse(b['price']?.toString() ?? '0') ?? 0;
            return priceB.compareTo(priceA);
          });
          break;
        case 'Newest First':
          _filteredProducts.sort((a, b) {
            final dateA = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime.now();
            final dateB = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime.now();
            return dateB.compareTo(dateA);
          });
          break;
        case 'Oldest First':
          _filteredProducts.sort((a, b) {
            final dateA = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime.now();
            final dateB = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime.now();
            return dateA.compareTo(dateB);
          });
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: AppColors.surface(context),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.websiteName,
              style: AppTypography.heading2(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.domain,
              style: AppTypography.bodySmall(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
        actions: [
          if (_loadingProducts)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary(context),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search and filters
          Container(
            padding: AppSpacing.paddingHorizontalLG.add(AppSpacing.paddingVerticalMD),
            decoration: BoxDecoration(
              color: AppColors.surface(context),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Search bar
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search products...',
                    prefixIcon: Icon(Icons.search, color: AppColors.textSecondary(context)),
                    filled: true,
                    fillColor: AppColors.card(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                
                // Sort dropdown
                Row(
                  children: [
                    Icon(Icons.sort, color: AppColors.textSecondary(context), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _sortOption,
                        decoration: InputDecoration(
                          hintText: 'Sort by',
                          filled: true,
                          fillColor: AppColors.card(context),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: _sortOptions.map((option) {
                          return DropdownMenuItem<String>(
                            value: option,
                            child: Text(
                              option,
                              style: AppTypography.bodySmall(context),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _sortOption = value;
                          });
                          _sortProducts();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Products grid
          Expanded(
            child: _loadingProducts
                ? Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary(context),
                    ),
                  )
                : _filteredProducts.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _fetchProducts,
                        child: GridView.builder(
                          padding: AppSpacing.paddingHorizontalLG.add(AppSpacing.paddingVerticalMD),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.75,
                          ),
                          itemCount: _filteredProducts.length,
                          itemBuilder: (context, index) {
                            final product = _filteredProducts[index];
                            return _buildProductCard(product, index);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No Products Found',
            style: AppTypography.heading3(context).copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No products have been published to this website yet',
            style: AppTypography.bodySmall(context).copyWith(
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _fetchProducts,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary(context),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(dynamic product, int index) {
    final name = product['name'] ?? 'Unknown Product';
    final price = product['price']?.toString() ?? '0';
    final images = product['images'] as List<dynamic>? ?? [];
    final firstImage = images.isNotEmpty ? images[0] : null;
    
    // Convert product to Product object
    final productObj = Product.fromMap(product);
    
    // Get first variation or create a default one
    Map<String, dynamic> firstVariation = {};
    if (productObj.variations.isNotEmpty) {
      firstVariation = productObj.variations.first;
    } else {
      // Create a default variation if none exists
      firstVariation = {
        'name': 'Default',
        'image': firstImage,
        'allImages': images,
      };
    }
    
    return ModernCard(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailScreen(
              product: productObj,
              variation: firstVariation,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product image
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey.shade100,
              ),
              child: firstImage != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: firstImage.toString(),
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary(context),
                            strokeWidth: 2,
                          ),
                        ),
                        errorWidget: (context, url, error) => Icon(
                          Icons.image,
                          size: 40,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.image,
                      size: 40,
                      color: Colors.grey.shade400,
                    ),
            ),
          ),
          const SizedBox(height: 8),
          // Product info
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTypography.bodyMedium(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '₹$price',
                  style: AppTypography.price(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
