class ChatMessage {
  final int id;
  final int chatRoomId;
  final int senderId;
  final String messageType; // 'text', 'image', 'product_info'
  final String messageContent;
  final ProductInfo? productInfo;
  final bool isRead;
  final bool isDelivered;
  final DateTime? deliveryTime;
  final DateTime? readTime;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? senderName;
  final String? senderAvatar;

  ChatMessage({
    required this.id,
    required this.chatRoomId,
    required this.senderId,
    required this.messageType,
    required this.messageContent,
    this.productInfo,
    required this.isRead,
    this.isDelivered = false,
    this.deliveryTime,
    this.readTime,
    required this.createdAt,
    required this.updatedAt,
    this.senderName,
    this.senderAvatar,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as int,
      chatRoomId: map['chat_room_id'] as int,
      senderId: map['sender_id'] as int,
      messageType: map['message_type'] as String? ?? 'text',
      messageContent: map['message_content'] as String,
      productInfo: map['product_info'] != null
          ? ProductInfo.fromMap(map['product_info'])
          : null,
      isRead: map['is_read'] as bool? ?? false,
      isDelivered: map['is_delivered'] as bool? ?? false,
      deliveryTime: map['delivery_time'] != null
          ? DateTime.parse(map['delivery_time'] as String)
          : null,
      readTime: map['read_time'] != null
          ? DateTime.parse(map['read_time'] as String)
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : DateTime.now(),
      senderName: map['sender_name'] as String?,
      senderAvatar: map['sender_avatar'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chat_room_id': chatRoomId,
      'sender_id': senderId,
      'message_type': messageType,
      'message_content': messageContent,
      'product_info': productInfo?.toMap(),
      'is_read': isRead,
      'is_delivered': isDelivered,
      'delivery_time': deliveryTime?.toIso8601String(),
      'read_time': readTime?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sender_name': senderName,
      'sender_avatar': senderAvatar,
    };
  }

  // Check if message is from current user
  bool isFromCurrentUser(int currentUserId) {
    return senderId == currentUserId;
  }

  // Check if message has product info
  bool get hasProductInfo => productInfo != null;

  // Get message status for display
  MessageStatus get status {
    if (isRead) return MessageStatus.read;
    if (isDelivered) return MessageStatus.delivered;
    return MessageStatus.sent;
  }

  // Get formatted time
  String get formattedTime {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  // Get time for display
  String get displayTime {
    final hour = createdAt.hour.toString().padLeft(2, '0');
    final minute = createdAt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // Get read time for display
  String? get readTimeDisplay {
    if (readTime == null) return null;
    final hour = readTime!.hour.toString().padLeft(2, '0');
    final minute = readTime!.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

enum MessageStatus {
  sent,
  delivered,
  read,
}

class ProductInfo {
  final int productId;
  final String productName;
  final double price;
  final String image;

  ProductInfo({
    required this.productId,
    required this.productName,
    required this.price,
    required this.image,
  });

  factory ProductInfo.fromMap(Map<String, dynamic> map) {
    return ProductInfo(
      productId: map['product_id'] as int,
      productName: map['product_name'] as String,
      price: (map['price'] as num).toDouble(),
      image: map['image'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'product_id': productId,
      'product_name': productName,
      'price': price,
      'image': image,
    };
  }

  // Get formatted price
  String get formattedPrice {
    return '₹${price.toStringAsFixed(1)}';
  }
}
