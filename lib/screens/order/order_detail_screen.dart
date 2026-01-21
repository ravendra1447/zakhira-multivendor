import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../config.dart';

class OrderDetailScreen extends StatefulWidget {
  final int orderId;

  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  Map<String, dynamic>? order;
  List<dynamic> orderItems = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchOrderDetails();
  }

  Future<void> _fetchOrderDetails() async {
    try {
      // Test server connectivity first
      try {
        final testResponse = await http.get(
          Uri.parse('https://node-api.bangkokmart.in/api/test'),
        ).timeout(const Duration(seconds: 5));
        print('Server test response: ${testResponse.statusCode}');
      } catch (e) {
        print('Server not accessible: $e');
        setState(() {
          errorMessage = 'Server not accessible. Please check if server is running on port 3000.';
          isLoading = false;
        });
        return;
      }

      // Use the exact URL format
      final url = 'https://node-api.bangkokmart.in/api/orders/${widget.orderId}';
      print('Order detail URL: $url'); // Debug log

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      print('Order detail response status: ${response.statusCode}'); // Debug log
      print('Order detail response body: ${response.body}'); // Debug log

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success']) {
          setState(() {
            order = responseData['order'];
            orderItems = responseData['items'] ?? [];
            isLoading = false;
          });
        } else {
          setState(() {
            errorMessage = responseData['message'] ?? 'Failed to fetch order details';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = 'Failed to fetch order details (Status: ${response.statusCode})';
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching order details: $e'); // Debug log
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
      return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
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
        title: Text(
          'Order #${widget.orderId}',
          style: const TextStyle(
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
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
          ? _buildErrorView()
          : order == null
          ? _buildEmptyView()
          : _buildOrderDetails(),
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
            onPressed: _fetchOrderDetails,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return const Center(
      child: Text(
        'Order not found',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildOrderDetails() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order Status Card
          _buildStatusCard(),

          const SizedBox(height: 16),

          // Order Items
          _buildOrderItems(),

          const SizedBox(height: 16),

          // Shipping Address
          _buildShippingAddress(),

          const SizedBox(height: 16),

          // Order Summary
          _buildOrderSummary(),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final status = order!['order_status'] ?? 'Pending';
    return Container(
      width: double.infinity,
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
              const Text(
                'Order Status',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _getStatusColor(status),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Order Date: ${_formatDate(order!['order_date'])}',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Payment Method: ${order!['payment_method'] ?? 'COD'}',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItems() {
    return Container(
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
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Order Items',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...orderItems.map((item) => _buildOrderItem(item)).toList(),
        ],
      ),
    );
  }

  Widget _buildOrderItem(dynamic item) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Product Image
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: item['image_url'] != null && item['image_url'].toString().isNotEmpty
                    ? Image.network(
                  'http://184.168.126.71/api/uploads/${item['image_url']}',
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 60,
                      height: 60,
                      color: Colors.grey[200],
                      child: Icon(
                        Icons.image_not_supported,
                        size: 24,
                        color: Colors.grey[400],
                      ),
                    );
                  },
                )
                    : Container(
                  width: 60,
                  height: 60,
                  color: Colors.grey[200],
                  child: Icon(
                    Icons.image_not_supported,
                    size: 24,
                    color: Colors.grey[400],
                  ),
                ),
              ),
            ),

            const SizedBox(width: 16),

            // Product Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product Name
                  Text(
                    item['product_name'] ?? 'Product',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),

                  // Color and Size Row
                  Row(
                    children: [
                      if (item['color'] != null && item['color'].toString().isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _getColorFromString(item['color']),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey[300]!, width: 1),
                          ),
                          child: Text(
                            item['color'],
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      if (item['size'] != null && item['size'].toString().isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[300]!, width: 1),
                          ),
                          child: Text(
                            item['size'],
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Price and Quantity
                  Row(
                    children: [
                      Text(
                        'Qty: ${item['quantity']}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      const Text('×'),
                      const SizedBox(width: 8),
                      Text(
                        '₹${item['price'].toString()}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Item Total
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '₹${((double.tryParse(item['quantity'].toString()) ?? 0.0) * (double.tryParse(item['price'].toString()) ?? 0.0)).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
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

  // Helper method to get color from string
  Color _getColorFromString(String colorString) {
    switch (colorString.toLowerCase()) {
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.yellow;
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purple;
      case 'pink':
        return Colors.pink;
      case 'black':
        return Colors.black;
      case 'white':
        return Colors.white;
      case 'grey':
      case 'gray':
        return Colors.grey;
      default:
        return Colors.grey[600]!;
    }
  }

  Widget _buildShippingAddress() {
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
          const Text(
            'Shipping Address',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.location_on_outlined, color: Colors.grey[600], size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${order!['shipping_street']}\n${order!['shipping_city']}, ${order!['shipping_state']} - ${order!['shipping_pincode']}\nPhone: ${order!['shipping_phone']}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSummary() {
    // Parse total_amount as double since it comes as string from database
    final totalAmount = double.tryParse(order!['total_amount'].toString()) ?? 0.0;

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
          const Text(
            'Order Summary',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Subtotal'),
              Text('₹${totalAmount.toStringAsFixed(2)}'),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Delivery Fee'),
              Text('FREE'),
            ],
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Amount',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '₹${totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
