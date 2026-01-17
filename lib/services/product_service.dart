import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'local_auth_service.dart';
import 'product_database_service.dart';
import '../models/product.dart';

class ProductService {
  // Base URL - Node.js Express API
  static const String baseUrl = "http://184.168.126.71:3000/api";

  /// Save Product (Draft or Publish) - FAST VERSION
  /// Saves locally first, then uploads images in background
  ///
  /// [productData] should contain:
  /// - name: String
  /// - category: String?
  /// - availableQty: String
  /// - priceSlabs: List<Map<String, dynamic>>
  /// - variations: List<Map<String, dynamic>> (color items with images)
  /// - attributes: Map<String, List<String>>
  /// - selectedAttributeValues: Map<String, String>
  /// - description: String
  /// - images: List<File>
  /// - sizes: Set<String>
  /// - status: String ('draft' or 'publish')
  static Future<Map<String, dynamic>> saveProduct({
    required Map<String, dynamic> productData,
    required List<File> images,
    required String status, // 'draft' or 'publish'
  }) async {
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        return {"success": false, "message": "User not logged in"};
      }

      print('⚡ FAST SAVE: Saving product locally first, then uploading in background...');

      // STEP 1: Save locally immediately with file paths (INSTANT)
      // Convert file paths to strings for local storage
      final List<String> imagePaths = images.map((img) => img.path).toList();
      
      // Process variations - keep file paths for now
      List<Map<String, dynamic>> processedVariations = [];
      if (productData['variations'] != null) {
        final variations = productData['variations'] as List<dynamic>;
        final stockMode = productData['stockMode'] as String? ?? 'simple';
        final stockByColorSize = productData['stockByColorSize'] as Map<String, dynamic>?;
        
        processedVariations = variations.map((variation) {
          final variationMap = Map<String, dynamic>.from(variation);
          // Keep file paths as-is for local storage
          // They will be uploaded in background
          // Include stock_mode metadata in first variation for easy retrieval
          if (variations.indexOf(variation) == 0) {
            variationMap['stock_mode'] = stockMode;
            if (stockMode == 'color_size' && stockByColorSize != null) {
              variationMap['stock_by_color_size'] = stockByColorSize;
            }
          }
          return variationMap;
        }).toList();
      }

      // Extract stock data
      final stockMode = productData['stockMode'] as String? ?? 'simple';
      final stockByColorSize = productData['stockByColorSize'] as Map<String, dynamic>?;
      
      // Convert stockByColorSize to proper format if needed
      Map<String, Map<String, int>>? stockByColorSizeTyped;
      if (stockByColorSize != null) {
        stockByColorSizeTyped = stockByColorSize.map(
          (color, sizeMap) => MapEntry(
            color.toString(),
            (sizeMap as Map<String, dynamic>).map(
              (size, qty) => MapEntry(size.toString(), (qty as num).toInt()),
            ),
          ),
        );
      }

      // Create Product model with file paths (not URLs yet)
      // Handle subcategory - ensure it's not empty string
      final subcategoryValue = productData['subcategory'];
      final subcategory = (subcategoryValue is String && subcategoryValue.trim().isNotEmpty) 
          ? subcategoryValue.trim() 
          : (subcategoryValue != null && subcategoryValue.toString().trim().isNotEmpty)
              ? subcategoryValue.toString().trim()
              : null;
      
      // Debug: Print subcategory value
      print('📦 ProductService: Saving subcategory: $subcategory');
      
      final product = Product(
        userId: userId,
        name: productData['name'] ?? '',
        category: productData['category'],
        subcategory: subcategory,
        availableQty: productData['availableQty'] ?? '0',
        description: productData['description'] ?? '',
        status: status,
        priceSlabs:
            (productData['priceSlabs'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            [],
        attributes:
            (productData['attributes'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, List<String>.from(v as List<dynamic>)),
            ) ??
            {},
        selectedAttributeValues:
            (productData['selectedAttributeValues'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v.toString())) ??
            {},
        variations: processedVariations,
        sizes: (productData['sizes'] is Set<String>)
            ? (productData['sizes'] as Set<String>).toList()
            : (productData['sizes'] is List<String>)
                ? (productData['sizes'] as List<String>)
                : [],
        images: imagePaths, // File paths for now
        marketplaceEnabled: productData['marketplaceEnabled'] == true,
        stockMode: stockMode,
        stockByColorSize: stockByColorSizeTyped,
      );

      // Save to local database IMMEDIATELY (INSTANT)
      final dbService = ProductDatabaseService();
      final localId = await dbService.saveProduct(product);
      print('✅ Product saved locally with ID: $localId');

      // STEP 2: Upload images in background (non-blocking)
      _uploadImagesInBackground(
        localId: localId,
        userId: userId,
        images: images,
        variations: processedVariations,
        dbService: dbService,
      );

      // Return success immediately
      return {
        "success": true,
        "message": "Product saved successfully. Images uploading in background...",
        "data": {"local_id": localId},
      };
    } catch (e) {
      return {"success": false, "message": "Error: ${e.toString()}"};
    }
  }

  /// Upload images in background and update product
  static void _uploadImagesInBackground({
    required int localId,
    required int userId,
    required List<File> images,
    required List<Map<String, dynamic>> variations,
    required ProductDatabaseService dbService,
  }) async {
    // Run in background (don't await)
    Future(() async {
      try {
        print('🔄 Background upload started for product $localId...');
        
        // Upload main images in parallel
        final List<String> imageUrls = [];
        if (images.isNotEmpty) {
          print('📤 Uploading ${images.length} main images in parallel (background)...');
          final uploadResults = await Future.wait(
            images.asMap().entries.map((entry) async {
              final index = entry.key;
              final image = entry.value;
              try {
                final imageUrl = await _uploadImage(image, userId);
                if (imageUrl.isNotEmpty) {
                  print('✅ Main image ${index + 1}/${images.length} uploaded');
                  return imageUrl;
                }
                return null;
              } catch (e) {
                print('❌ Error uploading main image ${index + 1}: $e');
                return null;
              }
            }),
          );
          imageUrls.addAll(uploadResults.whereType<String>());
        }

        // Upload variation images in parallel
        List<Map<String, dynamic>> processedVariations = [];
        for (var variation in variations) {
          try {
            final variationMap = Map<String, dynamic>.from(variation);
            
            // Upload main variation image
            if (variationMap['image'] != null) {
              final imageValue = variationMap['image'];
              if (imageValue is String && !imageValue.startsWith('http')) {
                final file = File(imageValue);
                if (file.existsSync()) {
                  final imageUrl = await _uploadImage(file, userId);
                  if (imageUrl.isNotEmpty) {
                    variationMap['image'] = imageUrl;
                  }
                }
              }
            }
            
            // Upload allImages
            if (variationMap['allImages'] != null) {
              final allImages = variationMap['allImages'] as List<dynamic>;
              print('📤 Uploading ${allImages.length} variation images for ${variationMap['name']} (background)...');
              
              final uploadResults = await Future.wait(
                allImages.asMap().entries.map((entry) async {
                  final index = entry.key;
                  final img = entry.value;
                  try {
                    String? imageUrl;
                    if (img is String && !img.startsWith('http')) {
                      final file = File(img);
                      if (file.existsSync()) {
                        imageUrl = await _uploadImage(file, userId);
                      }
                    } else if (img is String && img.startsWith('http')) {
                      imageUrl = img;
                    }
                    return imageUrl;
                  } catch (e) {
                    print('❌ Error uploading variation image ${index + 1}: $e');
                    return null;
                  }
                }),
              );
              
              variationMap['allImages'] = uploadResults.whereType<String>().toList();
            }
            
            processedVariations.add(variationMap);
          } catch (e) {
            print('❌ Error processing variation: $e');
          }
        }

        // Update product with uploaded URLs
        final product = await dbService.getProduct(localId);
        if (product != null) {
          final updatedProduct = product.copyWith(
            images: imageUrls,
            variations: processedVariations,
          );
          await dbService.saveProduct(updatedProduct);
          print('✅ Product $localId updated with uploaded image URLs');
          
          // Try to sync with server
          try {
            // Use stock data directly from Product model (now stored in separate fields)
            final stockMode = updatedProduct.stockMode;
            final stockByColorSize = updatedProduct.stockByColorSize;
            
            // Build variations for server (keep stock data in variations for compatibility)
            final variationsForServer = updatedProduct.variations.map((v) {
              final varMap = Map<String, dynamic>.from(v);
              // Remove metadata fields if present
              varMap.remove('stock_mode');
              varMap.remove('stock_by_color_size');
              return varMap;
            }).toList();
            
            // Debug: Print subcategory before sending to server
            final subcategoryForServer = (updatedProduct.subcategory != null && updatedProduct.subcategory!.trim().isNotEmpty) 
                ? updatedProduct.subcategory!.trim() 
                : null;
            print('📤 Sending to server - category: ${updatedProduct.category}, subcategory: $subcategoryForServer');
            
            final productPayload = {
              'user_id': userId,
              'name': updatedProduct.name,
              'category': updatedProduct.category ?? '',
              'subcategory': subcategoryForServer,
              'available_qty': updatedProduct.availableQty,
              'description': updatedProduct.description,
              'status': updatedProduct.status,
              'price_slabs': jsonEncode(updatedProduct.priceSlabs),
              'attributes': jsonEncode(updatedProduct.attributes),
              'selected_attribute_values': jsonEncode(updatedProduct.selectedAttributeValues),
              'variations': jsonEncode(variationsForServer),
              'sizes': jsonEncode(updatedProduct.sizes),
              'images': jsonEncode(updatedProduct.images),
              'stock_mode': stockMode,
              'stock_by_color_size': stockByColorSize != null ? jsonEncode(stockByColorSize) : null,
              'marketplace_enabled': updatedProduct.marketplaceEnabled ? 1 : 0,
            };

            final response = await http.post(
              Uri.parse("$baseUrl/products/save"),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode(productPayload),
            );

            final result = jsonDecode(response.body) as Map<String, dynamic>;
            if (result['success'] == true && result['data'] != null) {
              final serverId = result['data']['product_id'] as int?;
              if (serverId != null) {
                await dbService.markAsSynced(localId, serverId);
                print('✅ Product $localId synced with server (ID: $serverId)');
              }
            }
          } catch (e) {
            print('⚠️ Server sync failed (will retry later): $e');
          }
        }
        
        print('✅ Background upload completed for product $localId');
      } catch (e) {
        print('❌ Background upload error: $e');
      }
    });
  }

  /// Upload single image file using chunk upload for faster upload
  static Future<String> _uploadImage(File imageFile, int userId) async {
    try {
      final fileBytes = await imageFile.readAsBytes();
      final fileSize = fileBytes.length;
      final fileName = path.basename(imageFile.path);
      const chunkSize = 512 * 1024; // 512KB chunks
      final totalChunks = (fileSize / chunkSize).ceil();

      // For small files (< 1MB), use simple upload
      if (fileSize < 1024 * 1024) {
        return await _uploadImageSimple(imageFile, userId);
      }

      // For larger files, use chunk upload
      print(
        '📤 Uploading $fileName in $totalChunks chunks (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)...',
      );

      // Step 1: Initialize upload
      final initResponse = await http.post(
        Uri.parse("$baseUrl/products/upload-image/init"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'user_id': userId,
          'original_name': fileName,
          'total_size': fileSize,
        }),
      );

      final initResult = jsonDecode(initResponse.body) as Map<String, dynamic>;
      if (initResult['success'] != true) {
        print('Init failed, falling back to simple upload');
        return await _uploadImageSimple(imageFile, userId);
      }

      final uploadId = initResult['upload_id'] as String;

      // Step 2: Upload chunks
      for (int i = 0; i < totalChunks; i++) {
        final start = i * chunkSize;
        final end = (start + chunkSize < fileSize)
            ? start + chunkSize
            : fileSize;
        final chunkBytes = fileBytes.sublist(start, end);

        final chunkRequest = http.MultipartRequest(
          'POST',
          Uri.parse("$baseUrl/products/upload-image/chunk"),
        );
        chunkRequest.fields['upload_id'] = uploadId;
        chunkRequest.files.add(
          http.MultipartFile.fromBytes(
            'chunk',
            chunkBytes,
            filename: 'chunk_$i',
          ),
        );

        final chunkResponse = await chunkRequest.send();
        final chunkResult =
            jsonDecode(
                  await http.Response.fromStream(
                    chunkResponse,
                  ).then((r) => r.body),
                )
                as Map<String, dynamic>;

        if (chunkResult['success'] != true) {
          print('Chunk $i failed, falling back to simple upload');
          return await _uploadImageSimple(imageFile, userId);
        }

        if ((i + 1) % 5 == 0 || i == totalChunks - 1) {
          print('📦 Uploaded ${i + 1}/$totalChunks chunks');
        }
      }

      // Step 3: Finalize upload
      final finalizeResponse = await http.post(
        Uri.parse("$baseUrl/products/upload-image/finalize"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'upload_id': uploadId}),
      );

      final finalizeResult =
          jsonDecode(finalizeResponse.body) as Map<String, dynamic>;
      if (finalizeResult['success'] == true) {
        print('✅ Image uploaded successfully via chunk upload');
        return finalizeResult['image_url'] ?? '';
      }

      // Fallback to simple upload
      return await _uploadImageSimple(imageFile, userId);
    } catch (e) {
      print('Chunk upload error: $e, falling back to simple upload');
      return await _uploadImageSimple(imageFile, userId);
    }
  }

  /// Simple upload fallback
  static Future<String> _uploadImageSimple(File imageFile, int userId) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse("$baseUrl/products/upload-image"),
      );

      request.fields['user_id'] = userId.toString();
      request.files.add(
        await http.MultipartFile.fromPath(
          'image',
          imageFile.path,
          filename: path.basename(imageFile.path),
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final result = jsonDecode(response.body) as Map<String, dynamic>;

      if (result['success'] == true) {
        return result['image_url'] ?? '';
      }
      return '';
    } catch (e) {
      print('Simple image upload error: $e');
      return '';
    }
  }

  /// Get all products for current user
  static Future<Map<String, dynamic>> getProducts({
    String? status, // 'draft', 'publish', or null for all
    int? limit,
    int? offset,
    bool marketplace = false, // If true, get all users' products for marketplace
    int? user_id,
  }) async {
    try {
      final int? finalUserId = user_id ?? LocalAuthService.getUserId();


      final userId = LocalAuthService.getUserId();
      if (!marketplace && userId == null) {
        return {"success": false, "message": "User not logged in"};
      }

      final payload = {
        if (!marketplace && finalUserId != null) 'user_id': finalUserId, // ✅ CORRECT
        if (status != null) 'status': status,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
        if (marketplace) 'marketplace': true,
      };

      // ✅ CORRECT PAYLOAD BUILDING
      print('Payload: $payload');


      final response = await http.post(
        Uri.parse("$baseUrl/products/list"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {"success": false, "message": "Error: ${e.toString()}"};
    }
  }

  /// Get single product by ID
  static Future<Map<String, dynamic>> getProduct(int productId) async {
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        return {"success": false, "message": "User not logged in"};
      }

      final response = await http.post(
        Uri.parse("$baseUrl/products/get"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'user_id': userId, 'product_id': productId}),
      );

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {"success": false, "message": "Error: ${e.toString()}"};
    }
  }

  /// Update products for Instagram
  /// Sets is_insta_product = 'Y' and product_insta_url for selected products
  static Future<Map<String, dynamic>> updateProductsForInstagram({
    required List<int> productIds,
  }) async {
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        return {"success": false, "message": "User not logged in"};
      }

      final response = await http.post(
        Uri.parse("$baseUrl/products/update-instagram"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'user_id': userId,
          'product_ids': productIds,
        }),
      );

      final result = jsonDecode(response.body) as Map<String, dynamic>;
      
      // Update local database
      if (result['success'] == true && result['data'] != null) {
        final updatedProducts = result['data']['products'] as List<dynamic>;
        for (var productData in updatedProducts) {
          final productId = productData['product_id'] as int;
          final instaUrl = productData['insta_url'] as String;
          
          // Update local database
          await ProductDatabaseService().updateProductInstagramStatus(
            productId: productId,
            instaUrl: instaUrl,
            isInstaProduct: true,
          );
        }
      }

      return result;
    } catch (e) {
      return {"success": false, "message": "Error: ${e.toString()}"};
    }
  }

  /// Get Instagram products (where is_insta_product = 'Y')
  static Future<Map<String, dynamic>> getInstagramProducts() async {
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        return {"success": false, "message": "User not logged in"};
      }

      final response = await http.get(
        Uri.parse("$baseUrl/products/instagram?user_id=$userId"),
        headers: {"Content-Type": "application/json"},
      );

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {"success": false, "message": "Error: ${e.toString()}"};
    }
  }

  /// Update product
  static Future<Map<String, dynamic>> updateProduct({
    required int productId,
    required Map<String, dynamic> productData,
    List<File>? newImages,
  }) async {
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        return {"success": false, "message": "User not logged in"};
      }

      // Prepare update data
      // Handle subcategory - ensure it's not empty string
      final subcategoryValue = productData['subcategory'];
      final subcategory = (subcategoryValue is String && subcategoryValue.trim().isNotEmpty) 
          ? subcategoryValue.trim() 
          : (subcategoryValue != null && subcategoryValue.toString().trim().isNotEmpty)
              ? subcategoryValue.toString().trim()
              : null;
      
      final updatePayload = {
        'user_id': userId,
        'product_id': productId,
        'name': productData['name'] ?? '',
        'category': productData['category'] ?? '',
        'subcategory': subcategory,
        'available_qty': productData['availableQty'] ?? '0',
        'description': productData['description'] ?? '',
        'price_slabs': jsonEncode(productData['priceSlabs'] ?? []),
        'attributes': jsonEncode(productData['attributes'] ?? {}),
        'selected_attribute_values': jsonEncode(
          productData['selectedAttributeValues'] ?? {},
        ),
        'variations': jsonEncode(productData['variations'] ?? []),
        'sizes': jsonEncode(
          (productData['sizes'] as Set<String>?)?.toList() ?? [],
        ),
      };

      // Upload new images if provided
      if (newImages != null && newImages.isNotEmpty) {
        final List<String> imageUrls = [];
        for (var image in newImages) {
          try {
            final imageUrl = await _uploadImage(image, userId);
            if (imageUrl.isNotEmpty) {
              imageUrls.add(imageUrl);
            }
          } catch (e) {
            print('Error uploading image: $e');
          }
        }
        updatePayload['new_images'] = jsonEncode(imageUrls);
      }

      final response = await http.post(
        Uri.parse("$baseUrl/products/update"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(updatePayload),
      );

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {"success": false, "message": "Error: ${e.toString()}"};
    }
  }

  /// Delete product
  static Future<Map<String, dynamic>> deleteProduct(int productId) async {
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        return {"success": false, "message": "User not logged in"};
      }

      final response = await http.post(
        Uri.parse("$baseUrl/products/delete"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'user_id': userId, 'product_id': productId}),
      );

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {"success": false, "message": "Error: ${e.toString()}"};
    }
  }
}
