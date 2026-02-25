import 'package:flutter/material.dart';

class UpdatesScreen extends StatelessWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Updates",
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
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
              onPressed: () {},
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.search, color: Colors.white),
              onPressed: () {},
            ),
          ),
          PopupMenuButton<String>(
            iconColor: Colors.white,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: "status_privacy",
                child: Text("Status privacy"),
              ),
              const PopupMenuItem(
                value: "settings",
                child: Text("Settings"),
              ),
            ],
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
      body: ListView(
        children: [
          // Status Section
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                _statusItem(
                  imageUrl:
                  "https://i.pravatar.cc/150?img=5", // Add Status icon
                  name: "Add status",
                  isAddButton: true,
                ),
                _statusItem(
                  imageUrl: "https://i.pravatar.cc/150?img=1",
                  name: "Salman Bhai Ag",
                ),
                _statusItem(
                  imageUrl: "https://i.pravatar.cc/150?img=2",
                  name: "Suneel Raja",
                ),
                _statusItem(
                  imageUrl: "https://i.pravatar.cc/150?img=3",
                  name: "Bal Karan Patel",
                ),
              ],
            ),
          ),

          const Divider(),

          // Channels Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Channels",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text("Explore"),
                ),
              ],
            ),
          ),

          // Channel List
          _channelTile(
            name: "Hindi Behind Talkies",
            message: "ऐसा बॉयफ्रेंड कहा मिलेगा? 🥺🥺",
            time: "1:10 pm",
            unread: 6,
            imageUrl: "https://via.placeholder.com/150",
          ),
          _channelTile(
            name: "Tech Program Mind - Jobs and I...",
            message: "https://youtu.be/Q7vNxj82XvM",
            time: "1:02 pm",
            unread: 98,
            imageUrl: "https://via.placeholder.com/150",
          ),
          _channelTile(
            name: "Fresher Jobs | Internships | Soft...",
            message: "🔍 Unify Technologies Off Campus",
            time: "1:01 pm",
            unread: 124,
            imageUrl: "https://via.placeholder.com/150",
          ),
          _channelTile(
            name: "Ashok IT",
            message: "🔥 Few Hours to go ● Java Fulls...",
            time: "12:20 pm",
            unread: 88,
            imageUrl: "https://via.placeholder.com/150",
          ),
        ],
      ),
    );
  }

  // Widget for Status Item
  Widget _statusItem({
    required String imageUrl,
    required String name,
    bool isAddButton = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundImage: NetworkImage(imageUrl),
              ),
              if (isAddButton)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.green,
                    child: const Icon(Icons.add, size: 16, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: 60,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // Widget for Channel Tile
  Widget _channelTile({
    required String name,
    required String message,
    required String time,
    required int unread,
    required String imageUrl,
  }) {
    return ListTile(
      leading: CircleAvatar(
        radius: 25,
        backgroundImage: NetworkImage(imageUrl),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(message, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(time, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 5),
          if (unread > 0)
            CircleAvatar(
              radius: 10,
              backgroundColor: Colors.green,
              child: Text(
                unread.toString(),
                style: const TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
        ],
      ),
      onTap: () {},
    );
  }
}
