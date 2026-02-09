import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import '../config.dart';

class ImageEnhancementService {
  static SelfieSegmenter? _segmenterInstance;
  static final Dio _dio = Dio();
  
  static SelfieSegmenter get _segmenter {
    _segmenterInstance ??= SelfieSegmenter(
      mode: SegmenterMode.single,
      enableRawSizeMask: true,
    );
    return _segmenterInstance!;
  }

  /// Removes background from a product image and makes it professional (white background).
  /// Prioritizes remove.bg API if a key is provided in Config.
  /// Fallbacks to on-device ML Kit if no key is present or API fails.
  static Future<File> enhanceProductImage(File imageFile) async {
    try {
      File? processedFile;

      // 1. Try remove.bg API if key is available
      if (Config.removeBgApiKey.isNotEmpty) {
        processedFile = await _enhanceWithRemoveBg(imageFile);
      }

      // 2. Fallback to ML Kit if API failed or no key
      if (processedFile == null) {
        processedFile = await _enhanceWithMLKit(imageFile);
      }

      // 3. Apply Professional Centering (to standard 1200x1200px white canvas)
      return await _applyProfessionalLayout(processedFile ?? imageFile);
    } catch (e, stack) {
      print("Global enhancement error: $e");
      print(stack);
      return imageFile;
    }
  }

  /// High-quality background removal using remove.bg API
  static Future<File?> _enhanceWithRemoveBg(File imageFile) async {
    try {
      print("Using remove.bg API for enhancement...");
      
      FormData formData = FormData.fromMap({
        'size': 'auto',
        'image_file': await MultipartFile.fromFile(imageFile.path),
      });

      Response response = await _dio.post(
        'https://api.remove.bg/v1.0/removebg',
        data: formData,
        options: Options(
          headers: {'X-Api-Key': Config.removeBgApiKey},
          responseType: ResponseType.bytes,
        ),
      );

      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/rbg_${DateTime.now().millisecondsSinceEpoch}.png';
        final file = File(path);
        await file.writeAsBytes(response.data);
        return file;
      }
    } catch (e) {
      print("remove.bg API error: $e");
    }
    return null;
  }

  /// On-device background removal using ML Kit
  static Future<File?> _enhanceWithMLKit(File imageFile) async {
    try {
      print("Using on-device ML Kit for enhancement...");
      final inputImage = InputImage.fromFile(imageFile);
      final mask = await _segmenter.processImage(inputImage);

      if (mask == null) return null;

      final bytes = await imageFile.readAsBytes();
      final originalImage = img.decodeImage(bytes);
      if (originalImage == null) return null;

      final width = originalImage.width;
      final height = originalImage.height;
      
      // Create a transparent image
      final processedImage = img.Image(width: width, height: height, numChannels: 4);
      processedImage.clear(img.ColorRgba8(0, 0, 0, 0)); 

      final maskWidth = mask.width;
      final maskHeight = mask.height;
      final confidences = mask.confidences;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int maskX = ((x / width) * maskWidth).floor();
          final int maskY = ((y / height) * maskHeight).floor();
          final int maskIndex = maskY * maskWidth + maskX;

          if (maskIndex < confidences.length && confidences[maskIndex] > 0.45) {
            processedImage.setPixel(x, y, originalImage.getPixel(x, y));
          }
        }
      }

      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/mlk_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(path);
      await file.writeAsBytes(img.encodePng(processedImage));
      return file;
    } catch (e) {
      print("ML Kit enhancement error: $e");
    }
    return null;
  }

  /// Scales, centers, and places the product on a white 1200x1200px canvas
  static Future<File> _applyProfessionalLayout(File inputImageFile) async {
    try {
      final bytes = await inputImageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return inputImageFile;

      final width = image.width;
      final height = image.height;

      // 1. Find bounding box of the non-transparent content
      int minX = width, minY = height, maxX = 0, maxY = 0;
      bool contentFound = false;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final pixel = image.getPixel(x, y);
          // Check alpha channel (index 3 in Rgba8)
          if (pixel.a > 10) { 
            contentFound = true;
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }

      if (!contentFound) return inputImageFile;

      // Add 5% padding
      int pW = ((maxX - minX) * 0.05).toInt();
      int pH = ((maxY - minY) * 0.05).toInt();
      minX = (minX - pW).clamp(0, width - 1);
      maxX = (maxX + pW).clamp(0, width - 1);
      minY = (minY - pH).clamp(0, height - 1);
      maxY = (maxY + pH).clamp(0, height - 1);

      int contentWidth = maxX - minX;
      int contentHeight = maxY - minY;

      // 2. Create the final professional image (Square 1200x1200px)
      const canvasSize = 1200;
      final processedImage = img.Image(width: canvasSize, height: canvasSize);
      processedImage.clear(img.ColorRgb8(255, 255, 255)); // Pure white

      // 3. Calculate scaling
      double scale = (canvasSize * 0.85) / [contentWidth, contentHeight].reduce((a, b) => a > b ? a : b);
      int targetWidth = (contentWidth * scale).toInt();
      int targetHeight = (contentHeight * scale).toInt();

      // 4. Center on canvas
      int offsetX = (canvasSize - targetWidth) ~/ 2;
      int offsetY = (canvasSize - targetHeight) ~/ 2;
      
      // Use copyResize and composite
      final cropped = img.copyCrop(image, x: minX, y: minY, width: contentWidth, height: contentHeight);
      final resized = img.copyResize(cropped, width: targetWidth, height: targetHeight, interpolation: img.Interpolation.linear);
      
      img.compositeImage(processedImage, resized, dstX: offsetX, dstY: offsetY);

      final tempDir = await getTemporaryDirectory();
      final enhancedPath = '${tempDir.path}/final_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final enhancedFile = File(enhancedPath);
      await enhancedFile.writeAsBytes(img.encodeJpg(processedImage, quality: 90));

      return enhancedFile;
    } catch (e) {
      print("Layout error: $e");
      return inputImageFile;
    }
  }

  static Future<File> compressImage(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final decodedImage = img.decodeImage(bytes);
      if (decodedImage == null) return imageFile;

      final tempDir = await getTemporaryDirectory();
      final compressedPath = '${tempDir.path}/comp_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final compressedFile = File(compressedPath);
      
      img.Image resized = decodedImage;
      if (decodedImage.width > 1200 || decodedImage.height > 1200) {
        resized = img.copyResize(decodedImage, width: decodedImage.width > decodedImage.height ? 1200 : null, height: decodedImage.height >= decodedImage.width ? 1200 : null);
      }
      
      await compressedFile.writeAsBytes(img.encodeJpg(resized, quality: 75));
      return compressedFile;
    } catch (e) {
      return imageFile;
    }
  }
}
