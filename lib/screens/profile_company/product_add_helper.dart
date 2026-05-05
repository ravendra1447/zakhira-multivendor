import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../config.dart';

class ProductAddHelper {
  static Future<Map<String, dynamic>> checkCompanyStatus(String userPhone) async {
    try {
      final response = await http.get(
        Uri.parse('${Config.currentNodeApiUrl}/flutter/users/check-company/$userPhone'),
      );

      final data = json.decode(response.body);

      if (data['success']) {
        return {
          'success': true,
          'has_company': data['has_company'],
          'needs_registration': data['needs_registration'],
          'user_info': data['user_info'],
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to check company status',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }

  static Future<bool> showRegistrationDialog(BuildContext context, String userPhone) async {
    bool registrationSuccess = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CompanyRegistrationDialog(
        userPhone: userPhone,
        onRegistrationSuccess: () {
          registrationSuccess = true;
          Navigator.pop(context);
        },
      ),
    );

    return registrationSuccess;
  }

  static Future<bool> canPublishProduct(BuildContext context, String userPhone) async {
    // Check company status
    final companyStatus = await checkCompanyStatus(userPhone);

    if (!companyStatus['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(companyStatus['message']),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    // If user needs registration, show registration dialog
    if (companyStatus['needs_registration']) {
      final registrationSuccess = await showRegistrationDialog(context, userPhone);
      
      if (!registrationSuccess) {
        return false;
      }

      // Check company status again after registration
      final newStatus = await checkCompanyStatus(userPhone);
      return newStatus['success'] && !newStatus['needs_registration'];
    }

    return true;
  }

  static void showCompanyRequiredDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.business_center, color: Colors.orange),
            SizedBox(width: 8),
            Text('Business Registration Required'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.business,
              size: 60,
              color: Colors.orange,
            ),
            SizedBox(height: 16),
            Text(
              'To publish products, you need to register your business first',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Show registration dialog
              showRegistrationDialog(context, 'USER_PHONE_HERE'); // Replace with actual user phone
            },
            child: Text('Register Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanyRegistrationDialog extends StatefulWidget {
  final String userPhone;
  final VoidCallback onRegistrationSuccess;

  const _CompanyRegistrationDialog({
    required this.userPhone,
    required this.onRegistrationSuccess,
  });

  @override
  _CompanyRegistrationDialogState createState() => _CompanyRegistrationDialogState();
}

class _CompanyRegistrationDialogState extends State<_CompanyRegistrationDialog> {
  final companyController = TextEditingController();
  final branchController = TextEditingController();
  final cityController = TextEditingController();
  bool isRegistering = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.business, color: Colors.green),
          SizedBox(width: 8),
          Text('Register Your Business'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Register your company to start publishing products',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            SizedBox(height: 20),
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
                hintText: 'e.g., Delhi',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: isRegistering ? null : () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: isRegistering
              ? null
              : () async {
                  if (companyController.text.isEmpty ||
                      branchController.text.isEmpty) {
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
                      widget.onRegistrationSuccess();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✅ Company registered successfully!'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 3),
                        ),
                      );
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
                },
          child: isRegistering
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text('Register'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
