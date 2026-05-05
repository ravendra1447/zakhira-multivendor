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

      // Find the website domain from available websites list
      final website = availableWebsites.firstWhere(
        (w) => w['website_id'] == websiteId,
        orElse: () => null,
      );

      if (website == null) {
        throw Exception('Website not found');
      }

      print('=== LINKING WEBSITE ===');
      print('Website ID: $websiteId');
      print('Website Domain: ${website['domain']}');
      print('User ID: $userId');

      final url = '${Config.baseNodeApiUrl}/verify-app';
      print('API URL: $url');

      final requestBody = {
        'domain': website['domain'],
        'user_id': userId,
      };
      print('Request body: $requestBody');

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      print('Response status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          // Check verification details
          final verification = data['verification'];
          String message = 'Website linked successfully!';
          
          if (verification != null && verification['verified'] == true) {
            message = 'Website verified and linked successfully! ✅';
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          _fetchWebsites(); // Refresh the data
        } else {
          // Check if admin contact is required
          if (data['requires_admin'] == true) {
            final verification = data['verification'];
            String detailedMessage = data['message'] ?? 'Please contact administrator';
            
            if (verification != null) {
              if (verification['database_match'] == false) {
                detailedMessage += '\n\nDomain: ${verification['domain']}\nThis domain is not in the approved database.';
              } else if (verification['server_match'] == false) {
                detailedMessage += '\n\nDetected IP: ${verification['detected_ip']}\nYour Server IP: ${verification['your_server_ips']?.join(', ')}\n\nDatabase domain hosted on external server.';
              } else if (verification['error'] != null) {
                detailedMessage += '\n\nError: ${verification['error']}';
              }
            }
            
            _showAdminContactDialog(detailedMessage);
          } else {
            throw Exception(data['message'] ?? 'Failed to link website');
          }
        }
      } else {
        throw Exception('Server error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error in linkToWebsite: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLinking = false;
        });
      }
    }
  }

  Future<void> _unlinkWebsite(int websiteId, String domain) async {
    try {
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      print('=== UNLINKING WEBSITE ===');
      print('Website ID: $websiteId');
      print('Domain: $domain');
      print('User ID: $userId');

      setState(() {
        isLinking = true;
      });

      final url = '${Config.baseNodeApiUrl}/unlink-website';
      print('API URL: $url');

      final requestBody = {
        'user_id': userId,
        'domain': domain,
      };
      print('Request body: $requestBody');

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      print('Response status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Website unlinked successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchWebsites(); // Refresh the data
        } else {
          // Check if admin contact is required
          if (data['requires_admin'] == true) {
            _showAdminContactDialog(data['message'] ?? 'Please contact administrator for unlinking');
          } else {
            throw Exception(data['message'] ?? 'Failed to unlink website');
          }
        }
      } else {
        throw Exception('Server error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error in unlinkWebsite: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLinking = false;
        });
      }
    }
  }

  void _showUnlinkConfirmation(int websiteId, String websiteName, String domain) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Unlink Website'),
          content: Text('Are you sure you want to unlink "$websiteName"?\n\nThis will remove your access to this website.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _unlinkWebsite(websiteId, domain);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Unlink'),
            ),
          ],
        );
      },
    );
  }

  void _showAdminContactDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Administrator Contact Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 16),
              const Text(
                'Please contact the administrator to complete this linking process.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Admin will verify your database connection and approve the linking.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
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
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Unlink button
                                      ElevatedButton(
                                        onPressed: isLinking
                                            ? null
                                            : () => _showUnlinkConfirmation(
                                                website['website_id'],
                                                website['website_name'],
                                                website['domain']),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 4,
                                          ),
                                        ),
                                        child: const Text(
                                          'Unlink',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // View products button
                                      IconButton(
                                        onPressed: () {
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
                                        icon: const Icon(
                                          Icons.arrow_forward_ios,
                                          color: Color(0xFF128C7E),
                                        ),
                                      ),
                                    ],
                                  ),
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
