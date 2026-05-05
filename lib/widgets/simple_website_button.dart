import 'package:flutter/material.dart';
import '../services/website_verification_service.dart';

class SimpleWebsiteButton extends StatefulWidget {
  final String domain;
  final int userId;
  final Function(bool isLinked)? onLinkStatusChanged;

  const SimpleWebsiteButton({
    Key? key,
    required this.domain,
    required this.userId,
    this.onLinkStatusChanged,
  }) : super(key: key);

  @override
  _SimpleWebsiteButtonState createState() => _SimpleWebsiteButtonState();
}

class _SimpleWebsiteButtonState extends State<SimpleWebsiteButton> {
  bool _isLoading = false;
  bool _isLinked = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    setState(() => _isLoading = true);
    
    try {
      final result = await WebsiteVerificationService.checkWebsiteStatus(
        userId: widget.userId,
        domain: widget.domain,
      );
      
      if (result['success']) {
        setState(() {
          _isLinked = result['linked'];
        });
      }
    } catch (e) {
      print('Error checking status: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleLink() async {
    setState(() => _isLoading = true);
    
    try {
      if (_isLinked) {
        // Unlink
        final result = await WebsiteVerificationService.unlinkWebsite(
          domain: widget.domain,
          userId: widget.userId,
        );
        
        if (result['success']) {
          setState(() {
            _isLinked = false;
          });
          widget.onLinkStatusChanged?.call(false);
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Website unlinked successfully!'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        // Link
        final result = await WebsiteVerificationService.verifyAndLinkWebsite(
          domain: widget.domain,
          userId: widget.userId,
        );
        
        if (result['success']) {
          setState(() {
            _isLinked = true;
          });
          widget.onLinkStatusChanged?.call(true);
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Website linked successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('Error toggling link: $e');
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[600]!),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Loading...',
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _toggleLink,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isLinked ? Colors.red : Colors.blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 2,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isLinked ? Icons.link_off : Icons.link,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              _isLinked ? 'Unlink Website' : 'Link Website',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
