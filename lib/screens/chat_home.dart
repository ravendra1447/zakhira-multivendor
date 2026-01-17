import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:hive/hive.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/scheduler.dart';
import 'package:collection/collection.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';

import '../services/chat_service.dart';
import '../services/local_auth_service.dart';
import '../services/crypto_manager.dart';
import '../models/chat_model.dart';
import '../services/contact_service.dart';
import '../services/my_firebase_messaging_service.dart';
import 'chat_screen.dart';
import 'new_chat_page.dart';
import '../config.dart';
import 'package:whatsappchat/screens/set_mpin_page.dart';
import 'package:whatsappchat/screens/user_profile_page.dart';
import '../services/api_service.dart';
import '../models/profile_setting.dart';
import 'camera_interface_screen.dart';
import '../services/product_database_service.dart';
import '../models/product.dart';
import 'product/detail/product_detail_screen.dart';
import 'marketplace/marketplace_tab.dart';
import 'insta_pages_screen.dart';

class ChatHomePage extends StatefulWidget {
  final int? initialTabIndex;
  const ChatHomePage({super.key, this.initialTabIndex});

  @override
  State<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends State<ChatHomePage> {
  late int _selectedIndex;
  final Map<int, String> _userStatus = {};
  late StreamSubscription _userStatusSubscription;
  bool _contactsSynced = false;
  bool _permissionsAsked = false;

  final GlobalKey<_ProfileTabState> _profileTabKey = GlobalKey<_ProfileTabState>();
  final GlobalKey<MarketplaceTabState> _marketplaceTabKey = GlobalKey<MarketplaceTabState>();

  late final List<Widget> _screens = [
    ChatsTab(userStatus: _userStatus),
    MarketplaceTab(key: _marketplaceTabKey),
    ProfileTab(key: _profileTabKey),
  ];

  // Method to refresh marketplace
  void refreshMarketplace() {
    if (_marketplaceTabKey.currentState != null) {
      _marketplaceTabKey.currentState!.refresh();
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex ?? 0;
    _setupUserStatusListener();
    ChatService.ensureConnected();

    final userId = LocalAuthService.getUserId();
    if (userId != null) {
      ChatService.markAllMessagesAsDelivered(userId);
    }

    // ✅ Request permissions immediately after login (contacts and notifications)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissions();
      // If navigating to profile tab, refresh products
      if (widget.initialTabIndex == 2 && _profileTabKey.currentState != null) {
        _profileTabKey.currentState!.refreshProfile();
      }
    });
  }

  // ✅ Request permissions (contacts and notifications) after login
  Future<void> _requestPermissions() async {
    if (_permissionsAsked) return;

    _permissionsAsked = true;

    // Request contact permission
    final contactPermission = await fc.FlutterContacts.requestPermission();

    // Request notification permission (Firebase Messaging handles this automatically)
    // Initialize Firebase Messaging for notifications
    await MyFirebaseMessagingService.initialize();

    // After permissions, start contact sync
    if (contactPermission) {
      final userId = LocalAuthService.getUserId();
      if (userId != null) {
        setState(() {
          _contactsSynced = false;
        });
        await ContactService.fetchPhoneContacts(ownerUserId: userId);
        setState(() {
          _contactsSynced = true;
        });
      }
    } else {
      // Show dialog if permission denied
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Permission Required"),
            content: const Text("Please allow contact access to sync your contacts."),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
          ),
        );
      }
    }
  }

  void _setupUserStatusListener() {
    ChatService.ensureConnected();
    _userStatusSubscription = ChatService.onUserStatus.listen((statusData) {
      final userId = int.tryParse(statusData['userId']?.toString() ?? '');
      final status = statusData['status'] as String? ?? 'offline';
      if (userId != null) {
        setState(() {
          _userStatus[userId] = status;
        });
      }
    });
  }

  @override
  void dispose() {
    _userStatusSubscription.cancel();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;

      // Refresh marketplace when tab is selected
      if (index == 1 && _marketplaceTabKey.currentState != null) {
        _marketplaceTabKey.currentState!.refresh();
      }
    });
  }

  Future<void> _startContactSync() async {
    final userId = LocalAuthService.getUserId();
    if (userId == null) {
      print("Error: User ID is null. Cannot sync contacts.");
      return;
    }

    setState(() {
      _contactsSynced = false;
    });

    if (await fc.FlutterContacts.requestPermission()) {
      await ContactService.fetchPhoneContacts(ownerUserId: userId);
    }

    setState(() {
      _contactsSynced = true;
    });

    await MyFirebaseMessagingService.initialize();
  }

  // ✅ Show menu with Settings option
  void _showMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.grey),
              title: const Text("Settings"),
              onTap: () {
                Navigator.pop(context);
                final userId = LocalAuthService.getUserId();
                if (userId != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserProfilePage(userId: userId),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("User not found. Please login again.")),
                  );
                }
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
      // ✅ Hide AppBar when Profile or Marketplace tab is selected
      appBar: (_selectedIndex == 2 || _selectedIndex == 1)
          ? null
          : AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF075E54),
        title: const Text(
          "ZAKHIRA",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
            letterSpacing: 1.5,
          ),
        ),
        actions: [
          const Icon(Icons.search, color: Colors.white),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: _showMenu,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: const Color(0xFF075E54),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: "Chats"),
          BottomNavigationBarItem(icon: Icon(Icons.store), label: "Marketplace"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
        backgroundColor: const Color(0xFF25D366),
        child: const Icon(Icons.chat, color: Colors.white),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NewChatPage()),
          );
        },
      )
          : null,
    );
  }
}

class ChatsTab extends StatefulWidget {
  final Map<int, String> userStatus;
  const ChatsTab({super.key, required this.userStatus});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  static final _cryptoManager = CryptoManager();

  // ✅ SWIPE ACTION METHODS
  void _showMoreOptions(BuildContext context, Contact contact) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildBottomSheetHeader(contact),
              ListTile(
                leading: const Icon(Icons.volume_off, color: Colors.grey),
                title: const Text("Mute Notifications"),
                onTap: () {
                  Navigator.pop(context);
                  _muteChat(contact.chatId!, contact.name);
                },
              ),
              ListTile(
                leading: const Icon(Icons.cleaning_services, color: Colors.grey),
                title: const Text("Clear Chat"),
                onTap: () {
                  Navigator.pop(context);
                  _clearChat(contact.chatId!, contact.name);
                },
              ),
              ListTile(
                leading: const Icon(Icons.block, color: Colors.red),
                title: const Text("Block User"),
                onTap: () {
                  Navigator.pop(context);
                  _blockUser(contact.chatId!, contact.name);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text("Delete Chat"),
                onTap: () {
                  Navigator.pop(context);
                  _deleteChat(contact.chatId!, contact.name);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomSheetHeader(Contact contact) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.grey,
            child: const Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Chat options',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _muteChat(int chatId, String contactName) {
    print("Muted chat: $chatId");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Muted notifications for $contactName")),
    );
    // TODO: Implement actual mute logic in Hive
  }

  void _clearChat(int chatId, String contactName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Clear Chat?"),
        content: Text("Are you sure you want to clear all messages with $contactName?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _performClearChat(chatId, contactName);
            },
            child: const Text("CLEAR", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ✅ UPDATED: USE CHAT SERVICE FOR CLEARING CHAT
  void _performClearChat(int chatId, String contactName) async {
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) return;

      // Use ChatService to clear chat (this will notify server and other user)
      //await ChatService.clearChat(chatId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Cleared chat with $contactName")),
      );

      // Refresh UI
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print("Error clearing chat: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error clearing chat: $e")),
      );
    }
  }

  void _blockUser(int chatId, String contactName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Block User?"),
        content: Text("Are you sure you want to block $contactName? You will no longer receive messages from them."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _performBlockUser(chatId, contactName);
            },
            child: const Text("BLOCK", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ✅ UPDATED: USE CHAT SERVICE FOR BLOCKING USER
  void _performBlockUser(int chatId, String contactName) async {
    try {
      // Find the other user ID from the chat
      final messagesBox = Hive.box<Message>('messages');
      final userId = LocalAuthService.getUserId();

      if (userId == null) return;

      // Get the other user ID from any message in this chat
      final message = messagesBox.values.firstWhereOrNull((msg) => msg.chatId == chatId);
      if (message == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Cannot find user to block")),
        );
        return;
      }

      final otherUserId = message.senderId == userId ? message.receiverId : message.senderId;

      // Use ChatService to block user
      //await ChatService.blockUser(otherUserId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Blocked $contactName")),
      );

      // Refresh UI
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print("Error blocking user: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error blocking user: $e")),
      );
    }
  }

  void _deleteChat(int chatId, String contactName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Chat?"),
        content: Text("Are you sure you want to delete ALL messages with $contactName? This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _performDeleteChat(chatId, contactName);
            },
            child: const Text("DELETE", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ✅ COMPLETELY UPDATED: USE CHAT SERVICE deleteMessage FOR EACH MESSAGE
  void _performDeleteChat(int chatId, String contactName) async {
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) return;

      // Step 1: Get all messages for this chat
      final messagesBox = Hive.box<Message>('messages');
      final messages = messagesBox.values
          .where((msg) => msg.chatId == chatId)
          .toList();

      if (messages.isEmpty) {
        // If no messages, just delete from chat list
        final chatBox = Hive.box<Chat>('chatList');
        chatBox.delete(chatId);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Deleted chat with $contactName")),
        );

        if (mounted) setState(() {});
        return;
      }

      // Step 2: Delete each message using ChatService.deleteMessage
      int deletedCount = 0;
      for (var msg in messages) {
        try {
          // Determine role for deletion
          final String role = msg.senderId == userId ? 'sender' : 'receiver';

          // Use ChatService.deleteMessage API
          await ChatService.deleteMessage(
            messageId: msg.messageId,
            userId: userId,
            role: role,
          );

          deletedCount++;
        } catch (e) {
          print("Error deleting message ${msg.messageId}: $e");
        }
      }

      // Step 3: Delete from chat list
      final chatBox = Hive.box<Chat>('chatList');
      chatBox.delete(chatId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Deleted $deletedCount messages with $contactName")),
      );

      // Step 4: Refresh UI
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print("Error deleting chat: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error deleting chat: $e")),
      );
    }
  }

  // ✅ UNREAD COUNT FUNCTION
  int _getUnreadCount(int chatId, int currentUserId) {
    final messagesBox = Hive.box<Message>('messages');
    final unreadMessages = messagesBox.values.where((msg) =>
    msg.chatId == chatId &&
        msg.receiverId == currentUserId &&
        (msg.isRead == 0 || msg.isRead == null));
    return unreadMessages.length;
  }

  // ✅ MARK ALL MESSAGES AS READ FOR A CHAT
  Future<void> _markChatAsRead(int chatId, int currentUserId) async {
    final messagesBox = Hive.box<Message>('messages');
    final unreadMessages = messagesBox.values.where((msg) =>
    msg.chatId == chatId &&
        msg.receiverId == currentUserId &&
        (msg.isRead == 0 || msg.isRead == null));

    for (var msg in unreadMessages) {
      // Update local message status
      msg.isRead = 1;
      await messagesBox.put(msg.messageId, msg);

      // Notify server about read status
      await ChatService.markMessageRead(msg.messageId, chatId);
    }

    // Refresh UI
    if (mounted) {
      setState(() {});
    }
  }

  // ✅ WhatsApp style message display for home screen
  String _getDisplayMessage(Message message) {
    // ✅ Media message (encrypted or direct)
    if (message.messageType == 'media' ||
        message.messageType == 'encrypted_media' ||
        (message.messageId.toString().startsWith('temp_') &&
            message.messageType == 'media')) {
      return "📷 Photo";
    }

    // ✅ Encrypted message - check if it's media
    if (message.messageType == 'encrypted') {
      try {
        final decryptedData = _cryptoManager.decryptAndDecompress(message.messageContent);
        final decodedData = jsonDecode(decryptedData.toString());
        if (decodedData['type'] == 'media') {
          return "📷 Photo";
        }
      } catch (e) {
        // If decryption fails, check if it contains media indicators
        if (message.messageContent.contains('media') || message.messageContent == 'media') {
          return "📷 Photo";
        }
      }
    }

    // ✅ Regular text message - try to decrypt if encrypted
    if (message.messageType == 'encrypted') {
      try {
        final decryptedData = _cryptoManager.decryptAndDecompress(message.messageContent);
        final decodedData = jsonDecode(decryptedData.toString());
        return decodedData['content'] ?? "Message";
      } catch (e) {
        return "Message";
      }
    }

    // ✅ Plain text message
    return message.messageContent.isNotEmpty ? message.messageContent : "Message";
  }

  Future<Contact> _createContactFromMessage(
      Message message, int currentUserId) async {
    final otherUserId = message.senderId == currentUserId
        ? message.receiverId
        : message.senderId;
    final otherUserPhone = message.senderId == currentUserId
        ? message.receiverPhoneNumber
        : message.senderPhoneNumber;

    String displayName = "";

    if (otherUserPhone != null && otherUserPhone.isNotEmpty) {
      final localContactName =
      await ContactService.getContactNameByPhoneNumber(otherUserPhone);
      if (localContactName != null && localContactName.isNotEmpty) {
        displayName = localContactName;
      }
    }

    if (displayName.isEmpty) {
      final otherUserName = message.senderId == currentUserId
          ? message.receiverName
          : message.senderName;
      if (otherUserName != null && otherUserName.isNotEmpty) {
        displayName = otherUserName;
      }
    }

    if (displayName.isEmpty && otherUserPhone != null && otherUserPhone.isNotEmpty) {
      displayName = otherUserPhone;
    }

    if (displayName.isEmpty) {
      displayName = "User $otherUserId";
    }

    // ✅ Use the new display method
    final lastMessageContent = _getDisplayMessage(message);

    return Contact(
      id: otherUserId,
      name: displayName,
      lastMessage: lastMessageContent,
      lastMessageTime: message.timestamp,
      chatId: message.chatId,
      phoneNumber: otherUserPhone,
    );
  }

  Future<void> _onRefresh() async {
    final messagesBox = Hive.box<Message>('messages');
    final chatIds = messagesBox.values.map((msg) => msg.chatId).whereType<int>().toSet();

    await SchedulerBinding.instance.endOfFrame;

    for (var chatId in chatIds) {
      await ChatService.fetchMessages(chatId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<Message>>(
      valueListenable: Hive.box<Message>('messages').listenable(),
      builder: (context, box, _) {
        final userId = LocalAuthService.getUserId();
        if (userId == null) {
          return const Center(child: Text("Please login to see chats."));
        }

        final Map<int, Message> latestMessages = {};
        for (var message in box.values) {
          final otherUserId =
          message.senderId == userId ? message.receiverId : message.senderId;
          if (otherUserId > 0) {
            if (!latestMessages.containsKey(otherUserId) ||
                message.timestamp.isAfter(latestMessages[otherUserId]!.timestamp)) {
              latestMessages[otherUserId] = message;
            }
          }
        }

        if (latestMessages.isEmpty) {
          return const Center(child: Text("No chats yet. Start a new one!"));
        }

        return FutureBuilder<List<Contact>>(
          future: Future.wait(
            latestMessages.values
                .map((msg) => _createContactFromMessage(msg, userId))
                .toList(),
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              print("FutureBuilder Error: ${snapshot.error}");
              return Center(
                  child: Text("Error loading chats: ${snapshot.error}"));
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(
                  child: Text("No chats available. Start a new one!"));
            }

            final sortedContacts = snapshot.data!
              ..sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));

            return RefreshIndicator(
              onRefresh: _onRefresh,
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                itemCount: sortedContacts.length,
                itemBuilder: (context, index) {
                  final contact = sortedContacts[index];
                  final latestMessage = latestMessages.values.firstWhereOrNull((msg) => msg.chatId == contact.chatId);
                  final isOnline = widget.userStatus[contact.id] == 'online';
                  final unreadCount = contact.chatId != null ? _getUnreadCount(contact.chatId!, userId) : 0;

                  // ✅ SWIPE ENABLED CHAT TILE
                  return Slidable(
                    key: ValueKey(contact.chatId ?? contact.id),

                    // 👉 Right swipe for actions (WhatsApp style)
                    endActionPane: ActionPane(
                      motion: const DrawerMotion(),
                      children: [
                        // 🔹 "More" Button
                        SlidableAction(
                          onPressed: (context) => _showMoreOptions(context, contact),
                          backgroundColor: Colors.grey.shade700,
                          icon: Icons.more_vert,
                          label: 'More',
                        ),

                        // 🔹 "Delete" Button
                        SlidableAction(
                          onPressed: (context) => _deleteChat(contact.chatId!, contact.name),
                          backgroundColor: Colors.red,
                          icon: Icons.delete,
                          label: 'Delete',
                        ),
                      ],
                    ),

                    // 👉 Your existing ListTile content
                    child: ListTile(
                      leading: Stack(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.grey,
                            child: const Icon(Icons.person, color: Colors.white),
                          ),
                          if (isOnline)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                          if (unreadCount > 0)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 1.5),
                                ),
                                child: Center(
                                  child: Text(
                                    unreadCount > 9 ? '9+' : unreadCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        contact.name,
                        style: TextStyle(
                          fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Row(
                        children: [
                          if (latestMessage != null)
                            _buildTickIcon(latestMessage, userId),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              isOnline ? 'Online' : (contact.lastMessage ?? "No message"),
                              style: TextStyle(
                                color: isOnline
                                    ? Colors.green.shade600
                                    : (unreadCount > 0 ? Colors.black : Colors.grey),
                                fontWeight: isOnline || unreadCount > 0
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _formatTime(contact.lastMessageTime),
                            style: TextStyle(
                              fontSize: 12,
                              color: unreadCount > 0 ? Colors.black : Colors.grey,
                              fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (unreadCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF25D366),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                unreadCount > 9 ? '9+' : unreadCount.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      onTap: () {
                        if (contact.chatId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Chat ID not found.")),
                          );
                          return;
                        }

                        // ✅ MARK AS READ BEFORE OPENING CHAT
                        _markChatAsRead(contact.chatId!, userId);

                        // ✅ WHATSAPP-STYLE: Directly open at last message
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              chatId: contact.chatId!,
                              otherUserId: contact.id,
                              otherUserName: contact.name,
                            ),
                          ),
                        ).then((_) {
                          // ✅ Ensure UI refresh when returning from chat
                          if (mounted) {
                            setState(() {});
                          }
                        });
                      },
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (today == messageDate) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else {
      return '${timestamp.day}/${timestamp.month}';
    }
  }

  Widget _buildTickIcon(Message message, int currentUserId) {
    if (message.senderId != currentUserId) {
      return const SizedBox.shrink();
    }

    if (message.isRead == 1) {
      return const Icon(Icons.done_all, size: 16, color: Colors.blue);
    } else if (message.isDelivered == 1) {
      return const Icon(Icons.done_all, size: 16, color: Colors.grey);
    } else {
      return const Icon(Icons.check, size: 16, color: Colors.grey);
    }
  }
}

class Contact {
  final int id;
  final String name;
  final String? lastMessage;
  final DateTime lastMessageTime;
  final int? chatId;
  final String? phoneNumber;

  Contact({
    required this.id,
    required this.name,
    this.lastMessage,
    required this.lastMessageTime,
    this.chatId,
    this.phoneNumber,
  });
}

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  ProfileSetting? _profile;
  bool _loading = true;
  final ImagePicker _imagePicker = ImagePicker();
  String _selectedTab = 'Grid'; // Grid, Reels, or Profile
  List<dynamic> _publishedProducts = [];
  bool _loadingProducts = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadPublishedProducts();
  }

  // Public method to refresh profile
  void refreshProfile() {
    _loadProfile();
    _loadPublishedProducts();
  }

  // ✅ Show MPIN menu from hamburger menu
  void _showMpinMenu(BuildContext context) {
    final isMpinEnabled = LocalAuthService.isMpinEnabled();
    final hasMpin = LocalAuthService.hasMpin();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                "MPIN Settings",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              title: const Text("Enable MPIN"),
              subtitle: Text(isMpinEnabled ? "MPIN is enabled" : "MPIN is disabled"),
              trailing: Switch(
                value: isMpinEnabled,
                onChanged: (value) async {
                  Navigator.pop(context);
                  await LocalAuthService.setMpinEnabled(value);
                  if (mounted) {
                    setState(() {});
                  }
                  if (value) {
                    // If enabling, navigate to SetMpinPage if MPIN not set
                    if (!hasMpin) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SetMpinPage()),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("MPIN enabled.")),
                      );
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("MPIN disabled.")),
                    );
                  }
                },
              ),
            ),
            if (isMpinEnabled)
              ListTile(
                leading: const Icon(Icons.lock),
                title: const Text("Set MPIN"),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SetMpinPage()),
                  );
                },
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    final profile = await ApiService.getProfile();
    setState(() {
      _profile = profile;
      _loading = false;
    });
    // Debug print
    if (profile != null) {
      print("✅ Profile loaded - Name: ${profile.name}, Address: ${profile.address}");
    } else {
      print("❌ Profile is null - No data found");
    }
  }

  Future<void> _loadPublishedProducts() async {
    setState(() => _loadingProducts = true);
    try {
      final products = await ProductDatabaseService().getProducts(
        status: 'publish',
      );
      print("📦 Loaded ${products.length} published products");
      for (var product in products) {
        print("  Product: ${product.name}");
        print("    Main images: ${product.images.length}");
        print("    Variations: ${product.variations.length}");
        for (var variation in product.variations) {
          print("      Variation: ${variation['name']}");
          print("        Image: ${variation['image']}");
          print("        allImages type: ${variation['allImages'].runtimeType}");
          if (variation['allImages'] != null) {
            if (variation['allImages'] is List) {
              print("        allImages count: ${(variation['allImages'] as List).length}");
            } else if (variation['allImages'] is String) {
              print("        allImages is String, length: ${(variation['allImages'] as String).length}");
            }
          }
        }
      }
      setState(() {
        _publishedProducts = products;
        _loadingProducts = false;
      });
    } catch (e, stackTrace) {
      print("❌ Error loading products: $e");
      print("Stack trace: $stackTrace");
      setState(() {
        _publishedProducts = [];
        _loadingProducts = false;
      });
    }
  }

  // Open camera interface directly (full screen)
  void _showImagePickerOptions() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CameraInterfaceScreen(),
      ),
    );

    if (result != null && result is List<File>) {
      _handleSelectedImages(result);
    }
  }

  // Handle selected images
  void _handleSelectedImages(List<File> images) {
    if (images.isEmpty) return;

    // Show a snackbar with the number of selected images
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            images.length == 1
                ? '1 image selected'
                : '${images.length} images selected',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // TODO: Handle the selected images here
    // You can add your logic to process/upload/display the images
    print("Selected ${images.length} image(s)");
    for (var image in images) {
      print("Image path: ${image.path}");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_profile == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("No profile found"),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final userId = LocalAuthService.getUserId();
                if (userId != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserProfilePage(userId: userId),
                    ),
                  ).then((_) {
                    // Refresh profile after saving
                    _loadProfile();
                  });
                }
              },
              child: const Text("Create Profile"),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF128C7E),
      body: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF128C7E),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar with hamburger menu, profile photo, name with arrow, and plus icon
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
                child: Row(
                  children: [
                    // Hamburger menu (3 lines) on left
                    IconButton(
                      icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                      onPressed: () {
                        _showMpinMenu(context);
                      },
                    ),
                    const SizedBox(width: 8),
                    // Profile photo (circular, small)
                    if (_profile!.profileImage != null && _profile!.profileImage!.isNotEmpty)
                      ClipOval(
                        child: Image.network(
                          _profile!.profileImage!,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.person, color: Colors.white, size: 24),
                            );
                          },
                        ),
                      )
                    else
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person, color: Colors.white, size: 24),
                      ),
                    const SizedBox(width: 12),
                    // Name with arrow icon
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              _profile!.name ?? "No Name",
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Plus icon in white square (smaller size)
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.add, color: Colors.black, size: 18),
                        onPressed: () {
                          _showImagePickerOptions();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
              // Location below name (aligned with profile photo)
              if (_profile!.address != null && _profile!.address!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 64.0, right: 16.0, top: 4.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _profile!.address!,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.white,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              // Create Instagram Page button below location (LEFT ALIGNED)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 64.0, top: 12.0, bottom: 8.0),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const InstaPagesScreen(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF128C7E),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 2,
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_circle_outline, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Create Instagram Page',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // White content area below (marketplace)
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  ),
                  child: Column(
                    children: [
                      // Tabs: Grid, Reels, Profile
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Grid Tab
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedTab = 'Grid';
                                });
                              },
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Icon(
                                    Icons.grid_on,
                                    color: _selectedTab == 'Grid' ? Colors.black : Colors.grey,
                                    size: 28,
                                  ),
                                  if (_selectedTab == 'Grid')
                                    Positioned(
                                      top: -4,
                                      right: -4,
                                      child: Container(
                                        width: 12,
                                        height: 12,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF25D366),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Reels Tab
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedTab = 'Reels';
                                });
                              },
                              child: Icon(
                                Icons.play_circle_outline,
                                color: _selectedTab == 'Reels' ? Colors.black : Colors.grey,
                                size: 28,
                              ),
                            ),
                            // Profile Tab
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedTab = 'Profile';
                                });
                              },
                              child: Icon(
                                Icons.person_outline,
                                color: _selectedTab == 'Profile' ? Colors.black : Colors.grey,
                                size: 28,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Content based on selected tab
                      Expanded(
                        child: _selectedTab == 'Grid'
                            ? _buildProductsGrid()
                            : _selectedTab == 'Reels'
                            ? const Center(child: Text('Reels coming soon'))
                            : const Center(child: Text('Profile content')),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductsGrid() {
    if (_loadingProducts) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_publishedProducts.isEmpty) {
      return const Center(
        child: Text(
          'No published products yet',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    // Collect only the last image from each color variation
    List<Map<String, dynamic>> gridItems = [];
    for (var product in _publishedProducts) {
      if (product is Product) {
        // Get last image from each variation
        if (product.variations.isNotEmpty) {
          for (var variation in product.variations) {
            // Get allImages from variation
            List<String> allImages = [];
            if (variation['allImages'] != null) {
              dynamic allImagesData = variation['allImages'];

              // Handle if allImages is a JSON string
              if (allImagesData is String) {
                try {
                  final decoded = jsonDecode(allImagesData);
                  if (decoded is List) {
                    allImagesData = decoded;
                  }
                } catch (e) {
                  print('Error decoding allImages JSON in profile grid: $e');
                }
              }

              // Process as List
              if (allImagesData is List) {
                for (var img in allImagesData) {
                  if (img is String && img.isNotEmpty) {
                    allImages.add(img);
                  } else if (img != null) {
                    allImages.add(img.toString());
                  }
                }
              }
            }

            // Fallback to single image if allImages not available
            if (allImages.isEmpty && variation['image'] != null) {
              final img = variation['image'];
              if (img is String && img.isNotEmpty) {
                allImages.add(img);
              } else if (img != null) {
                allImages.add(img.toString());
              }
            }

            // Only add if we have images
            if (allImages.isNotEmpty) {
              // Get the last image (most recent)
              final lastImage = allImages.last;
              final imageIndex = allImages.length - 1;

              gridItems.add({
                'product': product,
                'variation': variation,
                'imageUrl': lastImage,
                'imageIndex': imageIndex,
                'allImages': allImages,
              });
            }
          }
        }
      }
    }

    if (gridItems.isEmpty) {
      return const Center(
        child: Text(
          'No images found',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: gridItems.length,
        itemBuilder: (context, index) {
          final item = gridItems[index];
          final product = item['product'] as Product;
          final variation = item['variation'] as Map<String, dynamic>;
          final imageUrl = item['imageUrl'] as String;
          final imageIndex = item['imageIndex'] as int;

          final allImages = item['allImages'] as List<String>;
          final totalImages = allImages.length;

          return GestureDetector(
            onTap: () {
              // Debug: Print variation data before navigation
              print('🔍 Navigating to product detail:');
              print('  Variation name: ${variation['name']}');
              print('  allImages type: ${variation['allImages']?.runtimeType}');
              if (variation['allImages'] != null) {
                if (variation['allImages'] is List) {
                  print('  allImages count: ${(variation['allImages'] as List).length}');
                } else {
                  print('  allImages: ${variation['allImages']}');
                }
              }
              print('  Total images in grid: $totalImages');
              print('  Image index: $imageIndex');

              // Navigate to product detail page
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProductDetailScreen(
                    product: product,
                    variation: variation,
                    initialImageIndex: imageIndex,
                  ),
                ),
              );
            },
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: Container(
                      color: Colors.grey.shade200,
                      child: _buildImageWidget(imageUrl),
                    ),
                  ),
                  // Image count badge on bottom right
                  if (totalImages > 1)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.photo_library,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$totalImages',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
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
  }

  Widget _buildImageWidget(String imageUrl) {
    // Handle HTTP/HTTPS URLs
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return SizedBox.expand(
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              color: Colors.grey.shade200,
              child: Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                      : null,
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            print("Error loading network image: $imageUrl - $error");
            return Container(
              color: Colors.grey.shade300,
              child: const Icon(Icons.broken_image, color: Colors.grey),
            );
          },
        ),
      );
    }

    // Try as local file path
    try {
      final file = File(imageUrl);
      if (file.existsSync()) {
        return SizedBox.expand(
          child: Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              print("Error loading file image: $imageUrl - $error");
              return Container(
                color: Colors.grey.shade300,
                child: const Icon(Icons.broken_image, color: Colors.grey),
              );
            },
          ),
        );
      }
    } catch (e) {
      print("Error checking file: $imageUrl - $e");
    }

    // Fallback
    return Container(
      color: Colors.grey.shade300,
      child: const Icon(Icons.broken_image, color: Colors.grey),
    );
  }
}