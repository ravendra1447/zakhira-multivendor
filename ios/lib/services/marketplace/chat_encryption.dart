import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:crypto/crypto.dart';

class ChatEncryption {
  static const String _algorithm = 'aes-256-gcm';
  static const int _keyLength = 32; // 256 bits
  static const int _ivLength = 16; // 128 bits
  static const int _tagLength = 16; // 128 bits

  // Generate a cryptographically secure random encryption key for each message
  static String generateKey() {
    final random = Random.secure();
    final randomBytes = Uint8List(_keyLength);
    for (int i = 0; i < _keyLength; i++) {
      randomBytes[i] = random.nextInt(256);
    }
    return bytesToHex(randomBytes);
  }

  // Convert bytes to hex string
  static String bytesToHex(List<int> bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join('');
  }

  // Convert hex string to bytes
  static Uint8List hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  // Simple XOR-based encryption for Flutter (since crypto package doesn't have AES-GCM)
  static String encrypt(String text, String keyHex) {
    try {
      final key = hexToBytes(keyHex);
      final textBytes = utf8.encode(text);
      final encrypted = Uint8List(textBytes.length);

      for (int i = 0; i < textBytes.length; i++) {
        encrypted[i] = textBytes[i] ^ key[i % key.length];
      }

      // Add a simple hash for integrity
      final hash = sha256.convert(encrypted);
      final combined = bytesToHex(encrypted) + ':' + bytesToHex(hash.bytes);
      
      return combined;
    } catch (error) {
      print('Encryption error: $error');
      throw Exception('Failed to encrypt message');
    }
  }

  // Decrypt message content
  static String decrypt(String encryptedData, String keyHex) {
    try {
      final parts = encryptedData.split(':');
      
      if (parts.length != 2) {
        throw Exception('Invalid encrypted data format');
      }
      
      final key = hexToBytes(keyHex);
      final encrypted = hexToBytes(parts[0]);
      final expectedHash = parts[1];
      
      // Verify integrity
      final actualHash = sha256.convert(encrypted);
      if (bytesToHex(actualHash.bytes) != expectedHash) {
        throw Exception('Message integrity check failed');
      }
      
      final decrypted = Uint8List(encrypted.length);
      for (int i = 0; i < encrypted.length; i++) {
        decrypted[i] = encrypted[i] ^ key[i % key.length];
      }
      
      return utf8.decode(decrypted);
    } catch (error) {
      print('Decryption error: $error');
      throw Exception('Failed to decrypt message');
    }
  }

  // Compress and encrypt for faster transmission
  static String compressAndEncrypt(String text, String keyHex) {
    try {
      // Simple compression - replace common patterns
      String compressed = text
          .replaceAll(RegExp(r'\s+'), ' ')  // Multiple spaces to single
          .replaceAll(RegExp(r'\n+'), '¶')  // Newlines to single character
          .trim();
      
      return encrypt(compressed, keyHex);
    } catch (error) {
      print('Compression and encryption error: $error');
      throw Exception('Failed to compress and encrypt message');
    }
  }

  // Decrypt and decompress
  static String decryptAndDecompress(String encryptedData, String keyHex) {
    try {
      final decrypted = decrypt(encryptedData, keyHex);
      
      // Decompress
      String decompressed = decrypted
          .replaceAll('¶', '\n')  // Restore newlines
          .replaceAll(RegExp(r'\s+'), ' ') // Normalize spaces
          .trim();
      
      return decompressed;
    } catch (error) {
      print('Decryption and decompression error: $error');
      throw Exception('Failed to decrypt and decompress message');
    }
  }

  // Generate hash for message integrity
  static String generateHash(String content) {
    final bytes = utf8.encode(content);
    final hash = sha256.convert(bytes);
    return bytesToHex(hash.bytes);
  }

  // Verify message integrity
  static bool verifyHash(String content, String expectedHash) {
    final actualHash = generateHash(content);
    return actualHash == expectedHash;
  }

  // Generate a session key for ongoing chat
  static String generateSessionKey(String userId, String chatRoomId) {
    final combined = '$userId-$chatRoomId-${DateTime.now().millisecondsSinceEpoch}';
    return generateHash(combined).substring(0, _keyLength * 2); // Get hex string of correct length
  }
}
