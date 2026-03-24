import 'package:flutter/material.dart';
import '../screens/chat_screen.dart';
import '../models/marketplace/marketplace_chat_room.dart';
import '../models/product.dart';

void main() {
  runApp(TestApp());
}

class TestApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: TestMarketplaceChatScreen(),
    );
  }
}

class TestMarketplaceChatScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Create a test marketplace chat room
    final testChatRoom = MarketplaceChatRoom(
      id: 1,
      productId: 123,
      sellerId: 1,
      buyerId: 2,
      sellerName: 'Test Seller',
      buyerName: 'Test Buyer',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Create a test product
    final testProduct = Product(
      id: 123,
      userId: 1,
      name: 'Test Product',
      price: 99.99,
      availableQty: '100',
      description: 'This is a test product for marketplace chat integration',
      status: 'publish',
      images: ['https://via.placeholder.com/300'],
      variations: [
        {
          'name': 'Test Product',
          'image': 'https://via.placeholder.com/300',
          'price': 99.99,
        }
      ],
      marketplaceEnabled: true,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Marketplace Chat Test'),
        backgroundColor: Colors.green,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(
                      chatId: 1,
                      otherUserId: 2,
                      otherUserName: 'Test Buyer',
                      isMarketplaceChat: true,
                      marketplaceChatRoom: testChatRoom,
                      product: testProduct,
                    ),
                  ),
                );
              },
              child: Text('Open Marketplace Chat'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(
                      chatId: 1,
                      otherUserId: 2,
                      otherUserName: 'Regular User',
                      isMarketplaceChat: false, // Regular chat
                    ),
                  ),
                );
              },
              child: Text('Open Regular Chat'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
