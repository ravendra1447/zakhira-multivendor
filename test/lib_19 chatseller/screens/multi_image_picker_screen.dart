import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class MultiImagePickerScreen extends StatefulWidget {
  final int maxSelection;
  final int chatId;
  final int receiverId;

  const MultiImagePickerScreen({
    Key? key,
    this.maxSelection = 10,
    required this.chatId,
    required this.receiverId,
  }) : super(key: key);

  @override
  State<MultiImagePickerScreen> createState() => _MultiImagePickerScreenState();
}

class _MultiImagePickerScreenState extends State<MultiImagePickerScreen> {
  List<File> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  Future<void> _pickMultipleImages() async {
    setState(() => _isLoading = true);

    try {
      final List<XFile>? pickedFiles = await _picker.pickMultiImage(
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 75,
      );

      if (pickedFiles != null && pickedFiles.isNotEmpty) {
        if (pickedFiles.length > widget.maxSelection) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Maximum ${widget.maxSelection} images allowed. First ${widget.maxSelection} will be selected.'),
            ),
          );

          final limitedFiles = pickedFiles.take(widget.maxSelection).toList();
          setState(() {
            _selectedImages = limitedFiles.map((file) => File(file.path)).toList();
          });
        } else {
          setState(() {
            _selectedImages = pickedFiles.map((file) => File(file.path)).toList();
          });
        }
      }
    } catch (e) {
      print("Error picking images: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to pick images')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  Future<void> _sendImages() async {
    if (_selectedImages.isEmpty) return;
    Navigator.pop(context, _selectedImages);
  }

  Widget _buildImageGrid() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading images...'),
          ],
        ),
      );
    }

    if (_selectedImages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.photo_library, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No images selected',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _pickMultipleImages,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF075E54),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                'SELECT IMAGES',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _selectedImages.length,
      itemBuilder: (context, index) {
        final imageFile = _selectedImages[index];

        return Stack(
          children: [
            Image.file(
              imageFile,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),

            Positioned(
              top: 5,
              right: 5,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),

            Positioned(
              top: 5,
              left: 5,
              child: GestureDetector(
                onTap: () => _removeImage(index),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F1F1F),
        elevation: 0,
        shadowColor: Colors.black.withOpacity(0.3),
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF25D366).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.photo_library,
                color: Color(0xFF25D366),
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _selectedImages.isEmpty
                  ? 'Select Images'
                  : 'Selected ${_selectedImages.length}/${widget.maxSelection}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          if (_selectedImages.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF25D366), Color(0xFF128C7E)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF25D366).withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextButton(
                onPressed: _sendImages,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'SEND ',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_selectedImages.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  const Color(0xFF25D366).withOpacity(0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
      body: _buildImageGrid(),
      floatingActionButton: _selectedImages.isNotEmpty && _selectedImages.length < widget.maxSelection
          ? FloatingActionButton(
        onPressed: _pickMultipleImages,
        backgroundColor: const Color(0xFF075E54),
        child: const Icon(Icons.add, color: Colors.white),
      )
          : null,
    );
  }
}