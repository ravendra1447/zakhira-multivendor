import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import '../config.dart';

class WhatsAppDirectService {
  static const String _baseUrl = Config.baseNodeApiUrl;

  // Direct WhatsApp sharing with QR code via server
  static Future<Map<String, dynamic>> shareOrderWithQR({
    required int orderId,
    required String customerPhone,
    required String message,
    required String qrCodePath,
  }) async {
    try {
      // Use default QR code API (no need to send QR code from app)
      final response = await http.post(
        Uri.parse('$_baseUrl/whatsapp/send-with-default-qr'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'orderId': orderId,
          'customerPhone': customerPhone,
          'message': message,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        return responseData;
      } else {
        return {
          'success': false,
          'error': 'Server error: ${response.statusCode}'
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: $e'
      };
    }
  }

  // Generate WhatsApp deep link with image attachment
  static Future<String> generateWhatsAppLink({
    required String phone,
    required String message,
    required String imageUrl,
  }) async {
    try {
      // Create custom WhatsApp URL with image parameter
      final encodedMessage = Uri.encodeComponent(message);
      final encodedImage = Uri.encodeComponent(imageUrl);
      
      // Try multiple WhatsApp URL formats for image attachment
      final urls = [
        'https://wa.me/$phone?text=$encodedMessage&media=$encodedImage',
        'https://api.whatsapp.com/send?phone=$phone&text=$encodedMessage&attachment=$encodedImage',
        'https://wa.me/$phone?text=$encodedMessage&image=$encodedImage',
      ];
      
      // Return the first URL (most likely to work)
      return urls[0];
    } catch (e) {
      // Fallback to regular WhatsApp link
      return 'https://wa.me/$phone?text=${Uri.encodeComponent(message)}';
    }
  }
}
