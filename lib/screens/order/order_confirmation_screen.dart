import 'package:flutter/material.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../config.dart';
import '../../services/whatsapp_payment_service.dart';
import '../../services/local_auth_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'order_success_screen.dart';
import 'my_orders_screen.dart';
import 'order_status_tracking_screen.dart';

class OrderConfirmationScreen extends StatefulWidget {
  final Map<String, dynamic> orderData;
  final List<dynamic> orderItems;
  final double totalAmount;

  const OrderConfirmationScreen({
    super.key,
    required this.orderData,
    required this.orderItems,
    required this.totalAmount,
  });

  @override
  State<OrderConfirmationScreen> createState() => _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState extends State<OrderConfirmationScreen> {
  bool _isProcessing = false;
  bool _paymentCompleted = false;
  String? _errorMessage;
  Timer? _paymentStatusTimer;

  @override
  void initState() {
    super.initState();
    _createOrderInDatabase();
  }

  @override
  void dispose() {
    _paymentStatusTimer?.cancel();
    super.dispose();
  }

  Future<void> _createOrderInDatabase() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      final orderPayload = {
        'user_id': userId,
        'total_amount': widget.totalAmount,
        'order_status': 'Pending',
        'payment_status': 'Pending',
        'payment_method': 'Online',
        'shipping_street': widget.orderData['shipping_street'],
        'shipping_city': widget.orderData['shipping_city'],
        'shipping_state': widget.orderData['shipping_state'],
        'shipping_pincode': widget.orderData['shipping_pincode'],
        'customer_phone': widget.orderData['customer_phone'],
        'customer_name': widget.orderData['customer_name'],
        'order_items': widget.orderItems,
        'delivery_fee': widget.orderData['delivery_fee'] ?? 250.0,
      };

      final response = await http.post(
        Uri.parse('${Config.baseNodeApiUrl}/orders'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(orderPayload),
      );

      if (response.statusCode == 201) {
        final responseData = json.decode(response.body);
        if (responseData['success']) {
          // Store order ID for payment processing
          widget.orderData['id'] = responseData['order']['id'];
          
          setState(() {
            _isProcessing = false;
          });
        } else {
          throw Exception(responseData['message'] ?? 'Failed to create order');
        }
      } else {
        throw Exception('Failed to create order: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _initiatePayment() async {
    if (widget.orderData['id'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order not created yet'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final orderId = widget.orderData['id'];
      final customerPhone = widget.orderData['customer_phone'];

      // Send WhatsApp message with payment link
      await WhatsAppPaymentService.sendWhatsAppMessage(
        orderId: orderId,
        customerPhone: customerPhone,
        orderItems: widget.orderItems,
        orderData: widget.orderData,
        onMessageSent: (whatsappUrl) async {
          // Open WhatsApp
          if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
            await launchUrl(Uri.parse(whatsappUrl));
          }
          
          // Start checking payment status
          _startPaymentStatusCheck();
        },
        onError: (error) {
          setState(() {
            _isProcessing = false;
            _errorMessage = error;
          });
        },
      );
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _startPaymentStatusCheck() {
    _paymentStatusTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (widget.orderData['id'] == null) {
        timer.cancel();
        return;
      }

      try {
        final statusResult = await WhatsAppPaymentService.checkPaymentStatus(widget.orderData['id']);
        
        if (statusResult['success']) {
          if (statusResult['payment_status'] == 'Paid' || statusResult['order_status'] == 'Paid') {
            timer.cancel();
            setState(() {
              _paymentCompleted = true;
              _isProcessing = false;
            });
            
            // Navigate to success screen
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) => OrderSuccessScreen(
                  orderId: widget.orderData['id'].toString(),
                  totalAmount: widget.totalAmount,
                ),
              ),
              (route) => false,
            );
          }
        }
      } catch (e) {
        print('Error checking payment status: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Order Confirmation',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 2,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isProcessing
          ? _buildProcessingView()
          : _errorMessage != null
              ? _buildErrorView()
              : _paymentCompleted
                  ? _buildPaymentCompletedView()
                  : _buildConfirmationView(),
    );
  }

  Widget _buildProcessingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            'Payment Processing...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your payment is being confirmed',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Order will be ready for shipment soon',
            style: TextStyle(
              fontSize: 14,
              color: Colors.green[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
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
              'Something went wrong',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _errorMessage ?? 'Unknown error occurred',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[300],
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Go Back'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _createOrderInDatabase,
                    child: const Text('Retry'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentCompletedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            color: Colors.green,
            size: 80,
          ),
          const SizedBox(height: 20),
          const Text(
            'Order Confirmed!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Your order has been placed successfully.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green[100],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Status: Ready for Shipment',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.green[700],
              ),
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => OrderStatusTrackingScreen(
                    orderId: widget.orderData['id'] ?? 0,
                  ),
                ),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Track Order',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmationView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order Status Card
          _buildOrderStatusCard(),
          
          const SizedBox(height: 20),
          
          // Order Items
          _buildOrderItemsCard(),
          
          const SizedBox(height: 20),
          
          // Shipping Address
          _buildShippingAddressCard(),
          
          const SizedBox(height: 20),
          
          // Price Breakdown
          _buildPriceBreakdownCard(),
          
          const SizedBox(height: 30),
          
          // Action Buttons
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildOrderStatusCard() {
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isProcessing ? Colors.blue[100] : Colors.orange[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _isProcessing ? Icons.payment : Icons.pending_actions,
                  color: _isProcessing ? Colors.blue[700] : Colors.orange[700],
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Order Status',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _isProcessing ? Colors.blue[100] : Colors.orange[100],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _isProcessing ? 'Processing Payment' : 'Waiting for Payment',
                  style: TextStyle(
                    color: _isProcessing ? Colors.blue[700] : Colors.orange[700],
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _isProcessing 
                ? 'Your payment is being processed and will be confirmed shortly'
                : 'Complete your payment to confirm order',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItemsCard() {
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
            'Order Items',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...widget.orderItems.map((item) => _buildOrderItem(item)).toList(),
        ],
      ),
    );
  }

  Widget _buildOrderItem(dynamic item) {
    final itemPrice = double.tryParse(item['price'].toString()) ?? 0.0;
    final quantity = int.tryParse(item['quantity'].toString()) ?? 1;
    final totalPrice = itemPrice * quantity;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Product Image Placeholder
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.image, color: Colors.grey),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['product_name'] ?? 'Product',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (item['color'] != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item['color'],
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.blue[700],
                          ),
                        ),
                      ),
                    if (item['size'] != null)
                      Container(
                        margin: const EdgeInsets.only(left: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item['size'],
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.green[700],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹$itemPrice x $quantity',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                '₹${totalPrice.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShippingAddressCard() {
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
            'Shipping Address',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.person, size: 20, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Text(
                widget.orderData['customer_name'] ?? 'N/A',
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.phone, size: 20, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Text(
                widget.orderData['customer_phone'] ?? 'N/A',
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.location_on, size: 20, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${widget.orderData['shipping_street']}, ${widget.orderData['shipping_city']}, ${widget.orderData['shipping_state']} - ${widget.orderData['shipping_pincode']}',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceBreakdownCard() {
    final subtotal = widget.totalAmount - (widget.orderData['delivery_fee'] ?? 250.0);
    final deliveryFee = widget.orderData['delivery_fee'] ?? 250.0;

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
            'Price Breakdown',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildPriceRow('Subtotal', '₹${subtotal.toStringAsFixed(2)}'),
          const SizedBox(height: 8),
          _buildPriceRow('Delivery Fee', '₹${deliveryFee.toStringAsFixed(2)}'),
          const Divider(height: 20),
          _buildPriceRow(
            'Total Amount',
            '₹${widget.totalAmount.toStringAsFixed(2)}',
            isBold: true,
            color: Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, String value, {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _initiatePayment,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.payment),
                SizedBox(width: 8),
                Text(
                  'Pay Now',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => const MyOrdersScreen(),
                ),
                (route) => false,
              );
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.grey),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
            child: const Text(
              'View My Orders',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
