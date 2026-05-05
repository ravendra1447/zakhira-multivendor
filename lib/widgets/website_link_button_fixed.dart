import 'package:flutter/material.dart';
import '../services/website_verification_service.dart';

class WebsiteLinkButtonFixed extends StatefulWidget {
  final String domain;
  final int userId;
  final Function(bool isLinked, Map<String, dynamic>? websiteData)? onLinkStatusChanged;

  const WebsiteLinkButtonFixed({
    Key? key,
    required this.domain,
    required this.userId,
    this.onLinkStatusChanged,
  }) : super(key: key);

  @override
  _WebsiteLinkButtonFixedState createState() => _WebsiteLinkButtonFixedState();
}

class _WebsiteLinkButtonFixedState extends State<WebsiteLinkButtonFixed> {
  bool _isLoading = false;
  bool _isLinked = false;
  Map<String, dynamic>? _websiteData;

  @override
  void initState() {
    super.initState();
    print('=== WEBSITE LINK BUTTON FIXED INIT ===');
    print('Domain: ${widget.domain}');
    print('UserId: ${widget.userId}');
    _checkLinkStatus();
  }

  Future<void> _checkLinkStatus() async {
    print('=== CHECKING LINK STATUS ===');
    print('Domain: ${widget.domain}');
    print('UserId: ${widget.userId}');
    
    setState(() => _isLoading = true);
    
    try {
      final result = await WebsiteVerificationService.checkWebsiteStatus(
        userId: widget.userId,
        domain: widget.domain,
      );
      
      print('Link Status Result: $result');
      
      if (result['success']) {
        setState(() {
          _isLinked = result['linked'];
          _websiteData = result['data'];
        });
        print('Set isLinked to: $_isLinked');
        widget.onLinkStatusChanged?.call(_isLinked, _websiteData);
      }
    } catch (e) {
      print('Error checking link status: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _linkWebsite() async {
    print('=== LINK WEBSITE METHOD CALLED ===');
    print('Domain: ${widget.domain}');
    print('UserId: ${widget.userId}');
    
    setState(() => _isLoading = true);
    
    try {
      final result = await WebsiteVerificationService.verifyAndLinkWebsite(
        domain: widget.domain,
        userId: widget.userId,
      );
      
      print('Link Result: $result');
      
      if (result['success']) {
        setState(() {
          _isLinked = true;
          _websiteData = result['data'];
        });
        widget.onLinkStatusChanged?.call(true, _websiteData);
        
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
              content: Text(result['message'] ?? 'Linking failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('Link Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _unlinkWebsite() async {
    print('=== UNLINK WEBSITE METHOD CALLED ===');
    print('Domain: ${widget.domain}');
    print('UserId: ${widget.userId}');
    
    setState(() => _isLoading = true);
    
    try {
      final result = await WebsiteVerificationService.unlinkWebsite(
        domain: widget.domain,
        userId: widget.userId,
      );
      
      print('Unlink Result: $result');
      
      if (result['success']) {
        setState(() {
          _isLinked = false;
          _websiteData = null;
        });
        widget.onLinkStatusChanged?.call(false, null);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Website unlinked successfully!'),
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
      print('Unlink Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
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
    print('=== BUILDING WIDGET ===');
    print('Is Linked: $_isLinked');
    print('Is Loading: $_isLoading');
    print('Website Data: $_websiteData');

    if (_isLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.grey.shade600),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Loading...',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (_isLinked) {
      print('=== BUILDING LINKED UI ===');
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Linked status row
            Row(
              children: [
                Icon(Icons.link, color: Colors.green.shade600, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Linked',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (_websiteData != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade600,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _websiteData!['website_name'] ?? 'Website',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Unlink button - Full width on mobile
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  print('=== UNLINK BUTTON PRESSED ===');
                  _unlinkWebsite();
                },
                icon: Icon(Icons.link_off, color: Colors.white, size: 18),
                label: Text(
                  'Unlink Website',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade500,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ),
      );
    }

    print('=== BUILDING LINK UI ===');
    return Container(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          print('=== LINK BUTTON PRESSED ===');
          _linkWebsite();
        },
        icon: const Icon(Icons.link, size: 18),
        label: const Text(
          'Link Website',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue.shade600,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 2,
        ),
      ),
    );
  }
}
