import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../config.dart';

class EditDeliveryFeeScreen extends StatefulWidget {
  final int orderId;
  final double currentSubtotal;
  final double currentDeliveryFee;
  final double currentTotal;

  const EditDeliveryFeeScreen({
    super.key,
    required this.orderId,
    required this.currentSubtotal,
    required this.currentDeliveryFee,
    required this.currentTotal,
  });

  @override
  State<EditDeliveryFeeScreen> createState() => _EditDeliveryFeeScreenState();
}

class _EditDeliveryFeeScreenState extends State<EditDeliveryFeeScreen> {
  final _deliveryFeeController = TextEditingController();
  bool _isLoading = false;
  double _newTotal = 0.0;

  @override
  void initState() {
    super.initState();
    _deliveryFeeController.text = widget.currentDeliveryFee.toStringAsFixed(2);
    _calculateNewTotal();
  }

  void _calculateNewTotal() {
    final deliveryFee = double.tryParse(_deliveryFeeController.text) ?? 0.0;
    setState(() {
      _newTotal = widget.currentSubtotal + deliveryFee;
    });
  }

  Future<void> _updateDeliveryFee() async {
    final deliveryFee = double.tryParse(_deliveryFeeController.text);
    
    if (deliveryFee == null || deliveryFee < 0) {
      _showError('Please enter a valid delivery fee');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Skip test and directly update delivery fee
      print('=== DEBUG INFO ===');
      print('Config.baseNodeApiUrl: ${Config.baseNodeApiUrl}');
      print('Widget Order ID: ${widget.orderId}');
      print('Delivery Fee: $deliveryFee');
      
      // Save to database
      print('Updating delivery fee...');
      final updateUrl = '${Config.baseNodeApiUrl}/orders/update-delivery-fee/${widget.orderId}';
      print('Full Update URL: $updateUrl');
      
      final response = await http.put(
        Uri.parse(updateUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'deliveryFee': deliveryFee}),
      );

      print('Update Response Status: ${response.statusCode}');
      print('Update Response Body: ${response.body}');
      
      // Parse response safely
      try {
        final data = json.decode(response.body);
        print('Parsed Data: $data');
        
        if (response.statusCode == 200) {
          if (data['success'] == true) {
            print('Success: Extracting delivery fee and total');
            Navigator.pop(context, {
              'delivery_fee': data['data']['delivery_fee'],
              'total': data['data']['total'],
              'success': true,
            });
            
            _showSuccess('Delivery fee updated successfully!');
          } else {
            print('Failed: ${data['message']}');
            _showError(data['message'] ?? 'Failed to update delivery fee');
          }
        } else {
          print('Server Error: Status ${response.statusCode}');
          _showError('Server error: ${response.statusCode}');
        }
      } catch (jsonError) {
        print('JSON Parse Error: $jsonError');
        _showError('Response parsing error: $jsonError');
      }
    } catch (e) {
      _showError('Error updating delivery fee: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Delivery Fee'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order Summary Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue[50]!, Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order #${widget.orderId}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[800],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildSummaryRow('Subtotal', '₹${widget.currentSubtotal.toStringAsFixed(2)}'),
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                    'Current Delivery', 
                    '₹${widget.currentDeliveryFee.toStringAsFixed(2)}',
                    isOld: true,
                  ),
                  const Divider(height: 16),
                  _buildSummaryRow('Current Total', '₹${widget.currentTotal.toStringAsFixed(2)}'),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Edit Delivery Fee Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Update Delivery Fee',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _deliveryFeeController,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Delivery Fee (₹)',
                      prefixIcon: Icon(Icons.local_shipping, color: Colors.blue[600]),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.blue[600]!, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                      hintText: 'Enter delivery fee amount',
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    onChanged: (value) => _calculateNewTotal(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Enter 0 for FREE delivery',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // New Total Preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green[50]!, Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Updated Summary',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildSummaryRow('Subtotal', '₹${widget.currentSubtotal.toStringAsFixed(2)}'),
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                    'New Delivery', 
                    '₹${(double.tryParse(_deliveryFeeController.text) ?? 0.0).toStringAsFixed(2)}',
                    isNew: true,
                  ),
                  const Divider(height: 16),
                  _buildSummaryRow(
                    'New Total', 
                    '₹${_newTotal.toStringAsFixed(2)}',
                    isTotal: true,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: Colors.grey[400]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _updateDeliveryFee,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Update Delivery Fee',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isTotal = false, bool isNew = false, bool isOld = false}) {
    Color labelColor = Colors.grey[600]!;
    Color valueColor = Colors.black87;
    FontWeight labelWeight = FontWeight.w500;
    FontWeight valueWeight = FontWeight.w600;
    
    if (isTotal) {
      labelColor = Colors.green[700]!;
      valueColor = Colors.green[800]!;
      labelWeight = FontWeight.w700;
      valueWeight = FontWeight.w800;
    } else if (isNew) {
      labelColor = Colors.blue[700]!;
      valueColor = Colors.blue[800]!;
      labelWeight = FontWeight.w600;
      valueWeight = FontWeight.w700;
    } else if (isOld) {
      labelColor = Colors.grey[500]!;
      valueColor = Colors.grey[600]!;
      labelWeight = FontWeight.w400;
      valueWeight = FontWeight.w500;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 15 : 13,
            color: labelColor,
            fontWeight: labelWeight,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 16 : 14,
            color: valueColor,
            fontWeight: valueWeight,
          ),
        ),
      ],
    );
  }
}
