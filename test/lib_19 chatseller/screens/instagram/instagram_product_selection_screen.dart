import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../services/local_auth_service.dart';
import '../../services/catalog_service.dart';

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

  Future<void> _showCatalogOptions() async {
    if (_selectedProducts.isEmpty) return;

    final userId = LocalAuthService.getUserId();
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User not found'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Show loading while fetching catalogs
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // Get existing catalogs
      final catalogsResult = await CatalogService.getCatalogs(userId);
      Navigator.pop(context); // Close loading dialog

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) => Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Catalog Options',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Selected products: ${_selectedProducts.length}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 20),
                
                // Create New Catalog option
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.add_circle,
                      color: Color(0xFF25D366),
                    ),
                  ),
                  title: const Text(
                    'Create New Catalog',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Create a new catalog with these products',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showCreateCatalogDialog();
                  },
                ),
                
                const Divider(height: 32),
                
                // Add to Existing Catalog section
                if (catalogsResult['success'] == true && 
                    catalogsResult['catalogs'] != null && 
                    catalogsResult['catalogs'].isNotEmpty) ...[
                  Text(
                    'Add to Existing Catalog',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: catalogsResult['catalogs'].length,
                      itemBuilder: (context, index) {
                        final catalog = catalogsResult['catalogs'][index];
                        return ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF128C7E).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.folder,
                              color: Color(0xFF128C7E),
                            ),
                          ),
                          title: Text(
                            catalog['catalog_name'] ?? 'Unnamed Catalog',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${catalog['product_count'] ?? 0} products • ${catalog['catalog_code'] ?? ''}',
                            style: const TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _addToExistingCatalog(catalog['id']);
                          },
                        );
                      },
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 20),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_open, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        Text(
                          'No existing catalogs',
                          style: TextStyle(color: Colors.grey[600], fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create a new catalog to get started',
                          style: TextStyle(color: Colors.grey[500], fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading catalogs: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showCreateCatalogDialog() async {
    final TextEditingController catalogNameController = TextEditingController();
    
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Catalog'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Create a catalog with ${_selectedProducts.length} selected products'),
            const SizedBox(height: 16),
            TextField(
              controller: catalogNameController,
              decoration: InputDecoration(
                labelText: 'Catalog Name (Optional)',
                hintText: 'Enter catalog name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _createNewCatalog(catalogNameController.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _createNewCatalog(String catalogName) async {
    final userId = LocalAuthService.getUserId();
    if (userId == null) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final result = await CatalogService.createCatalog(
        userId: userId,
        productIds: _selectedProducts.toList(),
        catalogName: catalogName.isNotEmpty ? catalogName : null,
      );

      Navigator.pop(context); // Close loading dialog

      if (result['success'] == true) {
        Navigator.pop(context, _selectedProducts.toList());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Catalog "${result['data']['catalog_name']}" created with ${_selectedProducts.length} products'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Failed to create catalog'),
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

  Future<void> _addToExistingCatalog(int catalogId) async {
    final userId = LocalAuthService.getUserId();
    if (userId == null) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final result = await CatalogService.addToCatalog(
        userId: userId,
        productIds: _selectedProducts.toList(),
        catalogId: catalogId,
      );

      Navigator.pop(context); // Close loading dialog

      if (result['success'] == true) {
        Navigator.pop(context, _selectedProducts.toList());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${result['data']['products_added']} products added to catalog'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Failed to add products to catalog'),
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
                _showCatalogOptions();
              },
              backgroundColor: const Color(0xFF25D366),
              icon: const Icon(Icons.folder, color: Colors.white),
              label: Text(
                'Create Catalog (${_selectedProducts.length})',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
  }
}

