import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import '../../config.dart';
import '../../services/admin_dashboard_service.dart';
import 'product_detail_screen.dart';

class ProductManagementScreen extends StatefulWidget {
  const ProductManagementScreen({super.key});

  @override
  State<ProductManagementScreen> createState() => _ProductManagementScreenState();
}

class _ProductManagementScreenState extends State<ProductManagementScreen> {
  bool isLoading = true;
  List<Map<String, dynamic>> products = [];
  String? errorMessage;
  String searchQuery = '';
  String selectedFilter = 'all'; // all, active, inactive, marketplace_enabled, marketplace_disabled
  int? currentUserId;
  
  // Auto-refresh variables
  Timer? _refreshTimer;
  bool _isAutoRefreshEnabled = true;
  int _refreshInterval = 10; // seconds
  DateTime? _lastRefreshTime;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    }

    try {
      await _fetchProducts();
      setState(() {
        _lastRefreshTime = DateTime.now();
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load products: $e';
      });
    } finally {
      setState(() {
        isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  // Auto-refresh methods
  void _startAutoRefresh() {
    if (_isAutoRefreshEnabled) {
      _refreshTimer = Timer.periodic(Duration(seconds: _refreshInterval), (timer) {
        if (mounted && !_isRefreshing) {
          _refreshDataSilently();
        }
      });
    }
  }

  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
  }

  void _toggleAutoRefresh() {
    setState(() {
      _isAutoRefreshEnabled = !_isAutoRefreshEnabled;
    });
    
    if (_isAutoRefreshEnabled) {
      _startAutoRefresh();
    } else {
      _stopAutoRefresh();
    }
  }

  Future<void> _refreshDataSilently() async {
    setState(() {
      _isRefreshing = true;
    });
    
    try {
      await _fetchProducts();
      setState(() {
        _lastRefreshTime = DateTime.now();
      });
    } catch (e) {
      print('Error during silent refresh: $e');
    } finally {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  Future<void> _manualRefresh() async {
    setState(() {
      _isRefreshing = true;
    });
    await _loadData(showLoading: false);
  }

  Future<void> _fetchProducts() async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/admin/products'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            products = List<Map<String, dynamic>>.from(data['products']);
            isLoading = false;
          });
        } else {
          throw Exception(data['message'] ?? 'Failed to fetch products');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      print('Error fetching products: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
      rethrow;
    }
  }

  Future<void> _toggleProductStatus(int productId, String field, bool currentValue) async {
    try {
      final newValue = !currentValue;
      final response = await http.put(
        Uri.parse('${Config.baseNodeApiUrl}/admin/products/$productId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          field: newValue ? 1 : 0,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            final productIndex = products.indexWhere((p) => p['id'] == productId);
            if (productIndex != -1) {
              products[productIndex][field] = newValue ? 1 : 0;
            }
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${field == 'is_active' ? 'Product status' : 'Marketplace visibility'} updated successfully'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          throw Exception(data['message'] ?? 'Failed to update product');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteProduct(int productId, String productName) async {
  // Show confirmation dialog
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete Product'),
      content: Text('Are you sure you want to delete "$productName"?\n\nThis action cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  try {
    final response = await http.delete(
      Uri.parse('${Config.baseNodeApiUrl}/admin/products/$productId'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success']) {
        setState(() {
          products.removeWhere((p) => p['id'] == productId);
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Product "$productName" deleted successfully'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        throw Exception(data['message'] ?? 'Failed to delete product');
      }
    } else {
      throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting product: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

Future<void> _toggleBothStatuses(int productId, Map<String, dynamic> product) async {
    try {
      final currentIsActive = product['is_active'] == 1;
      final currentMarketplaceEnabled = product['marketplace_enabled'] == 1;
      
      final response = await http.put(
        Uri.parse('${Config.baseNodeApiUrl}/admin/products/$productId/toggle-both'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'is_active': currentIsActive ? 0 : 1,
          'marketplace_enabled': currentMarketplaceEnabled ? 0 : 1,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            final productIndex = products.indexWhere((p) => p['id'] == productId);
            if (productIndex != -1) {
              products[productIndex]['is_active'] = currentIsActive ? 0 : 1;
              products[productIndex]['marketplace_enabled'] = currentMarketplaceEnabled ? 0 : 1;
            }
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Both product status and marketplace visibility updated successfully'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          throw Exception(data['message'] ?? 'Failed to update product');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildFilterChip(String label, String value, IconData icon) {
    final isSelected = selectedFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14),
            const SizedBox(width: 4),
            Text(label),
          ],
        ),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            selectedFilter = value;
          });
        },
        backgroundColor: Colors.white,
        selectedColor: _getFilterColor(value).withOpacity(0.2),
        labelStyle: TextStyle(
          color: isSelected ? _getFilterColor(value) : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        side: BorderSide(
          color: isSelected ? _getFilterColor(value) : Colors.grey[300]!,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Color _getFilterColor(String filter) {
    switch (filter) {
      case 'active':
        return Colors.green;
      case 'inactive':
        return Colors.red;
      case 'marketplace_enabled':
        return Colors.blue;
      case 'marketplace_disabled':
        return Colors.orange;
      default:
        return Colors.indigo;
    }
  }

  // Helper method to format time
  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  List<Map<String, dynamic>> get filteredProducts {
    List<Map<String, dynamic>> filtered = products;
    
    // Apply filter
    if (selectedFilter != 'all') {
      switch (selectedFilter) {
        case 'active':
          filtered = filtered.where((product) => product['is_active'] == 1).toList();
          break;
        case 'inactive':
          filtered = filtered.where((product) => product['is_active'] == 0).toList();
          break;
        case 'marketplace_enabled':
          filtered = filtered.where((product) => product['marketplace_enabled'] == 1).toList();
          break;
        case 'marketplace_disabled':
          filtered = filtered.where((product) => product['marketplace_enabled'] == 0).toList();
          break;
      }
    }
    
    // Apply search filter
    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((product) {
        final name = product['name']?.toString().toLowerCase() ?? '';
        final category = product['category']?.toString().toLowerCase() ?? '';
        final brand = product['brand']?.toString().toLowerCase() ?? '';
        final query = searchQuery.toLowerCase();
        return name.contains(query) || category.contains(query) || brand.contains(query);
      }).toList();
    }
    
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Flexible(
              child: Text(
                'Product Management',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.black,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (_isAutoRefreshEnabled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.autorenew,
                      size: 14,
                      color: Colors.green[700],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Auto',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 2,
        centerTitle: true,
        iconTheme: const IconThemeData(
          color: Colors.black,
        ),
        actions: [
          // Auto-refresh toggle
          IconButton(
            icon: Icon(
              _isAutoRefreshEnabled ? Icons.autorenew : Icons.autorenew_outlined,
              color: _isAutoRefreshEnabled ? Colors.green : Colors.grey,
            ),
            onPressed: _toggleAutoRefresh,
            tooltip: _isAutoRefreshEnabled ? 'Disable Auto-refresh' : 'Enable Auto-refresh',
          ),
          // Manual refresh
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.green),
              onPressed: _manualRefresh,
              tooltip: 'Manual Refresh',
            ),
        ],
      ),
      body: Column(
        children: [
          // Search and Filter Section
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                // Search Bar
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search products by name, category, or brand...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (value) {
                    setState(() {
                      searchQuery = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                // Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All', 'all', Icons.apps),
                      _buildFilterChip('Active', 'active', Icons.check_circle),
                      _buildFilterChip('Inactive', 'inactive', Icons.cancel),
                      _buildFilterChip('Marketplace', 'marketplace_enabled', Icons.store),
                      _buildFilterChip('Not in Marketplace', 'marketplace_disabled', Icons.store_outlined),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Products List
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage != null
                    ? _buildErrorView()
                    : filteredProducts.isEmpty
                        ? _buildEmptyView()
                        : _buildProductsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 80,
            color: Colors.red[400],
          ),
          const SizedBox(height: 20),
          Text(
            errorMessage ?? 'Something went wrong',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loadData,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 20),
          Text(
            'No products found',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            searchQuery.isNotEmpty || selectedFilter != 'all'
                ? 'Try adjusting your search or filters'
                : 'No products available in the system',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredProducts.length,
      itemBuilder: (context, index) {
        final product = filteredProducts[index];
        return _buildProductCard(product);
      },
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final isActive = product['is_active'] == 1;
    final isMarketplaceEnabled = product['marketplace_enabled'] == 1;
    final images = product['images'] != null 
        ? List<String>.from(json.decode(product['images'] ?? '[]'))
        : <String>[];
    final imageUrl = images.isNotEmpty ? images[0] : null;
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailScreen(product: product),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Stack(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey[100],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                              errorWidget: (context, url, error) => Icon(
                                Icons.image_not_supported,
                                color: Colors.grey[400],
                              ),
                            )
                          : Icon(
                              Icons.image,
                              color: Colors.grey[400],
                              size: 40,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product['name'] ?? 'Unknown Product',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        if (product['category'] != null) ...[
                          Text(
                            product['category'],
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        if (product['brand'] != null) ...[
                          Text(
                            'Brand: ${product['brand']}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        if (product['price'] != null) ...[
                          Text(
                            'Price: ₹${product['price']}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              // Delete icon in top-right corner
              Positioned(
                top: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () => _deleteProduct(product['id'], product['name'] ?? 'Unknown Product'),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.red.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Colors.red[600],
                    ),
                  ),
                ),
              ),
            ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () => _toggleProductStatus(product['id'], 'is_active', isActive),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        decoration: BoxDecoration(
                          color: isActive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isActive ? Colors.green : Colors.red,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isActive ? Icons.check_circle : Icons.cancel,
                              size: 14,
                              color: isActive ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                isActive ? 'Active' : 'Inactive',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isActive ? Colors.green : Colors.red,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 3,
                    child: GestureDetector(
                      onTap: () => _toggleProductStatus(product['id'], 'marketplace_enabled', isMarketplaceEnabled),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        decoration: BoxDecoration(
                          color: isMarketplaceEnabled ? Colors.blue.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isMarketplaceEnabled ? Colors.blue : Colors.orange,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isMarketplaceEnabled ? Icons.store : Icons.store_outlined,
                              size: 14,
                              color: isMarketplaceEnabled ? Colors.blue : Colors.orange,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                isMarketplaceEnabled ? 'Marketplace' : 'Hidden',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isMarketplaceEnabled ? Colors.blue : Colors.orange,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () => _toggleBothStatuses(product['id'], product),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.purple.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.purple,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.sync_alt,
                              size: 14,
                              color: Colors.purple,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Both',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.purple,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
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
}
