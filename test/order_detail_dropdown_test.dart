import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/screens/order/order_detail_screen.dart';

void main() {
  testWidgets('Order Detail Screen Dropdown Test', (WidgetTester tester) async {
    // Create a test widget
    await tester.pumpWidget(
      MaterialApp(
        home: OrderDetailScreen(orderId: 292),
      ),
    );

    // Wait for the widget to load
    await tester.pumpAndSettle();

    // Verify that dropdown elements are present
    expect(find.byType(DropdownButton<String>), findsWidgets);
    
    print('✅ Dropdown widgets found in Order Detail Screen');
  });
}
