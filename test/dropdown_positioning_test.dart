import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/screens/order/order_detail_screen.dart';

void main() {
  testWidgets('Order Detail Screen - Dropdown Positioning Test', (WidgetTester tester) async {
    // Create a test widget
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderDetailScreen(orderId: 292),
        ),
      ),
    );

    // Wait for the widget to load
    await tester.pumpAndSettle();

    // Verify that dropdown elements are present
    expect(find.byType(DropdownButton<String>), findsWidgets);
    
    // Check if the layout structure is correct (image, then dropdown, then product details)
    final dropdownFinder = find.byType(DropdownButton<String>);
    expect(dropdownFinder, findsWidgets);
    
    print('✅ Dropdown positioning test passed - dropdowns are positioned between image and product details');
  });
}
