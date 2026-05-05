import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../config.dart';

class ProfileScreenWithCompanyIntegration extends StatefulWidget {
  final String userPhone;
  final String userName;
  final String userLocation;

  const ProfileScreenWithCompanyIntegration({
    Key? key,
    required this.userPhone,
    required this.userName,
    required this.userLocation,
  }) : super(key: key);

  @override
  _ProfileScreenWithCompanyIntegrationState createState() =>
      _ProfileScreenWithCompanyIntegrationState();
}

class _ProfileScreenWithCompanyIntegrationState
    extends State<ProfileScreenWithCompanyIntegration> {
  bool hasCompany = false;
  bool needsRegistration = false;
  bool isLoading = true;
  Map<String, dynamic>? userInfo;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _checkCompanyStatus();
  }

  Future<void> _checkCompanyStatus() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse(
            '${Config.currentNodeApiUrl}/flutter/users/check-company/${widget.userPhone}'),
      );

      final data = json.decode(response.body);

      if (data['success']) {
        setState(() {
          hasCompany = data['has_company'];
          needsRegistration = data['needs_registration'];
          userInfo = data['user_info'];
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = data['message'] ?? 'Failed to check company status';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Network error: $e';
        isLoading = false;
      });
      print('Error checking company status: $e');
    }
  }

  void _showCompanyRegistrationDialog() {
    final companyController = TextEditingController();
    final branchController = TextEditingController();
    final cityController = TextEditingController();
    bool isRegistering = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
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
                          Uri.parse(
                              '${Config.currentNodeApiUrl}/flutter/users/quick-register-company'),
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
                          Navigator.pop(context);
                          // Refresh company status
                          await _checkCompanyStatus();
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
        ),
      ),
    );
  }

  Future<bool> _checkCanPublish() async {
    try {
      final response = await http.get(
        Uri.parse(
            '${Config.currentNodeApiUrl}/flutter/users/can-publish/${widget.userPhone}'),
      );

      final data = json.decode(response.body);

      if (data['success'] && data['can_publish']) {
        return true;
      } else {
        // Show message to register company first
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.info, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(data['message'] ??
                      'Please register your company first to publish products'),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Register Now',
              textColor: Colors.white,
              onPressed: () => _showCompanyRegistrationDialog(),
            ),
          ),
        );
        return false;
      }
    } catch (e) {
      print('Error checking publish permission: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error checking permissions'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }

  Widget _buildProfileHeader() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green, Colors.green.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.userName,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    widget.userLocation,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.white.withOpacity(0.2),
                child: Icon(
                  Icons.person,
                  size: 30,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  // Create Instagram Post functionality
                },
                icon: Icon(Icons.camera_alt, size: 16),
                label: Text('Create Instagram Post'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.green,
                  textStyle: TextStyle(fontSize: 12),
                ),
              ),
              SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  // Link Website functionality
                },
                icon: Icon(Icons.link, size: 16),
                label: Text('Link Website'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.green,
                  textStyle: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyRegistrationCard() {
    return Card(
      margin: EdgeInsets.all(16),
      elevation: 4,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [Colors.orange.shade50, Colors.orange.shade100],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.business_center, color: Colors.orange, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🏢 Register Your Business',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Start selling by registering your company',
                          style: TextStyle(
                            color: Colors.orange.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Container(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showCompanyRegistrationDialog(),
                  icon: Icon(Icons.add_business, size: 18),
                  label: Text('Register Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    textStyle: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompanyInfo() {
    if (!hasCompany || userInfo == null) return SizedBox.shrink();

    return Card(
      margin: EdgeInsets.all(16),
      elevation: 3,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [Colors.green.shade50, Colors.green.shade100],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.business, color: Colors.green, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Business Information',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              _buildInfoRow('Company', userInfo!['company_name'] ?? 'N/A'),
              SizedBox(height: 8),
              _buildInfoRow('Branch', userInfo!['branch_name'] ?? 'N/A'),
              if (userInfo!['city'] != null) ...[
                SizedBox(height: 8),
                _buildInfoRow('City', userInfo!['city']),
              ],
              SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 16),
                    SizedBox(width: 8),
                    Text(
                      '✅ Ready to publish products',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: Colors.grey.shade800,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Container(
      margin: EdgeInsets.all(16),
      child: Column(
        children: [
          // Publish Product Button
          Container(
            width: double.infinity,
            margin: EdgeInsets.only(bottom: 12),
            child: ElevatedButton.icon(
              onPressed: () async {
                if (await _checkCanPublish()) {
                  // Navigate to product creation
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Navigating to product creation...'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  // TODO: Navigate to your product creation screen
                  // Navigator.pushNamed(context, '/create-product');
                }
              },
              icon: Icon(Icons.add_shopping_cart, size: 20),
              label: Text(
                'Publish Product',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 14),
                elevation: 3,
              ),
            ),
          ),
          
          // View Orders Button (only if has company)
          if (hasCompany)
            Container(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  // Navigate to orders screen
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Opening orders...'),
                      backgroundColor: Colors.blue,
                    ),
                  );
                  // TODO: Navigate to orders screen
                },
                icon: Icon(Icons.list_alt, size: 20),
                label: Text(
                  'View Orders',
                  style: TextStyle(fontSize: 16),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                  side: BorderSide(color: Colors.blue),
                  padding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _checkCompanyStatus,
        child: SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildProfileHeader(),
              
              if (isLoading)
                Container(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(color: Colors.green),
                        SizedBox(height: 16),
                        Text(
                          'Checking business status...',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              
              if (errorMessage != null)
                Container(
                  margin: EdgeInsets.all(16),
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          errorMessage!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                      IconButton(
                        onPressed: _checkCompanyStatus,
                        icon: Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
              
              if (!isLoading && errorMessage == null) ...[
                if (needsRegistration)
                  _buildCompanyRegistrationCard(),
                
                if (hasCompany)
                  _buildCompanyInfo(),
                
                _buildActionButtons(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
