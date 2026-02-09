import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/product.dart';
import '../../services/product_database_service.dart';
import '../../services/product_service.dart';
import '../product/detail/product_detail_screen.dart';
import '../product/category_selection_screen.dart';
import 'package:whatsappchat/theme/app_theme.dart';
import 'package:whatsappchat/theme/app_colors.dart';
import 'package:whatsappchat/theme/app_typography.dart';
import 'package:whatsappchat/theme/app_spacing.dart';
import 'package:whatsappchat/widgets/filter_chip_widget.dart';
import 'package:whatsappchat/widgets/modern_card.dart';

class MarketplaceTab extends StatefulWidget {
  const MarketplaceTab({super.key});

  @override
  State<MarketplaceTab> createState() => MarketplaceTabState();
}

class MarketplaceTabState extends State<MarketplaceTab> {
  List<dynamic> _marketplaceProducts = [];
  List<dynamic> _filteredProducts = [];
  bool _loadingProducts = false;
  bool _loadingMore = false;
  int _currentPage = 0;
  final int _pageSize = 20;
  bool _hasMoreProducts = true;
  final TextEditingController _searchController = TextEditingController();
  String? _selectedCategory;
  String? _selectedGender;
  String? _sortOption;
  int? _selectedCategoryIndex;

  final List<Map<String, dynamic>> _categories = [
    {'icon': Icons.grid_view, 'label': 'Categories', 'color': Colors.pink, 'value': null},
    {'icon': Icons.checkroom, 'label': 'Kurti & Dress', 'color': Colors.purple, 'value': 'Kurti, Saree & Lehenga'},
    {'icon': Icons.child_care, 'label': 'Kids & Toys', 'color': Colors.blue, 'value': 'Kids & Toys'},
    {'icon': Icons.woman, 'label': 'Westernwear', 'color': Colors.orange, 'value': 'Women Western'},
    {'icon': Icons.home, 'label': 'Home', 'color': Colors.green, 'value': 'Home & Kitchen'},
  ];

  final List<String> _sortOptions = [
    'Price: Low to High',
    'Price: High to Low',
    'Newest First',
    'Oldest First',
  ];

  final List<String> _genderOptions = [
    'All',
    'Men',
    'Women',
    'Kids',
    'Unisex',
  ];

  @override
  void initState() {
    super.initState();
    _loadMarketplaceProducts(); // Load products from server only
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  // Method to refresh from outside
  void refresh() {
    _loadMarketplaceProducts();
  }

  void _onSearchChanged() {
    _applyFilters();
  }

  Future<void> _loadMarketplaceProducts({bool showLocalFirst = false, bool loadMore = false}) async {
    if (loadMore) {
      if (_loadingMore || !_hasMoreProducts) return;
      setState(() => _loadingMore = true);
    } else {
      if (_loadingProducts && _marketplaceProducts.isEmpty) return; 
      // Only show full loading if we have NO products yet.
      // If we have products, we update them silently in the background.
      if (_marketplaceProducts.isEmpty) {
        setState(() => _loadingProducts = true);
      }
      _currentPage = 0;
      // Note: Don't clear _marketplaceProducts here to avoid blank screen while fetching.
    }

    try {
      // Get products in smaller batches for faster initial load
      final result = await ProductService.getProducts(
        status: 'publish',
        marketplace: true,
        limit: _pageSize,
        offset: _currentPage * _pageSize,
      );

      List<Product> newProducts = [];
      if (result['success'] == true && result['data'] != null) {
        final productsData = result['data'] as List<dynamic>;
        newProducts = productsData.map((p) {
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
      }

      // Check if there are more products
      _hasMoreProducts = newProducts.length >= _pageSize;

      // Add new products to existing list
      if (loadMore) {
        _marketplaceProducts.addAll(newProducts);
      } else {
        _marketplaceProducts = newProducts;
      }

      print('✅ Loaded ${newProducts.length} products (page ${_currentPage + 1}) - Total: ${_marketplaceProducts.length}');

      setState(() {
        _filteredProducts = List.from(_marketplaceProducts);
        _loadingProducts = false;
        _loadingMore = false;
      });

      if (!loadMore) {
        _currentPage++;
        _applyFilters();
      } else {
        _currentPage++;
      }
    } catch (e) {
      print("❌ Error loading marketplace products: $e");
      setState(() {
        _loadingProducts = false;
        _loadingMore = false;
      });
    }
  }

  void _applyFilters() {
    List<dynamic> filtered = List.from(_marketplaceProducts);

    // Search filter
    final searchQuery = _searchController.text.toLowerCase();
    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((product) {
        if (product is Product) {
          return product.name.toLowerCase().contains(searchQuery) ||
              (product.description?.toLowerCase().contains(searchQuery) ?? false);
        }
        return false;
      }).toList();
    }

    // Category filter
    if (_selectedCategory != null) {
      filtered = filtered.where((product) {
        if (product is Product) {
          return product.category == _selectedCategory;
        }
        return false;
      }).toList();
    }

    // Sort
    if (_sortOption != null) {
      filtered.sort((a, b) {
        if (a is! Product || b is! Product) return 0;

        double? priceA;
        double? priceB;

        if (a.priceSlabs.isNotEmpty) {
          final priceStr = a.priceSlabs.first['price']?.toString() ?? '';
          priceA = double.tryParse(priceStr);
        }
        if (b.priceSlabs.isNotEmpty) {
          final priceStr = b.priceSlabs.first['price']?.toString() ?? '';
          priceB = double.tryParse(priceStr);
        }

        switch (_sortOption) {
          case 'Price: Low to High':
            return (priceA ?? 0).compareTo(priceB ?? 0);
          case 'Price: High to Low':
            return (priceB ?? 0).compareTo(priceA ?? 0);
          case 'Newest First':
            return (b.updatedAt ?? b.createdAt ?? DateTime(1970))
                .compareTo(a.updatedAt ?? a.createdAt ?? DateTime(1970));
          case 'Oldest First':
            return (a.updatedAt ?? a.createdAt ?? DateTime(1970))
                .compareTo(b.updatedAt ?? b.createdAt ?? DateTime(1970));
          default:
            return 0;
        }
      });
    }

    setState(() {
      _filteredProducts = filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Sticky Header Section: Greeting, Search, and Filters
            _buildStickyHeader(),

            // Scrollable Content
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _loadMarketplaceProducts(),
                color: Colors.orange,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (scrollInfo) {
                    if (scrollInfo.metrics.pixels == scrollInfo.metrics.maxScrollExtent) {
                      _loadMarketplaceProducts(loadMore: true);
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        // Delivery Location Banner
                        _buildDeliveryBanner(),

                        // Category Icons
                        _buildCategoryIcons(),

                        // Sale Banner
                        _buildSaleBanner(),

                        // Products Grid
                        _buildProductsGrid(),

                        // Load More Indicator
                        if (_loadingMore)
                          Container(
                            padding: const EdgeInsets.all(16),
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStickyHeader() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Top Section: Greeting and Search
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                // Greeting
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.waving_hand,
                        color: Colors.orange,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      "Hello, let's shop!",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Search Bar
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by Keyword or Product ID',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.mic, color: Colors.grey),
                            onPressed: () {
                              // TODO: Implement voice search
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.camera_alt, color: Colors.grey),
                            onPressed: () {
                              // TODO: Implement image search
                            },
                          ),
                        ],
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Filter/Sort Options - Sticky below search
          _buildFilterOptions(),
        ],
      ),
    );
  }

  Widget _buildDeliveryBanner() {
    return GestureDetector(
      onTap: () {
        // Show location selection dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Add Delivery Location'),
            content: const Text('Location feature coming soon!'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_on, color: Colors.blue, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Add delivery location to get extra discount',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.blue,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Text('>>>', style: TextStyle(color: Colors.blue)),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryIcons() {
    return Container(
      height: 85, // Reduced height
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = _selectedCategoryIndex == index;

          return GestureDetector(
            onTap: () {
              setState(() {
                if (_selectedCategoryIndex == index) {
                  _selectedCategoryIndex = null;
                  _selectedCategory = null;
                } else {
                  _selectedCategoryIndex = index;
                  _selectedCategory = category['value'] as String?;
                }
              });
              _applyFilters();
            },
            child: Container(
              width: 70, // Reduced width
              margin: const EdgeInsets.only(right: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 50, // Smaller circle
                    height: 50, // Smaller circle
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (category['color'] as Color)
                          : (category['color'] as Color).withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: category['color'] as Color, width: 2)
                          : null,
                    ),
                    child: Icon(
                      category['icon'] as IconData,
                      color: isSelected ? Colors.white : category['color'] as Color,
                      size: 24, // Smaller icon
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    category['label'] as String,
                    style: TextStyle(
                      fontSize: 10, // Smaller font
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? category['color'] as Color : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSaleBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 90, // Slightly increased to prevent overflow
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [Colors.yellow.shade400, Colors.purple.shade600],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'MAHA INDIAN',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                  Text(
                    'SAVINGS SALE',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt, color: Colors.yellow, size: 16),
                      const SizedBox(width: 3),
                      Flexible(
                        child: const Text(
                          'UP TO 70%* OFF',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '3-4 JAN',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
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

  Widget _buildFilterOptions() {
    return Container(
      padding: AppSpacing.paddingHorizontalLG.add(AppSpacing.paddingVerticalSM),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilterChipWidget(
              label: 'Sort',
              isSelected: _sortOption != null,
              onTap: _showSortDialog,
              icon: Icons.swap_vert,
            ),
            AppSpacing.horizontalSpaceSM,
            FilterChipWidget(
              label: 'Category',
              isSelected: _selectedCategory != null,
              onTap: _showCategoryDialog,
              icon: Icons.category,
            ),
            AppSpacing.horizontalSpaceSM,
            FilterChipWidget(
              label: 'Gender',
              isSelected: _selectedGender != null,
              onTap: _showGenderDialog,
              icon: Icons.person,
            ),
            AppSpacing.horizontalSpaceSM,
            FilterChipWidget(
              label: 'Filters',
              isSelected: false,
              onTap: _showFiltersDialog,
              icon: Icons.tune,
            ),
          ],
        ),
      ),
    );
  }

  void _showSortDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Sort By',
          style: AppTypography.heading2(context),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _sortOptions.map((option) {
            final isSelected = _sortOption == option;
            return Container(
              margin: AppSpacing.marginVerticalXS,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary(context).withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary(context)
                      : AppColors.border(context),
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: RadioListTile<String>(
                title: Text(
                  option,
                  style: AppTypography.bodyMedium(context).copyWith(
                    fontWeight: isSelected ? AppTypography.semibold : AppTypography.regular,
                  ),
                ),
                value: option,
                groupValue: _sortOption,
                activeColor: AppColors.primary(context),
                onChanged: (value) {
                  setState(() {
                    _sortOption = value;
                  });
                  Navigator.pop(context);
                  _applyFilters();
                },
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _sortOption = null;
              });
              Navigator.pop(context);
              _applyFilters();
            },
            child: Text(
              'Clear',
              style: AppTypography.button(context).copyWith(
                color: AppColors.error(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCategoryDialog() async {
    final picked = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CategorySelectionScreen(),
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedCategory = picked;
        _selectedCategoryIndex = _categories.indexWhere((c) => c['value'] == picked);
        if (_selectedCategoryIndex == -1) _selectedCategoryIndex = null;
      });
      _applyFilters();
    }
  }

  void _showGenderDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Select Gender',
          style: AppTypography.heading2(context),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _genderOptions.map((option) {
            final isSelected = _selectedGender == option || (_selectedGender == null && option == 'All');
            return Container(
              margin: AppSpacing.marginVerticalXS,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary(context).withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary(context)
                      : AppColors.border(context),
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: RadioListTile<String>(
                title: Text(
                  option,
                  style: AppTypography.bodyMedium(context).copyWith(
                    fontWeight: isSelected ? AppTypography.semibold : AppTypography.regular,
                  ),
                ),
                value: option,
                groupValue: _selectedGender ?? 'All',
                activeColor: AppColors.primary(context),
                onChanged: (value) {
                  setState(() {
                    _selectedGender = value == 'All' ? null : value;
                  });
                  Navigator.pop(context);
                  _applyFilters();
                },
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _selectedGender = null;
              });
              Navigator.pop(context);
              _applyFilters();
            },
            child: Text(
              'Clear',
              style: AppTypography.button(context).copyWith(
                color: AppColors.error(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFiltersDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filters'),
        content: const Text('More filter options coming soon!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsGrid() {
    if (_loadingProducts) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredProducts.isEmpty) {
      return const Center(
        child: Text(
          'No marketplace products yet',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    // Collect products with their variations
    List<Map<String, dynamic>> productItems = [];
    for (var product in _filteredProducts) {
      if (product is Product) {
        if (product.variations.isNotEmpty) {
          for (var variation in product.variations) {
            List<String> allImages = [];
            dynamic allImagesData = variation['allImages'];

            if (allImagesData is String) {
              try {
                final decoded = jsonDecode(allImagesData);
                if (decoded is List) {
                  allImagesData = decoded;
                }
              } catch (e) {
                print('Error decoding allImages JSON: $e');
              }
            }

            if (allImagesData is List) {
              for (var img in allImagesData) {
                if (img is String && img.isNotEmpty) {
                  allImages.add(img);
                } else if (img != null) {
                  allImages.add(img.toString());
                }
              }
            }

            if (allImages.isEmpty && variation['image'] != null) {
              final img = variation['image'];
              if (img is String && img.isNotEmpty) {
                allImages.add(img);
              } else if (img != null) {
                allImages.add(img.toString());
              }
            }

            if (allImages.isNotEmpty) {
              final firstImage = allImages.first;
              final imageIndex = 0;

              productItems.add({
                'product': product,
                'variation': variation,
                'imageUrl': firstImage,
                'imageIndex': imageIndex,
                'allImages': allImages,
              });
            }
          }
        }
      }
    }

    if (productItems.isEmpty) {
      return const Center(
        child: Text(
          'No products found',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 12,
          childAspectRatio: 0.65, // Increased height to make images bigger
        ),
        itemCount: productItems.length,
        itemBuilder: (context, index) {
          final item = productItems[index];
          final product = item['product'] as Product;
          final variation = item['variation'] as Map<String, dynamic>;
          final imageUrl = item['imageUrl'] as String;
          final imageIndex = item['imageIndex'] as int;
          final allImages = item['allImages'] as List<String>;

          return _buildProductCard(
            product: product,
            variation: variation,
            imageUrl: imageUrl,
            imageIndex: imageIndex,
            allImages: allImages,
          );
        },
      ),
    );
  }

  Widget _buildProductCard({
    required Product product,
    required Map<String, dynamic> variation,
    required String imageUrl,
    required int imageIndex,
    required List<String> allImages,
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
              variation: variation,
              initialImageIndex: imageIndex,
            ),
          ),
        );
      },
      child: ModernCard(
        padding: EdgeInsets.zero,
        elevation: 0.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Product Image - Bigger size
            Expanded(
              flex: 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      color: AppColors.surface(context),
                      child: _buildImageWidget(imageUrl),
                    ),
                  ),
                  // Image count badge
                  if (allImages.length > 1)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: AppSpacing.paddingHorizontalSM.add(AppSpacing.paddingVerticalXS),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.photo_library,
                              color: Colors.white,
                              size: 12,
                            ),
                            AppSpacing.horizontalSpaceXS,
                            Text(
                              '${allImages.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
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

            // Product Details - Only Name and Price
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
                  AppSpacing.verticalSpaceXS,

                  // Price Row
                  Row(
                    children: [
                      if (currentPrice != null) ...[
                        Flexible(
                          child: Text(
                            '₹${currentPrice.toStringAsFixed(0)}',
                            style: AppTypography.price(context).copyWith(fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageWidget(String imageUrl) {
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
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

    try {
      final file = File(imageUrl);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          alignment: Alignment.center,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey.shade300,
              child: const Icon(Icons.broken_image, color: Colors.grey),
            );
          },
        );
      }
    } catch (e) {
      print("Error checking file: $imageUrl - $e");
    }

    return Container(
      color: Colors.grey.shade300,
      child: const Icon(Icons.broken_image, color: Colors.grey),
    );
  }
}
