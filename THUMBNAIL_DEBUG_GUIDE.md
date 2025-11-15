# Thumbnail Display Debug Guide

## Server Side Flow (Node.js)

### 1. Thumbnail Generation
```javascript
// media_route.js line ~200
async function generateThumbnail(buffer) {
  const thumbnailBase64 = await sharp(buffer)
    .resize(150, 150, { fit: 'cover' })
    .jpeg({ quality: 70 })
    .toBuffer()
    .then(buffer => buffer.toString('base64'));
  return thumbnailBase64;
}
```

### 2. Thumbnail Sent to PHP API
```javascript
// media_route.js line ~600, ~800
const payload = {
  ...
  thumbnail_data: thumbnailBase64,
  ...
};
await axios.post(`${PHP_API_BASE}/send_message.php`, payload);
```

### 3. Thumbnail Emitted via Socket
```javascript
// media_route.js line ~600 (early emit)
io.emit("message_thumbnail_ready", {
  temp_id,
  thumbnail_data: thumbnailBase64,
  ...
});

// media_route.js line ~700, ~900 (with new_message)
io.emit("new_message", {
  ...
  thumbnail_data: thumbnailBase64,
  ...
});
```

## Flutter Side Flow

### 1. Socket Event Listeners

#### `message_thumbnail_ready` Event
```dart
// chat_service.dart line 356
_socket!.on("message_thumbnail_ready", (data) async {
  final tempId = data["temp_id"]?.toString();
  final thumbnailBase64 = data["thumbnail_data"]?.toString();
  
  if (tempId != null && thumbnailBase64 != null) {
    await _updateThumbnail(tempId, thumbnailBase64);
  }
});
```

#### `new_message` Event
```dart
// chat_service.dart line 280
_socket!.on("new_message", (data) async {
  await _handleIncomingData(data, source: "new_message");
});
```

### 2. Thumbnail Processing in `_handleIncomingData`

```dart
// chat_service.dart line 801-813
String? thumbnailBase64 = data["thumbnail_data"]?.toString() ?? 
                          data["thumbnail"]?.toString() ?? 
                          data["thumbnail_base64"]?.toString();

// Clean prefix if present
if (thumbnailBase64 != null && thumbnailBase64.isNotEmpty) {
  if (thumbnailBase64.contains(',')) {
    thumbnailBase64 = thumbnailBase64.split(',').last;
  }
  thumbnailBase64 = thumbnailBase64.trim();
}
```

### 3. Message Creation with Thumbnail

```dart
// chat_service.dart line 955-973
final msg = Message(
  ...
  thumbnailBase64: finalThumbnailBase64,
  ...
);
```

### 4. UI Display

```dart
// chat_screen.dart line 1740-1812
Widget _buildImageWithBlurHash(Message msg, String mediaUrl) {
  String? thumbnailBase64 = msg.thumbnailBase64?.trim();
  
  // Clean and validate
  if (thumbnailBase64 != null && thumbnailBase64.isNotEmpty) {
    if (thumbnailBase64.contains(',')) {
      thumbnailBase64 = thumbnailBase64.split(',').last.trim();
    }
  }
  
  // Use in Image.network frameBuilder
  if (thumbnailBase64 != null && thumbnailBase64.isNotEmpty) {
    final thumbnailBytes = base64Decode(thumbnailBase64);
    return Image.memory(thumbnailBytes, ...);
  }
}
```

## Debug Checklist

### ✅ Check Server Logs
1. `🖼️ Generating thumbnail...` - Thumbnail generation started
2. `✅ Thumbnail generated: X bytes` - Thumbnail generated successfully
3. Socket emit logs - Check if `thumbnail_data` is being sent

### ✅ Check Flutter Console Logs

#### When Receiving `new_message` Event:
1. `📨 [new_message] event received` - Event received
2. `🖼️ Thumbnail extracted from server: X chars` - Thumbnail extracted
3. `💾 NEW MESSAGE SAVED: Thumbnail: Available (X chars)` - Thumbnail saved

#### When Receiving `message_thumbnail_ready` Event:
1. `🖼️ [message_thumbnail_ready] event received` - Event received
2. `🖼️ Updating thumbnail for tempId: X, length: Y chars` - Thumbnail update started
3. `✅ Thumbnail updated for message: X` - Thumbnail updated

#### When Displaying in UI:
1. `🖼️ Building image with thumbnail: X chars, messageId: Y` - UI building with thumbnail
2. `✅ Thumbnail decoded successfully: X bytes` - Thumbnail decoded
3. `❌ Thumbnail decode error: ...` - If error occurs

## Common Issues & Solutions

### Issue 1: Thumbnail Not Received from Server
**Symptoms**: No `🖼️ Thumbnail extracted from server` log
**Solution**: 
- Check server logs for thumbnail generation
- Verify socket event is being emitted
- Check network tab for socket messages

### Issue 2: Thumbnail Not Saved to Message
**Symptoms**: `Thumbnail: Not Available` in save log
**Solution**:
- Check if `finalThumbnailBase64` is null
- Verify thumbnail cleaning logic
- Check duplicate message handling

### Issue 3: Thumbnail Not Displayed in UI
**Symptoms**: `⚠️ No thumbnail available for message` log
**Solution**:
- Verify `msg.thumbnailBase64` is not null
- Check thumbnail decode errors
- Verify UI refresh is happening

### Issue 4: Thumbnail Decode Error
**Symptoms**: `❌ Thumbnail decode error: ...`
**Solution**:
- Check if base64 string has prefix (should be cleaned)
- Verify base64 string is valid
- Check if string is empty or null

## Testing Steps

1. **Send Media Message**
   - Send image from Flutter app
   - Check server logs for thumbnail generation
   - Check Flutter logs for thumbnail processing

2. **Receive Media Message**
   - Receive image from another user
   - Check `new_message` event logs
   - Verify thumbnail in message object

3. **Display Media Message**
   - Open chat screen
   - Check UI logs for thumbnail display
   - Verify thumbnail shows in message bubble

4. **Thumbnail Update Event**
   - Wait for `message_thumbnail_ready` event
   - Check thumbnail update logs
   - Verify UI refreshes

## Expected Log Flow

```
[Server] 🖼️ Generating thumbnail...
[Server] ✅ Thumbnail generated: 5000 bytes
[Server] 📤 Emitting message_thumbnail_ready with thumbnail_data
[Flutter] 🖼️ [message_thumbnail_ready] event received
[Flutter] 🖼️ Updating thumbnail for tempId: temp_123, length: 5000 chars
[Flutter] ✅ Thumbnail updated for message: temp_123
[Flutter] 📨 [new_message] event received
[Flutter] 🖼️ Thumbnail extracted from server: 5000 chars
[Flutter] 💾 NEW MESSAGE SAVED: Thumbnail: Available (5000 chars)
[Flutter] 🖼️ Building image with thumbnail: 5000 chars, messageId: 123
[Flutter] ✅ Thumbnail decoded successfully: 3750 bytes
```

## Quick Fix Commands

If thumbnail still not showing, add these debug prints:

```dart
// In _buildImageWithBlurHash
print("🔍 DEBUG Thumbnail Check:");
print("   - msg.thumbnailBase64: ${msg.thumbnailBase64 != null ? 'NOT NULL' : 'NULL'}");
print("   - msg.thumbnailBase64 length: ${msg.thumbnailBase64?.length ?? 0}");
print("   - msg.thumbnailBase64 first 50: ${msg.thumbnailBase64?.substring(0, msg.thumbnailBase64!.length > 50 ? 50 : msg.thumbnailBase64!.length) ?? 'N/A'}");
```

