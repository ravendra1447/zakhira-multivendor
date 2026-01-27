import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product.dart';
import '../config.dart';
import '../models/user.dart';

class CartService {
  static final List<CartItem> _cartItems = [];
  static int? _currentUserId;

  static List<CartItem> get cartItems => List.from(_cartItems);

  static int get totalItems => _cartItems.fold(0, (sum, item) => sum + item.quantity);

  static double get totalPrice => _cartItems.fold(0.0, (sum, item) => sum + (item.price * item.quantity));

  static void setUserId(int userId) {
    _currentUserId = userId;
  }

  static Future<void> loadCartFromServer() async {
    if (_currentUserId == null) return;
    
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/cart/get-cart/$_currentUserId'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          _cartItems.clear();
          
          for (var item in data['items']) {
            // Convert server item to CartItem
            final product = Product(
              id: item['product_id'],
              userId: 1, // Default user ID - you may need to get this from user data
              name: item['name'] ?? 'Product',
              availableQty: '999', // Default available quantity
              description: item['description'] ?? '',
              status: 'publish', // Default status
              priceSlabs: [], // Empty price slabs
              attributes: {}, // Empty attributes
              selectedAttributeValues: {}, // Empty selected values
              variations: [], // Empty variations
              sizes: [item['size'] ?? 'M'], // Use item size or default
              images: item['image_url'] != null ? [item['image_url']] : [],
            );
            
            _cartItems.add(CartItem(
              product: product,
              variation: {'name': item['color'] ?? 'Default'},
              size: item['size'] ?? 'M',
              quantity: item['quantity'],
              price: double.parse(item['price'].toString()),
            ));
          }
          
          print('Cart loaded from server: ${_cartItems.length} items');
        }
      }
    } catch (e) {
      print('Error loading cart from server: $e');
    }
  }

  static Future<void> addToCart({
    required Product product,
    required Map<String, dynamic> variation,
    required String size,
    required int quantity,
    required double price,
  }) async {
    // Check if item already exists locally
    final existingIndex = _cartItems.indexWhere(
      (item) => item.product.id == product.id && 
                item.variation['name'] == variation['name'] && 
                item.size == size
    );

    if (existingIndex >= 0) {
      // Update existing item locally
      _cartItems[existingIndex].quantity += quantity;
    } else {
      // Add new item locally
      _cartItems.add(CartItem(
        product: product,
        variation: variation,
        size: size,
        quantity: quantity,
        price: price,
      ));
    }
    
    // Save to server if user is logged in
    if (_currentUserId != null) {
      print('DEBUG: Saving to server - User ID: $_currentUserId, Product ID: ${product.id}');
      try {
        final response = await http.post(
          Uri.parse('${Config.baseNodeApiUrl}/cart/add-item'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'userId': _currentUserId,
            'productId': product.id,
            'quantity': quantity,
            'price': price,
            'size': size,
            'color': variation['name'],
          }),
        );
        
        print('DEBUG: Server response status: ${response.statusCode}');
        print('DEBUG: Server response body: ${response.body}');
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success']) {
            print('Item saved to server successfully');
          } else {
            print('Server error: ${data['error']}');
          }
        } else {
          print('HTTP error: ${response.statusCode}');
        }
      } catch (e) {
        print('Error saving to server: $e');
      }
    } else {
      print('DEBUG: User ID is null, not saving to server');
    }
    
    // Print debug info
    print('Cart updated: ${_cartItems.length} items, total quantity: $totalItems');
  }

  static Future<void> removeFromCart(int index) async {
    if (index >= 0 && index < _cartItems.length) {
      final item = _cartItems[index];
      _cartItems.removeAt(index);
      
      // Remove from server if user is logged in
      if (_currentUserId != null) {
        try {
          // First get the cart to find the item ID
          final cartResponse = await http.get(
            Uri.parse('${Config.baseNodeApiUrl}/cart/get-cart/$_currentUserId'),
          );
          
          if (cartResponse.statusCode == 200) {
            final cartData = json.decode(cartResponse.body);
            if (cartData['success']) {
              // Find the matching item in server response
              for (var serverItem in cartData['items']) {
                if (serverItem['product_id'] == item.product.id &&
                    serverItem['size'] == item.size &&
                    serverItem['color'] == item.variation['name']) {
                  
                  // Remove from server
                  final deleteResponse = await http.delete(
                    Uri.parse('${Config.baseNodeApiUrl}/cart/remove-item/${serverItem['id']}'),
                  );
                  
                  if (deleteResponse.statusCode == 200) {
                    print('Item removed from server successfully');
                  }
                  break;
                }
              }
            }
          }
        } catch (e) {
          print('Error removing from server: $e');
        }
      }
      
      print('Item removed from cart: $totalItems items remaining');
    }
  }

  static Future<void> updateQuantity(int index, int quantity) async {
    if (index >= 0 && index < _cartItems.length) {
      _cartItems[index].quantity = quantity;
      
      // Update on server if user is logged in
      if (_currentUserId != null) {
        try {
          // First get the cart to find the item ID
          final cartResponse = await http.get(
            Uri.parse('${Config.baseNodeApiUrl}/cart/get-cart/$_currentUserId'),
          );
          
          if (cartResponse.statusCode == 200) {
            final cartData = json.decode(cartResponse.body);
            if (cartData['success']) {
              // Find the matching item in server response
              for (var serverItem in cartData['items']) {
                if (serverItem['product_id'] == _cartItems[index].product.id &&
                    serverItem['size'] == _cartItems[index].size &&
                    serverItem['color'] == _cartItems[index].variation['name']) {
                  
                  // Update on server
                  final updateResponse = await http.put(
                    Uri.parse('${Config.baseNodeApiUrl}/cart/update-item/${serverItem['id']}'),
                    headers: {'Content-Type': 'application/json'},
                    body: json.encode({'quantity': quantity}),
                  );
                  
                  if (updateResponse.statusCode == 200) {
                    print('Item quantity updated on server successfully');
                  }
                  break;
                }
              }
            }
          }
        } catch (e) {
          print('Error updating quantity on server: $e');
        }
      }
      
      print('Cart quantity updated: $totalItems items total');
    }
  }

  static Future<void> clearCart() async {
    _cartItems.clear();
    
    // Clear from server if user is logged in
    if (_currentUserId != null) {
      try {
        final response = await http.delete(
          Uri.parse('${Config.baseNodeApiUrl}/cart/clear-cart/$_currentUserId'),
        );
        
        if (response.statusCode == 200) {
          print('Cart cleared from server successfully');
        }
      } catch (e) {
        print('Error clearing cart from server: $e');
      }
    }
    
    print('Cart cleared: $totalItems items');
  }
}

class CartItem {
  final Product product;
  final Map<String, dynamic> variation;
  final String size;
  int quantity;
  final double price;

  CartItem({
    required this.product,
    required this.variation,
    required this.size,
    required this.quantity,
    required this.price,
  });

  String get colorName => variation['name'] as String? ?? 'Unknown';
  
  String get productImage {
    if (variation['image'] != null) {
      return variation['image'].toString();
    }
    if (variation['allImages'] != null && variation['allImages'].isNotEmpty) {
      return variation['allImages'][0].toString();
    }
    if (product.images.isNotEmpty) {
      return product.images.first;
    }
    return '';
  }

  Map<String, dynamic> toJson() {
    return {
      'product': product.toJson(),
      'variation': variation,
      'size': size,
      'quantity': quantity,
      'price': price,
    };
  }
}
