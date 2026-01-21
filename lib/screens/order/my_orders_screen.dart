import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../services/local_auth_service.dart';
import '../../config.dart';
import 'order_detail_screen.dart';

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  List<dynamic> orders = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        setState(() {
          errorMessage = 'User not logged in';
          isLoading = false;
        });
        return;
      }

      final userIdString = userId.toString();
      print('Fetching orders for user ID: $userIdString'); // Debug log

      // Test server connectivity first
      try {
        final testResponse = await http.get(
          Uri.parse('${Config.baseNodeApiUrl}/test'),
        ).timeout(const Duration(seconds: 5));
        print('Server test response: ${testResponse.statusCode}');
        print('Server test body: ${testResponse.body}');
      } catch (e) {
        print('Server not accessible: $e');
        setState(() {
          errorMessage = 'Server not accessible. Please check if server is running on port 3000.';
          isLoading = false;
        });
        return;
      }

      // Construct the exact URL you want
      final url = 'https://node-api.bangkokmart.in/api/orders/user/$userIdString';
      print('Request URL: $url'); // Debug log

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      print('Response status code: ${response.statusCode}'); // Debug log
      print('Response body: ${response.body}'); // Debug log

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('Orders response: ${responseData['orders']}'); // Debug log
        
        if (responseData['success']) {
          setState(() {
            orders = responseData['orders'] ?? [];
            print('User has ${orders.length} orders'); // Debug log
            isLoading = false;
          });
        } else {
          setState(() {
            errorMessage = responseData['message'] ?? 'Failed to fetch orders';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = 'Failed to fetch orders (Status: ${response.statusCode})';
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching orders: $e'); // Debug log
      print('Stack trace: ${StackTrace.current}'); // Debug log
      setState(() {
        errorMessage = 'Error: ${e.toString()}';
        isLoading = false;
      });
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return Colors.blue;
      case 'shipped':
        return Colors.purple;
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'My Orders',
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
      ),
      body: RefreshIndicator(
        onRefresh: _fetchOrders,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage != null
                ? _buildErrorView()
                : orders.isEmpty
                    ? _buildEmptyView()
                    : _buildOrdersList(),
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
            onPressed: _fetchOrders,
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
            Icons.shopping_bag_outlined,
            size: 100,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 20),
          Text(
            'No orders yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Start shopping to see your orders here',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        return _buildOrderCard(order, index);
      },
    );
  }

  Widget _buildOrderCard(dynamic order, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
      child: InkWell(
        onTap: () {
          final orderId = int.tryParse(order['id'].toString()) ?? 0;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OrderDetailScreen(orderId: orderId),
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Order #${order['id']}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(order['order_status'] ?? 'pending'),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      order['order_status'] ?? 'Pending',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Order Date and Amount
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Date: ${_formatDate(order['order_date'])}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    '₹${order['total_amount'].toString()}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Shipping Address Preview
              Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${order['shipping_street']}, ${order['shipping_city']}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // View Details Button
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'View Details',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: Colors.blue[600],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
