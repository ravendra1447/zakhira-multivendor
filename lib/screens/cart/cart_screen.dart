import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/cart_service.dart';
import '../checkout/checkout_screen.dart';
import '../product/detail/product_detail_screen.dart';
import '../../models/product.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final Set<int> _selectedItems = {};
  bool _selectAll = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCart();
  }

  Future<void> _loadCart() async {
    setState(() {
      _isLoading = true;
    });
    
    await CartService.loadCartFromServer();
    
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = CartService.cartItems;
    final totalPrice = CartService.totalPrice;
    final totalItems = CartService.totalItems;

    // Group items by product (for variants display)
    final Map<int, List<CartItem>> itemsByProduct = {};
    for (var item in cartItems) {
      final productId = item.product.id ?? 0;
      if (!itemsByProduct.containsKey(productId)) {
        itemsByProduct[productId] = [];
      }
      itemsByProduct[productId]!.add(item);
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'My Cart',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        actions: [
          if (cartItems.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() {
                  _selectAll = !_selectAll;
                  if (_selectAll) {
                    _selectedItems.clear();
                    _selectedItems.addAll(List.generate(cartItems.length, (index) => index));
                  } else {
                    _selectedItems.clear();
                  }
                });
              },
              child: Text(
                _selectAll ? 'Deselect All' : 'Select All',
                style: TextStyle(
                  color: Colors.blue[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading 
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : cartItems.isEmpty
              ? _buildEmptyCart()
              : Column(
              children: [
                // Selected items summary
                if (_selectedItems.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: Colors.blue[50],
                    child: Text(
                      '${_selectedItems.length} item${_selectedItems.length > 1 ? 's' : ''} selected',
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                
                // Cart items grouped by product
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: itemsByProduct.length,
                    itemBuilder: (context, productIndex) {
                      final productId = itemsByProduct.keys.elementAt(productIndex);
                      final productVariants = itemsByProduct[productId]!;
                      
                      return _buildProductSection(productVariants);
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: cartItems.isNotEmpty && _selectedItems.isNotEmpty
          ? _buildBottomBar(totalPrice, totalItems)
          : null,
    );
  }

  Widget _buildProductSection(List<CartItem> variants) {
    final product = variants.first.product;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product Name Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: _areAllVariantsSelected(variants),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectAllVariants(variants);
                      } else {
                        _deselectAllVariants(variants);
                      }
                    });
                  },
                  activeColor: Colors.blue[700],
                  shape: const CircleBorder(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Text(
                  '${variants.length} variants',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Variants List
          ...variants.asMap().entries.map((entry) {
            final index = entry.key;
            final variant = entry.value;
            final globalIndex = CartService.cartItems.indexOf(variant);
            
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Checkbox
                  Checkbox(
                    value: _selectedItems.contains(globalIndex),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedItems.add(globalIndex);
                        } else {
                          _selectedItems.remove(globalIndex);
                        }
                      });
                    },
                    activeColor: Colors.blue[700],
                    shape: const CircleBorder(),
                  ),
                  const SizedBox(width: 4),
                  
                  // Product Image (Bigger and more to left)
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: variant.productImage.isNotEmpty
                          ? Image.network(
                              variant.productImage,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(Icons.image, color: Colors.grey[400], size: 32);
                              },
                            )
                          : Icon(Icons.image, color: Colors.grey[400], size: 32),
                    ),
                  ),
                  const SizedBox(width: 6),
                  
                  // Variant Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Variant badges
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.blue[200]!),
                              ),
                              child: Text(
                                variant.colorName,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: Text(
                                'Size: ${variant.size}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        
                        // Price and Quantity
                        Row(
                          children: [
                            // Price on its own line
                            Expanded(
                              child: Text(
                                '₹${variant.price.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        
                        // Quantity and Delete on same line
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Quantity Controls
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey[300]!),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: () async {
                                      if (variant.quantity > 1) {
                                        await CartService.updateQuantity(globalIndex, variant.quantity - 1);
                                        setState(() {});
                                      }
                                    },
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.remove, size: 14),
                                    ),
                                  ),
                                  Container(
                                    width: 35,
                                    height: 28,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      border: Border.symmetric(
                                        vertical: BorderSide(color: Colors.grey[300]!),
                                      ),
                                    ),
                                    child: Text(
                                      '${variant.quantity}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () async {
                                      await CartService.updateQuantity(globalIndex, variant.quantity + 1);
                                      setState(() {});
                                    },
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.add, size: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            const SizedBox(width: 8),
                            
                            // Remove Button
                            GestureDetector(
                              onTap: () {
                                _showRemoveItemDialog(globalIndex);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.delete,
                                  color: Colors.red[600],
                                  size: 18,
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
            );
          }).toList(),
        ],
      ),
    );
  }

  // Helper methods for variant selection
  bool _areAllVariantsSelected(List<CartItem> variants) {
    for (var variant in variants) {
      final globalIndex = CartService.cartItems.indexOf(variant);
      if (!_selectedItems.contains(globalIndex)) {
        return false;
      }
    }
    return true;
  }

  void _selectAllVariants(List<CartItem> variants) {
    for (var variant in variants) {
      final globalIndex = CartService.cartItems.indexOf(variant);
      _selectedItems.add(globalIndex);
    }
  }

  void _deselectAllVariants(List<CartItem> variants) {
    for (var variant in variants) {
      final globalIndex = CartService.cartItems.indexOf(variant);
      _selectedItems.remove(globalIndex);
    }
  }

  int _getMinOrderQuantity(CartItem item) {
    // Check if product has price slabs with MOQ
    if (item.product.priceSlabs.isNotEmpty) {
      final firstSlab = item.product.priceSlabs.first;
      return (firstSlab['moq'] as num?)?.toInt() ?? 1;
    }
    return 1; // Default minimum order quantity
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 100,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 20),
          Text(
            'Your cart is empty',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Add some products to get started',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
            child: const Text(
              'Continue Shopping',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(double totalPrice, int totalItems) {
    final selectedTotal = _selectedItems.fold(0.0, (sum, index) {
      if (index < CartService.cartItems.length) {
        final item = CartService.cartItems[index];
        return sum + (item.price * item.quantity);
      }
      return sum;
    });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total (${_selectedItems.length} items)',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '₹${selectedTotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  if (_selectedItems.isNotEmpty) {
                    // Create a list of selected items for checkout
                    final selectedCartItems = _selectedItems
                        .map((index) => CartService.cartItems[index])
                        .toList();
                    
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CheckoutScreen(
                          cartItems: selectedCartItems,
                          totalPrice: selectedTotal,
                        ),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[600],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Check out',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRemoveItemDialog(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Item'),
        content: const Text('Are you sure you want to remove this item from cart?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await CartService.removeFromCart(index);
              _selectedItems.remove(index);
              // Adjust selected items indices after removal
              final adjustedSelected = <int>{};
              for (final itemIndex in _selectedItems) {
                if (itemIndex > index) {
                  adjustedSelected.add(itemIndex - 1);
                } else if (itemIndex < index) {
                  adjustedSelected.add(itemIndex);
                }
              }
              _selectedItems.clear();
              _selectedItems.addAll(adjustedSelected);
              setState(() {});
              Navigator.pop(context);
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.delete,
                  color: Colors.red,
                  size: 18,
                ),
                const SizedBox(width: 4),
                const Text('Remove', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
