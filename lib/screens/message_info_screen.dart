import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/chat_model.dart';
import '../services/local_auth_service.dart';
import 'media_viewer_screen.dart';

class MessageInfoScreen extends StatelessWidget {
  final Message message;
  final String otherUserName;

  const MessageInfoScreen({
    Key? key,
    required this.message,
    required this.otherUserName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // ✅ Get userId from LocalAuthService or context
    final userId = LocalAuthService.getUserId(); // You may need to import this
    final isMe = message.senderId == userId;
    
    // ✅ Get delivered and read timestamps
    final deliveredTime = message.extraData?['deliveredAt'] != null
        ? DateTime.tryParse(message.extraData!['deliveredAt'])
        : (message.isDelivered == 1 ? message.timestamp : null);
    
    final readTime = message.extraData?['readAt'] != null
        ? DateTime.tryParse(message.extraData!['readAt'])
        : (message.isRead == 1 ? message.timestamp : null);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF075E54),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Message info',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/chat_bg.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          children: [
            // ✅ End-to-end encryption banner
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              color: Colors.grey[100],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    'Messages and calls are end-to-end encrypted',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            
            // ✅ Message Preview Bubble
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: isMe ? const Radius.circular(16) : const Radius.circular(2),
                      topRight: isMe ? const Radius.circular(2) : const Radius.circular(16),
                      bottomLeft: const Radius.circular(16),
                      bottomRight: const Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ✅ Image Preview (if media message)
                      if (message.messageType == 'media' || message.messageType == 'encrypted_media')
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => MediaViewerScreen(
                                  mediaUrl: message.messageContent,
                                  messageId: message.messageId,
                                  isLocalFile: message.messageContent.startsWith('/') || 
                                      !message.messageContent.startsWith('http'),
                                  chatId: message.chatId,
                                ),
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: message.messageContent.startsWith('http')
                                ? Image.network(
                                    message.messageContent,
                                    width: double.infinity,
                                    height: 200,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      // ✅ FIX: Show thumbnail if available
                                      if (message.thumbnailBase64 != null && message.thumbnailBase64!.isNotEmpty) {
                                        try {
                                          final bytes = base64Decode(message.thumbnailBase64!);
                                          return Image.memory(
                                            bytes,
                                            width: double.infinity,
                                            height: 200,
                                            fit: BoxFit.cover,
                                          );
                                        } catch (_) {}
                                      }
                                      return Container(
                                        height: 200,
                                        color: Colors.grey[300],
                                        child: const Icon(Icons.image, size: 50),
                                      );
                                    },
                                  )
                                : Image.file(
                                    File(message.messageContent),
                                    width: double.infinity,
                                    height: 200,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        height: 200,
                                        color: Colors.grey[300],
                                        child: const Icon(Icons.image, size: 50),
                                      );
                                    },
                                  ),
                          ),
                        ),
                      
                      // ✅ Text Message (if text)
                      if (message.messageType == 'text')
                        Text(
                          message.messageContent,
                          style: const TextStyle(fontSize: 14),
                        ),
                      
                      const SizedBox(height: 8),
                      
                      // ✅ Timestamp
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatDetailedTime(message.timestamp),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            _buildMessageStatusIcon(message),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // ✅ Status Info Section
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    const SizedBox(height: 16),
                    
                    if (isMe) ...[
                      // ✅ Seen Status
                      if (message.isRead == 1 && readTime != null)
                        _buildStatusRow(
                          icon: Icons.done_all,
                          iconColor: Colors.blue,
                          title: 'Seen',
                          subtitle: _formatDetailedTime(readTime),
                        ),
                      
                      // ✅ Delivered Status
                      if (message.isDelivered == 1 && deliveredTime != null)
                        _buildStatusRow(
                          icon: Icons.done_all,
                          iconColor: message.isRead == 1 ? Colors.blue : Colors.grey,
                          title: 'Delivered',
                          subtitle: _formatDetailedTime(deliveredTime),
                        ),
                      
                      // ✅ Response Time
                      if (message.isRead == 1 && readTime != null && deliveredTime != null)
                        _buildStatusRow(
                          icon: Icons.timer_outlined,
                          iconColor: Colors.green,
                          title: 'Response time',
                          subtitle: _calculateResponseTime(deliveredTime, readTime),
                          isBold: true,
                        ),
                    ] else ...[
                      _buildStatusRow(
                        icon: Icons.send,
                        iconColor: Colors.grey,
                        title: 'Sent',
                        subtitle: _formatDetailedTime(message.timestamp),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: isBold ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageStatusIcon(Message msg) {
    if (msg.isRead == 1) {
      return const Icon(Icons.done_all, size: 14, color: Colors.blue);
    } else if (msg.isDelivered == 1) {
      return const Icon(Icons.done_all, size: 14, color: Colors.grey);
    } else {
      return const Icon(Icons.done, size: 14, color: Colors.grey);
    }
  }

  String _formatDetailedTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
    
    final timeStr = DateFormat('h:mm a').format(dateTime);
    
    if (messageDate == today) {
      return 'Today, $timeStr';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday, $timeStr';
    } else {
      return DateFormat('dd/MM/yyyy, h:mm a').format(dateTime);
    }
  }

  String _calculateResponseTime(DateTime delivered, DateTime read) {
    final duration = read.difference(delivered);
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds} seconds';
    } else if (duration.inMinutes < 60) {
      return '${duration.inMinutes} minute${duration.inMinutes > 1 ? 's' : ''}';
    } else if (duration.inHours < 24) {
      return '${duration.inHours} hour${duration.inHours > 1 ? 's' : ''}';
    } else {
      return '${duration.inDays} day${duration.inDays > 1 ? 's' : ''}';
    }
  }
}

