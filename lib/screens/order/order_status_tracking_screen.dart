import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../config.dart';
import '../../services/local_auth_service.dart';

class OrderStatusTrackingScreen extends StatefulWidget {
  final int orderId;

  const OrderStatusTrackingScreen({super.key, required this.orderId});

  @override
  State<OrderStatusTrackingScreen> createState() => _OrderStatusTrackingScreenState();
}

class _OrderStatusTrackingScreenState extends State<OrderStatusTrackingScreen> {
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
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/orders/${widget.orderId}'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

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
          errorMessage = 'Failed to fetch order details';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error: ${e.toString()}';
        isLoading = false;
      });
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
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 2,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? _buildErrorView()
              : order == null
                  ? _buildEmptyView()
                  : _buildOrderTrackingView(),
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
        'No order details available',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildOrderTrackingView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order Status Timeline
          _buildStatusTimeline(),
          
          const SizedBox(height: 20),
          
          // Order Details Card
          _buildOrderDetailsCard(),
          
          const SizedBox(height: 20),
          
          // Order Items
          _buildOrderItemsCard(),
          
          const SizedBox(height: 20),
          
          // Shipping Information
          _buildShippingInfoCard(),
        ],
      ),
    );
  }

  Widget _buildStatusTimeline() {
    final currentStatus = order!['order_status']?.toString().toLowerCase() ?? 'pending';
    
    print('🔍 Debug: Current order status: ${order!['order_status']} (lowercase: $currentStatus)');
    
    final statusSteps = [
      {'status': 'pending', 'title': 'Pending', 'icon': Icons.pending_actions, 'description': 'Your order has been placed'},
      {'status': 'waiting for payment', 'title': 'Waiting for Payment', 'icon': Icons.payment, 'description': 'Your order is waiting for payment confirmation'},
      {'status': 'ready for shipment', 'title': 'Ready for Shipment', 'icon': Icons.inventory, 'description': 'Payment confirmed, preparing for shipment'},
      {'status': 'shipped', 'title': 'Order Shipped', 'icon': Icons.local_shipping, 'description': 'Your order is on the way'},
      {'status': 'delivered', 'title': 'Order Delivered', 'icon': Icons.check_circle, 'description': 'Order has been delivered successfully'},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Status',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          ...statusSteps.asMap().entries.map((entry) {
            final index = entry.key;
            final step = entry.value;
            final isActive = currentStatus == step['status'];
            final isCompleted = _isStatusCompleted(currentStatus, step['status'] as String);
            
            return _buildStatusStep(
              step['title'] as String,
              step['description'] as String,
              step['icon'] as IconData,
              isActive,
              isCompleted,
              index < statusSteps.length - 1,
            );
          }).toList(),
        ],
      ),
    );
  }

  bool _isStatusCompleted(String currentStatus, String stepStatus) {
    final statusOrder = ['pending', 'waiting for payment', 'ready for shipment', 'shipped', 'delivered'];
    final currentIndex = statusOrder.indexOf(currentStatus);
    final stepIndex = statusOrder.indexOf(stepStatus);
    return stepIndex < currentIndex;
  }

  Widget _buildStatusStep(
    String title,
    String description,
    IconData icon,
    bool isActive,
    bool isCompleted,
    bool hasConnector,
  ) {
    Color stepColor;
    Color backgroundColor;
    
    if (isCompleted) {
      stepColor = Colors.green;
      backgroundColor = Colors.green[100]!;
    } else if (isActive) {
      stepColor = Colors.blue;
      backgroundColor = Colors.blue[100]!;
    } else {
      stepColor = Colors.grey;
      backgroundColor = Colors.grey[100]!;
    }

    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: backgroundColor,
                shape: BoxShape.circle,
                border: Border.all(color: stepColor, width: 2),
              ),
              child: Icon(
                isCompleted ? Icons.check : icon,
                size: 20,
                color: stepColor,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isCompleted || isActive ? Colors.black87 : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: isCompleted || isActive ? Colors.black54 : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (hasConnector)
          Container(
            margin: const EdgeInsets.only(left: 19, top: 8),
            height: 30,
            width: 2,
            color: isCompleted ? Colors.green : Colors.grey[300]!,
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildOrderDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildDetailRow('Order ID', '#${widget.orderId}'),
          _buildDetailRow('Order Date', _formatDate(order!['order_date'])),
          _buildDetailRow('Payment Method', order!['payment_method'] ?? 'Online'),
          _buildDetailRow('Total Amount', '₹${order!['total_amount'] ?? '0'}'),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItemsCard() {
    // Group items by product name first (same as order detail screen)
    final Map<String, List<dynamic>> itemsByProduct = {};

    for (var item in orderItems) {
      final productName = item['product_name'] ?? 'Unknown Product';
      if (!itemsByProduct.containsKey(productName)) {
        itemsByProduct[productName] = [];
      }
      itemsByProduct[productName]!.add(item);
    }

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
          // Header (without checkbox)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'Order Items',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Group items by product (same as order detail screen)
          ...itemsByProduct.entries.map((entry) {
            final productName = entry.key;
            final productVariants = entry.value;
            return _buildProductSection(productName, productVariants);
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildProductSection(String productName, List<dynamic> variants) {
    // Consolidate identical products (same color and size) to show only once
    final Map<String, Map<String, dynamic>> consolidatedVariants = {};

    for (var variant in variants) {
      final color = variant['color']?.toString() ?? '';
      final size = variant['size']?.toString() ?? '';
      final key = '${color.trim()}-${size.trim()}';

      if (consolidatedVariants.containsKey(key)) {
        // If same variant exists, just keep the first one (don't sum quantity)
        // The database already has correct data
        continue;
      } else {
        // Add new variant
        consolidatedVariants[key] = Map<String, dynamic>.from(variant);
      }
    }

    final List<dynamic> uniqueVariants = consolidatedVariants.values.toList();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product Name Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              productName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Unique Variants List (show each variant only once)
          ...uniqueVariants.asMap().entries.map((entry) {
            final index = entry.key;
            final variant = entry.value;
            return _buildVariantItem(variant, index == uniqueVariants.length - 1);
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildVariantItem(dynamic item, bool isLast) {
    // Get the individual item price (not the total)
    final itemPrice = double.tryParse(item['price'].toString()) ?? 0.0;
    final quantity = int.tryParse(item['quantity'].toString()) ?? 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Product Image (without onTap)
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: _buildProductImage(item),
            ),
          ),

          const SizedBox(width: 12),

          // Variant Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Variant badges
                Row(
                  children: [
                    if (item['color'] != null && item['color'].toString().isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getColorFromString(item['color']),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!, width: 1),
                        ),
                        child: Text(
                          item['color'],
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    if (item['size'] != null && item['size'].toString().isNotEmpty && item['size'].toString().toLowerCase() != 'no size')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!, width: 1),
                        ),
                        child: Text(
                          'Size: ${item['size']}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // Price and Quantity - Show actual quantity and individual price
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Qty: $quantity x ₹${itemPrice.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Total: ₹${(itemPrice * quantity).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductImage(dynamic item) {
    // Try multiple image sources in order of preference
    String? imageUrl;
    
    // First try: item-specific image_url
    if (item['image_url'] != null && item['image_url'].toString().isNotEmpty) {
      imageUrl = item['image_url'].toString();
    }
    
    if (imageUrl != null) {
      return Image.network(
        imageUrl,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildDefaultImage();
        },
      );
    }
    
    return _buildDefaultImage();
  }

  Widget _buildDefaultImage() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        Icons.image,
        color: Colors.grey[400],
        size: 30,
      ),
    );
  }

  Color _getColorFromString(String colorString) {
    // Map common color names to actual colors
    final Map<String, Color> colorMap = {
      'red': Colors.red,
      'blue': Colors.blue,
      'green': Colors.green,
      'yellow': Colors.yellow,
      'orange': Colors.orange,
      'purple': Colors.purple,
      'pink': Colors.pink,
      'brown': Colors.brown,
      'black': Colors.black,
      'white': Colors.white,
      'grey': Colors.grey,
      'gray': Colors.grey,
    };

    final lowerColor = colorString.toLowerCase().trim();
    
    // Check for exact match
    if (colorMap.containsKey(lowerColor)) {
      return colorMap[lowerColor]!;
    }
    
    // Check for partial matches
    for (String key in colorMap.keys) {
      if (lowerColor.contains(key)) {
        return colorMap[key]!;
      }
    }
    
    // Default color if no match found
    return Colors.blue;
  }

  Widget _buildShippingInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Shipping Information',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildShippingRow(Icons.person, 'Customer Name', order!['customer_name'] ?? 'N/A'),
          _buildShippingRow(Icons.phone, 'Phone Number', order!['customer_phone'] ?? order!['shipping_phone'] ?? 'N/A'),
          _buildShippingRow(Icons.location_on, 'Address', 
              '${order!['shipping_street']}, ${order!['shipping_city']}, ${order!['shipping_state']} - ${order!['shipping_pincode']}'),
        ],
      ),
    );
  }

  Widget _buildShippingRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'N/A';
    
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateString;
    }
  }
}
