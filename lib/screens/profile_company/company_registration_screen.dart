import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../config.dart';

class CompanyRegistrationScreen extends StatefulWidget {
  final String userPhone;
  final String userId;

  const CompanyRegistrationScreen({
    Key? key,
    required this.userPhone,
    required this.userId,
  }) : super(key: key);

  @override
  _CompanyRegistrationScreenState createState() => _CompanyRegistrationScreenState();
}

class _CompanyRegistrationScreenState extends State<CompanyRegistrationScreen> {
  final companyController = TextEditingController();
  final branchController = TextEditingController();
  final cityController = TextEditingController();
  bool isRegistering = false;

  @override
  void dispose() {
    companyController.dispose();
    branchController.dispose();
    cityController.dispose();
    super.dispose();
  }

  Future<void> _registerCompany() async {
    if (companyController.text.isEmpty || branchController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please fill required fields'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      isRegistering = true;
    });

    try {
      final response = await http.post(
        Uri.parse('${Config.currentNodeApiUrl}/flutter/users/quick-register-company'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'phone': widget.userPhone,
          'company_name': companyController.text,
          'branch_name': branchController.text,
          'city': cityController.text,
        }),
      );

      final data = json.decode(response.body);

      if (data['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Company registered successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        
        // Success ke baad previous screen par wapas jao
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Registration failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registration failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        isRegistering = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Register Business'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade50, Colors.green.shade100],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.business, color: Colors.green, size: 28),
                      SizedBox(width: 12),
                      Text(
                        'Business Registration',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Register your company to start publishing products',
                    style: TextStyle(
                      color: Colors.green.shade600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 24),
            
            // User Info
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'User Details',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text('Phone: ${widget.userPhone}'),
                  Text('User ID: ${widget.userId}'),
                ],
              ),
            ),
            
            SizedBox(height: 24),
            
            // Registration Form
            Text(
              'Business Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            
            SizedBox(height: 16),
            
            TextField(
              controller: companyController,
              decoration: InputDecoration(
                labelText: 'Company Name *',
                hintText: 'e.g., My Fashion Store',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.store),
              ),
            ),
            
            SizedBox(height: 16),
            
            TextField(
              controller: branchController,
              decoration: InputDecoration(
                labelText: 'Branch Name *',
                hintText: 'e.g., Main Branch',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_city),
              ),
            ),
            
            SizedBox(height: 16),
            
            TextField(
              controller: cityController,
              decoration: InputDecoration(
                labelText: 'City',
                hintText: 'e.g., Noida',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on),
              ),
            ),
            
            SizedBox(height: 32),
            
            // Register Button
            Container(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isRegistering ? null : _registerCompany,
                icon: isRegistering
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Icon(Icons.business_center),
                label: Text(
                  isRegistering ? 'Registering...' : 'Register Business',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  elevation: 3,
                ),
              ),
            ),
            
            SizedBox(height: 16),
            
            // Cancel Button
            Container(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade600,
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// YE AAPKE PRODUCT ADD SCREEN MEIN USE KARO:
/*
// Product add screen mein:
import '../profile_company/company_registration_screen.dart';

// + button ke onPressed mein:
onPressed: () async {
  // Pehle user company check karo
  final response = await http.get(
    Uri.parse('${Config.currentNodeApiUrl}/users/user-info/${widget.userPhone}'),
  );
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    if (data['success']) {
      final userInfo = data['data'];
      
      // User ID match check
      if (userInfo['user_id'].toString() != widget.userId.toString()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User ID and Phone do not match')),
        );
        return;
      }
      
      // Company check
      if (userInfo['company_id'] == null || userInfo['branch_id'] == null) {
        // Registration screen par jao
        final registered = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CompanyRegistrationScreen(
              userPhone: widget.userPhone,
              userId: widget.userId,
            ),
          ),
        );
        
        if (registered == true) {
          // Registration successful - product add kar sakte hain
          // AAPKA EXISTING PRODUCT ADD LOGIC
        }
      } else {
        // Company hai - directly product add kar sakte hain
        // AAPKA EXISTING PRODUCT ADD LOGIC
      }
    }
  }
},
*/
