import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/chat_model.dart';
import '../services/chat_service.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({Key? key}) : super(key: key);

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _chatBox = Hive.box<Chat>('chatList');
  final _messageBox = Hive.box<Message>('messages');
  final _authBox = Hive.box('authBox');

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  void _loadChats() async {
    // Ensure ChatService is initialized
    await ChatService.init();
    // Load initial chats if needed
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Chats',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        backgroundColor: const Color(0xFF075E54),
        elevation: 0,
        shadowColor: Colors.black.withOpacity(0.3),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.search, color: Colors.white),
              onPressed: () {},
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
                  Colors.white.withOpacity(0.2),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
      body: ValueListenableBuilder<Box<Chat>>(
        valueListenable: _chatBox.listenable(),
        builder: (context, box, child) {
          final chats = box.values.toList().cast<Chat>();

          if (chats.isEmpty) {
            return const Center(
              child: Text('No chats yet\nStart a new conversation!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, index) {
              return _buildChatTile(chats[index]);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _startNewChat,
        backgroundColor: const Color(0xFF075E54),
        child: const Icon(Icons.chat, color: Colors.white),
      ),
    );
  }

  Widget _buildChatTile(Chat chat) {
    return Slidable(
      key: ValueKey(chat.chatId),

      // 👉 Right swipe for actions
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        children: [
          // 🔹 "More" Button
          SlidableAction(
            onPressed: (context) => _showMoreOptions(context, chat),
            backgroundColor: Colors.grey.shade700,
            icon: Icons.more_vert,
            label: 'More',
          ),

          // 🔹 "Delete" Button
          SlidableAction(
            onPressed: (context) => _deleteChat(chat.chatId),
            backgroundColor: Colors.red,
            icon: Icons.delete,
            label: 'Delete',
          ),
        ],
      ),

      // 👉 Chat Tile Content
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.grey[300],
          child: Text(
            _getChatInitial(chat),
            style: const TextStyle(color: Color(0xFF075E54), fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          _getChatTitle(chat),
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          _getLastMessage(chat.chatId) ?? 'Start a conversation...',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _buildTrailing(chat.chatId),
        onTap: () => _openChat(chat),
      ),
    );
  }

  // 🔹 More Options Bottom Sheet
  void _showMoreOptions(BuildContext context, Chat chat) {
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
              _buildBottomSheetHeader(chat),
              ListTile(
                leading: const Icon(Icons.volume_off, color: Colors.grey),
                title: const Text("Mute Notifications"),
                onTap: () {
                  Navigator.pop(context);
                  _muteChat(chat.chatId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.cleaning_services, color: Colors.grey),
                title: const Text("Clear Chat"),
                onTap: () {
                  Navigator.pop(context);
                  _clearChat(chat.chatId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.block, color: Colors.red),
                title: const Text("Block User"),
                onTap: () {
                  Navigator.pop(context);
                  _blockUser(chat.chatId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text("Delete Chat"),
                onTap: () {
                  Navigator.pop(context);
                  _deleteChat(chat.chatId);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomSheetHeader(Chat chat) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.grey[300],
            child: Text(
              _getChatInitial(chat),
              style: const TextStyle(color: Color(0xFF075E54), fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getChatTitle(chat),
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

  // 🔹 Action Functions
  void _muteChat(int chatId) {
    print("Muted chat: $chatId");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Chat muted")),
    );
  }

  void _clearChat(int chatId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Clear Chat?"),
        content: const Text("Are you sure you want to clear all messages in this chat?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _performClearChat(chatId);
            },
            child: const Text("CLEAR", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _performClearChat(int chatId) {
    try {
      final messages = _messageBox.values
          .where((msg) => msg.chatId == chatId)
          .toList();

      for (var msg in messages) {
        _messageBox.delete(msg.messageId);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Chat cleared successfully")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error clearing chat")),
      );
    }
  }

  void _blockUser(int chatId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Block User?"),
        content: const Text("Are you sure you want to block this user? You will no longer receive messages from them."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _performBlockUser(chatId);
            },
            child: const Text("BLOCK", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _performBlockUser(int chatId) {
    // TODO: Implement actual block logic
    print("Blocked user in chat: $chatId");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("User blocked successfully")),
    );
  }

  void _deleteChat(int chatId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Chat?"),
        content: const Text("Are you sure you want to delete this chat? This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _performDeleteChat(chatId);
            },
            child: const Text("DELETE", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _performDeleteChat(int chatId) {
    try {
      // Delete chat from chat list
      _chatBox.delete(chatId);

      // Delete all messages for this chat
      final messages = _messageBox.values
          .where((msg) => msg.chatId == chatId)
          .toList();

      for (var msg in messages) {
        _messageBox.delete(msg.messageId);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Chat deleted successfully")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error deleting chat")),
      );
    }
  }

  void _openChat(Chat chat) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          chatId: chat.chatId,
          otherUserId: chat.contactId,
          otherUserName: _getChatTitle(chat),
        ),
      ),
    );
  }

  void _startNewChat() {
    // TODO: Implement new chat screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("New chat feature coming soon!")),
    );
  }

  // Helper methods
  String _getChatInitial(Chat chat) {
    final title = _getChatTitle(chat);
    return title.isNotEmpty ? title[0].toUpperCase() : 'U';
  }

  String _getChatTitle(Chat chat) {
    return chat.chatTitle.isNotEmpty ? chat.chatTitle : 'Unknown User';
  }

  String? _getLastMessage(int chatId) {
    try {
      final messages = _messageBox.values
          .where((msg) => msg.chatId == chatId)
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      if (messages.isNotEmpty) {
        final lastMsg = messages.first;
        if (lastMsg.messageType == 'media') {
          return '📷 Photo';
        }
        return lastMsg.messageContent;
      }
    } catch (e) {
      print("Error getting last message: $e");
    }
    return null;
  }

  int _getUnreadCount(int chatId) {
    try {
      return _messageBox.values
          .where((msg) => msg.chatId == chatId && msg.isRead == 0)
          .length;
    } catch (e) {
      return 0;
    }
  }

  Widget _buildTrailing(int chatId) {
    final unreadCount = _getUnreadCount(chatId);
    final lastMessageTime = _getLastMessageTime(chatId);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (lastMessageTime != null)
          Text(
            _formatTime(lastMessageTime),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        const SizedBox(height: 4),
        if (unreadCount > 0)
          CircleAvatar(
            radius: 10,
            backgroundColor: const Color(0xFF075E54),
            child: Text(
              unreadCount > 99 ? '99+' : '$unreadCount',
              style: const TextStyle(fontSize: 10, color: Colors.white),
            ),
          ),
      ],
    );
  }

  DateTime? _getLastMessageTime(int chatId) {
    try {
      final messages = _messageBox.values
          .where((msg) => msg.chatId == chatId)
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      return messages.isNotEmpty ? messages.first.timestamp : null;
    } catch (e) {
      return null;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(time.year, time.month, time.day);

    if (messageDate == today) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else {
      return '${time.day}/${time.month}';
    }
  }
}
