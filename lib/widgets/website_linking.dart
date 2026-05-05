import 'package:flutter/material.dart';
import '../services/website_verification_service.dart';
import 'simple_website_button.dart';
import 'test_button.dart';

class WebsiteLinking extends StatefulWidget {
  final int userId;

  const WebsiteLinking({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  _WebsiteLinkingState createState() => _WebsiteLinkingState();
}

class _WebsiteLinkingState extends State<WebsiteLinking> {
  final TextEditingController _domainController = TextEditingController();
  List<Map<String, dynamic>> _linkedWebsites = [];
  List<Map<String, dynamic>> _availableWebsites = [];
  bool _isLoadingLinked = false;
  bool _isLoadingAvailable = false;
  bool _isLinking = false;

  @override
  void initState() {
    super.initState();
    _loadLinkedWebsites();
    _loadAvailableWebsites();
  }

  @override
  void dispose() {
    _domainController.dispose();
    super.dispose();
  }

  Future<void> _loadLinkedWebsites() async {
    setState(() => _isLoadingLinked = true);
    
    try {
      final result = await WebsiteVerificationService.getUserWebsites(widget.userId);
      
      if (result['success']) {
        setState(() {
          _linkedWebsites = List<Map<String, dynamic>>.from(result['websites']);
        });
        // Filter available websites
        _filterAvailableWebsites();
      }
    } catch (e) {
      print('Error loading linked websites: $e');
    } finally {
      setState(() => _isLoadingLinked = false);
    }
  }

  Future<void> _loadAvailableWebsites() async {
    setState(() => _isLoadingAvailable = true);
    
    try {
      // You'll need to implement this API endpoint
      final response = await WebsiteVerificationService.getAvailableWebsites();
      
      if (response['success']) {
        setState(() {
          _availableWebsites = List<Map<String, dynamic>>.from(response['websites']);
        });
        _filterAvailableWebsites();
      }
    } catch (e) {
      print('Error loading available websites: $e');
    } finally {
      setState(() => _isLoadingAvailable = false);
    }
  }

  void _filterAvailableWebsites() {
    if (_linkedWebsites.isNotEmpty && _availableWebsites.isNotEmpty) {
      setState(() {
        _availableWebsites = _availableWebsites.where((available) =>
          !_linkedWebsites.any((linked) => linked['website_id'] == available['website_id'])
        ).toList();
      });
    }
  }

  void _onLinkStatusChanged(bool isLinked, Map<String, dynamic>? websiteData) {
    if (isLinked && websiteData != null) {
      setState(() {
        _linkedWebsites.add(websiteData);
        _availableWebsites.removeWhere((website) => 
          website['website_id'] == websiteData['website_id']
        );
      });
    }
  }

  Future<void> _handleLinkNewWebsite() async {
    if (_domainController.text.trim().isEmpty) return;

    setState(() => _isLinking = true);
    
    try {
      final result = await WebsiteVerificationService.verifyAndLinkWebsite(
        domain: _domainController.text.trim(),
        userId: widget.userId,
      );
      
      if (result['success']) {
        setState(() {
          _linkedWebsites.add(result['data']);
          _domainController.clear();
        });
        _filterAvailableWebsites();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Website linked successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        if (result['requires_admin'] == true) {
          _showAdminContactDialog(result['admin_last4'] ?? '');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Failed to link website'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLinking = false);
    }
  }

  void _showAdminContactDialog(String last4Digits) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Admin Verification Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This website requires admin verification. Please contact the administrator.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.phone, color: Colors.blue.shade600, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Admin: ****$last4Digits',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Link Website'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Link New Website Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Link New Website',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _domainController,
                          decoration: InputDecoration(
                            hintText: 'Enter website domain...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          onSubmitted: (_) => _handleLinkNewWebsite(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isLinking ? null : _handleLinkNewWebsite,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                        child: _isLinking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text('Link'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Websites Grid
            Row(
              children: [
                Expanded(
                  child: _buildLinkedWebsitesSection(),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildAvailableWebsitesSection(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkedWebsitesSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Linked Websites',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          if (_isLoadingLinked)
            const Center(child: CircularProgressIndicator())
          else if (_linkedWebsites.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.link_off,
                      size: 48,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No linked websites',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: _linkedWebsites.map((website) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    children: [
                      // Website info
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              website['website_name'] ?? 'Unknown Website',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              website['domain'] ?? '',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Unlink button
                      TestButton(
                        text: 'Unlink ${website['website_name'] ?? 'Website'}',
                        onPressed: () async {
                          try {
                            final result = await WebsiteVerificationService.unlinkWebsite(
                              domain: website['domain'] ?? '',
                              userId: widget.userId,
                            );
                            
                            if (result['success']) {
                              setState(() {
                                _linkedWebsites.removeWhere((w) => w['website_id'] == website['website_id']);
                              });
                              _loadAvailableWebsites();
                              
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Website unlinked successfully!'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(result['message'] ?? 'Unlinking failed'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: ${e.toString()}'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                        color: Colors.red,
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildAvailableWebsitesSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Available Websites',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          if (_isLoadingAvailable)
            const Center(child: CircularProgressIndicator())
          else if (_availableWebsites.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.language,
                      size: 48,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No available websites',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: _availableWebsites.map((website) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    children: [
                      // Website info
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              website['website_name'] ?? 'Unknown Website',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              website['domain'] ?? '',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Link button
                      TestButton(
                        text: 'Link ${website['website_name'] ?? 'Website'}',
                        onPressed: () async {
                          try {
                            final result = await WebsiteVerificationService.verifyAndLinkWebsite(
                              domain: website['domain'] ?? '',
                              userId: widget.userId,
                            );
                            
                            if (result['success']) {
                              _onLinkStatusChanged(true, {
                                ...result['data'],
                                'website_id': website['website_id'],
                                'website_name': website['website_name'],
                                'domain': website['domain'],
                              });
                              
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Website linked successfully!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(result['message'] ?? 'Linking failed'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: ${e.toString()}'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                        color: Colors.blue,
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
