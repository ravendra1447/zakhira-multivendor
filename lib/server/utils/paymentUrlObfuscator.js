const crypto = require('crypto');

class PaymentUrlObfuscator {
  /**
   * Generate an obfuscated payment URL that hides the actual order ID
   * This matches the frontend implementation
   */
  static generateObfuscatedUrl(orderId) {
    const timestamp = Date.now();
    
    // Create a base string with order ID, timestamp, and random bytes
    let baseString = `${orderId}_${timestamp}`;
    
    // Add random characters for obfuscation
    for (let i = 0; i < 8; i++) {
      baseString += `_${Math.floor(Math.random() * 10000)}`;
    }
    
    // Encode to base64 to make it non-obvious
    let encoded = Buffer.from(baseString).toString('base64');
    
    // Make it URL-safe and remove padding
    encoded = encoded.replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
    
    // Take only first 12 characters to keep it short but still unique
    return encoded.substring(0, 12);
  }

  /**
   * Extract order ID from obfuscated token
   * This attempts to reverse the encoding process
   */
  static extractOrderIdFromToken(token) {
    try {
      // Reverse the encoding process
      let padded = token;
      while (padded.length % 4 !== 0) {
        padded += '=';
      }
      
      let decoded = Buffer.from(padded.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString();
      
      // Extract order ID from the beginning
      let parts = decoded.split('_');
      if (parts.length > 0) {
        return parseInt(parts[0]);
      }
    } catch (e) {
      console.error('Error extracting order ID from token:', e);
    }
    return null;
  }

  /**
   * Generate a random-looking but deterministic URL for display purposes
   * This creates URLs that look random but can be traced back to the order on the server
   */
  static generateDisplayUrl(orderId) {
    // Use a simple hash-like approach for visual obfuscation
    let hash = this.hashOrderId(orderId);
    let randomLooking = this.base36Encode(hash);
    
    return `https://node-api.bangkokmart.in/api/whatsapp/payment-qr/${randomLooking}`;
  }

  /**
   * Simple hash function for order ID
   */
  static hashOrderId(orderId) {
    let hash = orderId;
    hash = ((hash << 5) ^ (hash >> 27)) & 0xFFFFFFFF;
    hash = hash * 31 + 123456789;
    hash = ((hash << 7) ^ (hash >> 25)) & 0xFFFFFFFF;
    return Math.abs(hash);
  }

  /**
   * Convert number to base36 for shorter, random-looking strings
   */
  static base36Encode(number) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    let result = '';
    
    while (number > 0) {
      result = chars[number % 36] + result;
      number = Math.floor(number / 36);
    }
    
    // Ensure minimum length of 8 characters
    while (result.length < 8) {
      result = 'a' + result;
    }
    
    return result;
  }

  /**
   * Handle both direct order IDs and obfuscated tokens
   * Returns the actual order ID
   */
  static getOrderIdFromParam(param) {
    // Try to parse as direct order ID first
    const directId = parseInt(param);
    if (!isNaN(directId) && directId > 0) {
      return directId;
    }
    
    // Try to extract from obfuscated token
    const extractedId = this.extractOrderIdFromToken(param);
    if (extractedId && extractedId > 0) {
      return extractedId;
    }
    
    // If both fail, return null
    return null;
  }
}

module.exports = PaymentUrlObfuscator;
