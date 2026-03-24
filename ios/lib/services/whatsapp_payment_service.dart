import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class WhatsAppPaymentService {
  static Future<void> sendWhatsAppMessage({
    required int orderId,
    required String customerPhone,
    required List<dynamic> orderItems,
    required Map<String, dynamic> orderData,
    required Function(String) onMessageSent,
    required Function(String) onError,
  }) async {
    try {
      // Format phone number - remove all non-digit characters
      String formattedPhone = customerPhone.replaceAll(RegExp(r'[^\d]'), '');
      
      // Handle different phone number formats
      if (formattedPhone.length == 10) {
        // 10-digit number (Indian), add 91 prefix
        formattedPhone = '91$formattedPhone';
      } else if (formattedPhone.length == 11 && formattedPhone.startsWith('0')) {
        // 11-digit number starting with 0, remove 0 and add 91
        formattedPhone = '91${formattedPhone.substring(1)}';
      } else if (formattedPhone.length == 12 && formattedPhone.startsWith('91')) {
        // Already has 91 prefix, use as is
        formattedPhone = formattedPhone;
      } else if (formattedPhone.length < 10) {
        throw Exception('Invalid phone number: too short');
      } else if (formattedPhone.length > 12) {
        throw Exception('Invalid phone number: too long');
      }

      // Create message
      String message = _createOrderMessage(orderId, orderItems, orderData);
      
      // Send via WhatsApp API using wa.me link
      String encodedText = Uri.encodeComponent(message);
      String whatsappUrl = "https://wa.me/$formattedPhone?text=$encodedText";
      
      print('📱 Opening WhatsApp for phone: $formattedPhone');
      print('📱 WhatsApp URL: $whatsappUrl');
      
      // Log the message for tracking
      await _logWhatsAppMessage(orderId, customerPhone, message);
      
      onMessageSent(whatsappUrl);
    } catch (e) {
      onError('Failed to send WhatsApp message: ${e.toString()}');
    }
  }

  static String createOrderMessage(int orderId, List<dynamic> orderItems, Map<String, dynamic> orderData) {
    return _createOrderMessage(orderId, orderItems, orderData);
  }

  static Future<void> logWhatsAppMessage(int orderId, String customerPhone, String message) async {
    await _logWhatsAppMessage(orderId, customerPhone, message);
  }

  static String _createOrderMessage(int orderId, List<dynamic> orderItems, Map<String, dynamic> orderData) {
    String message = '''
🛒 *Order Confirmation* 🛒

📋 *Order ID:* #$orderId
📅 *Order Date:* ${_formatDate(orderData['order_date'])}
💰 *Total Amount:* ₹${orderData['total_amount'] ?? '0'}

📦 *Order Items:*
''';

    for (var item in orderItems) {
      final itemPrice = double.tryParse(item['price'].toString()) ?? 0.0;
      final quantity = int.tryParse(item['quantity'].toString()) ?? 1;
      message += '''
• ${item['product_name'] ?? 'Product'}
  Qty: $quantity × ₹${itemPrice.toStringAsFixed(2)} = ₹${(itemPrice * quantity).toStringAsFixed(2)}
''';
    }

    message += '''

🏠 *Shipping Address:*
${orderData['shipping_street'] ?? 'N/A'}
${orderData['shipping_city'] ?? 'N/A'}, ${orderData['shipping_state'] ?? 'N/A'} - ${orderData['shipping_pincode'] ?? 'N/A'}

💳 *Payment & Timer Link:*
🔗 https://node-api.bangkokmart.in/api/whatsapp/payment-qr/$orderId

📲 *Click link above → See Timer & Scan QR*
⏰ *Please complete payment within 5 minutes to confirm your order.*

Thank you for your order! 🙏''';

    return message;
  }

  static String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateString;
    }
  }

  static Future<void> _logWhatsAppMessage(int orderId, String phoneNumber, String message) async {
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

  static Future<Map<String, dynamic>> checkPaymentStatus(int orderId) async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/orders/$orderId/payment-status'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success']) {
          return {
            'success': true,
            'payment_status': responseData['payment_status'],
            'order_status': responseData['order_status'],
            'time_elapsed': responseData['time_elapsed_minutes'],
            'is_within_5_minutes': responseData['is_within_5_minutes'],
          };
        }
      }
      
      return {'success': false, 'message': 'Failed to check payment status'};
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  static Future<Map<String, dynamic>> confirmPaymentManually({
    required int orderId,
    String? paymentMethod,
    String? transactionId,
    String? notes,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${Config.baseNodeApiUrl}/whatsapp/payment-success/$orderId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success']) {
          return {
            'success': true,
            'message': responseData['message'],
          };
        }
      }
      
      return {'success': false, 'message': 'Failed to confirm payment'};
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }
}
