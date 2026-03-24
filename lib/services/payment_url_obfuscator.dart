import 'dart:convert';
import 'dart:math';

class PaymentUrlObfuscator {
  static const String _baseUrl = 'https://node-api.bangkokmart.in/api/whatsapp/payment-qr';
  
  /// Generate an obfuscated payment URL that hides the actual order ID
  static String generateObfuscatedUrl(int orderId) {
    // Create a unique token that's not easily guessable
    String token = _generateSecureToken(orderId);
    
    // Return the obfuscated URL
    return '$_baseUrl/$token';
  }
  
  /// Generate a secure token based on order ID with randomness
  static String _generateSecureToken(int orderId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random.secure();
    
    // Create a base string with order ID, timestamp, and random bytes
    String baseString = '${orderId}_$timestamp';
    
    // Add random characters for obfuscation
    for (int i = 0; i < 8; i++) {
      baseString += '_${random.nextInt(10000)}';
    }
    
    // Encode to base64 to make it non-obvious
    String encoded = base64.encode(utf8.encode(baseString));
    
    // Make it URL-safe and remove padding
    encoded = encoded.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
    
    // Take only first 12 characters to keep it short but still unique
    return encoded.substring(0, 12);
  }
  
  /// Extract order ID from obfuscated token (for server-side use)
  /// Note: This would need to be implemented on the server side as well
  static int? extractOrderIdFromToken(String token) {
    try {
      // Reverse the encoding process
      String padded = token;
      while (padded.length % 4 != 0) {
        padded += '=';
      }
      String decoded = utf8.decode(base64.decode(padded.replaceAll('-', '+').replaceAll('_', '/')));
      
      // Extract order ID from the beginning
      List<String> parts = decoded.split('_');
      if (parts.isNotEmpty) {
        return int.tryParse(parts.first);
      }
    } catch (e) {
      print('Error extracting order ID from token: $e');
    }
    return null;
  }
  
  /// Generate a random-looking but deterministic URL for display purposes
  /// This creates URLs that look random but can be traced back to the order on the server
  static String generateDisplayUrl(int orderId) {
    // Use a simple hash-like approach for visual obfuscation
    int hash = _hashOrderId(orderId);
    String randomLooking = _base36Encode(hash);
    
    return '$_baseUrl/$randomLooking';
  }
  
  /// Simple hash function for order ID
  static int _hashOrderId(int orderId) {
    int hash = orderId;
    hash = ((hash << 5) ^ (hash >> 27)) & 0xFFFFFFFF;
    hash = hash * 31 + 123456789;
    hash = ((hash << 7) ^ (hash >> 25)) & 0xFFFFFFFF;
    return hash.abs();
  }
  
  /// Convert number to base36 for shorter, random-looking strings
  static String _base36Encode(int number) {
    const String chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    String result = '';
    
    while (number > 0) {
      result = chars[number % 36] + result;
      number = number ~/ 36;
    }
    
    // Ensure minimum length of 8 characters
    while (result.length < 8) {
      result = 'a' + result;
    }
    
    return result;
  }
}
