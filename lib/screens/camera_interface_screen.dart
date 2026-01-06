import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'selected_images_review_screen.dart';
import 'product_selection_screen.dart';

class CameraInterfaceScreen extends StatefulWidget {
  final bool returnImagesDirectly; // If true, return images directly instead of opening ProductSelectionScreen
  final List<File>? initialSelectedImages; // Prefill with existing images

  const CameraInterfaceScreen({super.key, this.returnImagesDirectly = false, this.initialSelectedImages});

  @override
  State<CameraInterfaceScreen> createState() => _CameraInterfaceScreenState();
}

class _CameraInterfaceScreenState extends State<CameraInterfaceScreen> {
  final ImagePicker _picker = ImagePicker();
  String _selectedMode = 'PHOTO'; // PHOTO, VIDEO, VIDEO NOTE
  bool _isFlashOn = false;
  bool _isFrontCamera = false;
  double _zoomLevel = 1.0;
  List<File> _selectedImages = [];
  Set<String> _selectedImagePaths = {}; // Track selected image paths for gallery ticks
  bool _isMultipleMode = false;
  final int _maxImages = 5;
  bool _isNavigatingToProduct = false; // Flag to hide camera when navigating

  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialSelectedImages != null && widget.initialSelectedImages!.isNotEmpty) {
      _selectedImages = List<File>.from(widget.initialSelectedImages!);
      _selectedImagePaths.addAll(widget.initialSelectedImages!.map((f) => f.path));
    }
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      setState(() {
        _isInitializing = true;
      });

      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras![_isFrontCamera ? 1 : 0],
          ResolutionPreset.high,
          enableAudio: false,
        );

        await _cameraController!.initialize();

        setState(() {
          _isCameraInitialized = true;
          _isInitializing = false;
        });
      } else {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      print("Error initializing camera: $e");
      setState(() {
        _isInitializing = false;
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras == null || _cameras!.length < 2) return;

    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });

    await _cameraController?.dispose();
    await _initializeCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  void _removeImage(int index) {
    if (index >= 0 && index < _selectedImages.length) {
      setState(() {
        final removedFile = _selectedImages[index];
        _selectedImages.removeAt(index);
        _selectedImagePaths.remove(removedFile.path);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera preview area with real camera feed
            GestureDetector(
              onScaleStart: (details) {
                // Store initial zoom level
              },
              onScaleUpdate: (details) {
                if (_cameraController != null && _cameraController!.value.isInitialized) {
                  setState(() {
                    _zoomLevel = (_zoomLevel * details.scale).clamp(1.0, 10.0);
                    _cameraController!.setZoomLevel(_zoomLevel);
                  });
                }
              },
              child: (_isCameraInitialized && _cameraController != null && !_isNavigatingToProduct)
                  ? SizedBox.expand(
                child: CameraPreview(_cameraController!),
              )
                  : Container(
                width: double.infinity,
                height: double.infinity,
                color: Colors.black,
                child: _isInitializing
                    ? const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                  ),
                )
                    : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.camera_alt,
                        size: 80,
                        color: Colors.white.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Camera not available',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Top bar with close button and flash
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Close button (X)
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    // Flash/AI icon
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isFlashOn = !_isFlashOn;
                        });
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isFlashOn ? Icons.flash_on : Icons.flash_off,
                          color: _isFlashOn ? Colors.yellow : Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Plus button at top right
            Positioned(
              top: 60,
              right: 16,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Plus button (to add more images)
                  if (_selectedImages.length < _maxImages)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: GestureDetector(
                        onTap: () => _openGallery(),
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
                          ),
                          child: const Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Bottom controls bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: 20,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Mode selector (VIDEO, PHOTO, VIDEO NOTE) + Send button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildModeButton('VIDEO', Icons.videocam),
                        const SizedBox(width: 16),
                        _buildModeButton('PHOTO', Icons.camera_alt),
                        const SizedBox(width: 16),
                        _buildModeButton('VIDEO NOTE', Icons.note),
                        const SizedBox(width: 12),
                        if (_selectedImages.isNotEmpty)
                          GestureDetector(
                            onTap: () async {
                              if (widget.returnImagesDirectly) {
                                Navigator.pop(context, _selectedImages);
                                return;
                              }
                              if (_selectedImages.isNotEmpty) {
                                setState(() {
                                  _isNavigatingToProduct = true;
                                });
                                final finalResult = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ProductSelectionScreen(
                                      selectedImages: List.from(_selectedImages),
                                    ),
                                  ),
                                );
                                if (finalResult != null && finalResult is List<File>) {
                                  Navigator.pop(context, finalResult);
                                } else {
                                  setState(() {
                                    _isNavigatingToProduct = false;
                                  });
                                }
                              }
                            },
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFF25D366),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF25D366).withOpacity(0.3),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  const Icon(Icons.send, color: Colors.white, size: 18),
                                  Positioned(
                                    bottom: 2,
                                    right: 2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.25),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '${_selectedImages.length}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Selected images slider (if any images selected)
                    if (_selectedImages.isNotEmpty)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          const double spacing = 8;
                          final double tileWidth = (constraints.maxWidth - (3 * spacing)) / 4;
                          return SizedBox(
                            height: tileWidth,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _selectedImages.length,
                              itemBuilder: (context, index) {
                                return GestureDetector(
                                  onTap: () => _removeImage(index),
                                  child: Container(
                                    width: tileWidth,
                                    height: tileWidth,
                                    margin: const EdgeInsets.only(right: spacing),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                    child: Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: Image.file(
                                            _selectedImages[index],
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            height: double.infinity,
                                          ),
                                        ),
                                        Positioned(
                                          top: 2,
                                          right: 2,
                                          child: GestureDetector(
                                            onTap: () => _removeImage(index),
                                            child: Container(
                                              width: 20,
                                              height: 20,
                                              decoration: const BoxDecoration(
                                                color: Colors.red,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.close,
                                                color: Colors.white,
                                                size: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),

                    // Done button moved next to "VIDEO NOTE" above

                    const SizedBox(height: 12),

                    // Bottom controls row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Gallery button - opens gallery where single click selects one, long press enables multiple
                        // Show last selected image if available, otherwise show icon
                        GestureDetector(
                          onTap: () {
                            if (_selectedImages.length < _maxImages) {
                              _openGallery();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Maximum $_maxImages images allowed. Remove an image first.'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white54, width: 2),
                            ),
                            child: _selectedImages.isNotEmpty
                                ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.file(
                                _selectedImages.last,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                            )
                                : Stack(
                              children: [
                                // Landscape/mountain icon
                                Positioned(
                                  bottom: 8,
                                  left: 8,
                                  right: 8,
                                  child: Container(
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                                // Sun icon (top right)
                                const Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Icon(
                                    Icons.wb_sunny,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Shutter button (large circle) with long press for multiple photos
                        GestureDetector(
                          onTap: () => _capturePhoto(),
                          onLongPressStart: (_) {
                            setState(() {
                              _isMultipleMode = true;
                            });
                          },
                          onLongPress: () {
                            if (_selectedMode == 'VIDEO') {
                              _startVideoRecording();
                            } else {
                              // Keep capturing photos while long pressed
                              _capturePhoto();
                            }
                          },
                          onLongPressEnd: (_) {
                            setState(() {
                              _isMultipleMode = false;
                            });
                            // Don't auto-return, let user press Done button
                          },
                          child: Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              color: _isMultipleMode ? Colors.red : Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _isMultipleMode ? Colors.red.shade300 : Colors.white70,
                                width: 4,
                              ),
                            ),
                            child: Container(
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: _isMultipleMode ? Colors.red.shade200 : Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),

                        // Camera switch button
                        GestureDetector(
                          onTap: () {
                            _switchCamera();
                          },
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.flip_camera_ios,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Loading overlay when navigating to product screen - must be last to appear on top
            if (_isNavigatingToProduct)
              Container(
                color: Colors.black,
                width: double.infinity,
                height: double.infinity,
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton(String mode, IconData icon) {
    final isSelected = _selectedMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedMode = mode;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.yellow : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          mode,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Future<void> _capturePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      // Fallback to image_picker if camera controller not available
      try {
        final XFile? pickedFile = await _picker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: _isFrontCamera ? CameraDevice.front : CameraDevice.rear,
          imageQuality: 75,
          maxWidth: 1080,
          maxHeight: 1920,
        );

        if (pickedFile != null) {
          final imageFile = File(pickedFile.path);
          // Always add to selected images list (multiple clicks support)
          if (_selectedImages.length < _maxImages) {
            setState(() {
              _selectedImages.add(imageFile);
              _selectedImagePaths.add(imageFile.path);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Captured ${_selectedImages.length}/$_maxImages photo(s)'),
                duration: const Duration(milliseconds: 500),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Maximum $_maxImages images allowed. Press Done to confirm.'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      } catch (e) {
        print("Error capturing photo: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to capture photo')),
          );
        }
      }
      return;
    }

    try {
      final XFile image = await _cameraController!.takePicture();
      final imageFile = File(image.path);

      // Always add to selected images list (multiple clicks support)
      if (_selectedImages.length < _maxImages) {
        setState(() {
          _selectedImages.add(imageFile);
          _selectedImagePaths.add(imageFile.path);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Captured ${_selectedImages.length}/$_maxImages photo(s)'),
            duration: const Duration(milliseconds: 500),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Maximum $_maxImages images allowed. Press Done to confirm.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print("Error capturing photo: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to capture photo')),
        );
      }
    }
  }

  Future<void> _startVideoRecording() async {
    // Video recording functionality can be added here
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Video recording not implemented yet')),
    );
  }

  Future<void> _openGallery() async {
    try {
      // Calculate how many images can be added
      final remainingSlots = _maxImages - _selectedImages.length;
      if (remainingSlots <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Maximum $_maxImages images allowed. Remove an image first.'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Hide camera BEFORE opening gallery to prevent any flash
      if (!widget.returnImagesDirectly) {
        setState(() {
          _isNavigatingToProduct = true;
        });
      }

      final List<XFile>? pickedFiles = await _picker.pickMultiImage(
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 75,
      );

      if (pickedFiles != null && pickedFiles.isNotEmpty) {
        final imageFiles = pickedFiles.map((file) => File(file.path)).toList();

        // If returnImagesDirectly is false, immediately navigate to product selection screen
        if (!widget.returnImagesDirectly && mounted) {

          // Quick check - if all images already selected
          final newImages = imageFiles.where((file) => !_selectedImagePaths.contains(file.path)).toList();
          if (newImages.isEmpty) {
            setState(() {
              _isNavigatingToProduct = false;
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('All selected images are already added.'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
            return;
          }

          // Take only what we can add (up to max limit)
          final imagesToAdd = newImages.take(remainingSlots).toList();

          // Combine all images
          final allImages = List<File>.from(_selectedImages)..addAll(imagesToAdd);

          // Use pushReplacement to replace camera screen immediately
          // This prevents camera screen from showing again
          final finalResult = await Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => ProductSelectionScreen(
                selectedImages: allImages,
              ),
            ),
          );

          // If product selection screen returns result, pass it to parent
          if (finalResult != null && finalResult is List<File> && mounted) {
            Navigator.pop(context, finalResult);
          }
          return;
        }

        // Only process if returnImagesDirectly is true (for product selection screen flow)
        final newImages = imageFiles.where((file) => !_selectedImagePaths.contains(file.path)).toList();

        if (newImages.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('All selected images are already added.'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          return;
        }

        // Only add up to the maximum limit
        final imagesToAdd = newImages.take(remainingSlots).toList();

        setState(() {
          _selectedImages.addAll(imagesToAdd);
          _selectedImagePaths.addAll(imagesToAdd.map((f) => f.path));
        });

        if (newImages.length > remainingSlots) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Only $remainingSlots image(s) added. Maximum $_maxImages images allowed.'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else if (imageFiles.length > newImages.length) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${imageFiles.length - newImages.length} image(s) already selected.'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      print("Error picking images: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to pick images')),
        );
      }
      setState(() {
        _isNavigatingToProduct = false;
      });
    }
  }
}
