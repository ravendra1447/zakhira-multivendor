class MarketplaceAttachment {
  final int id;
  final int messageId;
  final String fileName;
  final String filePath;
  final int fileSize;
  final String fileType;
  final String? thumbnailPath;
  final DateTime createdAt;

  MarketplaceAttachment({
    required this.id,
    required this.messageId,
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    required this.fileType,
    this.thumbnailPath,
    required this.createdAt,
  });

  factory MarketplaceAttachment.fromJson(Map<String, dynamic> json) {
    return MarketplaceAttachment(
      id: json['id'] ?? 0,
      messageId: json['message_id'] ?? 0,
      fileName: json['file_name'] ?? '',
      filePath: json['file_path'] ?? '',
      fileSize: json['file_size'] ?? 0,
      fileType: json['file_type'] ?? '',
      thumbnailPath: json['thumbnail_path'],
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'message_id': messageId,
      'file_name': fileName,
      'file_path': filePath,
      'file_size': fileSize,
      'file_type': fileType,
      'thumbnail_path': thumbnailPath,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
