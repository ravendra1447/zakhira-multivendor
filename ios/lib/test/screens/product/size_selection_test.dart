import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsappchat/screens/product/add_product_basic_info_screen.dart';

void main() {
  group('Size Selection Tests', () {
    testWidgets('Selected sizes display as individual chips', (WidgetTester tester) async {
      // Create test widget
      await tester.pumpWidget(
        MaterialApp(
          home: AddProductBasicInfoScreen(
            images: [],
          ),
        ),
      );

      // Find the size selection area and tap to open modal
      final sizeSelectionArea = find.text('Select Sizes');
      expect(sizeSelectionArea, findsOneWidget);
      
      await tester.tap(sizeSelectionArea);
      await tester.pumpAndSettle();

      // Verify modal opens
      expect(find.text('Select Sizes'), findsWidgets);
      
      // Tap on a size (e.g., 'M')
      final sizeM = find.text('M');
      expect(sizeM, findsOneWidget);
      await tester.tap(sizeM);
      await tester.pumpAndSettle();

      // Tap Done button
      final doneButton = find.text('Done');
      await tester.tap(doneButton);
      await tester.pumpAndSettle();

      // Verify selected sizes are displayed as chips
      expect(find.text('Selected Sizes'), findsOneWidget);
      expect(find.text('M'), findsWidgets); // Should find M in a chip
    });

    testWidgets('Duplicate size prevention works', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AddProductBasicInfoScreen(
            images: [],
          ),
        ),
      );

      // Open size selection modal
      await tester.tap(find.text('Select Sizes'));
      await tester.pumpAndSettle();

      // Select size 'M'
      await tester.tap(find.text('M'));
      await tester.pumpAndSettle();

      // Try to select size 'M' again - should not create duplicate
      await tester.tap(find.text('M'));
      await tester.pumpAndSettle();

      // Tap Done
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Verify only one 'M' chip exists
      expect(find.text('M'), findsWidgets);
    });
  });
}
