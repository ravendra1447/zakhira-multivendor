import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../widgets/instagram_creation_button.dart';

void main() {
  group('Instagram Creation Button Property Tests', () {
    
    /// Property 2: Button Visual Design Compliance
    /// For any Instagram creation button instance, it should use Instagram's 
    /// brand gradient colors, have a circular shape, include a camera icon, 
    /// maintain minimum 36x36 pixel size, and have subtle shadow elevation.
    testWidgets('Property 2: Button Visual Design Compliance', (WidgetTester tester) async {
      // Test with different sizes to ensure compliance across all instances
      final testSizes = [36.0, 40.0, 48.0, 56.0, 64.0];
      
      for (final size in testSizes) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InstagramCreationButton(
                onPressed: () {},
                size: size,
              ),
            ),
          ),
        );

        // Find the button container
        final containerFinder = find.byType(Container);
        expect(containerFinder, findsOneWidget);
        
        final Container container = tester.widget(containerFinder);
        final BoxDecoration decoration = container.decoration as BoxDecoration;
        
        // Verify circular shape
        expect(decoration.shape, BoxShape.circle);
        
        // Verify gradient colors (Instagram brand colors)
        final LinearGradient gradient = decoration.gradient as LinearGradient;
        expect(gradient.colors, [
          const Color(0xFF833AB4), // Purple
          const Color(0xFFE1306C), // Pink  
          const Color(0xFFFD1D1D), // Red
          const Color(0xFFFC8019), // Orange
        ]);
        
        // Verify gradient direction
        expect(gradient.begin, Alignment.topLeft);
        expect(gradient.end, Alignment.bottomRight);
        
        // Verify size (minimum 36x36 pixels)
        expect(size, greaterThanOrEqualTo(36.0));
        
        // Get the actual rendered size from the widget tester
        final containerSize = tester.getSize(containerFinder);
        expect(containerSize.width, size);
        expect(containerSize.height, size);
        
        // Verify shadow elevation exists
        expect(decoration.boxShadow, isNotNull);
        expect(decoration.boxShadow!.length, greaterThan(0));
        
        // Verify camera icon exists
        final iconFinder = find.byIcon(Icons.camera_alt);
        expect(iconFinder, findsOneWidget);
        
        final Icon icon = tester.widget(iconFinder);
        expect(icon.color, Colors.white);
        expect(icon.size, size * 0.5);
        
        await tester.pumpAndSettle();
      }
    });

    /// Property 3: Button Interaction Feedback
    /// For any button press event, the Instagram creation button should 
    /// provide visual feedback through ripple effect or color change.
    testWidgets('Property 3: Button Interaction Feedback', (WidgetTester tester) async {
      bool wasPressed = false;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InstagramCreationButton(
              onPressed: () {
                wasPressed = true;
              },
            ),
          ),
        ),
      );

      // Find the InkWell widget that provides ripple feedback
      final inkWellFinder = find.byType(InkWell);
      expect(inkWellFinder, findsOneWidget);
      
      final InkWell inkWell = tester.widget(inkWellFinder);
      
      // Verify InkWell has proper border radius for circular ripple
      expect(inkWell.borderRadius, BorderRadius.circular(20.0)); // 40/2 = 20
      
      // Verify onTap callback exists
      expect(inkWell.onTap, isNotNull);
      
      // Test interaction feedback by tapping
      await tester.tap(inkWellFinder);
      await tester.pump();
      
      // Verify the callback was executed
      expect(wasPressed, isTrue);
      
      // Test with disabled state
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InstagramCreationButton(
              onPressed: () {},
              isEnabled: false,
            ),
          ),
        ),
      );
      
      final disabledInkWell = tester.widget<InkWell>(find.byType(InkWell));
      expect(disabledInkWell.onTap, isNull);
    });

    /// Property 9: Accessibility Compliance
    /// For any accessibility configuration, the Instagram creation button should 
    /// have sufficient contrast ratio, support screen reader accessibility, 
    /// have appropriate semantic labels, and maintain minimum touch target size.
    testWidgets('Property 9: Accessibility Compliance', (WidgetTester tester) async {
      // Test with different sizes including minimum touch targets
      final testSizes = [44.0, 48.0]; // iOS and Android minimum touch targets
      
      for (final size in testSizes) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InstagramCreationButton(
                onPressed: () {},
                size: size,
              ),
            ),
          ),
        );

        // Find the Semantics widget with our specific properties
        final semanticsFinder = find.byWidgetPredicate((widget) => 
          widget is Semantics && 
          widget.properties.label == 'Create Instagram page'
        );
        expect(semanticsFinder, findsOneWidget);
        
        final Semantics semantics = tester.widget(semanticsFinder);
        
        // Verify semantic properties
        expect(semantics.properties.button, isTrue);
        expect(semantics.properties.enabled, isTrue);
        expect(semantics.properties.label, 'Create Instagram page');
        expect(semantics.properties.hint, 'Tap to create a new Instagram-style page');
        
        // Verify minimum touch target size
        final containerSize = tester.getSize(find.byType(Container));
        expect(containerSize.width, greaterThanOrEqualTo(44.0)); // iOS minimum
        expect(containerSize.height, greaterThanOrEqualTo(44.0)); // iOS minimum
        
        // Test disabled state accessibility
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InstagramCreationButton(
                onPressed: () {},
                isEnabled: false,
                size: size,
              ),
            ),
          ),
        );
        
        final disabledSemanticsFinder = find.byWidgetPredicate((widget) => 
          widget is Semantics && 
          widget.properties.label == 'Create Instagram page'
        );
        final disabledSemantics = tester.widget<Semantics>(disabledSemanticsFinder);
        expect(disabledSemantics.properties.enabled, isFalse);
        
        await tester.pumpAndSettle();
      }
    });

    // Additional unit tests for specific scenarios
    group('Unit Tests', () {
      testWidgets('should handle custom size parameter', (WidgetTester tester) async {
        const customSize = 56.0;
        
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InstagramCreationButton(
                onPressed: () {},
                size: customSize,
              ),
            ),
          ),
        );

        final containerSize = tester.getSize(find.byType(Container));
        expect(containerSize.width, customSize);
        expect(containerSize.height, customSize);
        
        final icon = tester.widget<Icon>(find.byIcon(Icons.camera_alt));
        expect(icon.size, customSize * 0.5);
      });

      testWidgets('should use default size when not specified', (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InstagramCreationButton(
                onPressed: () {},
              ),
            ),
          ),
        );

        final containerSize = tester.getSize(find.byType(Container));
        expect(containerSize.width, 40.0);
        expect(containerSize.height, 40.0);
      });

      testWidgets('should execute callback on tap when enabled', (WidgetTester tester) async {
        bool callbackExecuted = false;
        
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InstagramCreationButton(
                onPressed: () {
                  callbackExecuted = true;
                },
              ),
            ),
          ),
        );

        await tester.tap(find.byType(InkWell));
        expect(callbackExecuted, isTrue);
      });

      testWidgets('should not execute callback when disabled', (WidgetTester tester) async {
        bool callbackExecuted = false;
        
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InstagramCreationButton(
                onPressed: () {
                  callbackExecuted = true;
                },
                isEnabled: false,
              ),
            ),
          ),
        );

        // Try to tap - should not execute callback
        await tester.tap(find.byType(InkWell));
        expect(callbackExecuted, isFalse);
      });
    });
  });
}