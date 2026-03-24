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
    {'name': 'Other', 'icon': '📦'},
  ];

  // Map of categories to their subcategories
  final Map<String, List<String>> _subcategories = {
    'Popular': ['Kurtis & Dress Materials', 'Sarees', 'Westernwear', 'Jewellery', 'Men Fashion', 'Kids', 'Footwear', 'Beauty & Personal Care', 'Grocery'],
    'Kurti, Saree & Lehenga': ['Kurtis', 'Sarees', 'Lehengas', 'Dress Materials', 'Dupattas', 'Anarkali Suits', 'Other'],
    'Women Western': ['Tops', 'Shirts', 'Jeans', 'Dresses', 'Skirts', 'Shorts', 'Jackets', 'Blazers', 'Other'],
    'Lingerie': ['Bras', 'Panties', 'Lingerie Sets', 'Shapewear', 'Nightwear', 'Other'],
    'Men': ['Men Fashion', 'Shirts', 'T-Shirts', 'Jeans', 'Trousers', 'Formal Wear', 'Casual Wear', 'Accessories', 'Other'],
    'Kids & Toys': ['Kids Clothing', 'Toys', 'Baby Care', 'School Supplies', 'Games', 'Other'],
    'Home & Kitchen': ['Kitchenware', 'Home Decor', 'Furniture', 'Bedding', 'Bath', 'Storage', 'Other'],
    'Electronics': ['Mobiles', 'Laptops', 'Accessories', 'Audio', 'Cameras', 'Gaming', 'Other'],
    'Beauty & Personal Care': ['Skincare', 'Makeup', 'Hair Care', 'Fragrances', 'Personal Hygiene', 'Other'],
    'Footwear': ['Sneakers', 'Formal Shoes', 'Casual Shoes', 'Sandals', 'Boots', 'Slippers', 'Other'],
    'Other': ['Custom Category', 'Special Items', 'Miscellaneous'],
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

  String _getIconForSubcategory(String subcategoryName) {
    final name = subcategoryName.toLowerCase();
    switch (name) {
      case 'kurtis':
        return '👕';
      case 'sarees':
        return '🥻';
      case 'lehengas':
        return '👗';
      case 'dress materials':
        return '🧵';
      case 'dupattas':
        return '🧣';
      case 'anarkali suits':
        return '👘';
      case 'tops':
        return '👚';
      case 'shirts':
        return '👔';
      case 'jeans':
        return '👖';
      case 'dresses':
        return '👗';
      case 'skirts':
        return '👗';
      case 'shorts':
        return '🩳';
      case 'jackets':
        return '🧥';
      case 'blazers':
        return '🥋';
      case 'bras':
        return '👙';
      case 'panties':
        return '🩲';
      case 'lingerie sets':
        return '👙';
      case 'shapewear':
        return '🦺';
      case 'nightwear':
        return '🌙';
      case 'men fashion':
        return '👔';
      case 't-shirts':
        return '👕';
      case 'trousers':
        return '👖';
      case 'formal wear':
        return '🤵';
      case 'casual wear':
        return '👕';
      case 'accessories':
        return '⌚';
      case 'kids clothing':
        return '👶';
      case 'toys':
        return '🧸';
      case 'baby care':
        return '🍼';
      case 'school supplies':
        return '📚';
      case 'games':
        return '🎮';
      case 'kitchenware':
        return '🍳';
      case 'home decor':
        return '🏠';
      case 'furniture':
        return '🪑';
      case 'bedding':
        return '🛏️';
      case 'bath':
        return '🚿';
      case 'storage':
        return '📦';
      case 'mobiles':
        return '📱';
      case 'laptops':
        return '💻';
      case 'audio':
        return '🎧';
      case 'cameras':
        return '📷';
      case 'gaming':
        return '🎮';
      case 'skincare':
        return '🧴';
      case 'makeup':
        return '💄';
      case 'hair care':
        return '💇';
      case 'fragrances':
        return '🌸';
      case 'personal hygiene':
        return '🧼';
      case 'sneakers':
        return '👟';
      case 'formal shoes':
        return '👞';
      case 'casual shoes':
        return '👟';
      case 'sandals':
        return '👡';
      case 'boots':
        return '👢';
      case 'slippers':
        return '🩴';
      case 'westernwear':
        return '👗';
      case 'jewellery':
        return '💍';
      case 'kids':
        return '🧸';
      case 'footwear':
        return '👠';
      case 'beauty & personal care':
        return '💄';
      case 'grocery':
        return '🛒';
      case 'other':
        return '📦';
      case 'custom category':
        return '🏷️';
      case 'special items':
        return '✨';
      case 'miscellaneous':
        return '📦';
      default:
        return '📦';
    }
  }

  List<String> get _currentSubcategories {
    return _subcategories[_selectedCategory] ?? [];
  }

  List<Map<String, String>> get _filteredCategories {
    if (_searchQuery.isEmpty) {
      return _categories;
    }
    final query = _searchQuery.toLowerCase();
    
    // Search in category names
    final categoryMatches = _categories
        .where(
          (category) => category['name']!.toLowerCase().contains(query),
        )
        .toList();
    
    // Also search in subcategories and include their parent categories
    final subcategoryMatches = <String>{};
    _subcategories.forEach((category, subcategories) {
      if (subcategories.any((sub) => sub.toLowerCase().contains(query))) {
        subcategoryMatches.add(category);
      }
    });
    
    // Combine both results
    final allMatches = <String>{};
    allMatches.addAll(categoryMatches.map((c) => c['name']!));
    allMatches.addAll(subcategoryMatches);
    
    return _categories.where((cat) => allMatches.contains(cat['name']!)).toList();
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
              ? Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Search categories...',
                      border: InputBorder.none,
                      hintStyle: TextStyle(color: Colors.grey.shade600),
                      prefixIcon: Icon(Icons.search, color: Colors.grey.shade600, size: 20),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
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
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withOpacity(0.1),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: Center(
                                                child: Text(
                                                  item['image'] as String? ?? _getIconForCategory(item['category'] as String? ?? item['name'] as String),
                                                  style: const TextStyle(
                                                    fontSize: 32,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if ((item['badges'] as List? ?? []).isNotEmpty)
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
                                                    ((item['badges'] as List? ?? []).first).toString(),
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
                                            boxShadow: isSelected
                                                ? [
                                                    BoxShadow(
                                                      color: Colors.purple.withOpacity(0.3),
                                                      blurRadius: 8,
                                                      spreadRadius: 2,
                                                    ),
                                                  ]
                                                : [
                                                    BoxShadow(
                                                      color: Colors.black.withOpacity(0.1),
                                                      blurRadius: 4,
                                                      offset: const Offset(0, 2),
                                                    ),
                                                  ],
                                          ),
                                          child: Center(
                                            child: Text(
                                              _getIconForSubcategory(subcategory),
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
    if (_searchQuery.isEmpty) {
      return const Center(
        child: Text(
          'Type to search categories...',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }
    
    final query = _searchQuery.toLowerCase();
    final results = <Map<String, dynamic>>[];
    
    // Add matching categories
    for (final category in _categories) {
      if (category['name']!.toLowerCase().contains(query)) {
        results.add({
          'type': 'category',
          'name': category['name'],
          'icon': category['icon'],
        });
      }
    }
    
    // Add matching subcategories
    _subcategories.forEach((categoryName, subcategories) {
      for (final subcategory in subcategories) {
        if (subcategory.toLowerCase().contains(query)) {
          results.add({
            'type': 'subcategory',
            'name': subcategory,
            'category': categoryName,
            'icon': _getIconForSubcategory(subcategory),
          });
        }
      }
    });
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: results.isEmpty
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
              itemCount: results.length,
              itemBuilder: (context, index) {
                final result = results[index];
                final isCategory = result['type'] == 'category';
                return GestureDetector(
                  onTap: () async {
                    if (isCategory) {
                      await _saveRecentCategory(result['name'], null);
                      if (mounted) {
                        Navigator.pop(context, {
                          'category': result['name'],
                          'subcategory': null,
                        });
                      }
                    } else {
                      await _saveRecentCategory(result['category'], result['name']);
                      if (mounted) {
                        Navigator.pop(context, {
                          'category': result['category'],
                          'subcategory': result['name'],
                        });
                      }
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: isCategory ? Colors.purple.shade100 : Colors.grey.shade200,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            result['icon'],
                            style: const TextStyle(fontSize: 32),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Flexible(
                        child: Text(
                          result['name'],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isCategory ? Colors.purple : Colors.black87,
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
