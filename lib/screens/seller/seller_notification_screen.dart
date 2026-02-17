import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../config.dart';
import '../order/order_detail_screen.dart';

class SellerNotificationScreen extends StatefulWidget {
  final int sellerId;

  const SellerNotificationScreen({
    super.key,
    required this.sellerId,
  });

  @override
  _SellerNotificationScreenState createState() => _SellerNotificationScreenState();
}

class _SellerNotificationScreenState extends State<SellerNotificationScreen> {
  List<dynamic> notifications = [];
  bool isLoading = true;
  int unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      setState(() {
        isLoading = true;
      });

      final response = await http.get(
        Uri.parse('${Config.apiBaseUrl}/seller-orders/notifications/${widget.sellerId}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            notifications = data['notifications'] as List<dynamic>;
            unreadCount = data['unreadCount'] ?? 0;
            isLoading = false;
          });
        }
      }
    } catch (e) {
      print('❌ Error loading notifications: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _markNotificationAsRead(int notificationId) async {
    try {
      final response = await http.patch(
        Uri.parse('${Config.apiBaseUrl}/seller-orders/notifications/$notificationId/read'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        // Refresh notifications
        _loadNotifications();
      }
    } catch (e) {
      print('❌ Error marking notification as read: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      // Get all unread notification IDs
      final unreadIds = notifications
          .where((n) => n['is_read'] == 0)
          .map((n) => n['id'])
          .toList();

      for (final id in unreadIds) {
        await _markNotificationAsRead(id);
      }
    } catch (e) {
      print('❌ Error marking all as read: $e');
    }
  }

  String _formatNotificationTime(String? timeString) {
    if (timeString == null) return '';
    
    try {
      final dateTime = DateTime.parse(timeString);
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      
      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inDays < 1) {
        return '${difference.inHours}h ago';
      } else {
        return '${difference.inDays}d ago';
      }
    } catch (e) {
      return timeString;
    }
  }

  void _showOrderDetails(int orderId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderDetailScreen(
          orderId: orderId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const Icon(Icons.notifications, color: Colors.blue),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Order Notifications ($unreadCount)',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFF5F5F5),
        elevation: 0,
        actions: [
          // Mark all as read button
          if (unreadCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _markAllAsRead,
                icon: const Icon(Icons.done_all, color: Colors.blue, size: 18),
                label: const Text(
                  'Mark all read',
                  style: TextStyle(color: Colors.blue, fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blue, size: 20),
            onPressed: _loadNotifications,
            tooltip: 'Refresh',
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
            padding: const EdgeInsets.all(8),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.blue.shade200, width: 2),
                        ),
                        child: Icon(
                          Icons.notifications_none,
                          size: 64,
                          color: Colors.blue.shade300,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'No notifications yet',
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'When customers place orders,\nyou\'ll see them here',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: Colors.blue.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Check back later for new orders',
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      final notification = notifications[index];
                      final isRead = notification['is_read'] == 1;
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: isRead ? 1 : 4,
                        color: isRead ? Colors.white : Colors.blue.shade50,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isRead ? Colors.grey.shade300 : Colors.blue.shade200,
                            width: isRead ? 1 : 2,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Stack(
                            children: [
                              CircleAvatar(
                                backgroundColor: isRead ? Colors.grey.shade400 : Colors.blue,
                                radius: 24,
                                child: Icon(
                                  Icons.receipt,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                              if (!isRead)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  notification['title'] ?? 'New Order',
                                  style: TextStyle(
                                    fontWeight: isRead ? FontWeight.w500 : FontWeight.bold,
                                    color: isRead ? Colors.black87 : Colors.blue.shade800,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              if (!isRead)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.blue,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'NEW',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                notification['message'] ?? 'Order received',
                                style: TextStyle(
                                  color: isRead ? Colors.grey.shade600 : Colors.black87,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 14,
                                    color: Colors.grey.shade500,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatNotificationTime(notification['created_at']),
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (isRead)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'READ',
                                        style: TextStyle(
                                          color: Colors.green.shade700,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          trailing: isRead
                              ? const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey)
                              : const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.blue),
                          onTap: () {
                            print('🔔 Notification clicked: ${notification.toString()}');
                            print('🔔 Notification message: ${notification['message']}');
                            
                            // Extract order ID from notification message
                            final message = notification['message'] ?? '';
                            print('🔔 Extracting order ID from: $message');
                            
                            final orderIdMatch = RegExp(r'Order #(\d+)').firstMatch(message);
                            final orderId = orderIdMatch?.group(1);
                            
                            print('🔔 Extracted order ID: $orderId');
                            
                            if (orderId != null) {
                              print('🔔 Navigating to order details for order: $orderId');
                              
                              // Mark as read
                              if (!isRead) {
                                _markNotificationAsRead(notification['id']);
                              }
                              
                              _showOrderDetails(int.parse(orderId));
                            } else {
                              print('❌ Could not extract order ID from message');
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
