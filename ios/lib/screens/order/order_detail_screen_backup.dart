import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../config.dart';
import '../../services/local_auth_service.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

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
          print('Server response data: ${responseData.keys.toList()}');
          print('Order data: ${responseData['order']}');
          if (responseData['order'] != null) {
            print('Order keys: ${responseData['order'].keys.toList()}');
          }
          if (responseData['user'] != null) {
            print('User data: ${responseData['user']}');
          }
          
          setState(() {
            order = responseData['order'];
            orderItems = responseData['items'] ?? [];
            
            // Get current user name from LocalAuthService (same as all orders page)
            final currentUser = LocalAuthService.getCurrentUser();
            final userName = currentUser?['name'] ?? 
                           currentUser?['user_name'] ?? 
                           currentUser?['full_name'] ?? 
                           currentUser?['first_name'] ?? 
                           'User';
            
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
      print('Stack trace: ${StackTrace.current}');
      setState(() {
        errorMessage = 'Error: ${e.toString()}';
        isLoading = false;
      });
    }
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
                  top: 40,
                  right: 20,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
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
    } else {
      // Show placeholder if no image available
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.zero,
            child: Stack(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height,
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.image,
                            size: 100,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            item['product_name'] ?? 'Product',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No image available',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 40,
                  right: 20,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
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
        actions: [
          // Copy Button
          IconButton(
            onPressed: _copyOrderDetails,
            icon: const Icon(
              Icons.copy,
              color: Colors.green,
            ),
            tooltip: 'Copy Order Details',
          ),
          // WhatsApp Share Button
          IconButton(
            onPressed: _shareOnWhatsApp,
            icon: const Icon(
              Icons.share,
              color: Colors.green,
            ),
            tooltip: 'Share on WhatsApp',
          ),
          const SizedBox(width: 8),
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

  Future<void> _fetchUserDetails(int userId) async {
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
                         userData['user']['first_name'] ?? 'N/A';
          
          setState(() {
            if (order != null) {
              order!['display_name'] = userName;
            }
          });
        }
      }
    } catch (e) {
      print('Error fetching user details: $e');
    }
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
          // Group items by product name
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

                // Price and Quantity - Show individual price and quantity as 1
                Row(
                  children: [
                    Text(
                      'Qty: 1 x ₹${itemPrice.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                    const Spacer(),
                    // Item Total - Show individual item price
                    Text(
                      '₹${itemPrice.toStringAsFixed(2)}',
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

  // Helper method to build product image
  Widget _buildProductImage(dynamic item) {
    // Try multiple image sources in order of preference

    // 1. Check if order has image_url (from order details)
    if (order?['image_url'] != null && order!['image_url'].toString().isNotEmpty) {
      return Image.network(
        order!['image_url'],
        width: 80,
        height: 80,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholderImage(),
      );
    }

    // 2. Check if item has image_url
    if (item['image_url'] != null && item['image_url'].toString().isNotEmpty) {
      String imageUrl = item['image_url'].toString();

      // If it's a full URL, use it directly
      if (imageUrl.startsWith('http')) {
        return Image.network(
          imageUrl,
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholderImage(),
        );
      }

      // If it's a relative path, construct full URL
      return Image.network(
        'http://184.168.126.71/api/uploads/$imageUrl',
        width: 80,
        height: 80,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholderImage(),
      );
    }

    // 3. Use placeholder image with product name
    return _buildPlaceholderImage(productName: item['product_name'] ?? 'Product');
  }

  Widget _buildPlaceholderImage({String? productName}) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.grey[300]!, Colors.grey[400]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image,
            size: 24,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 4),
          if (productName != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                productName.length > 10 ? '${productName.substring(0, 10)}...' : productName,
                style: TextStyle(
                  fontSize: 8,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.green[50]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey[200]!, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.location_on_outlined,
                  color: Colors.green[700],
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Shipping Address',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.home_outlined, color: Colors.grey[600], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        order!['shipping_street'] ?? 'N/A',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.location_city_outlined, color: Colors.grey[600], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${order!['shipping_city'] ?? 'N/A'}, ${order!['shipping_state'] ?? 'N/A'} - ${order!['shipping_pincode'] ?? 'N/A'}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.phone_outlined, color: Colors.grey[600], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        order!['shipping_phone'] ?? 'N/A',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
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
            fontSize: isTotal ? 15 : 13,
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
            color: isTotal ? Colors.black87 : Colors.grey.shade700,
          ),
        ),
        if (isTotal)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple[400]!, Colors.purple[600]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.purple.withOpacity(0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.currency_rupee,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 2),
                Text(
                  value.contains('₹') ? value.substring(1) : value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isFree
                  ? Colors.green.shade50
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: isFree
                  ? Border.all(color: Colors.green.shade200)
                  : Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isFree
                    ? Colors.green.shade700
                    : Colors.black87,
              ),
            ),
          ),
      ],
    );
  }
}
