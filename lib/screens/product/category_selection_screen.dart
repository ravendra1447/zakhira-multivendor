import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class CategorySelectionScreen extends StatefulWidget {
  final List<String>? recentCategories;
  const CategorySelectionScreen({super.key, this.recentCategories});

  @override
  State<CategorySelectionScreen> createState() =>
      _CategorySelectionScreenState();
}

class _CategorySelectionScreenState extends State<CategorySelectionScreen> {
  String _selectedCategory = 'Popular';
  String? _selectedSubcategory;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showSearch = false;
  bool _showAllRecent = false;
  List<Map<String, dynamic>> _recentItems = [];

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

  // Map of categories to their subcategories
  final Map<String, List<String>> _subcategories = {
    'Popular': ['Kurtis & Dress Materials', 'Sarees', 'Westernwear', 'Jewellery', 'Men Fashion', 'Kids', 'Footwear', 'Beauty & Personal Care', 'Grocery'],
    'Kurti, Saree & Lehenga': ['Kurtis', 'Sarees', 'Lehengas', 'Dress Materials', 'Dupattas', 'Anarkali Suits'],
    'Women Western': ['Tops', 'Shirts', 'Jeans', 'Dresses', 'Skirts', 'Shorts', 'Jackets', 'Blazers'],
    'Lingerie': ['Bras', 'Panties', 'Lingerie Sets', 'Shapewear', 'Nightwear'],
    'Men': ['Men Fashion', 'Shirts', 'T-Shirts', 'Jeans', 'Trousers', 'Formal Wear', 'Casual Wear', 'Accessories'],
    'Kids & Toys': ['Kids Clothing', 'Toys', 'Baby Care', 'School Supplies', 'Games'],
    'Home & Kitchen': ['Kitchenware', 'Home Decor', 'Furniture', 'Bedding', 'Bath', 'Storage'],
    'Electronics': ['Mobiles', 'Laptops', 'Accessories', 'Audio', 'Cameras', 'Gaming'],
    'Beauty & Personal Care': ['Skincare', 'Makeup', 'Hair Care', 'Fragrances', 'Personal Hygiene'],
    'Footwear': ['Sneakers', 'Formal Shoes', 'Casual Shoes', 'Sandals', 'Boots', 'Slippers'],
  };

  @override
  void initState() {
    super.initState();
    _loadRecentCategories();
  }

  Future<void> _loadRecentCategories() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // Use recent categories passed from main screen if available
      if (widget.recentCategories != null && widget.recentCategories!.isNotEmpty) {
        _recentItems = widget.recentCategories!.map((name) => {
          'name': name,
          'isRecent': true,
        }).toList();
      } else {
        // Load from SharedPreferences
        final recentJson = prefs.getString('recent_categories');
        if (recentJson != null) {
          final List<dynamic> recentList = json.decode(recentJson);
          _recentItems = recentList.map((item) {
            final name = item['name'] as String;
            // Parse category and subcategory from name if not already present
            String? category = item['category'] as String?;
            String? subcategory = item['subcategory'] as String?;
            
            if (category == null && name.contains(' > ')) {
              final parts = name.split(' > ');
              category = parts[0];
              subcategory = parts.length > 1 ? parts[1] : null;
            } else if (category == null) {
              category = name;
            }
            
            return {
              'name': name,
              'category': category,
              'subcategory': subcategory,
              'isRecent': true,
            };
          }).toList();
        }
      }
    });
  }

  Future<void> _saveRecentCategory(String categoryName, String? subcategoryName) async {
    final displayName = subcategoryName != null 
        ? '$categoryName > $subcategoryName' 
        : categoryName;
    
    // Remove if already exists
    _recentItems.removeWhere((item) => item['name'] == displayName);
    
    // Add to beginning
    _recentItems.insert(0, {
      'name': displayName,
      'category': categoryName,
      'subcategory': subcategoryName,
      'image': _getIconForCategory(categoryName),
      'badges': [],
    });
    
    // Keep only last 20
    if (_recentItems.length > 20) {
      _recentItems = _recentItems.take(20).toList();
    }
    
    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('recent_categories', json.encode(_recentItems));
    
    setState(() {});
  }

  String _getIconForCategory(String categoryName) {
    final category = _categories.firstWhere(
      (cat) => cat['name'] == categoryName,
      orElse: () => {'name': categoryName, 'icon': '📦'},
    );
    return category['icon']!;
  }

  List<String> get _currentSubcategories {
    return _subcategories[_selectedCategory] ?? [];
  }

  List<Map<String, String>> get _filteredCategories {
    if (_searchQuery.isEmpty) {
      return _categories;
    }
    return _categories
        .where(
          (category) => category['name']!.toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ),
        )
        .toList();
  }

  List<Map<String, dynamic>> get _displayedRecentItems {
    if (_showAllRecent) {
      return _recentItems;
    }
    return _recentItems.take(3).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(50),
        child: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black, size: 22),
            onPressed: () => Navigator.pop(context),
          ),
          title: _showSearch
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: 'Search categories...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.grey),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                )
              : const Text(
                  'CATEGORIES',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
          centerTitle: true,
          actions: [
            if (_showSearch)
              IconButton(
                icon: const Icon(Icons.close, color: Colors.black, size: 22),
                onPressed: () {
                  setState(() {
                    _showSearch = false;
                    _searchQuery = '';
                    _searchController.clear();
                  });
                },
              )
            else
              IconButton(
                icon: const Icon(Icons.search, color: Colors.black, size: 22),
                onPressed: () {
                  setState(() {
                    _showSearch = true;
                  });
                },
              ),
          ],
        ),
      ),
      body: _showSearch
          ? _buildSearchResults()
          : Row(
              children: [
                // Left Sidebar
                Container(
                  width: 100,
                  color: Colors.grey.shade100,
                  child: ListView.builder(
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final category = _categories[index];
                      final isSelected = _selectedCategory == category['name'];
                      return GestureDetector(
                        onTap: () {
                      setState(() {
                        _selectedCategory = category['name']!;
                        _selectedSubcategory = null; // Reset subcategory when category changes
                      });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.purple.shade100
                                : Colors.transparent,
                            border: Border(
                              right: BorderSide(
                                color: isSelected
                                    ? Colors.purple
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isSelected && category['name'] == 'Popular')
                                const Icon(
                                  Icons.star,
                                  color: Colors.amber,
                                  size: 18,
                                )
                              else
                                Text(
                                  category['icon']!,
                                  style: const TextStyle(fontSize: 22),
                                ),
                              const SizedBox(height: 4),
                              Flexible(
                                child: Text(
                                  category['name']!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? Colors.purple
                                        : Colors.black87,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Main Content Area - Show Subcategories
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Recent Section - no top padding
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Recent',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 10),
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: 0.75,
                                    ),
                                itemCount: _displayedRecentItems.length,
                                itemBuilder: (context, index) {
                                  final item = _displayedRecentItems[index];
                                  return GestureDetector(
                                    onTap: () async {
                                      final category = item['category'] as String? ?? item['name'] as String;
                                      final subcategory = item['subcategory'] as String?;
                                      await _saveRecentCategory(category, subcategory);
                                      if (mounted) {
                                        Navigator.pop(context, {
                                          'category': category,
                                          'subcategory': subcategory,
                                        });
                                      }
                                    },
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Container(
                                              width: 70,
                                              height: 70,
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  item['image'] as String,
                                                  style: const TextStyle(
                                                    fontSize: 32,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if ((item['badges'] as List)
                                                .isNotEmpty)
                                              Positioned(
                                                top: -2,
                                                right: -2,
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 5,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.orange,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    (item['badges'] as List)
                                                        .first,
                                                    style: const TextStyle(
                                                      fontSize: 7,
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Flexible(
                                          child: Text(
                                            item['name'] as String,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.black87,
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              if (_recentItems.length > 3 && !_showAllRecent)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Center(
                                    child: TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _showAllRecent = true;
                                        });
                                      },
                                      child: const Text(
                                        'More',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.purple,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Subcategories Section
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'All ${_selectedCategory}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 10),
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: 0.75,
                                    ),
                                itemCount: _currentSubcategories.length,
                                itemBuilder: (context, index) {
                                  final subcategory = _currentSubcategories[index];
                                  final isSelected = _selectedSubcategory == subcategory;
                                  return GestureDetector(
                                    onTap: () async {
                                      await _saveRecentCategory(_selectedCategory, subcategory);
                                      if (mounted) {
                                        Navigator.pop(context, {
                                          'category': _selectedCategory,
                                          'subcategory': subcategory,
                                        });
                                      }
                                    },
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 70,
                                          height: 70,
                                          decoration: BoxDecoration(
                                            color: isSelected 
                                                ? Colors.purple.shade100 
                                                : Colors.grey.shade200,
                                            shape: BoxShape.circle,
                                            border: isSelected 
                                                ? Border.all(color: Colors.purple, width: 2)
                                                : null,
                                          ),
                                          child: Center(
                                            child: Text(
                                              _getIconForCategory(_selectedCategory),
                                              style: const TextStyle(
                                                fontSize: 32,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Flexible(
                                          child: Text(
                                            subcategory,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: isSelected 
                                                  ? FontWeight.w600 
                                                  : FontWeight.w500,
                                              color: isSelected 
                                                  ? Colors.purple 
                                                  : Colors.black87,
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSearchResults() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: _filteredCategories.isEmpty
          ? const Center(
              child: Text(
                'No categories found',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
                childAspectRatio: 0.75,
              ),
              itemCount: _filteredCategories.length,
              itemBuilder: (context, index) {
                final category = _filteredCategories[index];
                return GestureDetector(
                  onTap: () async {
                    // For search, just return category without subcategory
                    await _saveRecentCategory(category['name']!, null);
                    if (mounted) {
                      Navigator.pop(context, {
                        'category': category['name'],
                        'subcategory': null,
                      });
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            category['icon']!,
                            style: const TextStyle(fontSize: 32),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Flexible(
                        child: Text(
                          category['name']!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
