import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/image_enhancement_service.dart';

class SelectedImagesReviewScreen extends StatefulWidget {
  final List<File> selectedImages;

  const SelectedImagesReviewScreen({
    super.key,
    required this.selectedImages,
  });

  @override
  State<SelectedImagesReviewScreen> createState() => _SelectedImagesReviewScreenState();
}

class _SelectedImagesReviewScreenState extends State<SelectedImagesReviewScreen> {
  late List<File> _images;
  final PageController _pageController = PageController();
  bool _isEnhancing = false;
  int? _enhancingIndex;

  @override
  void initState() {
    super.initState();
    _images = List.from(widget.selectedImages);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
      // Update page controller if needed
      if (_pageController.hasClients) {
        if (index >= _images.length && _images.isNotEmpty) {
          _pageController.jumpToPage(_images.length - 1);
        }
      }
      // If no images left, go back with empty list
      if (_images.isEmpty) {
        Navigator.pop(context, []);
      }
    });
  }

  void _confirmSelection() {
    // Only return updated list when Done is pressed
    if (_images.isEmpty) {
      Navigator.pop(context, []);
    } else {
      Navigator.pop(context, _images);
    }
  }

  Future<void> _enhanceImage(int index) async {
    setState(() {
      _isEnhancing = true;
      _enhancingIndex = index;
    });

    try {
      final enhancedFile = await ImageEnhancementService.enhanceProductImage(_images[index]);
      setState(() {
        _images[index] = enhancedFile;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Professional background applied! ✨')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enhancement failed. Please try again.')),
      );
    } finally {
      setState(() {
        _isEnhancing = false;
        _enhancingIndex = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_images.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
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
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context, []),
            ),
          ),
          title: const Text(
            'Selected Images',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          centerTitle: true,
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
        body: const Center(
          child: Text(
            'No images selected',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
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
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              // Return original list when back is pressed (discard changes)
              Navigator.pop(context, widget.selectedImages);
            },
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
              '${_images.length} Image${_images.length > 1 ? 's' : ''} Selected',
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
        actions: [
          // Plus button to add more images (if less than 5)
          if (_images.length < 5)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton(
                onPressed: () async {
                  // Open gallery to add more images
                  final ImagePicker picker = ImagePicker();
                  final List<XFile>? pickedFiles = await picker.pickMultiImage(
                    maxWidth: 1080,
                    maxHeight: 1920,
                    imageQuality: 75,
                  );

                  if (pickedFiles != null && pickedFiles.isNotEmpty) {
                    final remainingSlots = 5 - _images.length;
                    final imagesToAdd = pickedFiles.take(remainingSlots).map((file) => File(file.path)).toList();
                    setState(() {
                      _images.addAll(imagesToAdd);
                    });
                    
                    if (pickedFiles.length > remainingSlots) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Only $remainingSlots image(s) added. Maximum 5 images allowed.'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                },
                icon: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
                  ),
                  child: const Icon(
                    Icons.add,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Main image viewer
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _images.length,
              itemBuilder: (context, index) {
                return Stack(
                  children: [
                    Center(
                      child: Image.file(
                        _images[index],
                        fit: BoxFit.contain,
                      ),
                    ),
                    // Remove button
                    Positioned(
                      top: 16,
                      right: 16,
                      child: GestureDetector(
                        onTap: () => _removeImage(index),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                    // Image number indicator
                    Positioned(
                      top: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${index + 1} / ${_images.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    // Magic Enhance button in bottom left
                    Positioned(
                      bottom: 16,
                      left: 16,
                      child: GestureDetector(
                        onTap: (_isEnhancing) ? null : () => _enhanceImage(index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.purple, Colors.blue],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.withOpacity(0.3),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isEnhancing && _enhancingIndex == index)
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              else
                                const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                              const SizedBox(width: 6),
                              const Text(
                                'Magic Enhance ✨',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Done button in bottom right corner
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: TextButton(
                        onPressed: _confirmSelection,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF25D366),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check, color: Colors.white, size: 18),
                              const SizedBox(width: 4),
                              const Text(
                                'Done',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // Thumbnail strip at bottom (Drag to reorder)
          Container(
            height: 110,
            padding: const EdgeInsets.symmetric(vertical: 10),
            color: Colors.black,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _images.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (oldIndex < newIndex) {
                    newIndex -= 1;
                  }
                  final item = _images.removeAt(oldIndex);
                  _images.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                return GestureDetector(
                  key: ValueKey(_images[index].path),
                  onTap: () {
                    _pageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: Container(
                    width: 80,
                    height: 80,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _pageController.hasClients && _pageController.page?.round() == index 
                            ? const Color(0xFF25D366) 
                            : Colors.white24,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        _images[index],
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

