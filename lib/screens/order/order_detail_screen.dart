import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import '../../config.dart';
import '../../services/local_auth_service.dart';
import '../../services/whatsapp_payment_service.dart';
import '../../services/whatsapp_direct_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

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

  Future<void> _fetchOrderDetails({bool silent = false}) async {
    if (!silent) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    }

    try {
      print('Fetching order details for order ID: ${widget.orderId}');

      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/orders/${widget.orderId}'),
        headers: {
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      print('Order detail response status: ${response.statusCode}');
      print('Order detail response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success']) {
          setState(() {
            order = responseData['order'];
            orderItems = responseData['items'] ?? [];

            // Get customer name from order data (server now includes customer_name)
            String userName = responseData['order']['customer_name'] ??
                responseData['order']['user_name'] ??
                responseData['order']['name'] ??
                responseData['order']['full_name'] ??
                responseData['order']['first_name'] ??
                'Customer';

            // If still no customer name, fetch from users table
            if (userName == 'Customer' && responseData['order']?['user_id'] != null) {
              _fetchCustomerName(responseData['order']['user_id']);
            }

            // Also check if there's a separate user object in response
            if (responseData['user'] != null) {
              userName = responseData['user']['name'] ??
                  responseData['user']['user_name'] ??
                  responseData['user']['full_name'] ??
                  responseData['user']['first_name'] ??
                  userName;
            }

            // If customer name still not found, fetch from users table using user_id
            if (userName == null || userName == 'N/A') {
              final userId = responseData['order']?['user_id'];
              if (userId != null) {
                _fetchCustomerName(userId);
              }
            }

            // Store user name in order object for display
            if (order != null) {
              order!['display_name'] = userName;
            }

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
      print('Error fetching order details: $e');
      setState(() {
        errorMessage = 'Error: ${e.toString()}';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white.withOpacity(0.3), Colors.white.withOpacity(0.1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
              ),
              child: const Icon(
                Icons.receipt_long,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Order #${widget.orderId}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Order Details',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.8),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ],
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF8B9DC3), // Light blue-gray
                const Color(0xFFA8B8D8), // Soft lavender blue
                const Color(0xFFC5B3E6), // Light purple
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
            ),
            child: IconButton(
              onPressed: _copyOrderDetails,
              icon: const Icon(Icons.copy_outlined, size: 20),
              tooltip: 'Copy Order Details',
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
            ),
            child: IconButton(
              onPressed: _shareOnWhatsApp,
              icon: const Icon(Icons.share_outlined, size: 20),
              tooltip: 'Share on WhatsApp',
            ),
          ),
        ],
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
            size: 64,
            color: Colors.red[400],
          ),
          const SizedBox(height: 16),
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
    return Center(
      child: Text(
        'No order details available',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildOrderDetails() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
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
              ],
            ),
          ),
        ),
        // Order Summary - Fixed at the bottom
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.2),
                spreadRadius: 2,
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: _buildOrderSummary(),
        ),
      ],
    );
  }

  Widget _buildStatusCard() {
    final status = order!['order_status'] ?? 'Pending';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.blue[50]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey[200]!, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.receipt_long,
                      color: Colors.blue[700],
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Order Status',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _getStatusColor(status),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: _getStatusColor(status).withOpacity(0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  status.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                // User Name
                _buildCompactInfoRow(
                  Icons.person_outline,
                  'Customer Name',
                  order!['display_name'] ?? 'N/A',
                ),
                const SizedBox(height: 8),
                // User Phone Number
                _buildCompactInfoRow(
                  Icons.phone_outlined,
                  'Phone Number',
                  order!['customer_phone'] ?? order!['shipping_phone'] ?? 'N/A',
                ),
                const SizedBox(height: 8),
                // Order Date and Payment Method on same line
                Row(
                  children: [
                    // Order Date
                    Expanded(
                      child: _buildCompactInfoRow(
                        Icons.calendar_today_outlined,
                        'Order Date',
                        _formatDate(order!['order_date']),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Payment Method
                    Expanded(
                      child: _buildCompactInfoRow(
                        Icons.payment_outlined,
                        'Payment',
                        order!['payment_method'] ?? 'COD',
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

  Widget _buildCompactInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Icon(
            icon,
            size: 18,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOrderItems() {
    // Group items by product name first
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
          // Group items by product
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
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          // Product Image
          GestureDetector(
            onTap: () => _showFullScreenImage(context, item),
            child: Container(
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
                    if (item['size'] != null && item['size'].toString().isNotEmpty)
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
                Row(
                  children: [
                    Text(
                      'Qty: $quantity x ₹${itemPrice.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                    const Spacer(),
                    // Item Total - Show total for this item (quantity x price)
                    Text(
                      '₹${(itemPrice * quantity).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 14,
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

    // 1. Check if item has image_url (from order items - first priority)
    if (item['image_url'] != null && item['image_url'].toString().isNotEmpty) {
      String tempImageUrl = item['image_url'].toString();
      if (tempImageUrl.startsWith('http')) {
        imageUrl = tempImageUrl;
      } else {
        imageUrl = 'http://184.168.126.71/api/uploads/$tempImageUrl';
      }
    }
    // 2. Check if order has image_url (fallback)
    else if (order?['image_url'] != null && order!['image_url'].toString().isNotEmpty) {
      imageUrl = order!['image_url'];
    }

    if (imageUrl != null) {
      return Image.network(
        imageUrl,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholderImage(),
      );
    }

    return _buildPlaceholderImage();
  }

  Widget _buildPlaceholderImage({String? productName}) {
    return Container(
      width: 60,
      height: 60,
      color: Colors.grey[200],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image,
            color: Colors.grey[400],
            size: 24,
          ),
          if (productName != null)
            Padding(
              padding: const EdgeInsets.all(2),
              child: Text(
                productName.length > 8 ? '${productName.substring(0, 8)}...' : productName,
                style: TextStyle(
                  fontSize: 8,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Color _getColorFromString(String colorString) {
    // Map common color names to Material colors
    switch (colorString.toLowerCase().trim()) {
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
      case 'brown':
        return Colors.brown;
      case 'black':
        return Colors.black;
      case 'white':
        return Colors.white;
      case 'grey':
      case 'gray':
        return Colors.grey;
      case 'light grey':
      case 'light gray':
        return Colors.grey[300]!;
      case 'dark grey':
      case 'dark gray':
        return Colors.grey[700]!;
      default:
      // Try to parse as hex color
        try {
          if (colorString.startsWith('#')) {
            return Color(int.parse(colorString.substring(1), radix: 16) + 0xFF000000);
          }
        } catch (e) {
          // If all fails, return a default color
          return Colors.grey[400]!;
        }
        return Colors.grey[400]!;
    }
  }

  Future<void> _fetchCustomerName(int userId) async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/user/$userId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final userData = json.decode(response.body);
        if (userData['success']) {
          final userName = userData['user']['name'] ??
              userData['user']['user_name'] ??
              userData['user']['full_name'] ??
              userData['user']['first_name'] ??
              'Customer';

          setState(() {
            if (order != null) {
              order!['display_name'] = userName;
            }
          });
        }
      }
    } catch (e) {
      print('Error fetching customer name: $e');
      // Set fallback name if API fails
      setState(() {
        if (order != null) {
          order!['display_name'] = 'Customer';
        }
      });
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.location_on_outlined,
                  color: Colors.green[700],
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Shipping Address',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order!['shipping_street'] ?? 'N/A',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${order!['shipping_city'] ?? 'N/A'}, ${order!['shipping_state'] ?? 'N/A'} - ${order!['shipping_pincode'] ?? 'N/A'}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.phone_outlined,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      order!['shipping_phone'] ?? 'N/A',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
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

  Widget _buildOrderSummary() {
    // Parse total_amount as double since it comes as string from database
    final totalAmount = double.tryParse(order!['total_amount'].toString()) ?? 0.0;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.purple[50]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
        border: Border.all(color: Colors.grey[200]!, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.receipt_long_outlined,
                      color: Colors.purple[700],
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Order Summary',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              IntrinsicHeight(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Manual Payment Confirmation Button (show if payment is pending)
                    if (order!['payment_status'] != 'paid')
                      Container(
                        height: 32,
                        child: GestureDetector(
                          onTap: _showManualPaymentConfirmation,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: Colors.orange[100],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.orange[300]!, width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.payment,
                                  color: Colors.orange[700],
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Confirm',
                                  style: TextStyle(
                                    color: Colors.orange[700],
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // Share Order Details Button
                    Container(
                      height: 32,
                      child: GestureDetector(
                        onTap: _shareOrderDetails,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green[300]!, width: 1),
                          ),
                          child: Icon(
                            Icons.arrow_forward_ios,
                            color: Colors.green[700],
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Summary Items
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                _buildCompactSummaryRow('Subtotal', '₹${totalAmount.toStringAsFixed(2)}'),
                const SizedBox(height: 8),
                _buildCompactSummaryRow('Delivery Fee', 'FREE', isFree: true),
                const Divider(height: 16),
                _buildCompactSummaryRow(
                  'Total Amount',
                  '₹${totalAmount.toStringAsFixed(2)}',
                  isTotal: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactSummaryRow(String label, String value, {bool isFree = false, bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
            color: isTotal ? Colors.black87 : Colors.grey[700],
          ),
        ),
        Row(
          children: [
            if (isFree)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'FREE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
              ),
            if (!isFree)
              Text(
                value,
                style: TextStyle(
                  fontSize: isTotal ? 15 : 13,
                  fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
                  color: isTotal ? Colors.purple[700] : Colors.black87,
                ),
              ),
          ],
        ),
      ],
    );
  }

  void _shareOrderDetails() async {
    if (order == null) return;

    // Get customer phone number
    final customerPhone = order!['customer_phone'] ?? order!['shipping_phone'];
    if (customerPhone == null || customerPhone == 'N/A' || customerPhone.toString().trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer phone number not available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Create structured order details message
    String shareMessage = _createStructuredShareMessage();

    try {
      // Copy message to clipboard first
      await Clipboard.setData(ClipboardData(text: shareMessage));

      // Share with QR code image
      _shareWithQRCode(shareMessage, customerPhone);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error preparing share: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _shareWithQRCode(String message, String customerPhone) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const Dialog(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 20),
                  Text('Opening WhatsApp with QR code...'),
                ],
              ),
            ),
          );
        },
      );

      // Format phone number
      String formattedPhone = customerPhone.replaceAll(RegExp(r'[^\d]'), '');
      if (formattedPhone.length == 10) {
        formattedPhone = '91$formattedPhone';
      } else if (formattedPhone.length == 11 && formattedPhone.startsWith('0')) {
        formattedPhone = '91${formattedPhone.substring(1)}';
      } else if (formattedPhone.length == 12 && formattedPhone.startsWith('91')) {
        formattedPhone = formattedPhone;
      }

      // QR code server URL (Dynamic Payment Page)
      String qrCodeUrl = 'https://node-api.bangkokmart.in/api/whatsapp/payment-qr/${widget.orderId}';

      print('🔍 DEBUG: Using Payment Page URL: $qrCodeUrl');

      // Close loading dialog
      Navigator.of(context).pop();

      // Open WhatsApp directly with customer number and message (no duplicate link)
      String whatsappUrl = 'https://wa.me/$formattedPhone?text=${Uri.encodeComponent(message)}';
      await launchUrl(Uri.parse(whatsappUrl), mode: LaunchMode.externalApplication);

      // Show success message with multiple options
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ WhatsApp opened! QR code ready to view'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 6),
          action: SnackBarAction(
            label: 'View QR',
            textColor: Colors.white,
            onPressed: () => _showQRCodeDialog(qrCodeUrl),
          ),
        ),
      );

    } catch (e) {
      // Close loading dialog if open
      Navigator.of(context).pop();

      print('Error sharing with QR code: $e');
      // Fallback to text-only sharing
      _shareViaWhatsApp(message, customerPhone);
    }
  }

  void _showQRCodeDialog(String qrUrl) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Container(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Payment QR Code',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 15),
                Image.network(
                  qrUrl,
                  height: 200,
                  width: 200,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 200,
                      width: 200,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.qr_code, size: 100, color: Colors.grey),
                    );
                  },
                ),
                SizedBox(height: 15),
                Text(
                  'Scan this QR code for payment',
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 10),
                Text(
                  'QR Code URL: $qrUrl',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: qrUrl));
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('QR URL copied!')),
                        );
                      },
                      child: Text('Copy URL'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showQRInstructions() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.info, color: Colors.blue[700]),
              SizedBox(width: 8),
              Text('How to Add QR Code'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'QR code is copied to your clipboard. Follow these steps:',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStep('1️⃣', 'Go to WhatsApp chat'),
                    _buildStep('2️⃣', 'Tap and hold in message area'),
                    _buildStep('3️⃣', 'Select "Paste"'),
                    _buildStep('4️⃣', 'QR code image will appear'),
                    _buildStep('5️⃣', 'Send the message'),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Got it!'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStep(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: TextStyle(fontSize: 16)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  String _createStructuredShareMessage() {
    if (order == null) return '';

    String message = '''
🛒 *ORDER DETAILS* 🛒
📋 *Order Information:*
• Order ID: #${widget.orderId}
• Date: ${_formatDateWithAmPm(order!['order_date'])}
━━━━━━━━━━━━━━━━━━━━━

📦 *Product Details:*
''';

    // Track unique products to avoid duplicates
    final Set<String> addedProducts = {};

    // Add each product with image, name, and price (only unique products)
    for (var item in orderItems) {
      final productName = item['product_name'] ?? 'Product';
      final color = item['color']?.toString() ?? '';
      final size = item['size']?.toString() ?? '';

      // Create unique key for product (name + color + size)
      final productKey = '${productName.trim()}_${color.trim()}_${size.trim()}';

      // Skip if already added
      if (addedProducts.contains(productKey)) {
        continue;
      }
      addedProducts.add(productKey);

      final itemPrice = double.tryParse(item['price'].toString()) ?? 0.0;
      final quantity = int.tryParse(item['quantity'].toString()) ?? 1;

      // Get image URL
      String? imageUrl;
      if (item['image_url'] != null && item['image_url'].toString().isNotEmpty) {
        String tempImageUrl = item['image_url'].toString();
        if (tempImageUrl.startsWith('http')) {
          imageUrl = tempImageUrl;
        } else {
          imageUrl = 'http://184.168.126.71/api/uploads/$tempImageUrl';
        }
      }

      // Build variant details - only include size if it's meaningful
      String variantDetails = '';
      if (color.isNotEmpty) {
        variantDetails += '   • Color: $color\n';
      }
      if (size.isNotEmpty && size.toLowerCase() != 'no size') {
        variantDetails += '   • Size: $size\n';
      }

      message += '''
🔸 *$productName*
$variantDetails   • Quantity: $quantity
   • Price: ₹${itemPrice.toStringAsFixed(2)}
   • Image: ${imageUrl ?? 'N/A'}
''';
    }

    message += '''━━━━━━━━━━━━━━━━━━━━━

💰 *Payment Summary:*
• Subtotal: ₹${order!['total_amount'] ?? '0'}
• Delivery: FREE
• *Total Amount: ₹${order!['total_amount'] ?? '0'}*
━━━━━━━━━━━━━━━━━━━━━

🏠 Delivery Address:
${order!['shipping_street'] ?? 'N/A'}
${order!['shipping_city'] ?? 'N/A'}, ${order!['shipping_state'] ?? 'N/A'} - ${order!['shipping_pincode'] ?? 'N/A'}
📞 ${order!['shipping_phone'] ?? 'N/A'}

Thank you for your order! 🙏
━━━━━━━━━━━━━━━━━━━━━
💳 PAYMENT INFORMATION:

📱 Scan the QR code below to pay
🔗 https://node-api.bangkokmart.in/api/whatsapp/payment-qr/${widget.orderId}

📲 *Click link above → See Timer & Scan QR*
⚡ *Fast & Secure Payment*
''';

    return message;
  }

  void _shareViaWhatsApp(String message, String customerPhone) async {
    try {
      // Format phone number
      String formattedPhone = customerPhone.replaceAll(RegExp(r'[^\d]'), '');
      if (formattedPhone.length == 10) {
        formattedPhone = '91$formattedPhone';
      } else if (formattedPhone.length == 11 && formattedPhone.startsWith('0')) {
        formattedPhone = '91${formattedPhone.substring(1)}';
      } else if (formattedPhone.length == 12 && formattedPhone.startsWith('91')) {
        formattedPhone = formattedPhone;
      }

      String encodedText = Uri.encodeComponent(message);
      String whatsappUrl = "https://wa.me/$formattedPhone?text=$encodedText";

      await launchUrl(Uri.parse(whatsappUrl), mode: LaunchMode.externalApplication);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open WhatsApp'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _sendWhatsAppToCustomer() async {
    if (order == null) return;

    // Get customer phone number
    final customerPhone = order!['customer_phone'] ?? order!['shipping_phone'];
    if (customerPhone == null || customerPhone == 'N/A' || customerPhone.toString().trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer phone number not available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    print('📞 Customer phone from order: $customerPhone');

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Dialog(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text('Opening WhatsApp...'),
              ],
            ),
          ),
        );
      },
    );

    try {
      // Format phone number
      String formattedPhone = customerPhone.replaceAll(RegExp(r'[^\d]'), '');
      if (formattedPhone.length == 10) {
        formattedPhone = '91$formattedPhone';
      } else if (formattedPhone.length == 11 && formattedPhone.startsWith('0')) {
        formattedPhone = '91${formattedPhone.substring(1)}';
      } else if (formattedPhone.length == 12 && formattedPhone.startsWith('91')) {
        formattedPhone = formattedPhone;
      }

      // Create message
      String message = WhatsAppPaymentService.createOrderMessage(
          widget.orderId,
          orderItems,
          order!
      );

      String encodedText = Uri.encodeComponent(message);

      bool whatsappOpened = false;
      String lastError = '';

      // Try different approaches - Enhanced WhatsApp detection
      List<Map<String, dynamic>> attempts = [
        // Try market URLs first (most reliable)
        {
          'url': "market://details?id=com.whatsapp.w4b",
          'mode': LaunchMode.externalApplication,
          'name': 'WhatsApp Business (Market)',
          'isInstall': true
        },
        {
          'url': "market://details?id=com.whatsapp",
          'mode': LaunchMode.externalApplication,
          'name': 'WhatsApp (Market)',
          'isInstall': true
        },
        // Try standard schemes with different approaches
        {
          'url': "whatsapp-business://send?phone=$formattedPhone&text=$encodedText",
          'mode': LaunchMode.externalApplication,
          'name': 'WhatsApp Business'
        },
        {
          'url': "whatsapp://send?phone=$formattedPhone&text=$encodedText",
          'mode': LaunchMode.externalApplication,
          'name': 'WhatsApp Mobile'
        },
        // Try without text
        {
          'url': "whatsapp-business://send?phone=$formattedPhone",
          'mode': LaunchMode.externalApplication,
          'name': 'WhatsApp Business (no text)'
        },
        {
          'url': "whatsapp://send?phone=$formattedPhone",
          'mode': LaunchMode.externalApplication,
          'name': 'WhatsApp Mobile (no text)'
        },
        // Web fallbacks
        {
          'url': "https://wa.me/$formattedPhone?text=$encodedText",
          'mode': LaunchMode.externalApplication,
          'name': 'Web WhatsApp'
        },
        {
          'url': "https://wa.me/$formattedPhone",
          'mode': LaunchMode.externalApplication,
          'name': 'Web WhatsApp (no text)'
        },
      ];

      // Debug: Check what URLs can be launched
      print('🔍 DEBUG: Checking available URL schemes...');
      List<String> testUrls = [
        "whatsapp-business://",
        "whatsapp://",
        "https://wa.me/",
        "market://details?id=com.whatsapp.w4b",
        "market://details?id=com.whatsapp",
      ];

      for (String testUrl in testUrls) {
        bool canLaunch = await canLaunchUrl(Uri.parse(testUrl));
        print('🔍 $testUrl -> $canLaunch');
      }

      // Try the most direct approach - simple WhatsApp Business URL
      print('🔍 Trying direct WhatsApp Business approach...');

      // Try WhatsApp Business with the simplest URL first
      String simpleBusinessUrl = "whatsapp-business://send?phone=$formattedPhone";
      if (await canLaunchUrl(Uri.parse(simpleBusinessUrl))) {
        print('✅ Simple WhatsApp Business URL works!');
        await launchUrl(Uri.parse(simpleBusinessUrl), mode: LaunchMode.externalApplication);
        whatsappOpened = true;
        _handleWhatsAppSuccess(customerPhone, message);
        return;
      }

      // Try with text
      String businessUrlWithText = "whatsapp-business://send?phone=$formattedPhone&text=$encodedText";
      if (await canLaunchUrl(Uri.parse(businessUrlWithText))) {
        print('✅ WhatsApp Business URL with text works!');
        await launchUrl(Uri.parse(businessUrlWithText), mode: LaunchMode.externalApplication);
        whatsappOpened = true;
        _handleWhatsAppSuccess(customerPhone, message);
        return;
      }

      // Try regular WhatsApp
      String simpleWhatsappUrl = "whatsapp://send?phone=$formattedPhone";
      if (await canLaunchUrl(Uri.parse(simpleWhatsappUrl))) {
        print('✅ Simple WhatsApp URL works!');
        await launchUrl(Uri.parse(simpleWhatsappUrl), mode: LaunchMode.externalApplication);
        whatsappOpened = true;
        _handleWhatsAppSuccess(customerPhone, message);
        return;
      }

      // Try with text
      String whatsappUrlWithText = "whatsapp://send?phone=$formattedPhone&text=$encodedText";
      if (await canLaunchUrl(Uri.parse(whatsappUrlWithText))) {
        print('✅ WhatsApp URL with text works!');
        await launchUrl(Uri.parse(whatsappUrlWithText), mode: LaunchMode.externalApplication);
        whatsappOpened = true;
        _handleWhatsAppSuccess(customerPhone, message);
        return;
      }

      // Try direct Android intent approach for WhatsApp Business
      if (Platform.isAndroid) {
        print('🔍 Trying Android Intent approach...');
        // Try WhatsApp Business first with different intent formats
        List<String> businessIntents = [
          "intent://send?phone=$formattedPhone&text=$encodedText#Intent;scheme=whatsapp;package=com.whatsapp.w4b;end",
          "intent://send?phone=$formattedPhone#Intent;scheme=whatsapp;package=com.whatsapp.w4b;end",
          "whatsapp-business://send?phone=$formattedPhone&text=$encodedText",
          "whatsapp-business://send?phone=$formattedPhone",
        ];

        for (String intent in businessIntents) {
          if (await canLaunchUrl(Uri.parse(intent))) {
            print('🚀 Launching WhatsApp Business via: $intent');
            await launchUrl(Uri.parse(intent), mode: LaunchMode.externalApplication);
            whatsappOpened = true;
            _handleWhatsAppSuccess(customerPhone, message);
            return;
          }
        }

        // Try regular WhatsApp with different intent formats
        List<String> whatsappIntents = [
          "intent://send?phone=$formattedPhone&text=$encodedText#Intent;scheme=whatsapp;package=com.whatsapp;end",
          "intent://send?phone=$formattedPhone#Intent;scheme=whatsapp;package=com.whatsapp;end",
          "whatsapp://send?phone=$formattedPhone&text=$encodedText",
          "whatsapp://send?phone=$formattedPhone",
        ];

        for (String intent in whatsappIntents) {
          if (await canLaunchUrl(Uri.parse(intent))) {
            print('🚀 Launching WhatsApp via: $intent');
            await launchUrl(Uri.parse(intent), mode: LaunchMode.externalApplication);
            whatsappOpened = true;
            _handleWhatsAppSuccess(customerPhone, message);
            return;
          }
        }
      }

      // First, try to directly check if WhatsApp is installed using package manager
      bool whatsappBusinessInstalled = await _canLaunchPackage('com.whatsapp.w4b');
      bool whatsappInstalled = await _canLaunchPackage('com.whatsapp');

      print('📱 WhatsApp Business installed: $whatsappBusinessInstalled');
      print('📱 WhatsApp installed: $whatsappInstalled');

      // Try direct package launch if installed
      if (whatsappBusinessInstalled) {
        String businessUrl = "whatsapp-business://send?phone=$formattedPhone&text=$encodedText";
        if (await canLaunchUrl(Uri.parse(businessUrl))) {
          await launchUrl(Uri.parse(businessUrl), mode: LaunchMode.externalApplication);
          whatsappOpened = true;
          _handleWhatsAppSuccess(customerPhone, message);
          return;
        }
      }

      if (whatsappInstalled) {
        String whatsappUrl = "whatsapp://send?phone=$formattedPhone&text=$encodedText";
        if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
          await launchUrl(Uri.parse(whatsappUrl), mode: LaunchMode.externalApplication);
          whatsappOpened = true;
          _handleWhatsAppSuccess(customerPhone, message);
          return;
        }
      }

      for (var attempt in attempts) {
        try {
          print('📱 Trying ${attempt['name']}: ${attempt['url']}');
          final uri = Uri.parse(attempt['url']);

          // Skip install URLs for now, only try direct WhatsApp URLs
          if (attempt['isInstall'] == true) {
            print('⏭️ Skipping install URL: ${attempt['name']}');
            continue;
          }

          // Try to launch with different modes
          List<LaunchMode> modes = [
            LaunchMode.platformDefault,
            LaunchMode.externalApplication,
            LaunchMode.externalNonBrowserApplication,
          ];

          for (var mode in modes) {
            try {
              print('🔍 Testing ${attempt['name']} with mode $mode');
              if (await canLaunchUrl(uri)) {
                print('✅ Can launch with mode $mode: ${attempt['url']}');
                await launchUrl(uri, mode: mode);
                whatsappOpened = true;

                // Log the message for tracking
                await WhatsAppPaymentService.logWhatsAppMessage(
                    widget.orderId,
                    customerPhone,
                    message
                );

                // Start payment status monitoring
                _startPaymentStatusMonitoring();

                Navigator.of(context).pop(); // Close loading dialog

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('WhatsApp opened via ${attempt['name']}!'),
                    backgroundColor: Colors.green,
                  ),
                );
                return;
              } else {
                print('❌ Cannot launch with mode $mode: ${attempt['url']}');
              }
            } catch (e) {
              print('❌ Error with mode $mode: $e');
            }
          }

          print('❌ Cannot launch ${attempt['name']}: ${attempt['url']}');
        } catch (e) {
          print('❌ Error launching ${attempt['name']}: $e');
          lastError = e.toString();
        }
      }

      Navigator.of(context).pop(); // Close loading dialog

      // Copy message to clipboard automatically
      await Clipboard.setData(ClipboardData(text: message));

      // Show enhanced dialog with debug info
      String debugInfo = "WhatsApp Business: " + (await canLaunchUrl(Uri.parse("whatsapp-business://"))).toString() +
          "\nWhatsApp: " + (await canLaunchUrl(Uri.parse("whatsapp://"))).toString() +
          "\nWeb WhatsApp: " + (await canLaunchUrl(Uri.parse("https://wa.me/"))).toString();

      _showWhatsAppNotFoundDialog(customerPhone, message, lastError, formattedPhone, debugInfo);
    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog
      print('❌ WhatsApp exception: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showWhatsAppNotFoundDialog(String customerPhone, String message, String lastError, String formattedPhone, String debugInfo) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange[700]),
              const SizedBox(width: 8),
              const Text('WhatsApp Not Available'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WhatsApp could not be opened automatically on this device.',
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Customer Phone: $formattedPhone',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '✅ Order message copied to clipboard!',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '❌ Error: $lastError',
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🔍 Device Detection:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            debugInfo,
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.blueGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Choose an option:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                launchUrl(Uri.parse("https://web.whatsapp.com"));
              },
              child: const Text('Open WhatsApp Web'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                launchUrl(Uri.parse("https://play.google.com/store/apps/details?id=com.whatsapp"));
              },
              child: const Text('Install WhatsApp'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                launchUrl(Uri.parse("https://play.google.com/store/apps/details?id=com.whatsapp.w4b"));
              },
              child: const Text('Install WhatsApp Business'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Copy phone number separately
                Clipboard.setData(ClipboardData(text: customerPhone));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Phone number copied! You can manually message this number.'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[700],
                foregroundColor: Colors.white,
              ),
              child: const Text('Copy Phone Number'),
            ),
          ],
        );
      },
    );
  }

  // Helper method to check if a package can be launched
  Future<bool> _canLaunchPackage(String packageName) async {
    try {
      // Try multiple approaches to check package availability
      List<String> checkUrls = [
        "market://details?id=$packageName",
        "https://play.google.com/store/apps/details?id=$packageName",
      ];

      for (String url in checkUrls) {
        if (await canLaunchUrl(Uri.parse(url))) {
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Helper method to directly launch package by name
  Future<bool> _launchPackageDirectly(String packageName, String phone, String text) async {
    try {
      // Try different launch methods for the package
      List<String> launchUrls = [
        "intent://send?phone=$phone&text=$text#Intent;scheme=whatsapp;package=$packageName;end",
        "intent://send?phone=$phone#Intent;scheme=whatsapp;package=$packageName;end",
      ];

      for (String url in launchUrls) {
        if (await canLaunchUrl(Uri.parse(url))) {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          return true;
        }
      }
      return false;
    } catch (e) {
      print('❌ Error launching package $packageName: $e');
      return false;
    }
  }

  // Helper method to handle successful WhatsApp launch
  Future<void> _handleWhatsAppSuccess(String customerPhone, String message) async {
    // Log the message for tracking
    await WhatsAppPaymentService.logWhatsAppMessage(
        widget.orderId,
        customerPhone,
        message
    );

    // Start payment status monitoring
    _startPaymentStatusMonitoring();

    Navigator.of(context).pop(); // Close loading dialog

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('WhatsApp opened successfully!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _startPaymentStatusMonitoring() {
    // Start a timer to check for payment status updates
    Timer(const Duration(minutes: 5), () {
      // Check if payment was made within 5 minutes
      _checkPaymentStatus();
    });
  }

  Future<void> _checkPaymentStatus() async {
    try {
      final result = await WhatsAppPaymentService.checkPaymentStatus(widget.orderId);

      if (result['success']) {
        if (result['payment_status'] == 'paid') {
          // Refresh order details to show updated status
          _fetchOrderDetails();

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment received! Order status updated.'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (result['is_within_5_minutes'] == false) {
          // Payment window expired
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment window expired. Please confirm payment manually.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      print('Error checking payment status: $e');
    }
  }

  void _showManualPaymentConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Payment'),
          content: const Text('Payment done by customer?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop(); // Close confirmation dialog (Yes/No)

                // 1. OPTIMISTIC UPDATE: Change status immediately in UI
                final originalOrder = Map<String, dynamic>.from(order!);
                setState(() {
                  order!['order_status'] = 'Processing';
                  order!['payment_status'] = 'Paid';
                });

                try {
                  final result = await WhatsAppPaymentService.confirmPaymentManually(
                    orderId: widget.orderId,
                  );

                  if (result['success']) {
                    // 2. DELAYED SILENT REFRESH: Wait for DB to settle
                    Future.delayed(const Duration(seconds: 2), () async {
                      if (mounted) {
                        await _fetchOrderDetails(silent: true);
                      }
                    });

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.white),
                              SizedBox(width: 8),
                              Text('Payment Confirmed Successfully!'),
                            ],
                          ),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  } else {
                    // ROLLBACK if failed
                    setState(() {
                      order = originalOrder;
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(result['message'] ?? 'Failed to confirm payment'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  // ROLLBACK on error
                  setState(() {
                    order = originalOrder;
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[700],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Yes, Confirm'),
            ),
          ],
        );
      },
    );
  }

  void _copyOrderDetails() {
    if (order == null) return;

    String orderDetails = '''
🛒 *Order Details* 🛒

📋 *Order ID:* #${widget.orderId}
📅 *Order Date:* ${_formatDate(order!['order_date'])}
💳 *Payment Method:* ${order!['payment_method'] ?? 'COD'}
🚚 *Order Status:* ${order!['order_status'] ?? 'Pending'}

📦 *Order Items:*
''';

    // Add order items
    for (var item in orderItems) {
      final itemTotal = (double.tryParse(item['quantity'].toString()) ?? 0.0) *
          (double.tryParse(item['price'].toString()) ?? 0.0);
      orderDetails += '''
• ${item['product_name'] ?? 'Product'}
  Qty: ${item['quantity']} × ₹${item['price']} = ₹${itemTotal.toStringAsFixed(2)}
''';
    }

    orderDetails += '''
🏠 *Shipping Address:*
${order!['shipping_street'] ?? 'N/A'}
${order!['shipping_city'] ?? 'N/A'}, ${order!['shipping_state'] ?? 'N/A'} - ${order!['shipping_pincode'] ?? 'N/A'}
📞 ${order!['shipping_phone'] ?? 'N/A'}

💰 *Order Summary:*
Subtotal: ₹${order!['total_amount'] ?? '0'}
Delivery Fee: FREE
*Total Amount: ₹${order!['total_amount'] ?? '0'}*

Thank you for your order! 🙏
''';

    Clipboard.setData(ClipboardData(text: orderDetails));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Order details copied to clipboard!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _shareOnWhatsApp() async {
    if (order == null) return;

    String orderDetails = '''
🛒 *Order Details* 🛒

📋 *Order ID:* #${widget.orderId}
📅 *Order Date:* ${_formatDate(order!['order_date'])}
💳 *Payment Method:* ${order!['payment_method'] ?? 'COD'}
🚚 *Order Status:* ${order!['order_status'] ?? 'Pending'}

📦 *Order Items:*
''';

    // Add order items
    for (var item in orderItems) {
      final itemTotal = (double.tryParse(item['quantity'].toString()) ?? 0.0) *
          (double.tryParse(item['price'].toString()) ?? 0.0);
      orderDetails += '''
• ${item['product_name'] ?? 'Product'}
  Qty: ${item['quantity']} × ₹${item['price']} = ₹${itemTotal.toStringAsFixed(2)}
''';
    }

    orderDetails += '''
🏠 *Shipping Address:*
${order!['shipping_street'] ?? 'N/A'}
${order!['shipping_city'] ?? 'N/A'}, ${order!['shipping_state'] ?? 'N/A'} - ${order!['shipping_pincode'] ?? 'N/A'}
📞 ${order!['shipping_phone'] ?? 'N/A'}

💰 *Order Summary:*
Subtotal: ₹${order!['total_amount'] ?? '0'}
Delivery Fee: FREE
*Total Amount: ₹${order!['total_amount'] ?? '0'}*

Thank you for your order! 🙏
''';

    // Encode for URL
    String encodedText = Uri.encodeComponent(orderDetails);
    String whatsappUrl = "https://wa.me/?text=$encodedText";

    try {
      await launchUrl(Uri.parse(whatsappUrl));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open WhatsApp'),
          backgroundColor: Colors.red,
        ),
      );
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

  String _formatDateWithAmPm(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final hour = date.hour;
      final minute = date.minute.toString().padLeft(2, '0');
      final amPm = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : hour == 0 ? 12 : hour;
      return '${date.day}/${date.month}/${date.year} at ${displayHour}:${minute} $amPm';
    } catch (e) {
      return dateString;
    }
  }

  void _showFullScreenImage(BuildContext context, dynamic item) {
    String? imageUrl;

    // Try to get the image URL from the same sources as _buildProductImage
    if (order?['image_url'] != null && order!['image_url'].toString().isNotEmpty) {
      imageUrl = order!['image_url'];
    } else if (item['image_url'] != null && item['image_url'].toString().isNotEmpty) {
      String tempImageUrl = item['image_url'].toString();
      if (tempImageUrl.startsWith('http')) {
        imageUrl = tempImageUrl;
      } else {
        imageUrl = 'http://184.168.126.71/api/uploads/$tempImageUrl';
      }
    }

    if (imageUrl != null) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.zero,
            child: Stack(
              children: [
                // Full screen image
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height,
                    child: InteractiveViewer(
                      panEnabled: true,
                      boundaryMargin: const EdgeInsets.all(20),
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Image.network(
                        imageUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: MediaQuery.of(context).size.width,
                            height: MediaQuery.of(context).size.height,
                            color: Colors.black,
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    size: 64,
                                    color: Colors.white,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'Image not available',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                // Close button
                Positioned(
                  top: 50,
                  right: 20,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return Colors.blue;
      case 'processing':
        return Colors.purple;
      case 'shipped':
        return Colors.indigo;
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'refunded':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }
}
