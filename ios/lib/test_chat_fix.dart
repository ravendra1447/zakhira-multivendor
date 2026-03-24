import 'package:flutter/material.dart';
import '../services/marketplace/marketplace_chat_service.dart';
import '../models/product.dart';

/// Test script to verify chat functionality after fixes
/// Run this to test if the chat system works like Alibaba
class ChatFixTest extends StatefulWidget {
  const ChatFixTest({super.key});

  @override
  State<ChatFixTest> createState() => _ChatFixTestState();
}

class _ChatFixTestState extends State<ChatFixTest> {
  final MarketplaceChatService _chatService = MarketplaceChatService();
  bool _isConnected = false;
  String _testResult = 'Not tested yet';

  @override
  void initState() {
    super.initState();
    _runTests();
  }

  Future<void> _runTests() async {
    setState(() => _testResult = 'Running tests...');
    
    try {
      // Test 1: Socket Connection
      print('🧪 Test 1: Socket Connection');
      await _chatService.initializeSocket(32); // Test with user ID 32
      
      if (_chatService.isConnected) {
        print('✅ Socket connected successfully');
        setState(() => _testResult = '✅ Socket connected\n');
      } else {
        print('❌ Socket connection failed');
        setState(() => _testResult = '❌ Socket connection failed\n');
        return;
      }

      // Test 2: Get Seller by Product
      print('🧪 Test 2: Get Seller by Product');
      try {
        final sellerId = await _chatService.getSellerByProductId(85); // Test product ID 85
        print('✅ Seller found: $sellerId');
        setState(() => _testResult += '✅ Seller found: $sellerId\n');
      } catch (e) {
        print('❌ Failed to get seller: $e');
        setState(() => _testResult += '❌ Failed to get seller: $e\n');
      }

      // Test 3: Create Chat Room
      print('🧪 Test 3: Create Chat Room');
      try {
        final chatRoom = await _chatService.createOrGetChatRoom(
          productId: 85,
          buyerId: 32, // Test buyer
          sellerId: 3,  // Test seller (from your logs)
        );
        print('✅ Chat room created: ${chatRoom.id}');
        setState(() => _testResult += '✅ Chat room created: ${chatRoom.id}\n');
      } catch (e) {
        print('❌ Failed to create chat room: $e');
        setState(() => _testResult += '❌ Failed to create chat room: $e\n');
      }

      setState(() => _testResult += '\n🎉 All tests completed!');
      
    } catch (e) {
      print('❌ Test failed: $e');
      setState(() => _testResult = '❌ Test failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Fix Test'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chat System Test Results:',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _testResult,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Expected Behavior (like Alibaba):',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text('• Click "Chat now" on product detail'),
            const Text('• Automatically creates chat room with seller'),
            const Text('• Shows product info in chat'),
            const Text('• Real-time messaging works'),
            const Text('• Notifications sent to seller'),
          ],
        ),
      ),
    );
  }
}
