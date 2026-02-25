# Profile Image Manager

This folder contains widgets and services for managing profile images with long-press functionality.

## Files

### `long_press_image.dart`
A wrapper widget that adds long-press gesture detection to any image widget. When long-pressed, it opens a modal with edit and delete options.

### `image_options_modal.dart`
A modal bottom sheet that displays:
- Image preview
- Edit button (opens image picker to select new image)
- Delete button (shows confirmation dialog)
- Cancel button

## Services

### `profile_image_service.dart`
Contains API service methods for:
- `editProfileImage()` - Update profile images
- `deleteProfileImage()` - Delete profile images  
- `editProductImage()` - Update product variation images
- `deleteProductImage()` - Delete product variation images

## Usage

```dart
LongPressImage(
  imageUrl: 'https://example.com/image.jpg',
  imageId: 'unique_image_id',
  productId: 123, // Optional for product images
  variationId: 'var_456', // Optional for product images
  imageIndex: 0,
  onRefresh: () {
    // Refresh the UI after edit/delete
  },
  allImages: ['img1.jpg', 'img2.jpg'], // Optional
  child: YourImageWidget(),
)
```

## Features

- ✅ Long-press gesture detection
- ✅ Modal with edit/delete options
- ✅ Image picker integration for editing
- ✅ Confirmation dialog for deletion
- ✅ Loading indicators
- ✅ Error handling
- ✅ Success feedback
- ✅ Automatic UI refresh after operations
