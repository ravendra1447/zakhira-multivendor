import 'dart:convert';
import 'dart:typed_data';
import 'package:hive/hive.dart';

part 'chat_model.g.dart';

@HiveType(typeId: 0)
class Message extends HiveObject {
  @HiveField(0)
  String messageId;

  @HiveField(1)
  int chatId;

  @HiveField(2)
  int senderId;

  @HiveField(3)
  int receiverId;

  @HiveField(4)
  String messageContent;

  @HiveField(5)
  String messageType;

  @HiveField(6)
  int isRead;

  @HiveField(7)
  DateTime timestamp;

  @HiveField(8)
  int isDelivered;

  // Optional fields
  @HiveField(9)
  String? senderName;

  @HiveField(10)
  String? receiverName;

  @HiveField(11)
  String? senderPhoneNumber;

  @HiveField(12)
  String? receiverPhoneNumber;

  // Deletion Status
  @HiveField(13)
  int isDeletedSender;

  @HiveField(14)
  int isDeletedReceiver;

  // Thumbnail for media preview
  @HiveField(15)
  Uint8List? thumbnail;

  // ✅ BLUR IMAGE FUNCTIONALITY
  @HiveField(16)
  String? blurImagePath;

  @HiveField(17)
  bool isImageLoaded;

  // ✅ LOW QUALITY URL FOR FAST LOADING
  @HiveField(18)
  String? lowQualityUrl;

  // ✅ NEW: EXTRA DATA FIELD FOR CUSTOM PROPERTIES
  @HiveField(19)
  Map<String, dynamic>? extraData;

  // ✅ NEW FIELDS FOR BLURHASH SUPPORT
  @HiveField(20)
  String? highQualityUrl;

  @HiveField(21)
  String? blurHash;

  // ✅ ADD THUMBNAIL BASE64 FIELD
  @HiveField(22)
  String? thumbnailBase64;

  @HiveField(23)
  int _imageLoadStage = 0;

  // ✅ NEW FIELDS FOR REPLY AND FORWARD FUNCTIONALITY
  @HiveField(24)
  String? replyToMessageId;

  @HiveField(25)
  bool isForwarded;

  @HiveField(26)
  String? forwardedFrom;

  // ✅ NEW FIELDS FOR MULTIPLE IMAGES GROUP UPLOAD
  @HiveField(27)
  String? groupId;

  @HiveField(28)
  int? imageIndex;

  @HiveField(29)
  int? totalImages;

  // ✅ NEW FIELDS FOR MULTIPLE IMAGE URLS
  @HiveField(30)
  List<String>? mediaUrls;

  @HiveField(31)
  List<String>? lowQualityUrls;

  @HiveField(32)
  List<String>? highQualityUrls;

  Message({
    required this.messageId,
    required this.chatId,
    required this.senderId,
    required this.receiverId,
    required this.messageContent,
    required this.messageType,
    required this.isRead,
    required this.timestamp,
    required this.isDelivered,
    this.senderName,
    this.receiverName,
    this.senderPhoneNumber,
    this.receiverPhoneNumber,
    this.isDeletedSender = 0,
    this.isDeletedReceiver = 0,
    this.thumbnail,
    this.blurImagePath,
    this.isImageLoaded = false,
    this.lowQualityUrl,
    this.extraData,
    this.highQualityUrl,
    this.blurHash,
    this.thumbnailBase64,
    // ✅ NEW FIELDS WITH DEFAULT VALUES
    this.replyToMessageId,
    this.isForwarded = false,
    this.forwardedFrom,
    // ✅ NEW GROUP UPLOAD FIELDS
    this.groupId,
    this.imageIndex,
    this.totalImages,
    // ✅ NEW MULTIPLE IMAGE URLS
    this.mediaUrls,
    this.lowQualityUrls,
    this.highQualityUrls,
  });

  // ✅ GETTERS FOR MULTIPLE IMAGE URLS
  bool get hasMediaUrls => mediaUrls != null && mediaUrls!.isNotEmpty;
  bool get hasLowQualityUrls => lowQualityUrls != null && lowQualityUrls!.isNotEmpty;
  bool get hasHighQualityUrls => highQualityUrls != null && highQualityUrls!.isNotEmpty;

  // ✅ PROGRESSIVE LOADING GETTERS AND SETTERS
  int get imageLoadStage => _imageLoadStage;
  set imageLoadStage(int stage) {
    _imageLoadStage = stage;
    save();
  }

  String get displayImageUrl {
    switch (_imageLoadStage) {
      case 3: return highQualityUrl ?? messageContent; // High quality loaded
      case 2: return lowQualityUrl ?? messageContent;  // Low quality loaded
      default: return lowQualityUrl ?? messageContent; // Default to low quality
    }
  }

  bool get shouldShowBlurHash {
    return blurHash != null && blurHash!.isNotEmpty && _imageLoadStage < 2;
  }

  bool get shouldLoadHighQuality {
    return _imageLoadStage == 2 && highQualityUrl != null;
  }

  // ✅ GROUP UPLOAD GETTERS
  bool get isPartOfGroup => groupId != null && groupId!.isNotEmpty;
  bool get isFirstInGroup => isPartOfGroup && imageIndex == 0;
  bool get isLastInGroup => isPartOfGroup && imageIndex == (totalImages! - 1);
  bool get hasGroupData => groupId != null && imageIndex != null && totalImages != null;

  // ✅ FROM JSON FACTORY METHOD - UPDATED WITH NEW FIELDS
  factory Message.fromJson(Map<String, dynamic> json) {
    try {
      final dynamic messageIdFromServer = json['message_id'];
      String parsedMessageId = (messageIdFromServer is int)
          ? messageIdFromServer.toString()
          : messageIdFromServer?.toString() ??
          'unknown_${DateTime.now().microsecondsSinceEpoch}';

      final int parsedChatId = _safeParseInt(json['chat_id']);
      final int parsedSenderId = _safeParseInt(json['sender_id']);
      final int parsedReceiverId = _safeParseInt(json['receiver_id']);
      final int parsedIsRead = _safeParseInt(json['is_read'], defaultValue: 0);
      final int parsedIsDelivered = _safeParseInt(json['is_delivered'], defaultValue: 0);
      final int parsedIsDeletedSender = _safeParseInt(json['is_deleted_sender'], defaultValue: 0);
      final int parsedIsDeletedReceiver = _safeParseInt(json['is_deleted_receiver'], defaultValue: 0);

      // ✅ SMART MEDIA URL RESOLUTION
      String? mediaUrl = json['media_url']?.toString() ?? json['mediaUrl']?.toString();
      String? lowQualityUrl = json['low_quality_url']?.toString() ?? json['lowQualityUrl']?.toString();
      String? highQualityUrl = json['high_quality_url']?.toString() ?? json['highQualityUrl']?.toString();

      // ✅ MULTIPLE IMAGE URLS
      final mediaUrls = json["media_urls"] != null ? List<String>.from(json["media_urls"]) : null;
      final lowQualityUrls = json["low_quality_urls"] != null ? List<String>.from(json["low_quality_urls"]) : null;
      final highQualityUrls = json["high_quality_urls"] != null ? List<String>.from(json["high_quality_urls"]) : null;

      // ✅ AUTO-RESOLVE MEDIA URLS IF NULL
      if (mediaUrl != null && mediaUrl.isNotEmpty) {
        if (lowQualityUrl == null && mediaUrl.contains('quality=low')) {
          lowQualityUrl = mediaUrl;
        }
        if (highQualityUrl == null && mediaUrl.contains('quality=high')) {
          highQualityUrl = mediaUrl;
        }
        // If no quality specified, use as both
        if (lowQualityUrl == null && !mediaUrl.contains('quality=')) {
          lowQualityUrl = mediaUrl;
        }
        if (highQualityUrl == null && !mediaUrl.contains('quality=')) {
          highQualityUrl = mediaUrl;
        }
      }

      // Use mediaUrl as messageContent for media messages
      final String messageContent = (json['message_type']?.toString() == 'media' ||
          json['message_type']?.toString() == 'encrypted_media')
          ? (mediaUrl ?? json['message_text']?.toString() ?? '')
          : (json['message_text']?.toString() ?? '');

      Uint8List? parsedThumbnail;
      String? thumbnailBase64;

      // ✅ HANDLE THUMBNAIL BASE64
      if (json['thumbnail'] != null && json['thumbnail'] is String) {
        try {
          thumbnailBase64 = json['thumbnail'] as String;
          parsedThumbnail = base64.decode(thumbnailBase64);
        } catch (e) {
          print('❌ Thumbnail decoding error: $e');
        }
      }

      // ✅ ALSO CHECK FOR thumbnail_base64 FIELD
      if (json['thumbnail_base64'] != null && json['thumbnail_base64'] is String) {
        thumbnailBase64 = json['thumbnail_base64'] as String;
        try {
          parsedThumbnail = base64.decode(thumbnailBase64);
        } catch (e) {
          print('❌ Thumbnail base64 decoding error: $e');
        }
      }

      // ✅ HANDLE REPLY AND FORWARD FIELDS
      final String? replyToMessageId = json['reply_to_message_id']?.toString();
      final bool isForwarded = json['is_forwarded'] == true || json['is_forwarded'] == 1;
      final String? forwardedFrom = json['forwarded_from']?.toString();

      // ✅ HANDLE GROUP UPLOAD FIELDS
      final String? groupId = json['group_id']?.toString();
      final int? imageIndex = json['image_index'] != null ? _safeParseInt(json['image_index']) : null;
      final int? totalImages = json['total_images'] != null ? _safeParseInt(json['total_images']) : null;

      DateTime parsedTimestamp;
      final dynamic timestampData = json['timestamp'];
      if (timestampData is int) {
        parsedTimestamp = DateTime.fromMillisecondsSinceEpoch(timestampData);
      } else if (timestampData is String) {
        parsedTimestamp = DateTime.tryParse(timestampData) ?? DateTime.now();
      } else {
        parsedTimestamp = DateTime.now();
      }

      return Message(
        messageId: parsedMessageId,
        chatId: parsedChatId,
        senderId: parsedSenderId,
        receiverId: parsedReceiverId,
        messageContent: messageContent,
        messageType: json['message_type']?.toString() ?? 'text',
        isRead: parsedIsRead,
        timestamp: parsedTimestamp,
        isDelivered: parsedIsDelivered,
        senderName: json['sender_name']?.toString() ?? json['senderName']?.toString(),
        receiverName: json['receiver_name']?.toString() ?? json['receiverName']?.toString(),
        senderPhoneNumber: json['sender_phone_number']?.toString() ?? json['senderPhoneNumber']?.toString(),
        receiverPhoneNumber: json['receiver_phone_number']?.toString() ?? json['receiverPhoneNumber']?.toString(),
        isDeletedSender: parsedIsDeletedSender,
        isDeletedReceiver: parsedIsDeletedReceiver,
        thumbnail: parsedThumbnail,
        thumbnailBase64: thumbnailBase64,
        blurImagePath: json['blur_image_path']?.toString(),
        isImageLoaded: json['is_image_loaded'] == true || json['is_image_loaded'] == 1,
        lowQualityUrl: lowQualityUrl,
        highQualityUrl: highQualityUrl,
        blurHash: json['blur_hash']?.toString() ?? json['blurHash']?.toString(),
        // ✅ NEW FIELDS
        replyToMessageId: replyToMessageId,
        isForwarded: isForwarded,
        forwardedFrom: forwardedFrom,
        // ✅ NEW GROUP UPLOAD FIELDS
        groupId: groupId,
        imageIndex: imageIndex,
        totalImages: totalImages,
        // ✅ NEW MULTIPLE IMAGE URLS
        mediaUrls: mediaUrls,
        lowQualityUrls: lowQualityUrls,
        highQualityUrls: highQualityUrls,
        extraData: json['extra_data'] != null
            ? Map<String, dynamic>.from(json['extra_data'])
            : null,
      );
    } catch (e, stackTrace) {
      print('❌ Error in Message.fromJson: $e\n$stackTrace');
      return Message(
        messageId: 'error_${DateTime.now().microsecondsSinceEpoch}',
        chatId: 0,
        senderId: 0,
        receiverId: 0,
        messageContent: 'Error loading message',
        messageType: 'text',
        isRead: 0,
        timestamp: DateTime.now(),
        isDelivered: 0,
      );
    }
  }

  // ✅ FROM MAP (existing - keep for backward compatibility)
  factory Message.fromMap(Map<String, dynamic> map) {
    return Message.fromJson(map);
  }

  static int _safeParseInt(dynamic value, {int defaultValue = 0}) {
    try {
      if (value == null) return defaultValue;
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? defaultValue;
      if (value is double) return value.toInt();
      return defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  // ✅ TO JSON METHOD - UPDATED WITH NEW FIELDS
  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      'chat_id': chatId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'message_text': messageContent,
      'message_type': messageType,
      'is_read': isRead,
      'timestamp': timestamp.toIso8601String(),
      'is_delivered': isDelivered,
      'sender_name': senderName,
      'receiver_name': receiverName,
      'sender_phone_number': senderPhoneNumber,
      'receiver_phone_number': receiverPhoneNumber,
      'is_deleted_sender': isDeletedSender,
      'is_deleted_receiver': isDeletedReceiver,
      'thumbnail': thumbnailBase64 ?? (thumbnail != null ? base64.encode(thumbnail!) : null),
      'thumbnail_base64': thumbnailBase64,
      'blur_image_path': blurImagePath,
      'is_image_loaded': isImageLoaded,
      'low_quality_url': lowQualityUrl,
      'high_quality_url': highQualityUrl,
      'blur_hash': blurHash,
      // ✅ NEW FIELDS
      'reply_to_message_id': replyToMessageId,
      'is_forwarded': isForwarded,
      'forwarded_from': forwardedFrom,
      // ✅ NEW GROUP UPLOAD FIELDS
      'group_id': groupId,
      'image_index': imageIndex,
      'total_images': totalImages,
      // ✅ NEW MULTIPLE IMAGE URLS
      'media_urls': mediaUrls,
      'low_quality_urls': lowQualityUrls,
      'high_quality_urls': highQualityUrls,
      'extra_data': extraData,
    };
  }

  // ✅ COPYWITH - UPDATED WITH NEW FIELDS
  Message copyWith({
    String? messageId,
    int? chatId,
    int? senderId,
    int? receiverId,
    String? messageContent,
    String? messageType,
    int? isRead,
    DateTime? timestamp,
    int? isDelivered,
    String? senderName,
    String? receiverName,
    String? senderPhoneNumber,
    String? receiverPhoneNumber,
    int? isDeletedSender,
    int? isDeletedReceiver,
    Uint8List? thumbnail,
    String? blurImagePath,
    bool? isImageLoaded,
    String? lowQualityUrl,
    Map<String, dynamic>? extraData,
    String? highQualityUrl,
    String? blurHash,
    String? thumbnailBase64,
    // ✅ NEW FIELDS
    String? replyToMessageId,
    bool? isForwarded,
    String? forwardedFrom,
    // ✅ NEW GROUP UPLOAD FIELDS
    String? groupId,
    int? imageIndex,
    int? totalImages,
    // ✅ NEW MULTIPLE IMAGE URLS
    List<String>? mediaUrls,
    List<String>? lowQualityUrls,
    List<String>? highQualityUrls,
  }) {
    return Message(
      messageId: messageId ?? this.messageId,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      messageContent: messageContent ?? this.messageContent,
      messageType: messageType ?? this.messageType,
      isRead: isRead ?? this.isRead,
      timestamp: timestamp ?? this.timestamp,
      isDelivered: isDelivered ?? this.isDelivered,
      senderName: senderName ?? this.senderName,
      receiverName: receiverName ?? this.receiverName,
      senderPhoneNumber: senderPhoneNumber ?? this.senderPhoneNumber,
      receiverPhoneNumber: receiverPhoneNumber ?? this.receiverPhoneNumber,
      isDeletedSender: isDeletedSender ?? this.isDeletedSender,
      isDeletedReceiver: isDeletedReceiver ?? this.isDeletedReceiver,
      thumbnail: thumbnail ?? this.thumbnail,
      blurImagePath: blurImagePath ?? this.blurImagePath,
      isImageLoaded: isImageLoaded ?? this.isImageLoaded,
      lowQualityUrl: lowQualityUrl ?? this.lowQualityUrl,
      highQualityUrl: highQualityUrl ?? this.highQualityUrl,
      blurHash: blurHash ?? this.blurHash,
      thumbnailBase64: thumbnailBase64 ?? this.thumbnailBase64,
      // ✅ NEW FIELDS
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      isForwarded: isForwarded ?? this.isForwarded,
      forwardedFrom: forwardedFrom ?? this.forwardedFrom,
      // ✅ NEW GROUP UPLOAD FIELDS
      groupId: groupId ?? this.groupId,
      imageIndex: imageIndex ?? this.imageIndex,
      totalImages: totalImages ?? this.totalImages,
      // ✅ NEW MULTIPLE IMAGE URLS
      mediaUrls: mediaUrls ?? this.mediaUrls,
      lowQualityUrls: lowQualityUrls ?? this.lowQualityUrls,
      highQualityUrls: highQualityUrls ?? this.highQualityUrls,
      extraData: extraData ?? this.extraData,
    );
  }

  // ✅ TO MAP (keep for backward compatibility)
  Map<String, dynamic> toMap() {
    return toJson();
  }

  // ✅ Utility Getters
  bool get hasThumbnail => thumbnail != null && thumbnail!.isNotEmpty;
  bool get hasThumbnailBase64 => thumbnailBase64 != null && thumbnailBase64!.isNotEmpty;
  bool get hasBlurImage => blurImagePath != null && blurImagePath!.isNotEmpty;
  bool get hasLowQualityUrl => lowQualityUrl != null && lowQualityUrl!.isNotEmpty;
  bool get hasHighQualityUrl => highQualityUrl != null && highQualityUrl!.isNotEmpty;
  bool get hasBlurHash => blurHash != null && blurHash!.isNotEmpty;

  // ✅ NEW GETTERS FOR REPLY AND FORWARD
  bool get hasReply => replyToMessageId != null && replyToMessageId!.isNotEmpty;
  bool get isForwardedMessage => isForwarded;

  // ✅ NEW GETTERS FOR GROUP UPLOAD
  bool get isGroupImage => groupId != null && groupId!.isNotEmpty;
  bool get hasGroupInfo => groupId != null && imageIndex != null && totalImages != null;
  String get groupPositionInfo => hasGroupInfo ? '${(imageIndex! + 1)}/$totalImages' : '';

  String get displayContent {
    if (messageType == 'media' || messageType == 'encrypted_media') {
      if (!isImageLoaded && hasBlurHash) return '🔄 Loading...';
      if (isGroupImage) return '📷 ${groupPositionInfo}';
      return hasThumbnail ? '📷 Image' : '📷 Media';
    }
    return messageContent;
  }

  String get displayImagePath {
    if (messageType == 'media' || messageType == 'encrypted_media') {
      if (isImageLoaded) return messageContent;
      if (hasLowQualityUrl) return lowQualityUrl!;
      if (hasBlurImage) return blurImagePath!;
      return messageContent;
    }
    return messageContent;
  }

  bool get shouldShowBlur =>
      (messageType == 'media' || messageType == 'encrypted_media') &&
          !isImageLoaded &&
          hasBlurHash &&
          !hasLowQualityUrl;

  bool get shouldUseLowQuality =>
      (messageType == 'media' || messageType == 'encrypted_media') &&
          !isImageLoaded &&
          hasLowQualityUrl;

  bool get shouldShowThumbnail =>
      (messageType == 'media' || messageType == 'encrypted_media') &&
          !isImageLoaded &&
          (hasThumbnail || hasThumbnailBase64) &&
          !hasLowQualityUrl;

  String? get bestAvailableImageUrl {
    if (messageType == 'media' || messageType == 'encrypted_media') {
      if (isImageLoaded && hasHighQualityUrl) return highQualityUrl;
      if (isImageLoaded) return messageContent;
      if (hasLowQualityUrl) return lowQualityUrl;
      if (hasBlurImage) return blurImagePath;
      return messageContent;
    }
    return null;
  }

  // ✅ Get the best available image URL for progressive loading
  String? get progressiveImageUrl {
    if (messageType == 'media' || messageType == 'encrypted_media') {
      // Return low quality first for instant display
      if (hasLowQualityUrl) return lowQualityUrl;
      // Fallback to regular media URL
      return messageContent;
    }
    return null;
  }

  // ✅ Get high quality URL for preloading
  String? get highQualityImageUrl {
    if (messageType == 'media' || messageType == 'encrypted_media') {
      if (hasHighQualityUrl) return highQualityUrl;
      return messageContent;
    }
    return null;
  }

  // ✅ Get thumbnail as Uint8List from base64
  Uint8List? get thumbnailBytes {
    if (thumbnail != null) return thumbnail;
    if (hasThumbnailBase64) {
      try {
        return base64.decode(thumbnailBase64!);
      } catch (e) {
        print('❌ Error decoding thumbnail base64: $e');
        return null;
      }
    }
    return null;
  }

  @override
  String toString() {
    return 'Message(id: $messageId, chat: $chatId, type: $messageType, '
        'content: ${messageContent.length > 20 ? '${messageContent.substring(0, 20)}...' : messageContent}, '
        'lowQuality: ${lowQualityUrl != null ? "available" : "none"}, '
        'highQuality: ${highQualityUrl != null ? "available" : "none"}, '
        'blurHash: ${blurHash != null ? "available" : "none"}, '
        'thumbnailBase64: ${thumbnailBase64 != null ? "${thumbnailBase64?.length} chars" : "none"}, '
        'replyTo: ${replyToMessageId ?? "none"}, '
        'forwarded: $isForwarded, '
        'groupId: ${groupId ?? "none"}, '
        'imageIndex: ${imageIndex ?? "none"}, '
        'totalImages: ${totalImages ?? "none"}, '
        'mediaUrls: ${mediaUrls?.length ?? 0}, '
        'lowQualityUrls: ${lowQualityUrls?.length ?? 0}, '
        'highQualityUrls: ${highQualityUrls?.length ?? 0}, '
        'loaded: $isImageLoaded)';
  }
}

@HiveType(typeId: 1)
class Chat extends HiveObject {
  @HiveField(0)
  int chatId;

  @HiveField(1)
  int contactId;

  @HiveField(2)
  List<int> userIds;

  @HiveField(3)
  String chatTitle;

  @HiveField(4)
  String? lastMessage;

  @HiveField(5)
  DateTime? lastMessageTime;

  @HiveField(6)
  int unreadCount;

  Chat({
    required this.chatId,
    required this.contactId,
    required this.userIds,
    required this.chatTitle,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
  });

  factory Chat.fromMap(Map<String, dynamic> map) {
    return Chat(
      chatId: map['chat_id'] as int,
      contactId: map['contact_id'] as int,
      userIds: List<int>.from(map['user_ids'] ?? []),
      chatTitle: map['chat_title'] as String? ?? '',
      lastMessage: map['last_message'] as String?,
      lastMessageTime: map['last_message_time'] != null
          ? DateTime.tryParse(map['last_message_time'].toString())
          : null,
      unreadCount: map['unread_count'] as int? ?? 0,
    );
  }

  // ✅ ADD FROMJSON METHOD FOR CHAT TOO
  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat.fromMap(json);
  }

  Map<String, dynamic> toMap() {
    return {
      'chat_id': chatId,
      'contact_id': contactId,
      'user_ids': userIds,
      'chat_title': chatTitle,
      'last_message': lastMessage,
      'last_message_time': lastMessageTime?.toIso8601String(),
      'unread_count': unreadCount,
    };
  }

  // ✅ ADD TOJSON METHOD
  Map<String, dynamic> toJson() {
    return toMap();
  }

  @override
  String toString() {
    return 'Chat(id: $chatId, title: $chatTitle, contact: $contactId, unread: $unreadCount)';
  }
}