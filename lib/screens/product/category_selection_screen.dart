import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class CategorySelectionScreen extends StatefulWidget {
  const CategorySelectionScreen({super.key});

  @override
  State<CategorySelectionScreen> createState() =>
      _CategorySelectionScreenState();
}

class _CategorySelectionScreenState extends State<CategorySelectionScreen> {
  String _selectedCategory = 'Popular';
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

  @override
  void initState() {
    super.initState();
    _loadRecentCategories();
  }

  Future<void> _loadRecentCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final recentJson = prefs.getString('recent_categories');
    if (recentJson != null) {
      final List<dynamic> recentList = json.decode(recentJson);
      setState(() {
        _recentItems = recentList.map((item) => {
          'name': item['name'],
          'image': item['image'] ?? _getIconForCategory(item['name']),
          'badges': item['badges'] ?? [],
        }).toList();
      });
    }
  }

  Future<void> _saveRecentCategory(String categoryName) async {
    // Remove if already exists
    _recentItems.removeWhere((item) => item['name'] == categoryName);
    
    // Add to beginning
    _recentItems.insert(0, {
      'name': categoryName,
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

  final List<Map<String, dynamic>> _allPopularItems = [
    {'name': 'Kurtis & Dress Materials', 'image': '👗'},
    {'name': 'Sarees', 'image': '👘'},
    {'name': 'Westernwear', 'image': '👚'},
    {'name': 'Jewellery', 'image': '💍'},
    {'name': 'Men Fashion', 'image': '👔'},
    {'name': 'Kids', 'image': '👶'},
    {'name': 'Footwear', 'image': '👠'},
    {'name': 'Beauty & Personal Care', 'image': '💄'},
    {'name': 'Grocery', 'image': '🛒'},
  ];

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
                // Main Content Area
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
                                      await _saveRecentCategory(item['name'] as String);
                                      if (mounted) {
                                        Navigator.pop(context, item['name']);
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
                        // All Popular Section
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'All Popular',
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
                                itemCount: _allPopularItems.length,
                                itemBuilder: (context, index) {
                                  final item = _allPopularItems[index];
                                  return GestureDetector(
                                    onTap: () async {
                                      await _saveRecentCategory(item['name'] as String);
                                      if (mounted) {
                                        Navigator.pop(context, item['name']);
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
                                              item['image'] as String,
                                              style: const TextStyle(
                                                fontSize: 32,
                                              ),
                                            ),
                                          ),
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
                    await _saveRecentCategory(category['name']!);
                    if (mounted) {
                      Navigator.pop(context, category['name']);
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
