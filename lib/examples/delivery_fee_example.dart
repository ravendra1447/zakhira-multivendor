// Example of how to use the dynamic delivery fee system
// This shows how to integrate the EditDeliveryFeeScreen in your app

import 'package:flutter/material.dart';
import '../screens/order/edit_delivery_fee_screen.dart';

class DeliveryFeeExample extends StatelessWidget {
  const DeliveryFeeExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Fee Example'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dynamic Delivery Fee System',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Example 1: From Order Detail Screen
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Example 1: Order Detail Integration',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('User can tap "Edit" button next to delivery fee:'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      // Navigate to edit delivery fee screen
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const EditDeliveryFeeScreen(
                            orderId: 123,
                            currentSubtotal: 1250.0,
                            currentDeliveryFee: 250.0,
                            currentTotal: 1500.0,
                          ),
                        ),
                      );
                    },
                    child: const Text('Try Edit Delivery Fee'),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Example 2: Manual Entry
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Example 2: What User Can Enter',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('User can type any amount:'),
                  const SizedBox(height: 8),
                  ...[
                    '0' -> FREE delivery,
                    '100' -> ₹100 delivery,
                    '350.50' -> ₹350.50 delivery,
                    '500' -> ₹500 delivery,
                  ].map((example) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('• $example'),
                  )),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Example 3: Real-time Calculation
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Example 3: Real-time Updates',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('As user types, total updates instantly:'),
                  const SizedBox(height: 8),
                  const Text('Subtotal: ₹1250.00'),
                  const Text('Delivery: ₹[USER INPUT]'),
                  const Text('Total: ₹[CALCULATED AUTOMATICALLY]'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Usage in your existing Order Detail Screen:
/*
class YourOrderDetailScreen extends StatefulWidget {
  // ... your existing code
  
  // Add this function to handle editing
  Future<void> _editDeliveryFee() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditDeliveryFeeScreen(
          orderId: widget.orderId,
          currentSubtotal: _subtotalAmount,
          currentDeliveryFee: _deliveryFee,
          currentTotal: _totalAmount,
        ),
      ),
    );

    if (result != null && result['success'] == true) {
      setState(() {
        _deliveryFee = result['delivery_fee'];
        _totalAmount = result['total'];
      });
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delivery fee updated to ₹${_deliveryFee.toStringAsFixed(2)}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}
*/
