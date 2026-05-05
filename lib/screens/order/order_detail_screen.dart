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
import '../../services/payment_url_obfuscator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'edit_delivery_fee_screen.dart';
import 'order_status_tracking_screen.dart';
import 'pending_orders_screen.dart';
import 'waiting_payment_orders_screen.dart';
import 'ready_shipment_orders_screen.dart';
import 'shipped_orders_screen.dart';
import 'delivered_orders_screen.dart';

class OrderDetailScreen extends StatefulWidget {
  final int orderId;
  final Function(String, String)? onOrderStatusChanged;

  const OrderDetailScreen({super.key, required this.orderId, this.onOrderStatusChanged});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  Map<String, dynamic>? order;
  List<dynamic> orderItems = [];
  bool isLoading = true;
  String? errorMessage;
  
  // Admin role check
  bool isAdmin = false;
  
  // Dynamic delivery fee
  double _deliveryFee = 250.0;
  double _subtotalAmount = 0.0;
  double _totalAmount = 0.0;
  
  // State for item availability tracking
  Map<String, String> _itemAvailability = {};
  Map<String, int> _manualStockQuantities = {};
  Map<String, bool> _useManualStock = {};
  bool _showManualStockMode = false;
  
  // Auto-refresh variables
  Timer? _refreshTimer;
  bool _isAutoRefreshEnabled = true;
  int _refreshInterval = 15; // seconds
  DateTime? _lastRefreshTime;
  bool _isRefreshing = false;
  
  // Add a refresh key to force UI rebuild
  final GlobalKey<_OrderDetailScreenState> _refreshKey = GlobalKey<_OrderDetailScreenState>();

  @override
  void initState() {
    super.initState();
    _checkAdminRole();
    _fetchOrderDetails();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // Check if current user is admin
  Future<void> _checkAdminRole() async {
    final adminStatus = await LocalAuthService.isAdmin();
    print('🔍 OrderDetailScreen - Admin Status Check Result: $adminStatus');
    setState(() {
      isAdmin = adminStatus;
      print('🔍 OrderDetailScreen - Set isAdmin state to: $isAdmin');
    });
  }

  Future<void> _fetchOrderDetails({bool silent = false}) async {
    if (!silent) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    }

    try {
      print('=== FETCHING ORDER DETAILS ===');
      print('Order ID: ${widget.orderId}');
      print('API URL: ${Config.baseNodeApiUrl}/orders/${widget.orderId}');

      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/orders/${widget.orderId}'),
        headers: {
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      print('Response Status: ${response.statusCode}');
      print('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('Response Data: $responseData');
        
        if (responseData['success'] == true) {
          setState(() {
            order = responseData['order'];
            orderItems = responseData['items'] ?? [];
            
            // Initialize item availability from database
            _itemAvailability.clear();
            _manualStockQuantities.clear();
            _useManualStock.clear();
            
            // Check if any item has manual stock enabled
            bool hasManualStockEnabled = false;
            
            for (var item in orderItems) {
              final itemId = item['id'].toString();
              
              // Check stock status first
              final stockStatus = item['stock_status']?.toString() ?? 'full';
              final availableQuantity = int.tryParse(item['available_quantity']?.toString() ?? item['quantity'].toString()) ?? 1;
              final requestedQuantity = int.tryParse(item['quantity'].toString()) ?? 1;
              final rawUseManualStock = item['use_manual_stock'];
              final useManualStock = rawUseManualStock == true || rawUseManualStock?.toString() == '1' || rawUseManualStock?.toString().toLowerCase() == 'true';
              final manualStockQuantity = int.tryParse(item['manual_stock_quantity']?.toString() ?? '0') ?? 0;
              final availabilityStatus = item['availability_status']?.toString();
              
              print('   Item $itemId: rawUseManualStock=$rawUseManualStock (${rawUseManualStock.runtimeType}), useManualStock=$useManualStock, manualStockQuantity=$manualStockQuantity, availabilityStatus=$availabilityStatus');
              
              // Track if any manual stock is enabled
              if (useManualStock) {
                hasManualStockEnabled = true;
              }
              
              // Initialize manual stock data
              _useManualStock[itemId] = useManualStock;
              _manualStockQuantities[itemId] = manualStockQuantity;
              
              // Use availability status from database if manual stock is enabled
              if (useManualStock) {
                if (manualStockQuantity == 0) {
                  _itemAvailability[itemId] = 'Not Available';
                } else if (manualStockQuantity < requestedQuantity) {
                  _itemAvailability[itemId] = 'Partial Available';
                } else {
                  _itemAvailability[itemId] = 'Available';
                }
              } else {
                // When manual stock is not enabled, use database availability_status
                if (availabilityStatus == '1') {
                  _itemAvailability[itemId] = 'Not Available';
                } else {
                  _itemAvailability[itemId] = 'Available';
                }
              }
              
              print('📊 Final availability for $itemId: ${_itemAvailability[itemId]}');
            }
            
            // Stop auto-refresh if manual stock is enabled
            if (hasManualStockEnabled) {
              print('🛑 Stopping auto-refresh because manual stock is enabled');
              _stopAutoRefresh();
            } else {
              print('▶️ Starting auto-refresh because no manual stock is enabled');
              _startAutoRefresh();
            }
            
            // Calculate amounts
            _subtotalAmount = double.tryParse(order!['total_amount'].toString()) ?? 0.0;
            _deliveryFee = double.tryParse(order!['delivery_fee'].toString()) ?? 250.0;
            _totalAmount = _subtotalAmount + _deliveryFee;
            
            // Recalculate totals based on actual availability
            _recalculateTotals();
            
            // Get customer name
            String userName = responseData['order']['customer_name'] ?? 'Customer';
            order!['display_name'] = userName;
            
            isLoading = false;
          });
        } else {
          setState(() {
            errorMessage = responseData['message'] ?? 'API returned success: false';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = 'HTTP Error: ${response.statusCode} - ${response.body}';
          isLoading = false;
        });
      }
    } catch (e) {
      print('=== ERROR FETCHING ORDER DETAILS ===');
      print('Error: $e');
      print('Stack Trace: ${StackTrace.current}');
      
      setState(() {
        errorMessage = 'Connection Error: ${e.toString()}';
        isLoading = false;
      });
    }
  }

  // Helper function to consolidate order items by product name and variant
  Map<String, Map<String, dynamic>> _consolidateOrderItems({bool includeUnavailable = false}) {
    final Map<String, Map<String, dynamic>> consolidatedItems = {};
    
    for (var item in orderItems) {
      final itemId = item['id'].toString();
      final isUnavailable = _itemAvailability[itemId] == 'Not Available';
      
      // Skip unavailable items unless explicitly requested
      if (!includeUnavailable && isUnavailable) continue;
      
      final productName = item['product_name'] ?? 'Product';
      final color = (item['color']?.toString() ?? '').trim();
      final size = (item['size']?.toString() ?? '').trim();
      final key = '${productName.trim()}-${color}-${size}';
      
      // Use available_quantity for sharing, fallback to requested quantity if not available
      final displayQuantity = isUnavailable ? 0 : 
          (int.tryParse(item['available_quantity']?.toString() ?? item['quantity'].toString()) ?? 1);
      
      if (consolidatedItems.containsKey(key)) {
        // Sum quantities for identical variants
        final existingItem = consolidatedItems[key]!;
        final existingQty = int.tryParse(existingItem['displayQuantity'].toString()) ?? 0;
        existingItem['displayQuantity'] = (existingQty + displayQuantity);
        // Keep the unavailable status if any variant is unavailable
        if (isUnavailable) {
          existingItem['isUnavailable'] = true;
        }
      } else {
        // Add new consolidated item
        final newItem = Map<String, dynamic>.from(item);
        newItem['isUnavailable'] = isUnavailable;
        newItem['displayQuantity'] = displayQuantity;
        consolidatedItems[key] = newItem;
      }
    }
    
    return consolidatedItems;
  }

  // Send WhatsApp message for unavailable item
  Future<void> _sendUnavailableMessage(dynamic item) async {
    try {
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

      // Format phone number
      String formattedPhone = customerPhone.replaceAll(RegExp(r'[^\d]'), '');
      if (formattedPhone.length == 10) {
        formattedPhone = '91$formattedPhone';
      } else if (formattedPhone.length == 11 && formattedPhone.startsWith('0')) {
        formattedPhone = '91${formattedPhone.substring(1)}';
      } else if (formattedPhone.length == 12 && formattedPhone.startsWith('91')) {
        formattedPhone = formattedPhone;
      }

      // Create the unavailable message
      String message = '*Order ID:* #${widget.orderId}\n\n We’re sorry, this product is currently unavailable. Kindly choose another product or variant. Thank you for visiting BangkokMart.';
      
      // Send via WhatsApp API using wa.me link
      String encodedText = Uri.encodeComponent(message);
      String whatsappUrl = "https://wa.me/$formattedPhone?text=$encodedText";
      
      print('📱 Sending unavailable message to phone: $formattedPhone');
      print('📱 WhatsApp URL: $whatsappUrl');
      
      // Log the message
      await _logWhatsAppMessage(widget.orderId, customerPhone, message);
      
      // Open WhatsApp
      if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
        await launchUrl(Uri.parse(whatsappUrl));
      } else {
        throw 'Could not launch $whatsappUrl';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WhatsApp message sent successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error sending unavailable message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending message: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Log WhatsApp message
  Future<void> _logWhatsAppMessage(int orderId, String phoneNumber, String message) async {
    try {
      await http.post(
        Uri.parse('${Config.baseNodeApiUrl}/whatsapp/log-message'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'order_id': orderId,
          'phone_number': phoneNumber,
          'message': message,
          'sent_at': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      print('Failed to log WhatsApp message: $e');
    }
  }

  // Send special cancellation message for all unavailable items
  Future<void> _sendAllUnavailableCancellationMessage() async {
    try {
      final customerPhone = order!['customer_phone'] ?? order!['shipping_phone'];
      if (customerPhone == null || customerPhone == 'N/A' || customerPhone.toString().trim().isEmpty) {
        print('Customer phone not available for unavailable items cancellation message');
        return;
      }

      // Format phone number
      String formattedPhone = customerPhone.replaceAll(RegExp(r'[^\d]'), '');
      if (formattedPhone.length == 10) {
        formattedPhone = '91$formattedPhone';
      } else if (formattedPhone.length == 11 && formattedPhone.startsWith('0')) {
        formattedPhone = '91${formattedPhone.substring(1)}';
      } else if (formattedPhone.length == 12 && formattedPhone.startsWith('91')) {
        formattedPhone = formattedPhone;
      }

      // Create list of unavailable items
      List<String> unavailableItems = [];
      for (var item in orderItems) {
        final itemId = item['id'].toString();
        final availability = _itemAvailability[itemId] ?? 'Available';
        if (availability == 'Not Available') {
          final itemName = item['product_name'] ?? item['name'] ?? 'Unknown Product';
          final itemVariant = item['variant'] != null && item['variant'].toString().isNotEmpty 
            ? ' (${item['variant']})' 
            : '';
          unavailableItems.add('• $itemName$itemVariant');
        }
      }

      // Create special cancellation message for all unavailable items
      String message = '''*Order ID:* #${widget.orderId}

We're sorry, this product is currently unavailable. Kindly choose another product or variant. Thank you for visiting BangkokMart.''';

      // Send via WhatsApp API
      String encodedText = Uri.encodeComponent(message);
      String whatsappUrl = "https://wa.me/$formattedPhone?text=$encodedText";
      
      print('📱 Sending all unavailable cancellation message to phone: $formattedPhone');
      
      // Log the message
      await _logWhatsAppMessage(widget.orderId, customerPhone, message);
      
      // Open WhatsApp
      if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
        await launchUrl(Uri.parse(whatsappUrl));
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Short cancellation message sent successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error sending all unavailable cancellation message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending cancellation message: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Send payment cancellation message to customer
  Future<void> _sendPaymentCancellationMessageToCustomer() async {
    try {
      final customerPhone = order!['customer_phone'] ?? order!['shipping_phone'];
      if (customerPhone == null || customerPhone == 'N/A' || customerPhone.toString().trim().isEmpty) {
        print('Customer phone not available for payment cancellation message');
        return;
      }

      // Format phone number
      String formattedPhone = customerPhone.replaceAll(RegExp(r'[^\d]'), '');
      if (formattedPhone.length == 10) {
        formattedPhone = '91$formattedPhone';
      } else if (formattedPhone.length == 11 && formattedPhone.startsWith('0')) {
        formattedPhone = '91${formattedPhone.substring(1)}';
      } else if (formattedPhone.length == 12 && formattedPhone.startsWith('91')) {
        formattedPhone = formattedPhone;
      }

      // Create payment cancellation message
      String message = '''Dear Customer,

Your order has been cancelled due to non-receipt of payment within the required time.

If you are still interested, you're welcome to place a new order anytime on our website.
Thank you for your understanding.

Bangkok Mart''';

      // Send via WhatsApp API
      String encodedText = Uri.encodeComponent(message);
      String whatsappUrl = "https://wa.me/$formattedPhone?text=$encodedText";
      
      print('📱 Sending payment cancellation message to phone: $formattedPhone');
      
      // Log the message
      await _logWhatsAppMessage(widget.orderId, customerPhone, message);
      
      // Open WhatsApp
      if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
        await launchUrl(Uri.parse(whatsappUrl));
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment cancellation message sent successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error sending payment cancellation message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending cancellation message: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Send cancellation message to customer
  Future<void> _sendCancellationMessageToCustomer() async {
    try {
      final customerPhone = order!['customer_phone'] ?? order!['shipping_phone'];
      if (customerPhone == null || customerPhone == 'N/A' || customerPhone.toString().trim().isEmpty) {
        print('Customer phone not available for cancellation message');
        return;
      }

      // Format phone number
      String formattedPhone = customerPhone.replaceAll(RegExp(r'[^\d]'), '');
      if (formattedPhone.length == 10) {
        formattedPhone = '91$formattedPhone';
      } else if (formattedPhone.length == 11 && formattedPhone.startsWith('0')) {
        formattedPhone = '91${formattedPhone.substring(1)}';
      } else if (formattedPhone.length == 12 && formattedPhone.startsWith('91')) {
        formattedPhone = formattedPhone;
      }

      // Create cancellation message
      String message = '''*Order Cancelled - #${widget.orderId}*

Dear Customer,

We regret to inform you that your order has been cancelled.

If you have already made a payment, a refund will be processed within 5-7 working days.

For any questions, please contact our customer support.

Thank you for your understanding.
BangkokMart Team''';

      // Send via WhatsApp API
      String encodedText = Uri.encodeComponent(message);
      String whatsappUrl = "https://wa.me/$formattedPhone?text=$encodedText";
      
      print('📱 Sending cancellation message to phone: $formattedPhone');
      
      // Log the message
      await _logWhatsAppMessage(widget.orderId, customerPhone, message);
      
      // Open WhatsApp
      if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
        await launchUrl(Uri.parse(whatsappUrl));
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cancellation message sent successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error sending cancellation message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending cancellation message: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Send payment confirmation to customer
  Future<void> _sendPaymentConfirmationToCustomer() async {
    try {
      final customerPhone = order!['customer_phone'] ?? order!['shipping_phone'];
      if (customerPhone == null || customerPhone == 'N/A' || customerPhone.toString().trim().isEmpty) {
        print('Customer phone not available for payment confirmation');
        return;
      }

      // Format phone number
      String formattedPhone = customerPhone.replaceAll(RegExp(r'[^\d]'), '');
      if (formattedPhone.length == 10) {
        formattedPhone = '91$formattedPhone';
      } else if (formattedPhone.length == 11 && formattedPhone.startsWith('0')) {
        formattedPhone = '91${formattedPhone.substring(1)}';
      } else if (formattedPhone.length == 12 && formattedPhone.startsWith('91')) {
        formattedPhone = formattedPhone;
      }

      // Create payment confirmation message
      String message = '''*Payment Confirmed - #${widget.orderId}*

Dear Customer,

Great news! Your payment has been confirmed and your order is now being prepared for shipment.

📦 *Order Details:*
• Order ID: #${widget.orderId}
• Total Amount: ₹${_totalAmount.toStringAsFixed(2)}
• Status: Ready for Shipment

Your order will be shipped soon. You will receive tracking details once shipped.

Thank you for shopping with BangkokMart!
Team BangkokMart''';

      // Send via WhatsApp API
      String encodedText = Uri.encodeComponent(message);
      String whatsappUrl = "https://wa.me/$formattedPhone?text=$encodedText";
      
      print('📱 Sending payment confirmation to phone: $formattedPhone');
      
      // Log the message
      await _logWhatsAppMessage(widget.orderId, customerPhone, message);
      
      // Open WhatsApp
      if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
        await launchUrl(Uri.parse(whatsappUrl));
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment confirmation sent successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error sending payment confirmation: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending payment confirmation: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Function to update manual stock quantity on server
  Future<void> _updateManualStockOnServer(String itemId, int manualStockQuantity, bool useManualStock) async {
    try {
      print('📤 Sending manual stock update: itemId=$itemId, manualStockQuantity=$manualStockQuantity, useManualStock=$useManualStock');
      final response = await http.post(
        Uri.parse('${Config.baseNodeApiUrl}/orders/update-manual-stock'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'orderId': widget.orderId,
          'itemId': itemId,
          'manualStockQuantity': manualStockQuantity,
          'useManualStock': useManualStock,
        }),
      ).timeout(const Duration(seconds: 10));
      
      print('📤 Sent manual stock update: itemId=$itemId, manualStockQuantity=$manualStockQuantity, useManualStock=$useManualStock');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('📥 Server response: $responseData');
        if (responseData['success'] == true) {
          print('✅ Updated manual stock for item $itemId to $manualStockQuantity');
        } else {
          print('❌ Failed to update manual stock: ${responseData['message']}');
        }
      } else {
        print('❌ HTTP error updating manual stock: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error updating manual stock: $e');
    }
  }

  // Show confirmation dialog before marking product as unavailable
  Future<void> _showDeleteConfirmationDialog(String itemId, dynamic item) async {
    final productName = item['product_name'] ?? 'Product';
    final color = item['color']?.toString() ?? '';
    final size = item['size']?.toString() ?? '';
    
    String variantInfo = '';
    if (color.isNotEmpty && size.isNotEmpty) {
      variantInfo = ' ($color, Size: $size)';
    } else if (color.isNotEmpty) {
      variantInfo = ' ($color)';
    } else if (size.isNotEmpty) {
      variantInfo = ' (Size: $size)';
    }

    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must tap button to close
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange[700],
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Confirm Product Deletion',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Do you want to delete this product variant?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      productName + variantInfo,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '⚠️ This action will:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '• Mark this item as "Not Available"\n• Delete the product variant from database\n• This action cannot be undone',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog without changes
              },
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                // Proceed with marking as unavailable
                setState(() {
                  _itemAvailability[itemId] = 'Not Available';
                });
                // Update server with unavailable status (1)
                _updateItemAvailabilityOnServer(itemId, 1);
                // Recalculate totals
                _recalculateTotals();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete, size: 16),
                  SizedBox(width: 4),
                  Text('Yes, Delete'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

// Update availability status on server
  Future<void> _updateItemAvailabilityOnServer(String itemId, int availabilityStatus) async {
    try {
      final response = await http.post(
        Uri.parse('${Config.baseNodeApiUrl}/orders/update-availability'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'orderId': widget.orderId,
          'itemId': itemId,
          'availabilityStatus': availabilityStatus,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          print('✅ Updated availability status for item $itemId to $availabilityStatus');
          
          // Check if variants were deleted
          if (responseData['data'] != null && responseData['data']['deletedVariants'] != null) {
            final deletedVariants = responseData['data']['deletedVariants'] as List;
            if (deletedVariants.isNotEmpty) {
              // Show success message for variant deletion
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ Product variant(s) deleted successfully: ${deletedVariants.join(', ')}'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                ),
              );
              print('🗑️ Deleted variants: ${deletedVariants.join(', ')}');
            }
          }
        } else {
          print('❌ Failed to update availability status: ${responseData['message']}');
          // Show error message to user
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ ${responseData['message']}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        print('❌ HTTP error updating availability status: ${response.statusCode}');
        // Show error message to user
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Failed to update availability status'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ Error updating availability status: $e');
      // Show error message to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // Recalculate totals based on available items and quantities
  void _recalculateTotals() {
    double availableSubtotal = 0.0;
    
    print('🧮 === RECALCULATING TOTALS ===');
    print('📦 Total items: ${orderItems.length}');
    
    // Use a Set to track unique item IDs to avoid duplicate calculations
    Set<String> processedItemIds = {};
    
    for (var item in orderItems) {
      final itemId = item['id'].toString();
      
      // Skip if we've already processed this item
      if (processedItemIds.contains(itemId)) {
        print('⏭️ Skipping duplicate item $itemId');
        continue;
      }
      processedItemIds.add(itemId);
      
      final availabilityStatus = _itemAvailability[itemId] ?? 'Available';
      final useManualStock = _useManualStock[itemId] ?? false;
      final requestedQuantity = int.tryParse(item['quantity'].toString()) ?? 1;
      final itemPrice = double.tryParse(item['price'].toString()) ?? 0.0;
      
      print('🔍 Item $itemId:');
      print('   - Availability: $availabilityStatus');
      print('   - Use Manual Stock: $useManualStock');
      print('   - Requested Quantity: $requestedQuantity');
      print('   - Manual Stock Quantity: ${_manualStockQuantities[itemId]}');
      print('   - Item Price: ₹$itemPrice');
      
      if (availabilityStatus != 'Not Available') {
        // Use manual stock quantity if enabled, otherwise use requested quantity
        int availableQuantity;
        if (useManualStock) {
          availableQuantity = _manualStockQuantities[itemId] ?? 0;
        } else {
          // When manual stock is not enabled, use requested quantity
          availableQuantity = requestedQuantity;
        }
        
        final itemTotal = itemPrice * availableQuantity;
        availableSubtotal += itemTotal;
        
        print('   - Available Quantity: $availableQuantity');
        print('   - Item Total: ₹$itemTotal');
      } else {
        print('   - Item is NOT AVAILABLE - skipping');
      }
    }
    
    setState(() {
      _subtotalAmount = availableSubtotal;
      _totalAmount = _subtotalAmount + _deliveryFee;
    });
    
    print('💰 FINAL CALCULATION:');
    print('   - Subtotal: ₹$_subtotalAmount');
    print('   - Delivery Fee: ₹$_deliveryFee');
    print('   - Total: ₹$_totalAmount');
    print('🧮 === END RECALCULATION ===');
  }

  @override
  Widget build(BuildContext context) {
    print('🔍 OrderDetailScreen Build - isAdmin: $isAdmin');
    
    return WillPopScope(
      onWillPop: () async {
        // Save any pending changes before going back
        await _savePendingChanges();
        return true;
      },
      child: Scaffold(
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Go Back',
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
            ),
            child: IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => OrderStatusTrackingScreen(
                      orderId: widget.orderId,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.track_changes, size: 20),
              tooltip: 'Track Order',
            ),
          ),
          // Share button - only for admin users
          if (isAdmin)
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
      ),
    );
  }

  // Check if all items are unavailable
  bool _areAllItemsUnavailable() {
    if (orderItems.isEmpty) return false;
    
    return orderItems.every((item) {
      final itemId = item['id'].toString();
      final availability = _itemAvailability[itemId] ?? 'Available';
      return availability == 'Not Available';
    });
  }

  // Save pending changes before navigation
  Future<void> _savePendingChanges() async {
    try {
      // Check if manual stock changes need to be saved
      if (_showManualStockMode && isAdmin) {
        print('💾 Saving pending manual stock changes...');
        
        // Save all manual stock changes
        for (String itemId in _manualStockQuantities.keys) {
          final useManualStock = _useManualStock[itemId] ?? false;
          final manualStockQuantity = _manualStockQuantities[itemId] ?? 0;
          
          await _updateManualStockOnServer(itemId, manualStockQuantity, useManualStock);
        }
      }
      
      // Force refresh to ensure latest data
      await _fetchOrderDetails(silent: true);
      
    } catch (e) {
      print('❌ Error saving pending changes: $e');
    }
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
            'Failed to Load Order Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Text(
              errorMessage ?? 'Unknown error occurred',
              style: TextStyle(
                fontSize: 14,
                color: Colors.red[700],
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _fetchOrderDetails,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go Back'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[600],
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Order ID: #${widget.orderId}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order Status Card
          _buildStatusCard(),

          const SizedBox(height: 6),

          // Manual Stock Management - temporarily hidden
          // if (isAdmin && (order!['order_status'] == 'Pending' || order!['order_status'] == 'pending')) _buildManualStockManagement(),

          const SizedBox(height: 6),

          // Order Items
          _buildOrderItems(),

          const SizedBox(height: 6),

          // Order Summary - Now scrollable with other content
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
                // User Name and Phone Number in same row
                Row(
                  children: [
                    Expanded(
                      child: _buildCompactInfoRow(
                        Icons.person_outline,
                        'Customer Name',
                        order!['display_name'] ?? 'N/A',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildCompactInfoRow(
                        Icons.phone_outlined,
                        'Phone Number',
                        order!['customer_phone'] ?? order!['shipping_phone'] ?? 'N/A',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Shipping Address
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Shipping Address',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        order!['shipping_street'] ?? 'N/A',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        '${order!['shipping_city'] ?? 'N/A'}, ${order!['shipping_state'] ?? 'N/A'} - ${order!['shipping_pincode'] ?? 'N/A'}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
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
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualStockManagement() {
    print('🔍 _buildManualStockManagement - isAdmin: $isAdmin');
    
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange[50]!, Colors.yellow[50]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.15),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.orange[200]!, width: 1),
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
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.inventory_2,
                      color: Colors.orange[700],
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Manual Stock Management',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              // Toggle manual stock mode
              GestureDetector(
                onTap: () {
                  setState(() {
                    final wasTurningOn = !_showManualStockMode;
                    _showManualStockMode = !_showManualStockMode;
                    
                    // Auto-enable manual stock for items when turning ON
                    if (wasTurningOn) {
                      for (var item in orderItems) {
                        final itemId = item['id'].toString();
                        final manualStockQuantity = _manualStockQuantities[itemId] ?? 0;
                        final requestedQuantity = int.tryParse(item['quantity'].toString()) ?? 1;
                        
                        // Enable manual stock if quantity is different from requested
                        if (manualStockQuantity != requestedQuantity && manualStockQuantity > 0) {
                          _useManualStock[itemId] = true;
                          print('Auto-enabled manual stock for item $itemId: $manualStockQuantity vs $requestedQuantity');
                        }
                      }
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _showManualStockMode ? Colors.orange[600] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _showManualStockMode ? 'ON' : 'OFF',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_showManualStockMode) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Set available quantities manually for each item:',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF616161), // Colors.grey[700]
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      // Enable manual stock for all items
                      for (var item in orderItems) {
                        final itemId = item['id'].toString();
                        _useManualStock[itemId] = true;
                        print('Manually enabled manual stock for item $itemId');
                      }
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Manual stock enabled for all items'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green[600],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Enable All',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Manual stock controls for unique items only
            Container(
              constraints: BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                child: Column(
                  children: _getUniqueItems().map((item) => _buildManualStockItem(item)).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Helper method to get unique items (avoid duplicates)
  List<dynamic> _getUniqueItems() {
    final Set<String> addedProducts = {};
    final List<dynamic> uniqueItems = [];
    
    for (var item in orderItems) {
      final productName = item['product_name'] ?? 'Product';
      final color = item['color']?.toString() ?? '';
      final size = item['size']?.toString() ?? '';
      
      // Create unique key for product (name + color + size)
      final productKey = '${productName.trim()}_${color.trim()}_${size.trim()}';
      
      // Skip if already added
      if (!addedProducts.contains(productKey)) {
        addedProducts.add(productKey);
        uniqueItems.add(item);
      }
    }
    
    return uniqueItems;
  }

  Widget _buildManualStockItem(dynamic item) {
    // Only show manual stock controls to admin users
    print('🔍 _buildManualStockItem - isAdmin: $isAdmin');
    if (!isAdmin) {
      // For regular users, show item info without controls
      final itemId = item['id'].toString();
      final productName = item['product_name'] ?? 'Product';
      final color = item['color']?.toString() ?? '';
      final size = item['size']?.toString() ?? '';
      final availabilityStatus = _itemAvailability[itemId] ?? 'Available';
      
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$productName${color.isNotEmpty ? ' ($color)' : ''}${size.isNotEmpty ? ' - $size' : ''}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Status: $availabilityStatus',
              style: TextStyle(
                fontSize: 11,
                color: availabilityStatus == 'Available' ? Colors.green : Colors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    
    final itemId = item['id'].toString();
    final productName = item['product_name'] ?? 'Product';
    final color = item['color']?.toString() ?? '';
    final size = item['size']?.toString() ?? '';
    final requestedQuantity = int.tryParse(item['quantity'].toString()) ?? 1;
    final currentManualStock = _manualStockQuantities[itemId] ?? 0;
    final useManualStock = _useManualStock[itemId] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$productName${color.isNotEmpty ? ' ($color)' : ''}${size.isNotEmpty ? ' - $size' : ''}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Enable manual stock checkbox
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Use Manual Stock',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF757575), // Colors.grey[600]
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () {
                        final newUseManualStock = !useManualStock;
                        print('🔄 Toggle manual stock: itemId=$itemId, currentUseManualStock=$useManualStock, newUseManualStock=$newUseManualStock, currentManualStock=$currentManualStock, requestedQuantity=$requestedQuantity');
                        setState(() {
                          _useManualStock[itemId] = newUseManualStock;
                          // Update availability status based on manual stock
                          if (newUseManualStock) {
                            // Enabling manual stock
                            if (currentManualStock == 0) {
                              _itemAvailability[itemId] = 'Not Available';
                            } else if (currentManualStock < requestedQuantity) {
                              _itemAvailability[itemId] = 'Partial Available';
                            } else {
                              _itemAvailability[itemId] = 'Available';
                            }
                          } else {
                            // Disabling manual stock - reset to automatic
                            _updateAvailabilityFromServer(item);
                          }
                        });
                        // When enabling manual stock, ensure we have a valid quantity
                        final stockQuantity = newUseManualStock ? (currentManualStock > 0 ? currentManualStock : requestedQuantity) : currentManualStock;
                        _updateManualStockOnServer(itemId, stockQuantity, newUseManualStock);
                        _recalculateTotals();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: useManualStock ? Colors.orange[100] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: useManualStock ? Colors.orange[300]! : Colors.grey[300]!,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              useManualStock ? Icons.check_box : Icons.check_box_outline_blank,
                              size: 16,
                              color: useManualStock ? Colors.orange[700] : Colors.grey[600],
                            ),
                            const SizedBox(width: 6),
                            Text(
                              useManualStock ? 'Enabled' : 'Disabled',
                              style: TextStyle(
                                fontSize: 11,
                                color: useManualStock ? Colors.orange[700] : Colors.grey[600],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Manual stock quantity input
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Available Qty',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF757575), // Colors.grey[600]
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 40,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          // Decrease button
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                if (currentManualStock > 0) {
                                  final newQuantity = currentManualStock - 1;
                                  setState(() {
                                    _manualStockQuantities[itemId] = newQuantity;
                                    // Update availability status
                                    if (useManualStock) {
                                      if (newQuantity == 0) {
                                        _itemAvailability[itemId] = 'Not Available';
                                      } else if (newQuantity < requestedQuantity) {
                                        _itemAvailability[itemId] = 'Partial Available';
                                      } else {
                                        _itemAvailability[itemId] = 'Available';
                                      }
                                    }
                                  });
                                  // Auto-enable manual stock if quantity is changed OR if global toggle is ON
                                  final shouldEnableManualStock = (!useManualStock && newQuantity != requestedQuantity) || (_showManualStockMode && !useManualStock);
                                  final finalUseManualStock = shouldEnableManualStock ? true : useManualStock;
                                  _updateManualStockOnServer(itemId, newQuantity, finalUseManualStock);
                                  
                                  // Update local state if auto-enabling
                                  if (shouldEnableManualStock) {
                                    setState(() {
                                      _useManualStock[itemId] = true;
                                      print('Auto-enabled manual stock for item $itemId (decrease): newQuantity=$newQuantity, requested=$requestedQuantity, globalToggle=$_showManualStockMode');
                                    });
                                  }
                                  _recalculateTotals();
                                }
                              },
                              child: Container(
                                height: 40,
                                child: Icon(
                                  Icons.remove,
                                  size: 16,
                                  color: Colors.red[600],
                                ),
                              ),
                            ),
                          ),
                          // Quantity display
                          Expanded(
                            child: Container(
                              height: 40,
                              child: Center(
                                child: Text(
                                  currentManualStock.toString(),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Increase button
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                final newQuantity = currentManualStock + 1;
                                setState(() {
                                  _manualStockQuantities[itemId] = newQuantity;
                                  // Update availability status
                                  if (useManualStock) {
                                    if (newQuantity == 0) {
                                      _itemAvailability[itemId] = 'Not Available';
                                    } else if (newQuantity < requestedQuantity) {
                                      _itemAvailability[itemId] = 'Partial Available';
                                    } else {
                                      _itemAvailability[itemId] = 'Available';
                                    }
                                  }
                                });
                                // Auto-enable manual stock if quantity is changed OR if global toggle is ON
                                final shouldEnableManualStock = (!useManualStock && newQuantity != requestedQuantity) || (_showManualStockMode && !useManualStock);
                                final finalUseManualStock = shouldEnableManualStock ? true : useManualStock;
                                _updateManualStockOnServer(itemId, newQuantity, finalUseManualStock);
                                
                                // Update local state if auto-enabling
                                if (shouldEnableManualStock) {
                                  setState(() {
                                    _useManualStock[itemId] = true;
                                    print('Auto-enabled manual stock for item $itemId (increase): newQuantity=$newQuantity, requested=$requestedQuantity, globalToggle=$_showManualStockMode');
                                  });
                                }
                                _recalculateTotals();
                              },
                              child: Container(
                                height: 40,
                                child: Icon(
                                  Icons.add,
                                  size: 16,
                                  color: Colors.green[600],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Stock info
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Req: $requestedQuantity',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF757575), // Colors.grey[600]
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      useManualStock 
                          ? 'Manual: $currentManualStock'
                          : 'Auto Stock',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: useManualStock ? Colors.orange[700] : Colors.blue[700],
                      ),
                    ),
                    if (useManualStock)
                      Text(
                        _itemAvailability[itemId] ?? 'Available',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: _getAvailabilityStatusColor(_itemAvailability[itemId] ?? 'Available'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Helper method to update availability from server data
  void _updateAvailabilityFromServer(dynamic item) {
    final itemId = item['id'].toString();
    final stockStatus = item['stock_status']?.toString() ?? 'full';
    final availableQuantity = int.tryParse(item['available_quantity']?.toString() ?? item['quantity'].toString()) ?? 1;
    final requestedQuantity = int.tryParse(item['quantity'].toString()) ?? 1;
    
    if (stockStatus == 'out_of_stock' || availableQuantity == 0) {
      _itemAvailability[itemId] = 'Not Available';
    } else if (stockStatus == 'partial') {
      _itemAvailability[itemId] = 'Partial Available';
    } else {
      _itemAvailability[itemId] = 'Available';
    }
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

    // Check if all items are unavailable
    bool allItemsUnavailable = orderItems.every((item) {
      final itemId = item['id'].toString();
      final availabilityStatus = _itemAvailability[itemId] ?? 'Available';
      final useManualStock = _useManualStock[itemId] ?? false;
      final manualStockQuantity = _manualStockQuantities[itemId] ?? 0;
      
      // If manual stock is enabled and quantity > 0, it's available
      if (useManualStock && manualStockQuantity > 0) {
        return false;
      }
      
      // Otherwise check availability status
      return availabilityStatus == 'Not Available';
    });

    // Check if any item has manual stock enabled
    bool hasManualStockEnabled = orderItems.any((item) {
      final itemId = item['id'].toString();
      return _useManualStock[itemId] ?? false;
    });

    return Container(
      decoration: BoxDecoration(
        color: hasManualStockEnabled ? Colors.grey[100] : Colors.white,
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
          // Header with master checkbox - only for admin users and Pending orders
          if (isAdmin && (order!['order_status'] == 'Pending' || order!['order_status'] == 'pending'))
            Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: hasManualStockEnabled ? Colors.grey[200] : Colors.grey[50],
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
                if (hasManualStockEnabled) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange[300]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 14,
                          color: Colors.orange[700],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Manual Stock Enabled',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const Spacer(),
                  // Master availability dropdown
                  // if (isAdmin && (order!['order_status'] == 'Pending' || order!['order_status'] == 'pending'))
                  //   Container(
                  //     height: 32,
                  //     decoration: BoxDecoration(
                  //       gradient: LinearGradient(
                  //         colors: allItemsUnavailable 
                  //           ? [Colors.red[400]!, Colors.red[300]!]
                  //           : [Colors.green[400]!, Colors.green[300]!],
                  //         begin: Alignment.topLeft,
                  //         end: Alignment.bottomRight,
                  //       ),
                  //       borderRadius: BorderRadius.circular(16),
                  //       border: Border.all(
                  //         color: allItemsUnavailable ? Colors.red[500]! : Colors.green[500]!,
                  //         width: 1.0,
                  //       ),
                  //       boxShadow: [
                  //         BoxShadow(
                  //           color: allItemsUnavailable 
                  //             ? Colors.red.withOpacity(0.2)
                  //             : Colors.green.withOpacity(0.2),
                  //           blurRadius: 3,
                  //           offset: const Offset(0, 1),
                  //         ),
                  //       ],
                  //     ),
                  //     child: DropdownButton<String>(
                  //       value: allItemsUnavailable ? 'All Unavailable' : 'All Available',
                  //       icon: const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white),
                  //       underline: const SizedBox(),
                  //       isDense: true,
                  //       style: const TextStyle(
                  //         fontSize: 9,
                  //         fontWeight: FontWeight.w700,
                  //         color: Colors.white,
                  //         shadows: [
                  //           Shadow(
                  //             color: Colors.black26,
                  //             offset: Offset(0, 0.5),
                  //             blurRadius: 1,
                  //           ),
                  //         ],
                  //       ),
                  //       dropdownColor: allItemsUnavailable ? Colors.red[400] : Colors.green[400],
                  //       items: [
                  //         DropdownMenuItem(
                  //           value: 'All Available',
                  //           child: Row(
                  //             mainAxisSize: MainAxisSize.min,
                  //             children: [
                  //               const Icon(Icons.check, size: 12, color: Colors.white),
                  //               const SizedBox(width: 4),
                  //               const Text('All Available'),
                  //             ],
                  //           ),
                  //         ),
                  //         DropdownMenuItem(
                  //           value: 'All Unavailable',
                  //           child: Row(
                  //             mainAxisSize: MainAxisSize.min,
                  //             children: [
                  //               const Icon(Icons.close, size: 12, color: Colors.white),
                  //               const SizedBox(width: 4),
                  //               const Text('All Unavailable'),
                  //             ],
                  //           ),
                  //         ),
                  //       ],
                  //       onChanged: (String? newValue) {
                  //         if (newValue != null) {
                  //           final makeAllUnavailable = newValue == 'All Unavailable';
                  //           setState(() {
                  //             // Toggle all items
                  //             for (var item in orderItems) {
                  //               final itemId = item['id'].toString();
                  //               _itemAvailability[itemId] = makeAllUnavailable ? 'Not Available' : 'Available';
                  //             }
                  //           });
                  //           // Update all items availability status on server
                  //           int availabilityStatus = makeAllUnavailable ? 1 : 0;
                  //           for (var item in orderItems) {
                  //             final itemId = item['id'].toString();
                  //             _updateItemAvailabilityOnServer(itemId, availabilityStatus);
                  //           }
                  //           // Recalculate totals
                  //           _recalculateTotals();
                  //         }
                  //       },
                  //     ),
                  //   ),
                ],
              ],
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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product Name Header with exact UI as shown in image
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                // Product Name
                Expanded(
                  child: Text(
                    productName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

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
    print('🔍 _buildVariantItem - isAdmin: $isAdmin');
    
    // Get the individual item price (not the total)
    final itemPrice = double.tryParse(item['price'].toString()) ?? 0.0;
    final requestedQuantity = int.tryParse(item['quantity'].toString()) ?? 1;
    final itemId = item['id'].toString();
    final availabilityStatus = _itemAvailability[itemId] ?? 'Available';
    final useManualStock = _useManualStock[itemId] ?? false;
    final manualStockQuantity = _manualStockQuantities[itemId] ?? 0;
    
    // Calculate available quantity based on manual stock or automatic stock
    int availableQuantity;
    if (useManualStock) {
      availableQuantity = manualStockQuantity;
    } else {
      // When manual stock is not enabled, use requested quantity (not server available_quantity)
      availableQuantity = requestedQuantity;
    }
    
    // Determine UI state based on availability status
    bool isUnavailable = availabilityStatus == 'Not Available';
    bool isPartial = availabilityStatus == 'Partial Available';
    
    // Only show stock status colors when manual stock is enabled
    Color statusColor = Colors.white;
    Color borderColor = Colors.grey[200]!;
    double borderWidth = 1;
    
    if (useManualStock) {
      statusColor = isUnavailable ? Colors.red[50]! : (isPartial ? Colors.orange[50]! : Colors.white);
      borderColor = isUnavailable ? Colors.red[200]! : (isPartial ? Colors.orange[300]! : Colors.grey[200]!);
      borderWidth = isUnavailable ? 2 : (isPartial ? 1.5 : 1);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: statusColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor,
          width: borderWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dropdown with Color and Size Info - positioned at top
          if (isAdmin && (order!['order_status'] == 'Pending' || order!['order_status'] == 'pending'))
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  // Small availability icon
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: isUnavailable ? Colors.red : Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: isUnavailable 
                      ? const Icon(Icons.close, size: 10, color: Colors.white)
                      : const Icon(Icons.check, size: 10, color: Colors.white),
                  ),
                  const SizedBox(width: 6),
                  
                  // Color Badge
                  if (item['color'] != null && item['color'].toString().isNotEmpty)
                    Flexible(
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getColorFromString(item['color']),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!, width: 1),
                        ),
                        child: Text(
                          item['color'],
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  
                  // Size Badge
                  if (item['size'] != null && item['size'].toString().isNotEmpty && item['size'].toString().toLowerCase() != 'no size')
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!, width: 1),
                      ),
                      child: Text(
                        'Size: ${item['size']}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  
                  const Spacer(),
                  
                  // Availability Dropdown or Disabled Indicator - moved to right
                  if (_showManualStockMode && useManualStock)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.orange[300]!,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 10,
                            color: Colors.orange[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Manual Stock',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange[700],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isUnavailable ? Colors.red[50] : Colors.green[50],
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isUnavailable ? Colors.red[300]! : Colors.green[300]!,
                          width: 1,
                        ),
                      ),
                      child: DropdownButton<String>(
                        value: isUnavailable ? 'Unavailable' : 'Available',
                        icon: const Icon(Icons.arrow_drop_down, size: 14),
                        underline: const SizedBox(),
                        isDense: true,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isUnavailable ? Colors.red[700] : Colors.green[700],
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'Available',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check, size: 10, color: Colors.green),
                                const SizedBox(width: 2),
                                const Text('Available'),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'Unavailable',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.close, size: 10, color: Colors.red),
                                const SizedBox(width: 2),
                                const Text('Unavailable'),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (String? newValue) {
                          if (newValue != null && !(_showManualStockMode && useManualStock)) {
                            // If changing to Unavailable, show confirmation dialog
                            if (newValue == 'Unavailable') {
                              _showDeleteConfirmationDialog(itemId, item);
                            } else {
                              // If changing to Available, proceed normally
                              setState(() {
                                _itemAvailability[itemId] = 'Available';
                              });
                              // Update server
                              _updateItemAvailabilityOnServer(itemId, 0);
                              // Recalculate totals
                              _recalculateTotals();
                            }
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
          
          // Product details row
          Row(
            children: [
              // Product Image
              GestureDetector(
                onTap: () => _showFullScreenImage(context, item),
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[300]!, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      children: [
                        _buildProductImage(item),
                        // Add a subtle zoom icon overlay to indicate it's clickable
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.zoom_in,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Variant Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Show requested quantity - always editable for testing
                        Row(
                          children: [
                            Text(
                              'Requested: ',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                _showQuantityEditDialog(item, requestedQuantity, itemPrice);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.blue[300]!),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '$requestedQuantity',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.blue[700],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(
                                      Icons.edit,
                                      size: 10,
                                      color: Colors.blue[700],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Text(
                              ' x Rs.${itemPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        // Show total based on available quantity
                        Text(
                          (_showManualStockMode && useManualStock)
                              ? 'Available Total: ₹${(itemPrice * availableQuantity).toStringAsFixed(2)}'
                              : 'Total: ₹${(itemPrice * (isUnavailable ? 0 : requestedQuantity)).toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isUnavailable ? Colors.grey[500] : ((_showManualStockMode && useManualStock) ? Colors.blue[700] : Colors.blue),
                            decoration: isUnavailable ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        if (_showManualStockMode && useManualStock && isAdmin && (order!['order_status'] == 'Pending' || order!['order_status'] == 'pending'))
                          Text(
                            'Requested Total: ₹${(itemPrice * requestedQuantity).toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[500],
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        // Show manual stock indicator - only when global toggle is ON
                        if (_showManualStockMode && useManualStock && isAdmin && (order!['order_status'] == 'Pending' || order!['order_status'] == 'pending'))
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue[300]!),
                            ),
                            child: Text(
                              'Manual Stock: $availableQuantity',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.blue[700],
                                fontWeight: FontWeight.w600,
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
      print('🖼️ _buildProductImage using item image_url: $imageUrl');
    }
    // 2. Check if item has product_image
    else if (item['product_image'] != null && item['product_image'].toString().isNotEmpty) {
      String tempImageUrl = item['product_image'].toString();
      if (tempImageUrl.startsWith('http')) {
        imageUrl = tempImageUrl;
      } else {
        imageUrl = 'http://184.168.126.71/api/uploads/$tempImageUrl';
      }
      print('🖼️ _buildProductImage using item product_image: $imageUrl');
    }
    // 3. Check if item has imageUrl
    else if (item['imageUrl'] != null && item['imageUrl'].toString().isNotEmpty) {
      String tempImageUrl = item['imageUrl'].toString();
      if (tempImageUrl.startsWith('http')) {
        imageUrl = tempImageUrl;
      } else {
        imageUrl = 'http://184.168.126.71/api/uploads/$tempImageUrl';
      }
      print('🖼️ _buildProductImage using item imageUrl: $imageUrl');
    }
    // 4. Check if order has image_url (fallback)
    else if (order?['image_url'] != null && order!['image_url'].toString().isNotEmpty) {
      imageUrl = order!['image_url'];
      print('🖼️ _buildProductImage using order image_url: $imageUrl');
    }

    if (imageUrl != null) {
      return Image.network(
        imageUrl,
        width: 70,
        height: 70,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholderImage(),
      );
    }

    return _buildPlaceholderImage();
  }

  Widget _buildPlaceholderImage({String? productName}) {
    return Container(
      width: 70,
      height: 70,
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
                      order!['customer_phone'] ?? order!['shipping_phone'] ?? 'N/A',
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
    final subtotalAmount = _subtotalAmount;
    final deliveryFee = _deliveryFee;
    final totalAmount = _totalAmount;

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
                    // Ship Button for Ready for Shipment
                    if (order!['order_status'] == 'Ready for Shipment')
                      Container(
                        height: 32,
                        child: GestureDetector(
                          onTap: () async {
                            // Show confirmation dialog
                            final confirmed = await _showStatusChangeDialog(
                              'Ship Order',
                              'Are you sure you want to ship this order?',
                              Icons.local_shipping,
                              Colors.blue,
                            );

                            if (confirmed == true) {
                              // Update order status to "Shipped"
                              await _updateOrderStatus('Shipped');

                              // Navigate to shipped screen
                              if (mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const ShippedOrdersScreen(),
                                  ),
                                );
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue[100],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.blue[300]!, width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.local_shipping,
                                  color: Colors.blue[700],
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Ship',
                                  style: TextStyle(
                                    color: Colors.blue[700],
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // Deliver Button for Shipped
                    if (order!['order_status'] == 'Shipped')
                      Container(
                        height: 32,
                        child: GestureDetector(
                          onTap: () async {
                            // Show confirmation dialog
                            final confirmed = await _showStatusChangeDialog(
                              'Deliver Order',
                              'Are you sure you want to mark this order as delivered?',
                              Icons.check_circle,
                              Colors.purple,
                            );

                            if (confirmed == true) {
                              // Update order status to "Delivered"
                              await _updateOrderStatus('Delivered');

                              // Navigate to delivered screen
                              if (mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const DeliveredOrdersScreen(),
                                  ),
                                );
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: Colors.purple[100],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.purple[300]!, width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.purple[700],
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Deliver',
                                  style: TextStyle(
                                    color: Colors.purple[700],
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // Cancel Button for cancellable orders - Only for non-admin users
                    if (!isAdmin && (order!['order_status'] == 'Pending' ||
                        order!['order_status'] == 'Waiting for Payment' ||
                        order!['order_status'] == 'Ready for Shipment'))
                      Container(
                        height: 32,
                        child: GestureDetector(
                          onTap: () async {
                            // Show confirmation dialog
                            final confirmed = await _showStatusChangeDialog(
                              'Cancel Order',
                              'Are you sure you want to cancel this order? This action cannot be undone.',
                              Icons.cancel,
                              Colors.red,
                            );

                            if (confirmed == true) {
                              // Update order status to "Cancelled"
                              await _updateOrderStatus('Cancelled');

                              // Navigate back to appropriate screen based on previous status
                              if (mounted) {
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const PendingOrdersScreen(),
                                  ),
                                      (route) => false,
                                );
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.red[100],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.red[300]!, width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.cancel,
                                  color: Colors.red[700],
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: Colors.red[700],
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
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

          // Summary Items with refresh button
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    children: [
                      _buildCompactSummaryRow('Subtotal', '₹${_subtotalAmount.toStringAsFixed(2)}'),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            key: ValueKey('delivery_fee_$_deliveryFee'),
                            child: _buildCompactSummaryRow('Delivery Fee', '₹${_deliveryFee.toStringAsFixed(2)}'),
                          ),
                          GestureDetector(
                            onTap: _editDeliveryFee,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.blue[200]!, width: 1),
                              ),
                              child: Icon(
                                Icons.edit_outlined,
                                size: 16,
                                color: Colors.blue[600],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      Container(
                        key: ValueKey('total_amount_$_totalAmount'),
                        child: _buildCompactSummaryRow(
                          'Total Amount',
                          '₹${_totalAmount.toStringAsFixed(2)}',
                          isTotal: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Action Buttons - Only for Waiting for Payment orders (admin only)
          if (order!['order_status'] == 'Waiting for Payment' && isAdmin)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  // Cancel Order Button
                  Expanded(
                    flex: 1,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red[300]!, width: 1.5),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () async {
                            // Show confirmation dialog
                            final confirmed = await _showStatusChangeDialog(
                              'Cancel Order - Non Payment',
                              'Cancel order due to non-receipt of payment? Customer will receive a cancellation message.',
                              Icons.cancel,
                              Colors.red,
                            );

                            if (confirmed == true) {
                              // Update order status to "Cancelled"
                              await _updateOrderStatus('Cancelled');

                              // Send payment cancellation message to customer
                              await _sendPaymentCancellationMessageToCustomer();

                              // Go back to orders list
                              if (mounted) {
                                Navigator.of(context).pop();
                              }
                            }
                          },
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.cancel_outlined,
                                  color: Colors.red[700],
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Cancel Order',
                                  style: TextStyle(
                                    color: Colors.red[700],
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Confirm Payment Button - with original functionality
                  Expanded(
                    flex: 1,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.orange[100],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange[300]!, width: 1.5),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () async {
                            // Show confirmation dialog
                            final confirmed = await _showStatusChangeDialog(
                              'Confirm Payment',
                              'Are you sure you want to confirm payment and move this order to "Ready for Shipment"?',
                              Icons.payment,
                              Colors.orange,
                            );

                            if (confirmed == true) {
                              // Process payment and update status to "Ready for Shipment"
                              await _processPaymentAndUpdateStatus();

                              // Send WhatsApp payment confirmation receipt to customer
                              await _sendPaymentConfirmationReceipt();

                              // Navigate to ready shipment screen
                              if (mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const ReadyShipmentOrdersScreen(),
                                  ),
                                );
                              }
                            }
                          },
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.payment,
                                  color: Colors.orange[700],
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Confirm Payment',
                                  style: TextStyle(
                                    color: Colors.orange[700],
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Warning message for all unavailable items
          if (_areAllItemsUnavailable() && order!['order_status'] == 'Pending')
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_outlined,
                    color: Colors.red[700],
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'All items are unavailable. Clicking "Cancel Order" will cancel this order and send a short message to the customer.',
                      style: TextStyle(
                        color: Colors.red[700],
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Confirm Order Button - Only for Pending orders (admin only)
          if (order!['order_status'] == 'Pending' && isAdmin)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 12),
              child: GestureDetector(
                onTap: () async {
                  // Check if all items are unavailable
                  final allUnavailable = _areAllItemsUnavailable();
                  print('🔍 All items unavailable: $allUnavailable');

                  if (allUnavailable) {
                    // All items are unavailable - cancel the order
                    final confirmed = await _showStatusChangeDialog(
                      'Cancel Order (All Items Unavailable)',
                      'All items are unavailable. Order will be cancelled and customer will receive a short cancellation message.',
                      Icons.cancel,
                      Colors.red,
                    );

                    if (confirmed == true) {
                      // Update order status to "Cancelled"
                      await _updateOrderStatus('Cancelled');
                      
                      // Send special cancellation message for all unavailable items
                      await _sendAllUnavailableCancellationMessage();
                      
                      // Go back to orders list
                      if (mounted) {
                        Navigator.of(context).pop();
                      }
                    }
                  } else {
                    // Normal confirmation flow
                    final confirmed = await _showStatusChangeDialog(
                      'Move to Waiting for Payment',
                      'Are you sure you want to move this order to "Waiting for Payment"?',
                      Icons.arrow_forward,
                      Colors.green,
                    );

                    if (confirmed == true) {
                      // Update order status to "Waiting for Payment"
                      await _updateOrderStatus('Waiting for Payment');

                      // Send WhatsApp order receipt to customer
                      await _sendOrderReceiptToCustomer();

                      // Navigate to waiting payment screen
                      if (mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const WaitingPaymentOrdersScreen(),
                          ),
                        );
                      }
                    }
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _areAllItemsUnavailable()
                          ? [Colors.red[300]!, Colors.red[500]!]
                          : [Colors.green[300]!, Colors.green[500]!],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: _areAllItemsUnavailable()
                            ? Colors.red.withOpacity(0.3)
                            : Colors.green.withOpacity(0.3),
                        spreadRadius: 2,
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _areAllItemsUnavailable() ? Icons.cancel : Icons.check_circle,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _areAllItemsUnavailable() ? 'Cancel Order' : 'Confirm Order',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
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

  // Edit delivery fee
  Future<void> _editDeliveryFee() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditDeliveryFeeScreen(
          orderId: widget.orderId,
          currentSubtotal: _subtotalAmount,
          currentDeliveryFee: _deliveryFee,
          currentTotal: _totalAmount,
        ),
      ),
    );

    if (result != null && result['success'] == true) {
      print('=== DELIVERY FEE UPDATE DEBUG ===');
      print('Result received: $result');
      print('New delivery fee: ${result['delivery_fee']}');
      print('New total: ${result['total']}');
      
      // Update state immediately and forcefully
      if (mounted) {
        // Update local state variables first
        final newDeliveryFee = result['delivery_fee']?.toDouble() ?? _deliveryFee;
        final newTotal = result['total']?.toDouble() ?? _totalAmount;
        
        print('=== BEFORE setState ===');
        print('Current _deliveryFee: $_deliveryFee');
        print('New delivery fee: $newDeliveryFee');
        
        // Force immediate state update
        setState(() {
          _deliveryFee = newDeliveryFee;
          _totalAmount = newTotal;
          
          // Update order object with new delivery fee
          if (order != null) {
            order!['delivery_fee'] = newDeliveryFee;
            order!['total_amount'] = newTotal;
            print('Updated order delivery_fee: ${order!['delivery_fee']}');
            print('Updated order total_amount: ${order!['total_amount']}');
          }
        });
        
        print('=== AFTER setState ===');
        print('Updated _deliveryFee: $_deliveryFee');
        print('Updated _totalAmount: $_totalAmount');
      }
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delivery fee updated to ₹${_deliveryFee.toStringAsFixed(2)}'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      // Refresh from server to ensure database sync (after a short delay)
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        await _fetchOrderDetails(silent: true);
      }
      
      print('Delivery fee update completed with immediate UI refresh');
    } else {
      print('=== DELIVERY FEE UPDATE FAILED ===');
      print('Result: $result');
    }
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

    // Check if all items are unavailable
    bool allItemsUnavailable = orderItems.every((item) => 
      _itemAvailability[item['id'].toString()] == 'Not Available'
    );

    // Create structured order details message
    String shareMessage = _createStructuredShareMessage();

    try {
      // Copy message to clipboard first
      await Clipboard.setData(ClipboardData(text: shareMessage));

      if (allItemsUnavailable) {
        // For all unavailable items, send simple WhatsApp message
        await _sendUnavailableWhatsAppMessage(customerPhone, shareMessage);
      } else {
        // For available items, share with QR code image
        _shareWithQRCode(shareMessage, customerPhone);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error preparing share: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Send WhatsApp message for unavailable items
  Future<void> _sendUnavailableWhatsAppMessage(String customerPhone, String message) async {
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

      // Send via WhatsApp API using wa.me link
      String encodedText = Uri.encodeComponent(message);
      String whatsappUrl = "https://wa.me/$formattedPhone?text=$encodedText";
      
      print('📱 Sending unavailable message to phone: $formattedPhone');
      print('📱 WhatsApp URL: $whatsappUrl');
      
      // Log the message
      await _logWhatsAppMessage(widget.orderId, customerPhone, message);
      
      // Open WhatsApp
      if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
        await launchUrl(Uri.parse(whatsappUrl));
      } else {
        throw 'Could not launch $whatsappUrl';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WhatsApp message sent successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error sending unavailable message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending message: ${e.toString()}'),
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

    print('=== CREATING WHATSAPP MESSAGE ===');
    print('TEST: This function is being called!');
    print('Order items count: ${orderItems.length}');
    print('📊 Manual Stock States:');
    for (var item in orderItems) {
      final itemId = item['id'].toString();
      print('   Item $itemId: useManualStock=${_useManualStock[itemId]}, manualStockQuantity=${_manualStockQuantities[itemId]}');
    }

    // Check if all items are unavailable
    bool allItemsUnavailable = orderItems.every((item) => 
      _itemAvailability[item['id'].toString()] == 'Not Available'
    );

    // If all items are unavailable, show simplified message
    if (allItemsUnavailable) {
      String message = '''
*Order ID:* #${widget.orderId}


We're sorry, this product is currently unavailable. Kindly choose another product or variant. Thank you for visiting BangkokMart.

📦 *Product Details:*
''';

      // Track unique products to avoid duplicates
      final Set<String> addedProducts = {};

      // Add each product with unavailable status
      for (var item in orderItems) {
        final productName = item['product_name'] ?? 'Product';
        final color = item['color']?.toString() ?? '';
        final size = item['size']?.toString() ?? '';
        final itemId = item['id'].toString();

        // Create unique key for product (name + color + size)
        final productKey = '${productName.trim()}_${color.trim()}_${size.trim()}';

        // Skip if already added
        if (addedProducts.contains(productKey)) {
          continue;
        }
        addedProducts.add(productKey);

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
   • Status: ❌ *UNAVAILABLE*
   • Image: ${imageUrl ?? 'N/A'}
''';
      }

      return message;
    }

    // Normal receipt format for available items
    String message = '''
🛒 *ORDER DETAILS* 🛒
📋 *Order Information:*
• Order ID: #${widget.orderId}
• Customer: ${order!['customer_name'] ?? 'N/A'}
• Date: ${_formatDateWithAmPm(order!['order_date'])}
━━━━━━━━━━━━━━━━━━━━━

📦 *Product Details:*
''';

    // Track unique products and sum their quantities
    final Map<String, Map<String, dynamic>> consolidatedProducts = {};

    // First, consolidate all items by product variant
    for (var item in orderItems) {
      final productName = item['product_name'] ?? 'Product';
      final color = item['color']?.toString() ?? '';
      final size = item['size']?.toString() ?? '';
      final itemId = item['id'].toString();
      final availabilityStatus = _itemAvailability[itemId] ?? 'Available';
      final isUnavailable = availabilityStatus == 'Not Available';
      final isPartial = availabilityStatus == 'Partial Available';
      
      // Create unique key for product (name + color + size)
      final productKey = '${productName.trim()}_${color.trim()}_${size.trim()}';

      if (!consolidatedProducts.containsKey(productKey)) {
        // Initialize product entry
        consolidatedProducts[productKey] = {
          'productName': productName,
          'color': color,
          'size': size,
          'price': double.tryParse(item['price'].toString()) ?? 0.0,
          'imageUrl': item['image_url'],
          'totalRequestedQuantity': 0,
          'totalManualQuantity': 0,
          'totalAvailableQuantity': 0,
          'hasManualStock': false,
          'hasUnavailable': false,
          'itemIds': [],
        };
      }

      final product = consolidatedProducts[productKey]!;
      final requestedQuantity = int.tryParse(item['quantity'].toString()) ?? 1;
      final useManualStock = _useManualStock[itemId] ?? false;
      final manualStockQuantity = _manualStockQuantities[itemId] ?? 0;
      final availableQuantity = useManualStock ? manualStockQuantity : 
          int.tryParse(item['available_quantity']?.toString() ?? requestedQuantity.toString()) ?? requestedQuantity;

      // Sum quantities
      product['totalRequestedQuantity'] += requestedQuantity;
      product['totalManualQuantity'] += manualStockQuantity;
      product['totalAvailableQuantity'] += availableQuantity;
      product['hasManualStock'] = product['hasManualStock'] || useManualStock;
      product['hasUnavailable'] = product['hasUnavailable'] || isUnavailable;
      product['itemIds'].add(itemId);
      
      print('   Consolidating item $itemId: requested=$requestedQuantity, manual=$manualStockQuantity, available=$availableQuantity, useManual=$useManualStock');
    }

    // Now create message for consolidated products
    for (var productEntry in consolidatedProducts.values) {
      final productName = productEntry['productName'] ?? 'Product';
      final color = productEntry['color']?.toString() ?? '';
      final size = productEntry['size']?.toString() ?? '';
      final itemPrice = productEntry['price'] ?? 0.0;
      final totalRequestedQuantity = productEntry['totalRequestedQuantity'] ?? 0;
      final totalManualQuantity = productEntry['totalManualQuantity'] ?? 0;
      final totalAvailableQuantity = productEntry['totalAvailableQuantity'] ?? 0;
      final hasManualStock = productEntry['hasManualStock'] ?? false;
      final hasUnavailable = productEntry['hasUnavailable'] ?? false;

      // Get image URL
      String? imageUrl;
      if (productEntry['imageUrl'] != null && productEntry['imageUrl'].toString().isNotEmpty) {
        String tempImageUrl = productEntry['imageUrl'].toString();
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

      // Add availability status with quantity information
      String statusText = '';
      String quantityInfo = '';
      String priceInfo = '';
      
      if (hasUnavailable && totalAvailableQuantity == 0) {
        statusText = '   *UNAVAILABLE*';
        quantityInfo = '   Quantity: $totalRequestedQuantity (Requested)\n';
      } else if (hasUnavailable && totalAvailableQuantity < totalRequestedQuantity) {
        statusText = '   *PARTIALLY AVAILABLE*';
        quantityInfo = '   Available: $totalAvailableQuantity of $totalRequestedQuantity\n';
        priceInfo = '   Price: ${itemPrice.toStringAsFixed(2)} (each)\n';
        priceInfo += '   Available Total: ${(itemPrice * totalAvailableQuantity).toStringAsFixed(2)}\n';
      } else {
        statusText = '   *Available*';
        // Show the actual quantity that will be charged/shipped
        final actualQuantity = hasManualStock ? totalManualQuantity : totalAvailableQuantity;
        quantityInfo = '   Quantity: $actualQuantity\n';
        priceInfo = '   Price: ${itemPrice.toStringAsFixed(2)}\n';
        if (hasManualStock) {
          quantityInfo = '   Manual Stock: $totalManualQuantity\n';
          quantityInfo += '   Requested Quantity: $totalRequestedQuantity\n';
        }
      }

      message += '''
🔸 *$productName*
$variantDetails$quantityInfo$priceInfo   • Status: $statusText
   • Image: ${imageUrl ?? 'N/A'}
''';
    }

    // Calculate totals based on consolidated products
    double sharedSubtotal = 0.0;
    
    // Calculate subtotal from consolidated products
    for (var productEntry in consolidatedProducts.values) {
      final itemPrice = productEntry['price'] ?? 0.0;
      final totalAvailableQuantity = productEntry['totalAvailableQuantity'] ?? 0;
      final hasUnavailable = productEntry['hasUnavailable'] ?? false;
      
      if (!hasUnavailable || totalAvailableQuantity > 0) {
        sharedSubtotal += itemPrice * totalAvailableQuantity;
      }
    }
    
    final subtotalAmount = sharedSubtotal;
    final deliveryFee = _deliveryFee;
    final totalAmount = sharedSubtotal + _deliveryFee;

    message += '''━━━━━━━━━━━━━━━━━━━━━

💰 *Payment Summary:*
• Subtotal: ₹${subtotalAmount.toStringAsFixed(2)}
• Delivery: ₹${deliveryFee.toStringAsFixed(2)}
• *Total Amount: ₹${totalAmount.toStringAsFixed(2)}*
━━━━━━━━━━━━━━━━━━━━━

🏠 Delivery Address:
${order!['shipping_street'] ?? 'N/A'}
${order!['shipping_city'] ?? 'N/A'}, ${order!['shipping_state'] ?? 'N/A'} - ${order!['shipping_pincode'] ?? 'N/A'}
📞 ${order!['shipping_phone'] ?? 'N/A'}

Thank you for your order! 🙏
━━━━━━━━━━━━━━━━━━━━━
💳 PAYMENT INFORMATION:

📱 Scan the QR code below to pay
🔗 ${PaymentUrlObfuscator.generateObfuscatedUrl(widget.orderId)}

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

    // Group and consolidate items (include both available and unavailable)
    final consolidatedItems = _consolidateOrderItems(includeUnavailable: true);

    String orderDetails = '''
🛒 *Order Details* 🛒

📋 *Order ID:* #${widget.orderId}
👤 *Customer Name:* ${order!['customer_name'] ?? 'N/A'}
📅 *Order Date:* ${_formatDate(order!['order_date'])}
💳 *Payment Method:* ${order!['payment_method'] ?? 'COD'}
🚚 *Order Status:* ${order!['order_status'] ?? 'Pending'}

📦 *Order Items:*
''';

    // Calculate subtotal for available items only
    double availableSubtotal = 0.0;
    
    // Add consolidated order items with proper status
    for (var item in consolidatedItems.values) {
      final itemPrice = double.tryParse(item['price'].toString()) ?? 0.0;
      final quantity = int.tryParse(item['displayQuantity'].toString()) ?? 1;
      final isUnavailable = item['isUnavailable'] == true;
      final itemTotal = itemPrice * quantity;
      
      // Only add to subtotal if item is available
      if (!isUnavailable) {
        availableSubtotal += itemTotal;
      }
      
      orderDetails += '''
• ${item['product_name'] ?? 'Product'}
  Color: ${item['color'] ?? 'N/A'}, Size: ${item['size'] ?? 'N/A'}
  Qty: $quantity × ₹${itemPrice.toStringAsFixed(2)} = ₹${itemTotal.toStringAsFixed(2)}
  Status: ${isUnavailable ? '❌ UNAVAILABLE' : '✅ Available'}
''';
    }

    // Calculate totals with delivery fee (only for available items)
    final deliveryFee = _deliveryFee;
    final totalAmount = availableSubtotal + deliveryFee;

    orderDetails += '''
🏠 *Shipping Address:*
${order!['shipping_street'] ?? 'N/A'}
${order!['shipping_city'] ?? 'N/A'}, ${order!['shipping_state'] ?? 'N/A'} - ${order!['shipping_pincode'] ?? 'N/A'}
📞 ${order!['shipping_phone'] ?? 'N/A'}

💰 *Order Summary:*
Subtotal: ₹${availableSubtotal.toStringAsFixed(2)}
Delivery Fee: ₹${deliveryFee.toStringAsFixed(2)}
*Total Amount: ₹${totalAmount.toStringAsFixed(2)}*

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

    print('🔥 === WHATSAPP SHARE STARTED ===');
    print('📊 Manual Stock States in _shareOnWhatsApp:');
    for (var item in orderItems) {
      final itemId = item['id'].toString();
      print('   Item $itemId: useManualStock=${_useManualStock[itemId]}, manualStockQuantity=${_manualStockQuantities[itemId]}');
    }

    // Check if all items are unavailable
    bool allItemsUnavailable = orderItems.every((item) => 
      _itemAvailability[item['id'].toString()] == 'Not Available'
    );

    // If all items are unavailable, send unavailable message
    if (allItemsUnavailable) {
      await _sendUnavailableMessage(null);
      return;
    }

    // Group and consolidate items with manual stock support
    final Map<String, Map<String, dynamic>> consolidatedItems = {};
    
    for (var item in orderItems) {
      final itemId = item['id'].toString();
      final productName = item['product_name'] ?? 'Product';
      final color = item['color']?.toString() ?? '';
      final size = item['size']?.toString() ?? '';
      final availabilityStatus = _itemAvailability[itemId] ?? 'Available';
      final isUnavailable = availabilityStatus == 'Not Available';
      final useManualStock = (_useManualStock[itemId] ?? false) && _showManualStockMode;
      final manualStockQuantity = _manualStockQuantities[itemId] ?? 0;
      final requestedQuantity = int.tryParse(item['quantity'].toString()) ?? 1;
      final itemPrice = double.tryParse(item['price'].toString()) ?? 0.0;
      
      print('🔍 Processing item $itemId:');
      print('   - _showManualStockMode: $_showManualStockMode');
      print('   - _useManualStock[$itemId]: ${_useManualStock[itemId]}');
      print('   - useManualStock: $useManualStock');
      print('   - manualStockQuantity: $manualStockQuantity');
      print('   - requestedQuantity: $requestedQuantity');
      
      // Create unique key for product (name + color + size)
      final productKey = '${productName.trim()}_${color.trim()}_${size.trim()}';
      
      if (!consolidatedItems.containsKey(productKey)) {
        consolidatedItems[productKey] = {
          'product_name': productName,
          'color': color,
          'size': size,
          'price': itemPrice,
          'image_url': item['image_url'],
          'isUnavailable': isUnavailable,
          'displayQuantity': 0,
          'manualQuantity': 0,
          'requestedQuantity': 0,
          'hasManualStock': false,
        };
      }
      
      final consolidatedItem = consolidatedItems[productKey]!;
      
      // Use manual quantity if enabled, otherwise use requested quantity
      int actualQuantity;
      if ((_useManualStock[itemId] ?? false) && _showManualStockMode) {
        actualQuantity = manualStockQuantity;
        consolidatedItem['hasManualStock'] = true;
        consolidatedItem['manualQuantity'] += manualStockQuantity;
      } else {
        actualQuantity = requestedQuantity;
      }
      
      consolidatedItem['displayQuantity'] += actualQuantity;
      consolidatedItem['requestedQuantity'] += requestedQuantity;
      consolidatedItem['isUnavailable'] = consolidatedItem['isUnavailable'] && isUnavailable;
    }

    print('📋 FINAL CONSOLIDATED ITEMS:');
    for (var key in consolidatedItems.keys) {
      final item = consolidatedItems[key]!;
      print('   $key: hasManualStock=${item['hasManualStock']}, displayQuantity=${item['displayQuantity']}, manualQuantity=${item['manualQuantity']}');
    }
    
    // Check if any items have manual stock enabled
    bool hasAnyManualStock = consolidatedItems.values.any((item) => item['hasManualStock'] == true);
    
    print('🔔 GLOBAL MANUAL STOCK MODE: $_showManualStockMode');
    print('🔔 HAS ANY MANUAL STOCK: $hasAnyManualStock');

    // Calculate totals for available items only
    double availableSubtotal = 0.0;
    for (var item in consolidatedItems.values) {
      if (!(item['isUnavailable'] == true)) {
        final itemPrice = item['price'] ?? 0.0;
        final quantity = int.tryParse(item['displayQuantity'].toString()) ?? 1;
        availableSubtotal += itemPrice * quantity;
      }
    }

    String orderDetails = '''
🛒 *ORDER DETAILS* 🛒
📋 *Order Information:*
• Order ID: #${widget.orderId}
• Customer: ${order!['customer_name'] ?? 'N/A'}
• Date: ${_formatDateWithAmPm(order!['order_date'])}
${hasAnyManualStock ? '🔔 *Status: Manual Stock Applied*' : ''}
━━━━━━━━━━━━━━━━━━━━━

📦 *Product Details:*
''';

    // Add consolidated order items with proper status
    for (var item in consolidatedItems.values) {
      final itemPrice = double.tryParse(item['price'].toString()) ?? 0.0;
      final quantity = int.tryParse(item['displayQuantity'].toString()) ?? 1;
      final isUnavailable = item['isUnavailable'] == true;
      final hasManualStock = item['hasManualStock'] == true;
      final manualQuantity = int.tryParse(item['manualQuantity'].toString()) ?? 0;
      final requestedQuantity = int.tryParse(item['requestedQuantity'].toString()) ?? 0;
      
      // Build quantity information with manual stock details
      String quantityInfo = '';
      String priceInfo = '';
      String statusInfo = '';
      
      if (hasManualStock) {
        // Manual stock is enabled - show detailed breakdown
        quantityInfo = '   📦 *Available Quantity: $manualQuantity*\n   📝 Requested Quantity: $requestedQuantity\n';
        
        // Calculate price based on available quantity
        final availableTotal = itemPrice * manualQuantity;
        final requestedTotal = itemPrice * requestedQuantity;
        priceInfo = '   💰 Available Total: ₹${availableTotal.toStringAsFixed(2)}\n   📋 Requested Total: ₹${requestedTotal.toStringAsFixed(2)}\n   💵 Unit Price: ₹${itemPrice.toStringAsFixed(2)}\n';
        
        // Status based on manual stock
        if (manualQuantity == 0) {
          statusInfo = '   ⚠️ Status: *OUT OF STOCK*\n';
        } else if (manualQuantity < requestedQuantity) {
          statusInfo = '   ⚡ Status: *PARTIALLY AVAILABLE*\n';
        } else {
          statusInfo = '   ✅ Status: *FULLY AVAILABLE*\n';
        }
      } else {
        // Normal stock - show regular quantity
        quantityInfo = '   📦 Quantity: $quantity\n';
        priceInfo = '   💰 Total: ₹${(itemPrice * quantity).toStringAsFixed(2)}\n   💵 Unit Price: ₹${itemPrice.toStringAsFixed(2)}\n';
        statusInfo = '   ${isUnavailable ? '⚠️ Status: *UNAVAILABLE*' : '✅ Status: *Available*'}\n';
      }
      
      orderDetails += '''
🔸 *${item['product_name'] ?? 'Product'}*
   • 🎨 Color: ${item['color'] ?? 'N/A'}
   • 📏 Size: ${item['size'] ?? 'N/A'}
$quantityInfo$priceInfo$statusInfo   🖼️ Image: ${item['image_url'] ?? 'N/A'}

''';
    }

    // Calculate totals with delivery fee (only for available items)
    final deliveryFee = _deliveryFee;
    final totalAmount = availableSubtotal + deliveryFee;
    
    String paymentSummary = '''━━━━━━━━━━━━━━━━━━━━━

💰 *Payment Summary:*''';
    
    if (hasAnyManualStock) {
      paymentSummary += '''
📋 *Based on Available Quantities:*
• Available Subtotal: ₹${availableSubtotal.toStringAsFixed(2)}
• Delivery Fee: ₹${deliveryFee.toStringAsFixed(2)}
• 💳 *Total Payable: ₹${totalAmount.toStringAsFixed(2)}*

🔔 *Note: Some items have manual stock adjustments*''';
    } else {
      paymentSummary += '''
• Subtotal: ₹${availableSubtotal.toStringAsFixed(2)}
• Delivery: ₹${deliveryFee.toStringAsFixed(2)}
• 💳 *Total Amount: ₹${totalAmount.toStringAsFixed(2)}*''';
    }
    
    paymentSummary += '''
━━━━━━━━━━━━━━━━━━━━━''';
    
    orderDetails += paymentSummary + '''

🏠 *Delivery Address:*
${order!['shipping_street'] ?? 'N/A'}
${order!['shipping_city'] ?? 'N/A'}, ${order!['shipping_state'] ?? 'N/A'} - ${order!['shipping_pincode'] ?? 'N/A'}
📞 ${order!['shipping_phone'] ?? 'N/A'}

Thank you for your order! 🙏
━━━━━━━━━━━━━━━━━━━━━
💳 *PAYMENT INFORMATION:*

📱 Scan the QR code below to pay
🔗 ${_generatePaymentUrlWithAmount()}

📲 *Click link above → See Timer & Scan QR*
⚡ *Fast & Secure Payment*''';

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
    // 1. Check if item has image_url (from order items - first priority)
    if (item['image_url'] != null && item['image_url'].toString().isNotEmpty) {
      String tempImageUrl = item['image_url'].toString();
      if (tempImageUrl.startsWith('http')) {
        imageUrl = tempImageUrl;
      } else {
        imageUrl = 'http://184.168.126.71/api/uploads/$tempImageUrl';
      }
      print('🖼️ Using item image_url: $imageUrl');
    }
    // 2. Check if order has image_url (fallback)
    else if (order?['image_url'] != null && order!['image_url'].toString().isNotEmpty) {
      imageUrl = order!['image_url'];
      print('🖼️ Using order image_url: $imageUrl');
    }
    // 3. Try additional image fields
    else if (item['product_image'] != null && item['product_image'].toString().isNotEmpty) {
      String tempImageUrl = item['product_image'].toString();
      if (tempImageUrl.startsWith('http')) {
        imageUrl = tempImageUrl;
      } else {
        imageUrl = 'http://184.168.126.71/api/uploads/$tempImageUrl';
      }
      print('🖼️ Using item product_image: $imageUrl');
    }
    else if (item['imageUrl'] != null && item['imageUrl'].toString().isNotEmpty) {
      String tempImageUrl = item['imageUrl'].toString();
      if (tempImageUrl.startsWith('http')) {
        imageUrl = tempImageUrl;
      } else {
        imageUrl = 'http://184.168.126.71/api/uploads/$tempImageUrl';
      }
      print('🖼️ Using item imageUrl: $imageUrl');
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

  // Show confirmation dialog for status changes
  Future<bool?> _showStatusChangeDialog(String title, String message, IconData icon, Color color) async {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.grey[600],
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  // Update order status function
  Future<void> _updateOrderStatus(String newStatus) async {
    try {
      // Store old status before updating
      final oldStatus = order?['order_status'] ?? '';
      
      final response = await http.put(
        Uri.parse('${Config.baseNodeApiUrl}/orders/${widget.orderId}/status'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'order_status': newStatus,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success']) {
          // Call callback to notify dashboard of status change
          if (widget.onOrderStatusChanged != null && oldStatus != newStatus) {
            widget.onOrderStatusChanged!(oldStatus, newStatus);
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Order status updated to $newStatus'),
              backgroundColor: Colors.green,
            ),
          );
          // Refresh order details
          _fetchOrderDetails(silent: false);
        } else {
          setState(() {
            errorMessage = responseData['message'] ?? 'Failed to update order status';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = 'Failed to update order status (Status: ${response.statusCode})';
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error updating order status: $e');
      setState(() {
        errorMessage = 'Error: ${e.toString()}';
        isLoading = false;
      });
    }
  }

  // Send WhatsApp payment confirmation receipt to customer
  Future<void> _sendPaymentConfirmationReceipt() async {
    try {
      final customerPhone = order!['customer_phone'] ?? order!['shipping_phone'];
      
      if (customerPhone != null && customerPhone != 'N/A') {
        // Format phone number
        String formattedPhone = customerPhone.replaceAll(RegExp(r'\D'), '');
        if (formattedPhone.length == 10) {
          formattedPhone = '91$formattedPhone';
        } else if (formattedPhone.length == 11 && formattedPhone.startsWith('0')) {
          formattedPhone = '91${formattedPhone.substring(1)}';
        }

        // Format order date
        DateTime orderDate;
        try {
          orderDate = order!['order_date'] != null 
              ? DateTime.parse(order!['order_date'])
              : DateTime.now();
        } catch (e) {
          orderDate = DateTime.now();
        }
        final formattedDate = '${orderDate.day}/${orderDate.month}/${orderDate.year} at ${orderDate.hour}:${orderDate.minute.toString().padLeft(2, '0')} ${orderDate.hour >= 12 ? 'PM' : 'AM'}';

        // Build product details string with consolidation
        String productDetails = '';
        double availableSubtotal = 0.0;
        
        try {
          // Group and consolidate items (include both available and unavailable)
          final consolidatedItems = _consolidateOrderItems(includeUnavailable: true);

          // Calculate totals for available items only
          for (var item in consolidatedItems.values) {
            if (!(item['isUnavailable'] == true)) {
              final itemPrice = double.tryParse(item['price'].toString()) ?? 0.0;
              final quantity = int.tryParse(item['quantity'].toString()) ?? 1;
              availableSubtotal += itemPrice * quantity;
            }
          }

          // Build product details from consolidated items
          for (var item in consolidatedItems.values) {
            if (item != null) {
              final isUnavailable = item['isUnavailable'] == true;
              final itemPrice = double.tryParse(item['price'].toString()) ?? 0.0;
              
              productDetails += '🔸 *${item['product_name'] ?? 'Product'}*\n';
              productDetails += '   • Color: ${item['color'] ?? 'N/A'}\n';
              productDetails += '   • Size: ${item['size'] ?? 'N/A'}\n';
              productDetails += '   • Quantity: ${item['quantity'] ?? 1}\n';
              if (isUnavailable) {
                productDetails += '   • Status: ❌ *UNAVAILABLE*\n';
              } else {
                productDetails += '   • Price: ₹${itemPrice.toStringAsFixed(2)}\n';
                productDetails += '   • Status: ✅ *Available*\n';
              }
              if (item['image_url'] != null && item['image_url'].toString().isNotEmpty) {
                productDetails += '   • Image: ${item['image_url']}\n';
              }
              productDetails += '\n';
            }
          }
          
          // If no available items, add message
          bool hasAvailableItems = consolidatedItems.values.any((item) => !(item['isUnavailable'] == true));
          if (!hasAvailableItems) {
            productDetails = 'No available items in this order.\n';
          }
        } catch (e) {
          print('Error building product details: $e');
          productDetails = '• Product details unavailable\n';
        }

        // Calculate totals (use available items subtotal)
        final subtotal = availableSubtotal;
        final deliveryFee = _deliveryFee;
        final totalAmount = subtotal + deliveryFee;

        // Create complete payment confirmation message with order details
        final message = '''✅ *PAYMENT CONFIRMED* ✅

🎉 Thank you for your payment!

📋 *Order Information:*
• Order ID: #${widget.orderId}
• Date: ${formattedDate}
• Status: Ready for Shipment
━━━━━━━━━━━━━━━━━━━━━

📦 *Product Details:*
${productDetails}
━━━━━━━━━━━━━━━━━━━━━

💰 *Payment Summary:*
• Subtotal: ₹${subtotal.toStringAsFixed(2)}
• Delivery: ₹${deliveryFee.toStringAsFixed(2)}
• *Total Amount: ₹${totalAmount.toStringAsFixed(2)}*
━━━━━━━━━━━━━━━━━━━━━

🏠 Delivery Address:
${order!['shipping_street'] ?? 'N/A'}
${(order!['shipping_city'] ?? '') + ', ' + (order!['shipping_state'] ?? '') + ' - ' + (order!['shipping_pincode'] ?? 'N/A')}
📞 ${customerPhone}

Thank you for your order! 🙏
━━━━━━━━━━━━━━━━━━━━━
💳 PAYMENT CONFIRMED:

✅ *Payment Successfully Received*
• Amount: ₹${totalAmount.toStringAsFixed(2)}
• Date: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}
• Status: ✅ CONFIRMED

🚚 *Shipping Information:*
Your order is now being prepared for shipment.
You will receive tracking details once shipped.

📞 *Need Help?*
Contact us for any order-related queries.

Thank you for choosing BangkokMart! 🙏
━━━━━━━━━━━━━━━━━━━━━''';

        // Log WhatsApp message
        await http.post(
          Uri.parse('https://node-api.bangkokmart.in/api/whatsapp/log-message'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: json.encode({
            'order_id': widget.orderId,
            'phone_number': customerPhone,
            'message': message,
            'sent_at': DateTime.now().toIso8601String(),
            'message_type': 'payment_confirmation_with_details'
          }),
        );

        print('WhatsApp payment confirmation with order details sent to $formattedPhone for order ${widget.orderId}');
      }
    } catch (error) {
      print('Error sending WhatsApp payment confirmation: $error');
      // Don't fail the process if WhatsApp fails
    }
  }

  // Process payment and update status
  Future<void> _processPaymentAndUpdateStatus() async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Processing payment...'),
            ],
          ),
        ),
      );

      // Update order status to "Ready for Shipment"
      final response = await http.put(
        Uri.parse('${Config.baseNodeApiUrl}/orders/${widget.orderId}/status'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'order_status': 'Ready for Shipment',
          'payment_status': 'Paid',
        }),
      );

      // Close loading dialog
      Navigator.pop(context);

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success']) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment confirmed! Order is ready for shipment.'),
              backgroundColor: Colors.green,
            ),
          );
          // Refresh order details
          _fetchOrderDetails(silent: false);
        }
      }
    } catch (e) {
      // Close loading dialog if open
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error processing payment: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Send WhatsApp order receipt to customer
  Future<void> _sendOrderReceiptToCustomer() async {
    try {
      final customerPhone = order!['customer_phone'] ?? order!['shipping_phone'];
      
      if (customerPhone != null && customerPhone != 'N/A') {
        // Format phone number
        String formattedPhone = customerPhone.replaceAll(RegExp(r'\D'), '');
        if (formattedPhone.length == 10) {
          formattedPhone = '91$formattedPhone';
        } else if (formattedPhone.length == 11 && formattedPhone.startsWith('0')) {
          formattedPhone = '91${formattedPhone.substring(1)}';
        }

        // Format order date
        DateTime orderDate;
        try {
          orderDate = order!['order_date'] != null 
              ? DateTime.parse(order!['order_date'])
              : DateTime.now();
        } catch (e) {
          orderDate = DateTime.now();
        }
        final formattedDate = '${orderDate.day}/${orderDate.month}/${orderDate.year} at ${orderDate.hour}:${orderDate.minute.toString().padLeft(2, '0')} ${orderDate.hour >= 12 ? 'PM' : 'AM'}';

        // Check if all items are unavailable
        bool allItemsUnavailable = orderItems.every((item) => 
          _itemAvailability[item['id'].toString()] == 'Not Available'
        );

        // If all items are unavailable, send unavailable message
        if (allItemsUnavailable) {
          await _sendUnavailableMessage(null);
          return;
        }

        // Build product details string with consolidation
        String productDetails = '';
        double availableSubtotal = 0.0;
        
        try {
          // Group and consolidate items (include both available and unavailable)
          final consolidatedItems = _consolidateOrderItems(includeUnavailable: true);

          // Calculate totals for available items only
          for (var item in consolidatedItems.values) {
            if (!(item['isUnavailable'] == true)) {
              final itemPrice = double.tryParse(item['price'].toString()) ?? 0.0;
              final quantity = int.tryParse(item['quantity'].toString()) ?? 1;
              availableSubtotal += itemPrice * quantity;
            }
          }

          // Build product details from consolidated items
          for (var item in consolidatedItems.values) {
            if (item != null) {
              final isUnavailable = item['isUnavailable'] == true;
              final itemPrice = double.tryParse(item['price'].toString()) ?? 0.0;
              
              productDetails += '🔸 *${item['product_name'] ?? 'Product'}*\n';
              productDetails += '   • Color: ${item['color'] ?? 'N/A'}\n';
              productDetails += '   • Size: ${item['size'] ?? 'N/A'}\n';
              productDetails += '   • Quantity: ${item['quantity'] ?? 1}\n';
              if (isUnavailable) {
                productDetails += '   • Status: ❌ *UNAVAILABLE*\n';
              } else {
                productDetails += '   • Price: ₹${itemPrice.toStringAsFixed(2)}\n';
                productDetails += '   • Status: ✅ *Available*\n';
              }
              if (item['image_url'] != null && item['image_url'].toString().isNotEmpty) {
                productDetails += '   • Image: ${item['image_url']}\n';
              }
              productDetails += '\n';
            }
          }
          
          // If no available items, add message
          bool hasAvailableItems = consolidatedItems.values.any((item) => !(item['isUnavailable'] == true));
          if (!hasAvailableItems) {
            productDetails = 'No available items in this order.\n';
          }
        } catch (e) {
          print('Error building product details: $e');
          productDetails = '• Product details unavailable\n';
        }

        // Calculate totals (use available items subtotal)
        final subtotal = availableSubtotal;
        final deliveryFee = _deliveryFee;
        final totalAmount = subtotal + deliveryFee;

        // Create complete order receipt message
        final message = '''🛒 *ORDER DETAILS* 🛒
📋 *Order Information:*
• Order ID: #${widget.orderId}
• Customer: ${order!['customer_name'] ?? 'N/A'}
• Date: $formattedDate
━━━━━━━━━━━━━━━━━━━━━

📦 *Product Details:*
$productDetails
━━━━━━━━━━━━━━━━━━━━━

💰 *Payment Summary:*
• Subtotal: ₹${subtotal.toStringAsFixed(2)}
• Delivery: ₹${deliveryFee.toStringAsFixed(2)}
• *Total Amount: ₹${totalAmount.toStringAsFixed(2)}*
━━━━━━━━━━━━━━━━━━━━━

🏠 Delivery Address:
${order!['shipping_street'] ?? 'N/A'}
${(order!['shipping_city'] ?? '') + ', ' + (order!['shipping_state'] ?? '') + ' - ' + (order!['shipping_pincode'] ?? 'N/A')}
📞 $customerPhone

Thank you for your order! 🙏
━━━━━━━━━━━━━━━━━━━━━
💳 *PAYMENT INFORMATION:*

📱 Scan the QR code below to pay
🔗 ${_generatePaymentUrlWithAmount()}

📲 *Click link above → See Timer & Scan QR*
⚡ *Fast & Secure Payment*''';

        // Send WhatsApp message directly
        await _sendWhatsAppMessage(formattedPhone, message);
        
        print('WhatsApp order receipt sent to $formattedPhone for order ${widget.orderId}');
      }
    } catch (error) {
      print('Error sending WhatsApp order receipt: $error');
      // Don't fail the process if WhatsApp fails
    }
  }

  // Send WhatsApp message
  Future<void> _sendWhatsAppMessage(String phoneNumber, String message) async {
    try {
      // Create WhatsApp deep link
      final whatsappUrl = 'https://wa.me/$phoneNumber?text=${Uri.encodeComponent(message)}';
      
      // Try to open WhatsApp
      if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
        await launchUrl(
          Uri.parse(whatsappUrl),
          mode: LaunchMode.externalApplication,
        );
        print('WhatsApp opened successfully for $phoneNumber');
      } else {
        // Fallback: copy message to clipboard and show instructions
        await Clipboard.setData(ClipboardData(text: message));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Message copied to clipboard. Please send it to $phoneNumber manually.'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Open WhatsApp',
              onPressed: () async {
                final fallbackUrl = 'https://wa.me/$phoneNumber';
                if (await canLaunchUrl(Uri.parse(fallbackUrl))) {
                  await launchUrl(
                    Uri.parse(fallbackUrl),
                    mode: LaunchMode.externalApplication,
                  );
                }
              },
            ),
          ),
        );
        print('Could not open WhatsApp, message copied to clipboard');
      }
    } catch (e) {
      print('Error sending WhatsApp message: $e');
      // Show manual send option
      await Clipboard.setData(ClipboardData(text: message));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please send this message to $phoneNumber manually (copied to clipboard)'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // Generate payment URL with amount for available items only
  String _generatePaymentUrlWithAmount() {
    // Calculate available items total
    double availableSubtotal = 0.0;
    for (var item in orderItems) {
      final itemId = item['id'].toString();
      final isUnavailable = _itemAvailability[itemId] == 'Not Available';
      
      if (!isUnavailable) {
        final itemPrice = double.tryParse(item['price'].toString()) ?? 0.0;
        final quantity = int.tryParse(item['quantity'].toString()) ?? 1;
        availableSubtotal += itemPrice * quantity;
      }
    }
    
    final totalAmount = availableSubtotal + _deliveryFee;
    
    // Generate obfuscated URL without amount parameter
    // Amount will be shown when user clicks the link
    String obfuscatedToken = _generateObfuscatedOrderId(widget.orderId);
    return 'https://node-api.bangkokmart.in/api/whatsapp/payment-qr/$obfuscatedToken';
  }

  // Generate obfuscated order ID for payment QR link
  String _generateObfuscatedOrderId(int orderId) {
    // Create a base string with order ID, timestamp, and random elements
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    String baseString = '${orderId}_$timestamp';
    
    // Add random characters for obfuscation
    for (int i = 0; i < 8; i++) {
      baseString += '_${(1000 + (orderId * 7) + i * 13) % 10000}';
    }
    
    // Encode to base64 to make it non-obvious
    List<int> bytes = baseString.codeUnits;
    String encoded = base64.encode(bytes);
    
    // Make it URL-safe and remove padding
    encoded = encoded.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
    
    // Take only first 12 characters to keep it short but still unique
    String obfuscatedId = encoded.substring(0, 12);
    
    print('🔐 Order ID $orderId obfuscated to: $obfuscatedId');
    return obfuscatedId;
  }

  // Auto-refresh methods
  void _startAutoRefresh() {
    if (_isAutoRefreshEnabled) {
      _refreshTimer = Timer.periodic(Duration(seconds: _refreshInterval), (timer) {
        if (mounted && !_isRefreshing) {
          _refreshDataSilently();
        }
      });
    }
  }

  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
  }

  void _toggleAutoRefresh() {
    setState(() {
      _isAutoRefreshEnabled = !_isAutoRefreshEnabled;
    });
    
    if (_isAutoRefreshEnabled) {
      _startAutoRefresh();
    } else {
      _stopAutoRefresh();
    }
  }

  Future<void> _refreshDataSilently() async {
    setState(() {
      _isRefreshing = true;
      _lastRefreshTime = DateTime.now();
    });

    try {
      await _fetchOrderDetails(silent: true);
    } catch (e) {
      print('Silent refresh error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.grey;
      case 'waiting for payment':
        return Colors.orange;
      case 'ready for shipment':
        return Colors.blue;
      case 'shipped':
        return Colors.purple;
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

  // Helper method to get availability status color
  Color _getAvailabilityStatusColor(String status) {
    switch (status) {
      case 'Not Available':
        return Colors.red[700]!;
      case 'Partial Available':
        return Colors.orange[700]!;
      case 'Available':
      default:
        return Colors.green[700]!;
    }
  }
  
  // Show quantity edit dialog
  Future<void> _showQuantityEditDialog(dynamic item, int currentQuantity, double itemPrice) async {
    // Store item data to avoid scope issues
    final String itemId = item['id'].toString();
    final String productName = item['product_name'] ?? 'Unknown Product';
    final String? itemColor = item['color'];
    final String? itemSize = item['size'];
    
    final TextEditingController _quantityController = TextEditingController(text: currentQuantity.toString());
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Edit Quantity'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Product: $productName'),
              const SizedBox(height: 8),
              if (itemColor != null && itemColor.isNotEmpty)
                Text('Color: $itemColor'),
              if (itemSize != null && itemSize.isNotEmpty)
                Text('Size: $itemSize'),
              const SizedBox(height: 16),
              TextField(
                controller: _quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'New Quantity',
                  border: OutlineInputBorder(),
                  prefixText: 'Qty: ',
                ),
                onChanged: (value) {
                  // Allow only positive numbers
                  if (value.isNotEmpty && int.tryParse(value) == null) {
                    _quantityController.text = currentQuantity.toString();
                    _quantityController.selection = TextSelection.fromPosition(
                      TextPosition(offset: _quantityController.text.length),
                    );
                  }
                },
              ),
              const SizedBox(height: 8),
              Text(
                'New Total: Rs.${itemPrice * (int.tryParse(_quantityController.text) ?? currentQuantity)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange[300]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.orange[700],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Note: Editing quantity will enable manual stock mode and update availability automatically',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newQuantity = int.tryParse(_quantityController.text);
                
                if (newQuantity != null && newQuantity > 0) {
                  try {
                    // Update the quantity in the database
                    await _updateItemQuantity(itemId, newQuantity);
                    
                    Navigator.of(context).pop();
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Quantity updated successfully! Manual stock mode enabled.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid quantity'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Update'),
            ),
          ],
        );
      },
    );
  }

  // Update item quantity on server
  Future<void> _updateItemQuantity(String itemId, int newQuantity) async {
    try {
      // Enable manual stock mode when quantity is edited
      setState(() {
        _useManualStock[itemId] = true;
        _manualStockQuantities[itemId] = newQuantity;
        
        // Update availability status based on new quantity
        final requestedQuantity = int.tryParse(orderItems.firstWhere((item) => item['id'].toString() == itemId)['quantity'].toString()) ?? 1;
        if (newQuantity == 0) {
          _itemAvailability[itemId] = 'Not Available';
        } else if (newQuantity < requestedQuantity) {
          _itemAvailability[itemId] = 'Partial Available';
        } else {
          _itemAvailability[itemId] = 'Available';
        }
      });

      final response = await http.post(
        Uri.parse('${Config.baseNodeApiUrl}/orders/update-manual-stock'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'orderId': widget.orderId,
          'itemId': itemId,
          'manualStockQuantity': newQuantity,
          'useManualStock': true,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          print('Quantity updated successfully for item $itemId to $newQuantity (manual stock enabled)');
          
          // Update the order items locally to reflect the change
          setState(() {
            // Find and update the specific item in orderItems
            for (var item in orderItems) {
              if (item['id'].toString() == itemId) {
                item['quantity'] = newQuantity.toString();
                item['manual_stock_quantity'] = newQuantity.toString();
                item['use_manual_stock'] = true;
                item['available_quantity'] = newQuantity.toString();
                break;
              }
            }
            
            // Stop auto-refresh when manual stock is enabled
            _stopAutoRefresh();
            _isAutoRefreshEnabled = false;
            _showManualStockMode = true;
            
            // Recalculate totals after update
            _recalculateTotals();
          });
        } else {
          print('Failed to update quantity: ${responseData['message']}');
        }
      } else {
        print('HTTP error updating quantity: ${response.statusCode}');
      }
    } catch (e) {
      print('Error updating quantity: $e');
    }
  }
}
