import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../services/local_auth_service.dart';
import '../../services/admin_dashboard_service.dart';
import '../../config.dart';
import 'all_orders_screen.dart';
import 'admin_all_orders_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  Map<String, dynamic>? stats;
  Map<String, dynamic>? codStats;
  Map<String, dynamic>? pickupStats;
  bool isLoading = true;
  String? errorMessage;
  late TabController _tabController;
  
  // Admin dashboard specific variables
  bool isAdmin = false;
  Map<String, dynamic>? adminData;
  List<Map<String, dynamic>>? adminWebsites;
  Map<String, dynamic>? adminStats;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _checkAdminAndFetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Check if user is admin and fetch appropriate data
  Future<void> _checkAdminAndFetchData() async {
    try {
      final adminStatus = await AdminDashboardService.isAdminUser();
      setState(() {
        isAdmin = adminStatus;
      });
      
      if (isAdmin) {
        await _fetchAdminDashboardData();
      } else {
        await _fetchDashboardStats();
      }
    } catch (e) {
      print('Error checking admin status: $e');
      await _fetchDashboardStats(); // Fallback to regular dashboard
    }
  }

  // Fetch admin dashboard data
  Future<void> _fetchAdminDashboardData() async {
    try {
      print('Fetching admin dashboard data...');
      
      final data = await AdminDashboardService.getAdminDashboardData();
      
      setState(() {
        adminData = data;
        adminStats = data['stats'];
        adminWebsites = (data['websites'] as List?)?.cast<Map<String, dynamic>>();
        isLoading = false;
        errorMessage = null;
      });
      
      print('Admin dashboard data loaded successfully');
      print('Websites: ${adminWebsites?.length}');
      print('Stats: $adminStats');
      
    } catch (e) {
      print('Admin Dashboard Error: $e');
      setState(() {
        isLoading = false;
        errorMessage = 'Admin dashboard error: ${e.toString()}';
      });
    }
  }

  Future<void> _fetchDashboardStats() async {
    try {
      print('Fetching dashboard stats using working endpoint...');
      
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }
      
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/orders/user/$userId'),
        headers: {
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      print('Dashboard Response status: ${response.statusCode}');
      print('Dashboard Response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] && responseData['orders'] != null) {
          final orders = responseData['orders'] as List;
          
          // Filter orders by payment method
          final codOrders = orders.where((order) => 
            order['payment_method']?.toString().toLowerCase() == 'cod'
          ).toList();
          
          final pickupOrders = orders.where((order) => 
            order['payment_method']?.toString().toLowerCase() != 'cod'
          ).toList();
          
          // Calculate stats for all orders
          stats = _calculateStats(orders);
          
          // Calculate stats for COD orders
          codStats = _calculateStats(codOrders);
          
          // Calculate stats for Pickup & Delivery orders
          pickupStats = _calculateStats(pickupOrders);
          
          setState(() {
            isLoading = false;
            errorMessage = null;
          });
        } else {
          throw Exception('API returned failure');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      print('Dashboard API Error: $e');
      // Show demo data when API fails
      setState(() {
        stats = _getDemoStats();
        codStats = _getDemoStats();
        pickupStats = _getDemoStats();
        isLoading = false;
        errorMessage = 'Server not available - Using demo data';
      });
    }
  }

  Map<String, dynamic> _calculateStats(List orders) {
    final totalOrders = orders.length;
    
    // Calculate today's orders
    final todayOrders = orders.where((order) {
      try {
        final orderDate = DateTime.parse(order['order_date']);
        final today = DateTime.now();
        return orderDate.day == today.day && 
               orderDate.month == today.month && 
               orderDate.year == today.year;
      } catch (e) {
        return false;
      }
    }).length;
    
    // Calculate yesterday's orders
    final yesterdayOrders = orders.where((order) {
      try {
        final orderDate = DateTime.parse(order['order_date']);
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        return orderDate.day == yesterday.day && 
               orderDate.month == yesterday.month && 
               orderDate.year == yesterday.year;
      } catch (e) {
        return false;
      }
    }).length;
    
    // Calculate cancelled orders
    final cancelledOrders = orders.where((o) => 
      o['order_status']?.toString().toLowerCase() == 'cancelled'
    ).length;
    
    // Calculate total revenue
    final totalRevenue = orders.fold<double>(0, (sum, order) {
      final amount = double.tryParse(order['total_amount']?.toString() ?? '0') ?? 0;
      return sum + amount;
    });
    
    return {
      'todayOrders': todayOrders,
      'yesterdayOrders': yesterdayOrders,
      'totalOrders': totalOrders,
      'cancelledOrders': cancelledOrders,
      'totalRevenue': totalRevenue,
      'weekRevenue': 0, // TODO: Calculate this week revenue
      'monthRevenue': 0, // TODO: Calculate this month revenue
    };
  }

  Map<String, dynamic> _getDemoStats() {
    return {
      'todayOrders': 0,
      'yesterdayOrders': 0,
      'totalOrders': 0,
      'cancelledOrders': 0,
      'totalRevenue': 0,
      'weekRevenue': 0,
      'monthRevenue': 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Dashboard',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 2,
        centerTitle: true,
        iconTheme: const IconThemeData(
          color: Colors.black,
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.purple,
          labelColor: Colors.purple,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'COD'),
            Tab(text: 'Pickup & Delivery'),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _checkAdminAndFetchData,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (errorMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        border: Border.all(color: Colors.orange.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning, color: Colors.orange.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: TextStyle(color: Colors.orange.shade700, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: isAdmin 
                        ? [
                            _buildAdminDashboardView(adminStats, 'Overview'),
                            _buildAdminDashboardView(adminStats, 'COD'),
                            _buildAdminDashboardView(adminStats, 'Pickup & Delivery'),
                          ]
                        : [
                            _buildDashboardView(stats, 'Overview'),
                            _buildDashboardView(codStats, 'COD'),
                            _buildDashboardView(pickupStats, 'Pickup & Delivery'),
                          ],
                    ),
                  ),
                ],
              ),
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
            onPressed: _fetchDashboardStats,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return const Center(
      child: Text(
        'No data available',
        style: TextStyle(
          fontSize: 18,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildDashboardView(Map<String, dynamic>? currentStats, String title) {
    if (currentStats == null) {
      return _buildEmptyView();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Orders Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Orders',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              if (title == 'Overview')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Last 30 Days',
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down, size: 20, color: Colors.grey[600]),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Today's and Yesterday's Orders Row
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdminAllOrdersScreen(
                          orders: [],
                          initialFilter: 'today',
                        ),
                      ),
                    );
                  },
                  child: _buildOrderCard(
                    'Today\'s Orders',
                    currentStats['todayOrders'].toString(),
                    Colors.blue,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdminAllOrdersScreen(
                          orders: [],
                          initialFilter: 'yesterday',
                        ),
                      ),
                    );
                  },
                  child: _buildOrderCard(
                    'Yesterday\'s Orders',
                    currentStats['yesterdayOrders'].toString(),
                    Colors.orange,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Total Orders (Clickable only in Overview)
          if (title == 'Overview')
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AllOrdersScreen(),
                  ),
                );
              },
              child: _buildOrderCard(
                'Total Orders',
                currentStats['totalOrders'].toString(),
                Colors.green,
                isClickable: true,
              ),
            )
          else
            _buildOrderCard(
              'Total Orders',
              currentStats['totalOrders'].toString(),
              Colors.green,
            ),
          
          const SizedBox(height: 16),
          
          // Cancelled Orders
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AdminAllOrdersScreen(
                    orders: [],
                    initialFilter: 'cancelled',
                  ),
                ),
              );
            },
            child: _buildOrderCard(
              'Cancelled Orders',
              currentStats['cancelledOrders'].toString(),
              Colors.red,
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Summary Lines
          _buildSummaryLine('Total Freight Charges', '₹0'),
          _buildSummaryLine('Average Shipping Cost', '₹0'),
          
          const SizedBox(height: 24),
          
          // Revenue Section
          const Text(
            'Revenue',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          
          // Revenue Cards
          Row(
            children: [
              Expanded(
                child: _buildRevenueCard(
                  'Lifetime',
                  '₹${currentStats['totalRevenue'].toString()}',
                  Colors.purple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildRevenueCard(
                  'This Week',
                  '₹${currentStats['weekRevenue'].toString()}',
                  Colors.teal,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          _buildRevenueCard(
            'This Month',
            '₹${currentStats['monthRevenue'].toString()}',
            Colors.indigo,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryLine(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[700],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(String title, String value, Color color, {bool isClickable = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              if (isClickable)
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey[600],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // Show admin orders screen
  void _showAdminOrders() {
    if (adminData != null && adminData!['orders'] != null) {
      final orders = adminData!['orders'] as List;
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AdminAllOrdersScreen(orders: orders),
        ),
      );
    }
  }

  // Helper method to get status color
  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      case 'processing':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  // Admin Dashboard View
  Widget _buildAdminDashboardView(Map<String, dynamic>? currentStats, String title) {
    if (currentStats == null) {
      return _buildEmptyView();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Admin Badge and Websites Info
          if (isAdmin)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                border: Border.all(color: Colors.purple.shade200),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.admin_panel_settings, color: Colors.purple.shade700, size: 24),
                      const SizedBox(width: 8),
                      const Text(
                        'Admin Dashboard',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple,
                        ),
                      ),
                    ],
                  ),
                  if (adminWebsites != null && adminWebsites!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Managed Websites:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...adminWebsites!.map((website) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(Icons.link, color: Colors.purple.shade600, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${website['website_name']} (${website['domain']})',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )).toList(),
                  ],
                ],
              ),
            ),
          
          // Orders Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Orders',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              if (title == 'Overview')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'All Websites',
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down, size: 20, color: Colors.grey[600]),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Today's and Yesterday's Orders Row
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdminAllOrdersScreen(
                          orders: adminData?['orders'] ?? [],
                          initialFilter: 'today',
                        ),
                      ),
                    );
                  },
                  child: _buildOrderCard(
                    'Today\'s Orders',
                    currentStats['todayOrders'].toString(),
                    Colors.blue,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdminAllOrdersScreen(
                          orders: adminData?['orders'] ?? [],
                          initialFilter: 'yesterday',
                        ),
                      ),
                    );
                  },
                  child: _buildOrderCard(
                    'Yesterday\'s Orders',
                    currentStats['yesterdayOrders'].toString(),
                    Colors.orange,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Total Orders (Clickable for admin users)
          if (isAdmin && title == 'Overview')
            GestureDetector(
              onTap: () {
                _showAdminOrders();
              },
              child: _buildOrderCard(
                'Total Orders',
                currentStats['totalOrders'].toString(),
                Colors.green,
                isClickable: true,
              ),
            )
          else if (!isAdmin && title == 'Overview')
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AllOrdersScreen(),
                  ),
                );
              },
              child: _buildOrderCard(
                'Total Orders',
                currentStats['totalOrders'].toString(),
                Colors.green,
                isClickable: true,
              ),
            )
          else
            _buildOrderCard(
              'Total Orders',
              currentStats['totalOrders'].toString(),
              Colors.green,
            ),
          
          const SizedBox(height: 16),
          
          // Cancelled Orders
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AdminAllOrdersScreen(
                    orders: adminData?['orders'] ?? [],
                    initialFilter: 'cancelled',
                  ),
                ),
              );
            },
            child: _buildOrderCard(
              'Cancelled Orders',
              currentStats['cancelledOrders'].toString(),
              Colors.red,
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Summary Lines
          _buildSummaryLine('Managed Websites', '${adminWebsites?.length ?? 0}'),
          if (adminData != null && adminData!['products'] != null)
            _buildSummaryLine('Total Products', '${adminData!['products'].length}'),
          
          const SizedBox(height: 24),
          
          // Revenue Section
          const Text(
            'Revenue',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          
          // Revenue Cards
          Row(
            children: [
              Expanded(
                child: _buildRevenueCard(
                  'Lifetime',
                  '₹${currentStats['totalRevenue'].toString()}',
                  Colors.purple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildRevenueCard(
                  'This Week',
                  '₹${currentStats['weekRevenue'].toString()}',
                  Colors.teal,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          _buildRevenueCard(
            'This Month',
            '₹${currentStats['monthRevenue'].toString()}',
            Colors.indigo,
          ),
        ],
      ),
    );
  }
}
