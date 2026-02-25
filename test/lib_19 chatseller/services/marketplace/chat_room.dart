class ChatRoom {
  final int id;
  final int productId;
  final int buyerId;
  final int sellerId;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? productName;
  final String? productImages;
  final String? buyerName;
  final String? sellerName;
  final int unreadCount;
  final String? lastMessage;
  final DateTime? lastMessageTime;

  ChatRoom({
    required this.id,
    required this.productId,
    required this.buyerId,
    required this.sellerId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.productName,
    this.productImages,
    this.buyerName,
    this.sellerName,
    this.unreadCount = 0,
    this.lastMessage,
    this.lastMessageTime,
  });

  factory ChatRoom.fromMap(Map<String, dynamic> map) {
    return ChatRoom(
      id: map['id'] as int,
      productId: map['product_id'] as int,
      buyerId: map['buyer_id'] as int,
      sellerId: map['seller_id'] as int,
      status: map['status'] as String? ?? 'active',
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : DateTime.now(),
      productName: map['product_name'] as String?,
      productImages: map['product_images'] as String?,
      buyerName: map['buyer_name'] as String?,
      sellerName: map['seller_name'] as String?,
      unreadCount: map['unread_count'] as int? ?? 0,
      lastMessage: map['last_message'] as String?,
      lastMessageTime: map['last_message_time'] != null
          ? DateTime.parse(map['last_message_time'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'product_name': productName,
      'product_images': productImages,
      'buyer_name': buyerName,
      'seller_name': sellerName,
      'unread_count': unreadCount,
      'last_message': lastMessage,
      'last_message_time': lastMessageTime?.toIso8601String(),
    };
  }

  // Get first product image if multiple images exist
  String? get firstProductImage {
    if (productImages == null || productImages!.isEmpty) return null;
    
    try {
      final images = productImages!.split(',');
      return images.isNotEmpty ? images.first.trim() : null;
    } catch (e) {
      return productImages;
    }
  }

  // Get display name for the other user (not current user)
  String getOtherUserName(int currentUserId) {
    if (currentUserId == buyerId) {
      return sellerName ?? 'Seller';
    } else {
      return buyerName ?? 'Buyer';
    }
  }

  // Check if current user is seller
  bool isCurrentUserSeller(int currentUserId) {
    return currentUserId == sellerId;
  }

  // Check if current user is buyer
  bool isCurrentUserBuyer(int currentUserId) {
    return currentUserId == buyerId;
  }
}
