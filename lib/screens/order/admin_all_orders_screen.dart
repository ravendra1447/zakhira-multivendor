import 'package:flutter/material.dart';
import 'order_detail_screen.dart';
import 'admin_shipment_management_screen.dart';

class AdminAllOrdersScreen extends StatefulWidget {
  final List<dynamic> orders;
  final String? initialFilter;
  final String? websiteFilter;

  const AdminAllOrdersScreen({
    super.key,
    required this.orders,
    this.initialFilter,
    this.websiteFilter,
  });

  @override
  State<AdminAllOrdersScreen> createState() => _AdminAllOrdersScreenState();
}

class _AdminAllOrdersScreenState extends State<AdminAllOrdersScreen> {
  String _searchQuery = '';
  String _selectedStatus = 'All';
  String? _selectedWebsite; // New state variable for selected website
  List<String> _websiteFilters = []; // New list to hold unique website names

  @override
  void initState() {
    super.initState();
    _populateWebsiteFilters();
    _setInitialFilter();
    _selectedWebsite = widget.websiteFilter; // Set initial website filter
  }

  void _setInitialFilter() {
    // Set initial filter based on parameter
    if (widget.initialFilter != null) {
      switch (widget.initialFilter) {
        case 'today':
          _selectedStatus = 'Today';
          break;
        case 'yesterday':
          _selectedStatus = 'Yesterday';
          break;
        case 'cancelled':
          _selectedStatus = 'Cancelled';
          break;
        default:
          _selectedStatus = 'All';
      }
    }
  }

  void _populateWebsiteFilters() {
    // Hardcode only BangkokMart and Zakhira websites
    _websiteFilters = ['All', 'BangkokMart', 'Zakhira'];
    _selectedWebsite = 'All'; // Initialize with 'All' selected
  }

  List<dynamic> get _filteredOrders {
    var filtered = widget.orders.where((order) {
      // Handle date-based filters
      if (_selectedStatus == 'Today') {
        try {
          final orderDate = DateTime.parse(order['order_date']);
          final today = DateTime.now();
          return orderDate.day == today.day && 
                 orderDate.month == today.month && 
                 orderDate.year == today.year;
        } catch (e) {
          return false;
        }
      }
      
      if (_selectedStatus == 'Yesterday') {
        try {
          final orderDate = DateTime.parse(order['order_date']);
          final yesterday = DateTime.now().subtract(const Duration(days: 1));
          return orderDate.day == yesterday.day && 
                 orderDate.month == yesterday.month && 
                 orderDate.year == yesterday.year;
        } catch (e) {
          return false;
        }
      }
      
      // Handle status-based filters
      final matchesStatus = _selectedStatus == 'All' || 
                           order['order_status']?.toString().toLowerCase() == _selectedStatus.toLowerCase();
      
      final matchesWebsite = _selectedWebsite == 'All' || 
                           order['website_name'] == _selectedWebsite;
      
      return matchesStatus && matchesWebsite;
    }).toList();

    // Sort by date (newest first)
    filtered.sort((a, b) {
      final dateA = DateTime.tryParse(a['order_date'] ?? '') ?? DateTime.now();
      final dateB = DateTime.tryParse(b['order_date'] ?? '') ?? DateTime.now();
      return dateB.compareTo(dateA);
    });

    return filtered;
  }

  final List<String> _statusOptions = [
    'Pending',
    'Today',
    'Yesterday',
    'All',
    'Waiting for Payment',
    'Ready for Shipment',
    'Shipped',
    'Delivered',
    'Cancelled'
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'All Website Orders (${_filteredOrders.length})',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 2,
        iconTheme: const IconThemeData(
          color: Colors.black,
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AdminShipmentManagementScreen(),
                ),
              );
            },
            icon: const Icon(Icons.local_shipping),
            tooltip: 'Shipment Management',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Status Filters (First)
                  ..._statusOptions.map((status) {
                    final isSelected = status == _selectedStatus;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(
                          status,
                          style: TextStyle(
                            fontSize: 12,
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _selectedStatus = status;
                          });
                        },
                        backgroundColor: Colors.white,
                        selectedColor: Colors.purple.shade100,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.purple.shade700 : Colors.black87,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color: isSelected ? Colors.purple : Colors.grey[300]!,
                        ),
                      ),
                    );
                  }).toList(),
                  
                  // Website Filters (Second)
                  ..._websiteFilters.map((website) {
                    final isSelected = website == _selectedWebsite;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(
                          website,
                          style: TextStyle(
                            fontSize: 12,
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _selectedWebsite = website;
                          });
                        },
                        backgroundColor: Colors.white,
                        selectedColor: Colors.blue.shade100,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.blue.shade700 : Colors.black87,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color: isSelected ? Colors.blue : Colors.grey[300]!,
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
        ),
      ),
      body: _filteredOrders.isEmpty
          ? _buildEmptyView()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _filteredOrders.length,
              itemBuilder: (context, index) {
                final order = _filteredOrders[index];
                return _buildOrderCard(order);
              },
            ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No orders found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your search or filter',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(dynamic order) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          // Navigate to order detail
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OrderDetailScreen(orderId: order['id']),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Order Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Order ID Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '#${order['id'] ?? 'N/A'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade700,
                      ),
                    ),
                  ),
                  
                  const Spacer(),
                  
                  // Status Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getStatusColor(order['order_status']).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      order['order_status'] ?? 'Pending',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _getStatusColor(order['order_status']),
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Customer Info
              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 20,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order['customer_name'] ?? 'Unknown Customer',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              
              // Phone and Date
              Row(
                children: [
                  Icon(
                    Icons.phone_outlined,
                    size: 20,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      order['customer_phone'] ?? 'N/A',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 20,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _formatDate(order['order_date']),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Amount and Website
              Row(
                children: [
                  // Amount
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '₹${order['total_amount'] ?? '0'}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // Website Info
                  if (order['website_name'] != null)
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.link,
                            size: 16,
                            color: Colors.purple.shade600,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              order['website_name'],
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.purple.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'pending':
        return Colors.grey;
      case 'waiting for payment':
        return Colors.orange;
      case 'ready for shipment':
        return Colors.blue;
      case 'shipped':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'N/A';
    
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }
}
