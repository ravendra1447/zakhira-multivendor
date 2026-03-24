import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../services/local_auth_service.dart';
import 'website_products_screen.dart';

class WebsiteSelectionScreen extends StatefulWidget {
  const WebsiteSelectionScreen({super.key});

  @override
  State<WebsiteSelectionScreen> createState() => _WebsiteSelectionScreenState();
}

class _WebsiteSelectionScreenState extends State<WebsiteSelectionScreen> {
  List<dynamic> availableWebsites = [];
  List<dynamic> userWebsites = [];
  bool isLoading = true;
  bool isLinking = false;

  @override
  void initState() {
    super.initState();
    _fetchWebsites();
  }

  Future<void> _fetchWebsites() async {
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      // Fetch available websites
      final availableResponse = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/websites/available'),
      );

      // Fetch user's linked websites
      final userWebsitesResponse = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/websites/user/$userId'),
      );

      if (availableResponse.statusCode == 200 && userWebsitesResponse.statusCode == 200) {
        final availableData = jsonDecode(availableResponse.body);
        final userData = jsonDecode(userWebsitesResponse.body);

        if (mounted) {
          setState(() {
            availableWebsites = availableData['data'] ?? [];
            userWebsites = userData['data'] ?? [];
            isLoading = false;
          });
        }
      } else {
        throw Exception('Failed to load websites');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _linkToWebsite(int websiteId) async {
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      setState(() {
        isLinking = true;
      });

      final response = await http.post(
        Uri.parse('${Config.baseNodeApiUrl}/websites/link'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'userId': userId,
          'websiteId': websiteId,
          'role': 'user',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Website linked successfully!')),
          );
          _fetchWebsites(); // Refresh the data
        } else {
          throw Exception(data['message'] ?? 'Failed to link website');
        }
      } else {
        throw Exception('Failed to link website');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLinking = false;
        });
      }
    }
  }

  bool _isWebsiteLinked(int websiteId) {
    return userWebsites.any((website) => website['website_id'] == websiteId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Link Website'),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchWebsites,
              child: Column(
                children: [
                  // User's linked websites section
                  if (userWebsites.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      color: Colors.grey[100],
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Your Linked Websites',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF075E54),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...userWebsites.map((website) => Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: const Icon(
                                    Icons.link,
                                    color: Color(0xFF25D366),
                                  ),
                                  title: Text(website['website_name']),
                                  subtitle: Text(website['domain']),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'Linked',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => WebsiteProductsScreen(
                                          websiteId: website['website_id'],
                                          websiteName: website['website_name'],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              )),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                  // Available websites section
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Available Websites',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF075E54),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: availableWebsites.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No websites available to link',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: availableWebsites.length,
                                    itemBuilder: (context, index) {
                                      final website = availableWebsites[index];
                                      final isLinked = _isWebsiteLinked(
                                          website['website_id']);

                                      return Card(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        child: ListTile(
                                          leading: Icon(
                                            isLinked
                                                ? Icons.check_circle
                                                : Icons.add_circle_outline,
                                            color: isLinked
                                                ? Colors.green
                                                : const Color(0xFF128C7E),
                                          ),
                                          title: Text(website['website_name']),
                                          subtitle: Text(website['domain']),
                                          trailing: isLinked
                                              ? Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey,
                                                    borderRadius:
                                                        BorderRadius.circular(12),
                                                  ),
                                                  child: const Text(
                                                    'Linked',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                )
                                              : ElevatedButton(
                                                  onPressed: isLinking
                                                      ? null
                                                      : () => _linkToWebsite(
                                                          website['website_id']),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        const Color(0xFF25D366),
                                                    foregroundColor: Colors.white,
                                                  ),
                                                  child: const Text('Link'),
                                                ),
                                        ),
                                      );
                                    },
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
  }
}
