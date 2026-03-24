import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart'; // Add this import for SharedPreferences

import '../models/chat_model.dart';
import 'chat_home.dart';
import '../config.dart'; // Make sure you have this new config.dart file in the same lib folder
import '../services/local_auth_service.dart';
import 'package:whatsappchat/screens/set_mpin_page.dart';
import 'package:whatsappchat/widgets/optimized_image_widget.dart';
import '../widgets/theme_toggle_switch.dart';

class UserProfilePage extends StatefulWidget {
  final int userId;
  const UserProfilePage({super.key, required this.userId});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  bool _loading = false;

  // UI and upload state
  File? _imageFile;
  double _uploadProgress = 0.0; // 0.0 - 1.0
  String _uploadStatus = "";

  final ImagePicker _picker = ImagePicker();

  // No need for 'baseUrl', 'chunkSize', 'concurrency' variables here.
  // We'll use the values from the Config class.

  // internal prepared pieces after pick
  String? _preparedFileId;
  List<Uint8List>? _preparedChunks;
  Uint8List? _encryptionKey;
  Uint8List? _encryptionIv;
  String? _originalFileName;

  // -------------------------
  // Helper: random bytes
  // -------------------------
  Uint8List _randomBytes(int len) {
    final rnd = Random.secure();
    final b = List<int>.generate(len, (_) => rnd.nextInt(256));
    return Uint8List.fromList(b);
  }

  // -------------------------
  // Compress image (returns bytes)
  // -------------------------
  Future<Uint8List?> _compressImage(File file) async {
    try {
      final result = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        quality: 80,
      );
      return result != null ? Uint8List.fromList(result) : null;
    } catch (e) {
      debugPrint("Compress error: $e");
      return null;
    }
  }

  // -------------------------
  // Encrypt bytes using AES-256-CBC (PKCS7)
  // -------------------------
  Map<String, dynamic> _encryptBytes(Uint8List plain) {
    final key = _randomBytes(32);
    final iv = _randomBytes(16);

    final keyParam = encrypt_pkg.Key(key);
    final ivParam = encrypt_pkg.IV(iv);
    final encrypter = encrypt_pkg.Encrypter(encrypt_pkg.AES(keyParam, mode: encrypt_pkg.AESMode.cbc));

    final encrypted = encrypter.encryptBytes(plain, iv: ivParam);
    return {
      'cipherBytes': encrypted.bytes,
      'key': key,
      'iv': iv,
    };
  }

  // -------------------------
  // Split bytes -> chunks list
  // -------------------------
  List<Uint8List> _splitToChunks(Uint8List data, int size) {
    final int total = data.length;
    final List<Uint8List> chunks = [];
    for (int offset = 0; offset < total; offset += size) {
      final end = (offset + size > total) ? total : offset + size;
      chunks.add(Uint8List.view(data.buffer, offset, end - offset));
    }
    return chunks;
  }

  // -------------------------
  // Prepares compressed+encrypted chunks right after picking image
  // -------------------------
  Future<void> _prepareImageForUpload(File file) async {
    setState(() {
      _uploadStatus = "Compressing image...";
      _uploadProgress = 0.0;
      _loading = true;
    });

    try {
      _originalFileName = path.basename(file.path);
      final compressed = await _compressImage(file);
      if (compressed == null) throw Exception("Compression failed");

      setState(() {
        _uploadStatus = "Encrypting image...";
      });

      final enc = _encryptBytes(compressed);
      final cipherBytes = enc['cipherBytes'] as Uint8List;
      _encryptionKey = enc['key'] as Uint8List;
      _encryptionIv = enc['iv'] as Uint8List;

      setState(() {
        _uploadStatus = "Splitting into chunks...";
      });

      final chunks = _splitToChunks(cipherBytes, Config.chunkSize);
      _preparedChunks = chunks;
      _preparedFileId = DateTime.now().millisecondsSinceEpoch.toString();
      setState(() {
        _uploadStatus = "Prepared ${chunks.length} chunks; ready to upload";
        _uploadProgress = 0.0;
      });

      _startUploadingPreparedChunks();
    } catch (e) {
      setState(() {
        _uploadStatus = "Prepare failed: $e";
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------------------------
  // Pick image and immediately prepare (compress+encrypt+chunk)
  // -------------------------
  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final f = File(pickedFile.path);
      setState(() {
        _imageFile = f;
      });
      await _prepareImageForUpload(f);
    }
  }

  // -------------------------
  // Upload single chunk by index (PHP API)
  // -------------------------
  Future<bool> _uploadChunk({
    required String fileId,
    required int chunkIndex,
    required int totalChunks,
    required Uint8List chunkData,
  }) async {
    try {
      final uri = Uri.parse("${Config.basePhpApiUrl}/upload_chunk.php");
      final req = http.MultipartRequest('POST', uri);

      req.fields['fileId'] = fileId;
      req.fields['chunkIndex'] = chunkIndex.toString();
      req.fields['totalChunks'] = totalChunks.toString();
      req.fields['userId'] = widget.userId.toString();
      req.fields['encrypted'] = '1';

      req.files.add(http.MultipartFile.fromBytes('chunk', chunkData, filename: 'chunk_$chunkIndex'));

      final streamedResp = await req.send();
      final respStr = await streamedResp.stream.bytesToString();

      if (streamedResp.statusCode != 200) {
        debugPrint("Chunk $chunkIndex failed: ${streamedResp.statusCode} -> $respStr");
        return false;
      }

      try {
        final j = json.decode(respStr);
        if (j is Map && j['success'] == false) {
          debugPrint("Server error for chunk $chunkIndex: ${j['message']}");
          return false;
        }
      } catch (_) {}
      return true;
    } catch (e) {
      debugPrint("Upload chunk exception: $e");
      return false;
    }
  }

  // -------------------------
  // Upload prepared chunks in parallel with concurrency limit
  // -------------------------
  Future<void> _startUploadingPreparedChunks() async {
    if (_preparedChunks == null || _preparedFileId == null) {
      setState(() {
        _uploadStatus = "Nothing prepared to upload";
      });
      return;
    }

    setState(() {
      _loading = true;
      _uploadStatus = "Starting upload...";
      _uploadProgress = 0.0;
    });

    final fileId = _preparedFileId!;
    final chunks = _preparedChunks!;
    final total = chunks.length;

    int uploadedCount = 0;
    final sem = _AsyncSemaphore(Config.concurrency);

    final List<Future<void>> futures = [];

    for (int i = 0; i < total; i++) {
      final idx = i;
      final chunk = chunks[i];

      final f = () async {
        await sem.acquire();
        try {
          setState(() {
            _uploadStatus = "Uploading chunk ${idx + 1} / $total";
          });
          final ok = await _uploadChunk(
            fileId: fileId,
            chunkIndex: idx,
            totalChunks: total,
            chunkData: chunk,
          );
          if (!ok) {
            throw Exception("Chunk ${idx + 1} failed");
          }
          uploadedCount++;
          if (mounted) {
            setState(() {
              _uploadProgress = uploadedCount / total;
              _uploadStatus = "Uploaded $uploadedCount / $total chunks";
            });
          }
        } finally {
          sem.release();
        }
      }();
      futures.add(f);
    }

    try {
      await Future.wait(futures);
    } catch (e) {
      setState(() {
        _uploadStatus = "Upload failed: $e";
      });
      _loading = false;
      return;
    }

    setState(() {
      _uploadStatus = "Finalizing upload on server...";
    });

    final finalizeOk = await _finalizeUpload(
      fileId: fileId,
      totalChunks: total,
      originalName: _originalFileName ?? 'upload.jpg',
      key: _encryptionKey!,
      iv: _encryptionIv!,
    );

    if (finalizeOk) {
      setState(() {
        _uploadStatus = "Upload complete";
        _uploadProgress = 1.0;
      });
    } else {
      setState(() {
        _uploadStatus = "Finalize failed";
      });
    }

    setState(() {
      _loading = false;
    });
  }

  // -------------------------
  // Finalize call - PHP API
  // -------------------------
  Future<bool> _finalizeUpload({
    required String fileId,
    required int totalChunks,
    required String originalName,
    required Uint8List key,
    required Uint8List iv,
  }) async {
    try {
      final uri = Uri.parse("${Config.basePhpApiUrl}/finalize_upload.php");
      final resp = await http.post(uri, body: {
        'fileId': fileId,
        'userId': widget.userId.toString(),
        'totalChunks': totalChunks.toString(),
        'original_name': originalName,
        'encrypted': '1',
        'aes_key_b64': base64Encode(key),
        'aes_iv_b64': base64Encode(iv),
      });

      if (resp.statusCode != 200) {
        debugPrint("Finalize HTTP ${resp.statusCode}: ${resp.body}");
        return false;
      }
      final j = json.decode(resp.body);
      if (j is Map && (j['success'] == true || j['fileId'] != null)) {
        return true;
      } else {
        debugPrint("Finalize response: ${resp.body}");
        return false;
      }
    } catch (e) {
      debugPrint("Finalize exception: $e");
      return false;
    }
  }

  // -------------------------
  // Call create_basic_profile.php (PHP API)
  // -------------------------
  Future<void> _callCreateProfile({String? profileFileId}) async {
    final resp = await http.post(Uri.parse("${Config.basePhpApiUrl}/create_basic_profile.php"), body: {
      "user_id": widget.userId.toString(),
      "name": _nameController.text.trim(),
      "address": _locationController.text.trim(),
      "profile_file_id": profileFileId ?? "",
    });

    if (resp.statusCode == 200) {
      try {
        final j = json.decode(resp.body);
        if (j['success'] == true) {
          return; // Don't navigate yet, we need to check for backup first.
        } else {
          throw Exception(j['message'] ?? resp.body);
        }
      } catch (e) {
        throw Exception("Invalid response: ${resp.body}");
      }
    } else {
      throw Exception("Profile API failed: ${resp.statusCode}");
    }
  }

  // --- NEW CODE: Backup Logic (Node.js API) ---

  Future<bool> _checkBackup() async {
    try {
      final uri = Uri.parse("${Config.baseNodeApiUrl}/check_backup?user_id=${widget.userId}");
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['has_backup'] ?? false;
      }
    } catch (e) {
      debugPrint("Backup check failed: $e");
    }
    return false;
  }

  Future<void> _deleteBackup() async {
    try {
      final uri = Uri.parse("${Config.baseNodeApiUrl}/delete_backup");
      await http.post(uri, body: {'user_id': widget.userId.toString()});
    } catch (e) {
      debugPrint("Delete backup failed: $e");
    }
  }

  Future<void> _restoreBackup() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isRestoring', true);
    debugPrint("Starting message restoration...");

    try {
      // API से लेटेस्ट 50 मैसेज फ़ेच करने के लिए
      final uri = Uri.parse(
          "${Config.baseNodeApiUrl}/restore_messages?user_id=${widget.userId}&limit=50&offset=0"
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final messages = data['messages'] as List;

        if (messages.isNotEmpty) {
          // Hive बॉक्स खोलें
          final chatBox = await Hive.openBox('chatMessages');

          // बॉक्स के पुराने डेटा को हटा दें ताकि केवल लेटेस्ट बैकअप रहे
          await chatBox.clear();

          for (var messageJson in messages) {
            // JSON को `Message` मॉडल में बदलें और Hive में जोड़ें
            final message = Message.fromMap(messageJson);
            await chatBox.put(message.messageId, message);
          }

          debugPrint("Fetched and saved ${messages.length} latest messages to Hive.");
        } else {
          debugPrint("No messages to restore.");
        }
      } else {
        debugPrint("Server error: ${response.statusCode}");
      }

    } on TimeoutException catch (e) {
      debugPrint("Restore API request timed out: $e");
    } catch (e) {
      debugPrint("Restore API call failed: $e");
    } finally {
      await prefs.setBool('isRestoring', false);
    }
  }

  Future<void> _showBackupDialog() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Icon(
                Icons.backup,
                size: 60,
                color: Colors.blue,
              ),
              const SizedBox(height: 16),
              const Text(
                "Restore message history?",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                "An old message backup was found. Would you like to restore it?",
                style: TextStyle(fontSize: 16, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop('restore');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text(
                  "Restore",
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop('skip');
                },
                child: const Text(
                  "Skip",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (result == 'restore') {
      await _restoreBackup();
      _navigateToChatHomePage();
    } else {
      await _deleteBackup();
      _navigateToChatHomePage();
    }
  }

  void _navigateToChatHomePage() {
    // ✅ If accessed from menu, just pop back. Otherwise replace.
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile saved successfully!")),
      );
      // Trigger profile refresh in ProfileTab
      // This will be handled by the parent widget
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ChatHomePage()));
    }
  }

  // --- MODIFIED _saveProfile() to include the new flow ---
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
    });

    try {
      if (_preparedFileId != null && _uploadProgress < 1.0) {
        setState(() {
          _uploadStatus = "Waiting for image upload to complete...";
        });
        while (_uploadProgress < 1.0 && _loading) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      await _callCreateProfile(profileFileId: _preparedFileId);

      // --- NEW FLOW STARTS HERE ---
      final hasBackup = await _checkBackup();

      if (hasBackup) {
        await _showBackupDialog();
      } else {
        _navigateToChatHomePage();
      }
      // --- NEW FLOW ENDS HERE ---

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  // ✅ Show menu with MPIN enable/disable and Set MPIN options
  void _showMenu() {
    final isMpinEnabled = LocalAuthService.isMpinEnabled();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: const Text("Enable MPIN"),
              subtitle: Text(isMpinEnabled ? "MPIN is enabled" : "MPIN is disabled"),
              value: isMpinEnabled,
              onChanged: (value) async {
                await LocalAuthService.setMpinEnabled(value);
                Navigator.pop(context);
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(value
                        ? "MPIN enabled. You can set MPIN now."
                        : "MPIN disabled. MPIN will not work on app restart."),
                  ),
                );
              },
            ),
            if (isMpinEnabled)
              ListTile(
                leading: const Icon(Icons.lock, color: Colors.grey),
                title: const Text("Set MPIN"),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SetMpinPage(),
                    ),
                  );
                },
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("User Profile Details"),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showMenu,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: _imageFile != null ? FileImage(_imageFile!) : null,
                      child: _imageFile == null
                          ? const Icon(Icons.person, size: 50)
                          : null,
                    ),
                    if (_imageFile != null)
                      Positioned.fill(
                        child: ClipOval(
                          child: OptimizedImageWidget(
                            imageUrl: _imageFile!.path,
                            width: 100,
                            height: 100,
                            memCacheWidth: 200,
                            memCacheHeight: 200,
                            enableFadeIn: true,
                            fadeInDuration: const Duration(milliseconds: 300),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: InkWell(
                        onTap: _pickImage,
                        child: const CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.blue,
                          child: Icon(Icons.edit, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_uploadProgress > 0 && _uploadProgress < 1)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: _uploadProgress),
                    const SizedBox(height: 6),
                    Text(_uploadStatus),
                    const SizedBox(height: 12),
                  ],
                )
              else if (_uploadProgress == 1.0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: 1.0),
                    const SizedBox(height: 6),
                    Text(_uploadStatus),
                    const SizedBox(height: 12),
                  ],
                )
              else if (_uploadStatus.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_uploadStatus),
                      const SizedBox(height: 12),
                    ],
                  ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: "Full Name", border: OutlineInputBorder()),
                validator: (value) => value!.isEmpty ? "Full Name is required" : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _locationController,
                decoration: InputDecoration(
                  labelText: "Location/Address",
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.location_on),
                    onPressed: () {
                      // TODO: Add automatic location fetching here if geolocator is available
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Enter location manually or enable location services")),
                      );
                    },
                  ),
                ),
                validator: (value) => value!.isEmpty ? "Location is required" : null,
              ),
              const SizedBox(height: 24),
              // Theme Toggle Switch
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Theme',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Choose your preferred theme',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                    const ThemeToggleSwitch(),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loading ? null : _saveProfile,
                child: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text("Save & Continue"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AsyncSemaphore {
  int _available;
  final Queue<Completer<void>> _waiters = Queue();
  _AsyncSemaphore(this._available);
  Future<void> acquire() {
    if (_available > 0) {
      _available--;
      return Future.value();
    } else {
      final completer = Completer<void>();
      _waiters.add(completer);
      return completer.future;
    }
  }
  void release() {
    if (_waiters.isNotEmpty) {
      final completer = _waiters.removeFirst();
      completer.complete();
    } else {
      _available++;
    }
  }
}