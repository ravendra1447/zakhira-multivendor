import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import '../models/chat_model.dart';

class ChatMessageWidget extends StatelessWidget {
  final Message msg;
  final bool isSender;
  final VoidCallback? onImageTap;
  final VoidCallback? onMediaTap;

  const ChatMessageWidget({
    Key? key,
    required this.msg,
    this.isSender = false,
    this.onImageTap,
    this.onMediaTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bgColor = isSender ? Color(0xFFDCF8C6) : Colors.white;
    final align = isSender ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: isSender ? const Radius.circular(12) : const Radius.circular(4),
      bottomRight: isSender ? const Radius.circular(4) : const Radius.circular(12),
    );

    return Column(
      crossAxisAlignment: align,
      children: [
        // Reply indicator if this is a reply
        if (msg.replyToMessageId != null && msg.replyToMessageId!.isNotEmpty)
          _buildReplyIndicator(context),

        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: borderRadius,
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          child: _buildMessageContent(),
        ),

        // Message status and timestamp
        _buildMessageFooter(),
      ],
    );
  }

  Widget _buildReplyIndicator(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 8),
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Icon(Icons.reply, size: 16, color: Colors.grey[600]),
          SizedBox(width: 4),
          Expanded(
            child: Text(
              'Replying to message',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageContent() {
    switch (msg.messageType) {
      case 'media':
        return _buildMediaMessage();
      case 'image':
        return _buildImageMessage();
      case 'video':
        return _buildVideoMessage();
      case 'file':
        return _buildFileMessage();
      case 'audio':
        return _buildAudioMessage();
      default:
        return _buildTextMessage();
    }
  }

  Widget _buildMediaMessage() {
    return GestureDetector(
      onTap: onMediaTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail display
          if (msg.thumbnailBase64 != null && msg.thumbnailBase64!.isNotEmpty)
            _buildThumbnailFromBase64()
          else if (msg.blurHash != null && msg.blurHash!.isNotEmpty)
            _buildBlurHashPlaceholder()
          else
            _buildMediaPlaceholder(),

          // File info if available
          if (_hasFileInfo())
            _buildFileInfo(),
        ],
      ),
    );
  }

  Widget _buildImageMessage() {
    return GestureDetector(
      onTap: onImageTap,
      child: Stack(
        children: [
          // Thumbnail from base64
          if (msg.thumbnailBase64 != null && msg.thumbnailBase64!.isNotEmpty)
            _buildThumbnailFromBase64()
          else if (msg.blurHash != null && msg.blurHash!.isNotEmpty)
            _buildBlurHashPlaceholder()
          else
            _buildImagePlaceholder(),

          // Image indicator
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                Icons.photo,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoMessage() {
    return GestureDetector(
      onTap: onMediaTap,
      child: Stack(
        children: [
          // Thumbnail from base64
          if (msg.thumbnailBase64 != null && msg.thumbnailBase64!.isNotEmpty)
            _buildThumbnailFromBase64()
          else if (msg.blurHash != null && msg.blurHash!.isNotEmpty)
            _buildBlurHashPlaceholder()
          else
            _buildVideoPlaceholder(),

          // Video play indicator
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),

          // Video duration if available
          if (_hasFileInfo())
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _getFileInfoText(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFileMessage() {
    return GestureDetector(
      onTap: onMediaTap,
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(
              Icons.insert_drive_file,
              color: Colors.grey[600],
              size: 32,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getFileName() ?? 'File',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_hasFileInfo())
                    Text(
                      _getFileInfoText(),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.download,
              color: Colors.grey[600],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioMessage() {
    return GestureDetector(
      onTap: onMediaTap,
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(
              Icons.audiotrack,
              color: Colors.blue,
              size: 32,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Audio Message',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  if (_hasFileInfo())
                    Text(
                      _getFileInfoText(),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.play_arrow,
              color: Colors.blue,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextMessage() {
    return SelectableText(
      msg.messageContent,
      style: TextStyle(fontSize: 16),
    );
  }

  Widget _buildThumbnailFromBase64() {
    try {
      final cleanBase64 = msg.thumbnailBase64!
          .replaceAll('\n', '')
          .replaceAll('\r', '')
          .trim();

      final bytes = base64Decode(cleanBase64);

      return Image.memory(
        bytes,
        width: 200,
        height: 150,
        fit: BoxFit.cover,
        gaplessPlayback: true, // ✅ prevents flicker while UI updates
        errorBuilder: (context, error, stackTrace) {
          print("❌ Thumbnail decode error: $error");
          return _buildMediaPlaceholder();
        },
      );
    } catch (e) {
      print("❌ Exception while decoding base64: $e");
      return _buildMediaPlaceholder();
    }
  }

  Widget _buildBlurHashPlaceholder() {
    return Container(
      width: 200,
      height: 150,
      child: BlurHash(
        hash: msg.blurHash!,
        imageFit: BoxFit.cover,
        decodingWidth: 32,
        decodingHeight: 32,
        image: msg.messageContent.isNotEmpty &&
            (msg.messageContent.startsWith('http') ||
                msg.messageContent.startsWith('/'))
            ? msg.messageContent
            : null,
      ),
    );
  }

  Widget _buildMediaPlaceholder() {
    return Container(
      width: 200,
      height: 150,
      color: Colors.grey[300],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_library,
            color: Colors.grey,
            size: 40,
          ),
          SizedBox(height: 8),
          Text(
            'Media',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      width: 200,
      height: 150,
      color: Colors.grey[300],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo,
            color: Colors.grey,
            size: 40,
          ),
          SizedBox(height: 8),
          Text(
            'Image',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPlaceholder() {
    return Container(
      width: 200,
      height: 150,
      color: Colors.grey[300],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.videocam,
            color: Colors.grey,
            size: 40,
          ),
          SizedBox(height: 8),
          Text(
            'Video',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileInfo() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_getFileTypeIcon() != null)
            Icon(
              _getFileTypeIcon(),
              color: Colors.white,
              size: 12,
            ),
          SizedBox(width: 4),
          Text(
            _getFileInfoText(),
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: isSender ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Text(
            _formatTime(msg.timestamp),
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(width: 4),
          if (isSender) _buildMessageStatus(),
        ],
      ),
    );
  }

  Widget _buildMessageStatus() {
    if (msg.isRead == 1) {
      return Icon(Icons.done_all, size: 12, color: Colors.blue);
    } else if (msg.isDelivered == 1) {
      return Icon(Icons.done_all, size: 12, color: Colors.grey);
    } else {
      return Icon(Icons.done, size: 12, color: Colors.grey);
    }
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (messageDate == today) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else {
      return '${timestamp.day}/${timestamp.month} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  // Helper methods
  bool _hasFileInfo() {
    return msg.messageContent.isNotEmpty &&
        (msg.messageContent.contains('.') ||
            _getFileSize() != null);
  }

  String? _getFileName() {
    if (msg.messageContent.contains('/')) {
      return msg.messageContent.split('/').last;
    }
    return null;
  }

  double? _getFileSize() {
    // Extract file size from message content or use metadata
    // This would depend on your actual data structure
    return null;
  }

  String _getFileInfoText() {
    final size = _getFileSize();
    if (size != null) {
      if (size >= 1024 * 1024) {
        return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
      } else if (size >= 1024) {
        return '${(size / 1024).toStringAsFixed(1)} KB';
      } else {
        return '${size.toStringAsFixed(0)} B';
      }
    }

    // Fallback to file extension
    final fileName = _getFileName();
    if (fileName != null && fileName.contains('.')) {
      final ext = fileName.split('.').last.toUpperCase();
      return '$ext File';
    }

    return 'File';
  }

  IconData? _getFileTypeIcon() {
    final fileName = _getFileName()?.toLowerCase() ?? '';

    if (fileName.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (fileName.endsWith('.doc') || fileName.endsWith('.docx')) return Icons.description;
    if (fileName.endsWith('.xls') || fileName.endsWith('.xlsx')) return Icons.table_chart;
    if (fileName.endsWith('.zip') || fileName.endsWith('.rar')) return Icons.archive;
    if (fileName.endsWith('.mp3') || fileName.endsWith('.wav')) return Icons.audiotrack;
    if (fileName.endsWith('.mp4') || fileName.endsWith('.avi')) return Icons.videocam;

    return Icons.insert_drive_file;
  }
}