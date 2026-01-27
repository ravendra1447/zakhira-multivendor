import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../../models/product.dart';
import '../../services/product_database_service.dart';
import '../../services/product_service.dart';
import '../../services/website_service.dart';
import '../product/detail/product_detail_screen.dart';
import 'website_products_list_screen.dart';
import 'package:whatsappchat/theme/app_theme.dart';
import 'package:whatsappchat/theme/app_colors.dart';
import 'package:whatsappchat/theme/app_typography.dart';
import 'package:whatsappchat/theme/app_spacing.dart';
import 'package:whatsappchat/widgets/modern_card.dart';

class WebsiteTab extends StatefulWidget {
  const WebsiteTab({super.key});

  @override
  State<WebsiteTab> createState() => WebsiteTabState();
}

class WebsiteTabState extends State<WebsiteTab> {
  List<Map<String, dynamic>> _websites = [];
  List<Map<String, dynamic>> _filteredWebsites = [];
  bool _loadingWebsites = false;
  final TextEditingController _searchController = TextEditingController();
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _fetchWebsites();
    _searchController.addListener(_filterWebsites);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchWebsites() async {
    setState(() {
      _loadingWebsites = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      
      if (userId != null) {
        print('🔍 Fetching websites with products for user: $userId');
        final result = await WebsiteService.getWebsitesWithProducts(int.parse(userId));
        
        if (result['success'] == true) {
          setState(() {
            _websites = List<Map<String, dynamic>>.from(result['websites']);
            _filteredWebsites = _websites;
          });
          print('✅ Successfully loaded ${_websites.length} websites');
        } else {
          print('❌ Failed to load websites');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to load websites'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        print('❌ User ID is null');
      }
    } catch (e) {
      print('❌ Error fetching websites: $e');
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
        _loadingWebsites = false;
      });
    }
  }

  void _filterWebsites() {
    setState(() {
      _filteredWebsites = _websites.where((website) {
        final matchesSearch = website['website_name'].toString().toLowerCase()
            .contains(_searchController.text.toLowerCase()) ||
            website['domain'].toString().toLowerCase()
                .contains(_searchController.text.toLowerCase());
        
        return matchesSearch;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: Column(
        children: [
          // Header with search
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
                Row(
                  children: [
                    Icon(
                      Icons.language,
                      color: AppColors.primary(context),
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Published Websites',
                        style: AppTypography.heading2(context).copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (_loadingWebsites)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary(context),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                // Search bar
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search websites...',
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
              ],
            ),
          ),
          
          // Website list
          Expanded(
            child: _loadingWebsites
                ? Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary(context),
                    ),
                  )
                : _filteredWebsites.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _fetchWebsites,
                        child: ListView.builder(
                          padding: AppSpacing.paddingHorizontalLG.add(AppSpacing.paddingVerticalMD),
                          itemCount: _filteredWebsites.length,
                          itemBuilder: (context, index) {
                            final website = _filteredWebsites[index];
                            return _buildWebsiteCard(website, index);
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
            Icons.language_outlined,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No Published Websites',
            style: AppTypography.heading3(context).copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Publish products to websites to see them here',
            style: AppTypography.bodySmall(context).copyWith(
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _fetchWebsites,
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

  Widget _buildWebsiteCard(Map<String, dynamic> website, int index) {
    final productCount = website['product_count'] ?? 0;
    final websiteName = website['website_name'] ?? 'Unknown Website';
    final domain = website['domain'] ?? 'No domain';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: ModernCard(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => WebsiteProductsListScreen(
                websiteId: website['website_id'],
                websiteName: websiteName,
                domain: domain,
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Website icon/avatar
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.primary(context).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.language,
                    color: AppColors.primary(context),
                    size: 30,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        websiteName,
                        style: AppTypography.heading3(context).copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        domain,
                        style: AppTypography.bodySmall(context).copyWith(
                          color: AppColors.textSecondary(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary(context).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$productCount products',
                              style: AppTypography.caption(context).copyWith(
                                color: AppColors.primary(context),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: AppColors.textSecondary(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
