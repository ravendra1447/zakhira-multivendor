import 'package:flutter/material.dart';

class CommunitiesScreen extends StatelessWidget {
  const CommunitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Communities",
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
              icon: const Icon(Icons.search, color: Colors.white),
              onPressed: () {},
            ),
          ),
          PopupMenuButton<String>(
            iconColor: Colors.white,
            itemBuilder: (context) => [
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
          // New Community Banner
          ListTile(
            leading: const CircleAvatar(
              radius: 25,
              backgroundColor: Colors.green,
              child: Icon(Icons.group, color: Colors.white),
            ),
            title: const Text("New Community"),
            subtitle: const Text("Create a new community"),
            onTap: () {},
          ),
          const Divider(),

          // Example Community Group
          ListTile(
            leading: const CircleAvatar(
              radius: 25,
              backgroundImage:
              NetworkImage("https://via.placeholder.com/150"),
            ),
            title: const Text("Flutter Devs"),
            subtitle: const Text("Latest: Meeting tomorrow at 5 PM"),
            onTap: () {},
          ),
          ListTile(
            leading: const CircleAvatar(
              radius: 25,
              backgroundImage:
              NetworkImage("https://via.placeholder.com/150"),
            ),
            title: const Text("Job Alerts Group"),
            subtitle: const Text("Latest: New openings in IT sector"),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
