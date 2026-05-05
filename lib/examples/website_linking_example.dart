import 'package:flutter/material.dart';
import '../widgets/website_link_button.dart';
import '../services/website_verification_service.dart';

class WebsiteLinkingExample extends StatefulWidget {
  @override
  _WebsiteLinkingExampleState createState() => _WebsiteLinkingExampleState();
}

class _WebsiteLinkingExampleState extends State<WebsiteLinkingExample> {
  final TextEditingController _domainController = TextEditingController();
  final int _currentUserId = 1; // Replace with actual user ID
  
  List<Map<String, dynamic>> _linkedWebsites = [];
  bool _isLoadingWebsites = false;

  @override
  void initState() {
    super.initState();
    _loadUserWebsites();
  }

  Future<void> _loadUserWebsites() async {
    setState(() => _isLoadingWebsites = true);
    
    try {
      final result = await WebsiteVerificationService.getUserWebsites(_currentUserId);
      
      if (result['success']) {
        setState(() {
          _linkedWebsites = List<Map<String, dynamic>>.from(result['websites']);
        });
      }
    } catch (e) {
      print('Error loading websites: $e');
    } finally {
      setState(() => _isLoadingWebsites = false);
    }
  }

  void _onLinkStatusChanged(bool isLinked, Map<String, dynamic>? websiteData) {
    if (isLinked) {
      _loadUserWebsites(); // Refresh the list
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Website Linking Demo'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Input section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Link New Website',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _domainController,
                      decoration: InputDecoration(
                        labelText: 'Domain',
                        hintText: 'example.com',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.language),
                      ),
                    ),
                    const SizedBox(height: 12),
                    WebsiteLinkButton(
                      domain: _domainController.text.trim(),
                      userId: _currentUserId,
                      onLinkStatusChanged: _onLinkStatusChanged,
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Linked websites section
            Text(
              'Your Linked Websites',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            if (_isLoadingWebsites)
              Center(child: CircularProgressIndicator())
            else if (_linkedWebsites.isEmpty)
              Container(
                padding: EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.link_off,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No websites linked yet',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _linkedWebsites.length,
                  itemBuilder: (context, index) {
                    final website = _linkedWebsites[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          child: Icon(
                            Icons.language,
                            color: Colors.blue.shade600,
                          ),
                        ),
                        title: Text(
                          website['website_name'] ?? 'Unknown Website',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(website['domain'] ?? ''),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Linked',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        onTap: () {
                          // Navigate to website products or details
                          print('Tapped on website: ${website['website_id']}');
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
