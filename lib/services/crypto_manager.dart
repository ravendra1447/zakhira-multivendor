// lib/services/crypto_manager.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'dart:io';
import '../config.dart';

/// A singleton class for handling encryption across the app.
class CryptoManager {
  static final CryptoManager _instance = CryptoManager._internal();

  factory CryptoManager() {
    return _instance;
  }

  CryptoManager._internal();

  // The 32-byte key (same as PHP, hex decoded). This must match the server.
  static final Uint8List _keyBytes = _hexToBytes(
    'b1b2b3b4b5b6b7b8b9babbbcbdbebff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff00',
  );

  final _algo = AesGcm.with256bits();
  late final SecretKey _secretKey;

  Future<void> init() async {
    _secretKey = SecretKey(_keyBytes);
  }

  /// 🔒 Encrypt and Gzip compress message data.
  Future<Map<String, dynamic>> encryptAndCompress(String message) async {
    final Map<String, dynamic> messageMap = {
      "type": "text",
      "content": message,
    };
    final inner = jsonEncode(messageMap);
    final gz = gzipEncode(utf8.encode(inner));

    final nonce = _algo.newNonce();
    final secretBox = await _algo.encrypt(
      gz,
      secretKey: _secretKey,
      nonce: nonce,
    );

    final encryptedData = {
      "nonce": base64Encode(nonce),
      "ciphertext": base64Encode(secretBox.cipherText),
      "tag": base64Encode(secretBox.mac.bytes),
    };

    return {
      'type': 'encrypted',
      'content': jsonEncode(encryptedData),
    };
  }

  /// 🔒 Encrypt and Gzip compress media payload (URL + thumbnail)
  Future<Map<String, dynamic>> encryptMediaPayload(String mediaUrl, String? thumbnailBase64) async {
    final Map<String, dynamic> mediaMap = {
      "type": "media",
      "content": mediaUrl,
      "thumbnail": thumbnailBase64,
    };
    final inner = jsonEncode(mediaMap);
    final gz = gzipEncode(utf8.encode(inner));

    final nonce = _algo.newNonce();
    final secretBox = await _algo.encrypt(
      gz,
      secretKey: _secretKey,
      nonce: nonce,
    );

    final encryptedData = {
      "nonce": base64Encode(nonce),
      "ciphertext": base64Encode(secretBox.cipherText),
      "tag": base64Encode(secretBox.mac.bytes),
    };

    return {
      'type': 'encrypted_media',
      'content': jsonEncode(encryptedData),
    };
  }

  /// 🔓 FIXED: Extract ONLY content from decrypted data
  Future<String> extractMessageContent(String encryptedData) async {
    try {
      print("🔍 Extracting content from encrypted data");

      // First try to decrypt properly
      final decryptedResult = await decryptAndDecompress(encryptedData);

      print("🔍 Decrypted Result: $decryptedResult");

      // ✅ FIXED: Properly extract content from the decrypted JSON
      if (decryptedResult.containsKey('content')) {
        final content = decryptedResult['content']?.toString() ?? '';

        // ✅ CHECK: If content is still JSON, parse it again
        if (content.startsWith('{') && content.contains('"content"')) {
          try {
            final nestedJson = jsonDecode(content);
            if (nestedJson.containsKey('content')) {
              final nestedContent = nestedJson['content']?.toString() ?? '';
              print("✅ Extracted nested content: $nestedContent");
              return nestedContent;
            }
          } catch (e) {
            print("❌ Nested JSON parse failed, using original content");
          }
        }

        print("✅ Extracted content: $content");
        return content;
      }

      // If no content found, return the decrypted result as string
      return decryptedResult.toString();

    } catch (e) {
      print("❌ Content extraction failed: $e");
      return "[Message]"; // Return generic message on error
    }
  }

  /// 🔓 FIXED: Handle media message decryption with proper content extraction
  Future<Map<String, dynamic>> decryptMediaMessage(String encryptedMediaData) async {
    try {
      print("🎯 Starting media-specific decryption");

      Map<String, dynamic> encryptedPayload;

      if (encryptedMediaData.startsWith('{')) {
        encryptedPayload = jsonDecode(encryptedMediaData);
      } else {
        try {
          final decoded = utf8.decode(base64Decode(encryptedMediaData));
          encryptedPayload = jsonDecode(decoded);
        } catch (e) {
          encryptedPayload = jsonDecode(encryptedMediaData);
        }
      }

      if (!encryptedPayload.containsKey('nonce') ||
          !encryptedPayload.containsKey('ciphertext') ||
          !encryptedPayload.containsKey('tag')) {
        throw Exception("Invalid media encryption format");
      }

      final nonce = base64Decode(encryptedPayload['nonce']);
      final ciphertext = base64Decode(encryptedPayload['ciphertext']);
      final tag = base64Decode(encryptedPayload['tag']);

      final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(tag));
      final decrypted = await _algo.decrypt(secretBox, secretKey: _secretKey);

      final decompressed = gzipDecode(decrypted);
      final mediaData = jsonDecode(utf8.decode(decompressed));

      print("✅ Media decryption successful: ${mediaData['type']}");

      // ✅ FIXED: Ensure content is properly extracted
      if (mediaData.containsKey('content') && mediaData['content'] is String) {
        final content = mediaData['content'] as String;

        // If content is still JSON, parse it
        if (content.startsWith('{') && content.contains('"content"')) {
          try {
            final nestedJson = jsonDecode(content);
            if (nestedJson.containsKey('content')) {
              mediaData['content'] = nestedJson['content']?.toString() ?? '';
              print("✅ Fixed nested content in media");
            }
          } catch (e) {
            print("❌ Nested media JSON parse failed");
          }
        }
      }

      return mediaData as Map<String, dynamic>;

    } catch (e, stackTrace) {
      print("❌ Media-specific decryption failed: $e");
      print("Stack trace: $stackTrace");

      return await decryptAndDecompress(encryptedMediaData);
    }
  }

  /// 🔓 SMART DECRYPTION: Handle both text and media messages
  Future<Map<String, dynamic>> decryptAndDecompress(String encryptedString) async {
    try {
      print("🔐 Attempting to decrypt: ${encryptedString.length} chars");

      // ✅ STEP 1: Check if this is actually a plain media URL (not encrypted)
      if (_isPlainMediaUrl(encryptedString)) {
        print("🎯 Detected plain media URL, returning as media");
        return {
          "type": "media",
          "content": encryptedString,
          "thumbnail": null,
        };
      }

      // ✅ STEP 2: Check if this is the word "media" (unencrypted media indicator)
      if (encryptedString.trim() == 'media') {
        print("🎯 Detected unencrypted media indicator");
        return {
          "type": "media",
          "content": "media",
          "thumbnail": null,
        };
      }

      // ✅ STEP 3: Handle base64 encoded encrypted data
      String dataToDecrypt = encryptedString;
      if (!encryptedString.startsWith('{') && !encryptedString.startsWith('[')) {
        try {
          print("🔄 Decoding base64 encoded data");
          dataToDecrypt = utf8.decode(base64Decode(encryptedString));
        } catch (e) {
          print("❌ Base64 decode failed, treating as plain text");
          return {
            "type": "text",
            "content": encryptedString,
          };
        }
      }

      // ✅ STEP 4: Parse JSON envelope
      final envelope = jsonDecode(dataToDecrypt);

      // ✅ STEP 5: Validate encrypted data structure
      if (envelope is! Map ||
          !envelope.containsKey('nonce') ||
          !envelope.containsKey('ciphertext') ||
          !envelope.containsKey('tag')) {
        print("❌ Invalid encrypted data format, returning as text");
        return {
          "type": "text",
          "content": encryptedString,
        };
      }

      // ✅ STEP 6: Perform decryption
      final nonce = base64Decode(envelope['nonce']);
      final ciphertext = base64Decode(envelope['ciphertext']);
      final tag = base64Decode(envelope['tag']);

      final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(tag));
      final decrypted = await _algo.decrypt(secretBox, secretKey: _secretKey);

      // ✅ STEP 7: Decompress and parse decrypted data
      final decompressed = gzipDecode(decrypted);
      final decodedJson = jsonDecode(utf8.decode(decompressed));

      print("✅ Successfully decrypted message type: ${decodedJson['type']}");

      // ✅ STEP 8: FIXED - Ensure clean content extraction
      if (decodedJson.containsKey('content') && decodedJson['content'] is String) {
        final content = decodedJson['content'] as String;

        // If content is still JSON, parse it recursively
        if (content.startsWith('{') && content.contains('"content"')) {
          try {
            final nestedJson = jsonDecode(content);
            if (nestedJson.containsKey('content')) {
              decodedJson['content'] = nestedJson['content']?.toString() ?? '';
              print("✅ Fixed nested JSON content");
            }
          } catch (e) {
            print("❌ Nested JSON parse failed, keeping original");
          }
        }
      }

      return decodedJson as Map<String, dynamic>;

    } catch (e, stackTrace) {
      print("❌ Decrypt/Decompress failed: $e");
      print("Stack trace: $stackTrace");

      // ✅ SMART FALLBACK: Analyze the original data to determine type
      if (_isMediaUrl(encryptedString)) {
        print("🎯 Fallback: Treating as media URL after decryption failure");
        return {
          "type": "media",
          "content": encryptedString,
          "thumbnail": null,
        };
      } else if (_isLikelyPlainText(encryptedString)) {
        print("🎯 Fallback: Treating as plain text after decryption failure");
        return {
          "type": "text",
          "content": encryptedString,
        };
      } else {
        print("🎯 Fallback: Unknown data type, returning error message");
        return {
          "type": "text",
          "content": "[Message]"
        };
      }
    }
  }

  /// 🔒 Encrypt and Gzip compress a byte array.
  Future<Map<String, dynamic>> encryptAndCompressBytes(Uint8List bytes) async {
    final compressedBytes = gzipEncode(bytes);
    final nonce = _algo.newNonce();
    final secretBox = await _algo.encrypt(
      compressedBytes,
      secretKey: _secretKey,
      nonce: nonce,
    );

    final encryptedData = {
      "nonce": base64Encode(nonce),
      "ciphertext": base64Encode(secretBox.cipherText),
      "tag": base64Encode(secretBox.mac.bytes),
    };

    return {
      'type': 'encrypted_media',
      'content': jsonEncode(encryptedData),
    };
  }

  /// 🔓 Decrypt and Gzip decompress a byte array.
  Future<Uint8List> decryptAndDecompressBytes(dynamic encryptedInput) async {
    try {
      // Step 1: Input normalize (agar String ho to UTF8 decode nahi karna)
      String jsonString;

      if (encryptedInput is Uint8List) {
        jsonString = utf8.decode(encryptedInput);
      } else if (encryptedInput is String) {
        jsonString = encryptedInput;
      } else {
        throw Exception("Invalid encrypted input type: ${encryptedInput.runtimeType}");
      }

      // Step 2: JSON parse
      final envelope = jsonDecode(jsonString);

      final nonce = base64Decode(envelope['nonce']);
      final ciphertext = base64Decode(envelope['ciphertext']);
      final tag = base64Decode(envelope['tag']);

      // Step 3: AES-GCM decrypt
      final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(tag));
      final decrypted = await _algo.decrypt(secretBox, secretKey: _secretKey);

      // Step 4: GZIP decompress
      final decompressed = gzipDecode(decrypted);

      // Step 5: Return pure bytes
      return Uint8List.fromList(decompressed);
    } catch (e) {
      print("❌ Decrypt/Decompress failed: $e");
      rethrow;
    }
  }

  // ✅ ENCRYPT THUMBNAIL: Encrypt thumbnail base64 data
  Future<Map<String, dynamic>> encryptThumbnail(String thumbnailBase64) async {
    final Map<String, dynamic> thumbnailMap = {
      "type": "thumbnail",
      "content": thumbnailBase64,
    };
    final inner = jsonEncode(thumbnailMap);
    final gz = gzipEncode(utf8.encode(inner));

    final nonce = _algo.newNonce();
    final secretBox = await _algo.encrypt(
      gz,
      secretKey: _secretKey,
      nonce: nonce,
    );

    final encryptedData = {
      "nonce": base64Encode(nonce),
      "ciphertext": base64Encode(secretBox.cipherText),
      "tag": base64Encode(secretBox.mac.bytes),
    };

    return {
      'type': 'encrypted_thumbnail',
      'content': jsonEncode(encryptedData),
    };
  }

  // ✅ DECRYPT THUMBNAIL: Decrypt thumbnail data
  Future<String?> decryptThumbnail(String encryptedThumbnail) async {
    try {
      final decryptedData = await decryptAndDecompress(encryptedThumbnail);
      if (decryptedData['type'] == 'thumbnail') {
        return decryptedData['content'] as String?;
      }
      return null;
    } catch (e) {
      print("❌ Thumbnail decryption failed: $e");
      return null;
    }
  }

  // ✅ IMPROVED: Check if string is a plain media URL (not encrypted)
  bool _isPlainMediaUrl(String data) {
    return data.startsWith('http') ||
        data.startsWith('/uploads/') ||
        data.startsWith('${Config.baseNodeApiUrl}/') ||
        data.contains('/media/file/') ||
        data.contains('.jpg') ||
        data.contains('.jpeg') ||
        data.contains('.png') ||
        data.contains('.mp4') ||
        data.contains('.mov') ||
        data.contains('.gif') ||
        data.contains('.webp');
  }

  // ✅ IMPROVED: Check if string is likely a media URL
  bool _isMediaUrl(String data) {
    return data.contains('http') ||
        data.contains('/uploads/') ||
        data.contains('/media/') ||
        data.endsWith('.jpg') ||
        data.endsWith('.jpeg') ||
        data.endsWith('.png') ||
        data.endsWith('.mp4') ||
        data.endsWith('.mov') ||
        data.endsWith('.gif') ||
        data.endsWith('.webp') ||
        data.contains('media');
  }

  // ✅ IMPROVED: Check if string is likely plain text
  bool _isLikelyPlainText(String data) {
    return data.length < 1000 &&
        !data.contains('nonce') &&
        !data.contains('ciphertext') &&
        !data.contains('tag') &&
        RegExp(r'^[a-zA-Z0-9\s.,!?@#$%^&*()_+\-=\[\]{};:"|,.<>?/~`]+$').hasMatch(data);
  }

  // gzip helpers
  List<int> gzipEncode(List<int> data) => GZipCodec(level: 6).encode(data);
  List<int> gzipDecode(List<int> data) => GZipCodec().decode(data);

  static Uint8List _hexToBytes(String hex) {
    if (hex.length % 2 != 0) {
      throw FormatException('Hex string must have an even length');
    }
    final result = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }
}