import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product.dart';

class CartService {
  static final List<CartItem> _cartItems = [];

  static List<CartItem> get cartItems => List.from(_cartItems);

  static int get totalItems => _cartItems.fold(0, (sum, item) => sum + item.quantity);

  static double get totalPrice => _cartItems.fold(0.0, (sum, item) => sum + (item.price * item.quantity));

  static void addToCart({
    required Product product,
    required Map<String, dynamic> variation,
    required String size,
    required int quantity,
    required double price,
  }) {
    // Check if item already exists
    final existingIndex = _cartItems.indexWhere(
      (item) => item.product.id == product.id && 
                item.variation['name'] == variation['name'] && 
                item.size == size
    );

    if (existingIndex >= 0) {
      // Update existing item
      _cartItems[existingIndex].quantity += quantity;
    } else {
      // Add new item
      _cartItems.add(CartItem(
        product: product,
        variation: variation,
        size: size,
        quantity: quantity,
        price: price,
      ));
    }
    
    // Print debug info
    print('Cart updated: ${_cartItems.length} items, total quantity: $totalItems');
  }

  static void removeFromCart(int index) {
    if (index >= 0 && index < _cartItems.length) {
      _cartItems.removeAt(index);
      print('Item removed from cart: $totalItems items remaining');
    }
  }

  static void updateQuantity(int index, int quantity) {
    if (index >= 0 && index < _cartItems.length) {
      _cartItems[index].quantity = quantity;
      print('Cart quantity updated: $totalItems items total');
    }
  }

  static void clearCart() {
    _cartItems.clear();
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
