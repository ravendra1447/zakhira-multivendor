// lib/pages/media_viewer_screen.dart - COMPLETELY FIXED VERSION

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import '../models/chat_model.dart';
import 'message_info_screen.dart';

class MediaViewerScreen extends StatefulWidget {
  final String mediaUrl;
  final String messageId;
  final bool isLocalFile;
  final int chatId;
  final String? otherUserName; // ✅ FIX: Add otherUserName parameter

  const MediaViewerScreen({
    Key? key,
    required this.mediaUrl,
    required this.messageId,
    required this.isLocalFile,
    required this.chatId,
    this.otherUserName,
  }) : super(key: key);

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  final PageController _pageController = PageController();
  final _messageBox = Hive.box<Message>('messages');

  List<Message> _mediaMessages = [];
  int _currentIndex = 0;
  double _verticalDragOffset = 0.0;
  double _opacity = 1.0;

  @override
  void initState() {
    super.initState();
    _loadMediaMessages();
  }

  void _loadMediaMessages() {
    try {
      // Get all media messages for this chat
      final allMessages = _messageBox.values.toList();
      _mediaMessages = allMessages
          .where((msg) =>
      msg.chatId == widget.chatId &&
          (msg.messageType == 'media' || msg.messageType == 'encrypted_media') &&
          msg.messageContent.isNotEmpty &&
          !msg.messageContent.contains('[Media URL Missing]') &&
          !msg.messageContent.contains('[Decryption Failed]'))
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Find current index - EXACT MATCH
      _currentIndex = _mediaMessages.indexWhere((msg) =>
      msg.messageId == widget.messageId);

      if (_currentIndex == -1) {
        // Fallback: try to match by media URL
        _currentIndex = _mediaMessages.indexWhere((msg) =>
        msg.messageContent == widget.mediaUrl);
      }

      if (_currentIndex == -1) _currentIndex = 0;

      print("📸 Loaded ${_mediaMessages.length} media messages, current index: $_currentIndex");

      // Set page controller to current index
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients && _mediaMessages.length > 1) {
          _pageController.jumpToPage(_currentIndex);
        }
      });

    } catch (e) {
      print("❌ Error loading media messages: $e");
    }
  }

  void _goToNextImage() {
    if (_currentIndex < _mediaMessages.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _pageController.animateToPage(
        _currentIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToPreviousImage() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _pageController.animateToPage(
        _currentIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    _verticalDragOffset += details.primaryDelta!;
    final screenHeight = MediaQuery.of(context).size.height;
    final dragPercentage = (_verticalDragOffset / screenHeight).abs();

    setState(() {
      _opacity = 1.0 - dragPercentage.clamp(0.0, 1.0);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final screenHeight = MediaQuery.of(context).size.height;
    final dragPercentage = (_verticalDragOffset / screenHeight).abs();

    if (dragPercentage > 0.2) { // 20% threshold to close
      Navigator.of(context).pop();
    } else {
      // Reset to original position
      setState(() {
        _verticalDragOffset = 0.0;
        _opacity = 1.0;
      });
    }
  }

  // ✅ FIXED: CORRECT HERO TAG FOR EACH IMAGE
  String _getHeroTag(Message message) {
    return '${message.messageId}_${message.messageContent}';
  }

  Widget _buildMediaItem(Message message, int index) {
    final mediaUrl = message.messageContent;
    final isLocalFile = mediaUrl.startsWith('/') ||
        mediaUrl.contains('cache') ||
        mediaUrl.contains('temp_') ||
        (File(mediaUrl).existsSync() && !mediaUrl.startsWith('http'));

    final heroTag = _getHeroTag(message);
    final isCurrentImage = index == _currentIndex;

    try {
      if (isLocalFile) {
        return GestureDetector(
          onVerticalDragUpdate: isCurrentImage ? _onVerticalDragUpdate : null,
          onVerticalDragEnd: isCurrentImage ? _onVerticalDragEnd : null,
          onLongPress: isCurrentImage ? () => _showImageOptions(context, message) : null, // ✅ FIX: Long press for info
          child: Transform.translate(
            offset: Offset(0, isCurrentImage ? _verticalDragOffset : 0),
            child: Opacity(
              opacity: isCurrentImage ? _opacity : 1.0,
              child: Hero(
                tag: heroTag, // ✅ EXACT SAME TAG AS CHATSCREEN
                child: PhotoView(
                  imageProvider: FileImage(File(mediaUrl)),
                  backgroundDecoration: const BoxDecoration(color: Colors.black),
                  minScale: PhotoViewComputedScale.contained * 0.8,
                  maxScale: PhotoViewComputedScale.covered * 4.0,
                  initialScale: PhotoViewComputedScale.contained,
                ),
              ),
            ),
          ),
        );
      } else {
        return GestureDetector(
          onVerticalDragUpdate: isCurrentImage ? _onVerticalDragUpdate : null,
          onVerticalDragEnd: isCurrentImage ? _onVerticalDragEnd : null,
          onLongPress: isCurrentImage ? () => _showImageOptions(context, message) : null, // ✅ FIX: Long press for info
          child: Transform.translate(
            offset: Offset(0, isCurrentImage ? _verticalDragOffset : 0),
            child: Opacity(
              opacity: isCurrentImage ? _opacity : 1.0,
              child: Hero(
                tag: heroTag, // ✅ EXACT SAME TAG AS CHATSCREEN
                child: PhotoView(
                  imageProvider: CachedNetworkImageProvider(mediaUrl),
                  backgroundDecoration: const BoxDecoration(color: Colors.black),
                  minScale: PhotoViewComputedScale.contained * 0.8,
                  maxScale: PhotoViewComputedScale.covered * 4.0,
                  initialScale: PhotoViewComputedScale.contained,
                  // ✅ FIX: Show loading indicator while image loads
                  loadingBuilder: (context, event) {
                    if (event == null) {
                      // Image is loaded, don't show loading
                      return Container(color: Colors.black);
                    }
                    final progress = event.cumulativeBytesLoaded / (event.expectedTotalBytes ?? 1);
                    return Stack(
                      children: [
                        Container(color: Colors.black),
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: progress,
                                backgroundColor: Colors.white24,
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '${(progress * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.white, size: 50),
                        const SizedBox(height: 16),
                        const Text(
                          'Failed to load image',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap to close',
                          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    } catch (e) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 50),
            const SizedBox(height: 16),
            Text(
              'Error: $e',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Close',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: Stack(
          children: [
            // ✅ FIXED: PAGE VIEW STARTS FROM CURRENT IMAGE
            if (_mediaMessages.length > 1)
              PageView.builder(
                controller: _pageController,
                itemCount: _mediaMessages.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                    _verticalDragOffset = 0.0;
                    _opacity = 1.0;
                  });
                },
                itemBuilder: (context, index) {
                  return _buildMediaItem(_mediaMessages[index], index);
                },
              )
            else if (_mediaMessages.isNotEmpty)
              _buildMediaItem(_mediaMessages[_currentIndex], _currentIndex)
            else
              _buildSingleMediaView(),

            // CLOSE BUTTON (TOP LEFT)
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
            ),

            // IMAGE COUNTER (TOP CENTER) - Only show if multiple images
            if (_mediaMessages.length > 1)
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_currentIndex + 1}/${_mediaMessages.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // ✅ FIX: Timestamp display at bottom (WhatsApp style)
            if (_mediaMessages.isNotEmpty)
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatTime(_mediaMessages[_currentIndex].timestamp),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          // ✅ FIX: Show delivery/seen status
                          if (_mediaMessages[_currentIndex].isDelivered == 1)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(width: 4),
                                Icon(
                                  _mediaMessages[_currentIndex].isRead == 1
                                      ? Icons.done_all
                                      : Icons.done_all,
                                  size: 12,
                                  color: _mediaMessages[_currentIndex].isRead == 1
                                      ? Colors.blue
                                      : Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _mediaMessages[_currentIndex].isRead == 1 ? 'Seen' : 'Delivered',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // SWIPE GESTURE DETECTORS FOR SINGLE IMAGE
            if (_mediaMessages.length == 1)
              Positioned.fill(
                child: Row(
                  children: [
                    // LEFT SWIPE FOR PREVIOUS
                    Expanded(
                      flex: 1,
                      child: GestureDetector(
                        onHorizontalDragEnd: (details) {
                          if (details.primaryVelocity! < -100) {
                            _goToPreviousImage();
                          } else if (details.primaryVelocity! > 100) {
                            _goToNextImage();
                          }
                        },
                        child: Container(color: Colors.transparent),
                      ),
                    ),

                    // MIDDLE AREA FOR VERTICAL DRAG
                    Expanded(
                      flex: 3,
                      child: Container(color: Colors.transparent),
                    ),

                    // RIGHT SWIPE FOR NEXT
                    Expanded(
                      flex: 1,
                      child: GestureDetector(
                        onHorizontalDragEnd: (details) {
                          if (details.primaryVelocity! < -100) {
                            _goToPreviousImage();
                          } else if (details.primaryVelocity! > 100) {
                            _goToNextImage();
                          }
                        },
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleMediaView() {
    try {
      // ✅ FIXED: CORRECT HERO TAG FOR SINGLE IMAGE
      final heroTag = '${widget.messageId}_${widget.mediaUrl}';

      if (widget.isLocalFile) {
        return GestureDetector(
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          child: Transform.translate(
            offset: Offset(0, _verticalDragOffset),
            child: Opacity(
              opacity: _opacity,
              child: Hero(
                tag: heroTag, // ✅ EXACT SAME TAG
                child: PhotoView(
                  imageProvider: FileImage(File(widget.mediaUrl)),
                  backgroundDecoration: const BoxDecoration(color: Colors.black),
                  minScale: PhotoViewComputedScale.contained * 0.8,
                  maxScale: PhotoViewComputedScale.covered * 4.0,
                  initialScale: PhotoViewComputedScale.contained,
                ),
              ),
            ),
          ),
        );
      } else {
        return GestureDetector(
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          child: Transform.translate(
            offset: Offset(0, _verticalDragOffset),
            child: Opacity(
              opacity: _opacity,
              child: Hero(
                tag: heroTag, // ✅ EXACT SAME TAG
                child: PhotoView(
                  imageProvider: CachedNetworkImageProvider(widget.mediaUrl),
                  backgroundDecoration: const BoxDecoration(color: Colors.black),
                  minScale: PhotoViewComputedScale.contained * 0.8,
                  maxScale: PhotoViewComputedScale.covered * 4.0,
                  initialScale: PhotoViewComputedScale.contained,
                  // ✅ FIX: Show loading indicator while image loads
                  loadingBuilder: (context, event) {
                    if (event == null) {
                      // Image is loaded, don't show loading
                      return Container(color: Colors.black);
                    }
                    final progress = event.cumulativeBytesLoaded / (event.expectedTotalBytes ?? 1);
                    return Stack(
                      children: [
                        Container(color: Colors.black),
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: progress,
                                backgroundColor: Colors.white24,
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '${(progress * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      }
    } catch (e) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 50),
            const SizedBox(height: 16),
            Text(
              'Error: $e',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Close',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }
  }

  // ✅ FIX: Format time for display
  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);
    
    final timeStr = DateFormat('h:mm a').format(timestamp);
    
    if (messageDate == today) {
      return 'Today, $timeStr';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday, $timeStr';
    } else {
      return DateFormat('dd/MM/yyyy, h:mm a').format(timestamp);
    }
  }

  // ✅ FIX: Show image options on long press (WhatsApp style)
  void _showImageOptions(BuildContext context, Message message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Info'),
              onTap: () {
                Navigator.pop(context); // Close bottom sheet
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MessageInfoScreen(
                      message: message,
                      otherUserName: widget.otherUserName ?? 'User',
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(context);
                // Add share functionality if needed
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Save'),
              onTap: () {
                Navigator.pop(context);
                // Add save functionality if needed
              },
            ),
          ],
        ),
      ),
    );
  }
}