import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../config.dart';

class ShippingManagementScreen extends StatefulWidget {
  const ShippingManagementScreen({super.key});

  @override
  State<ShippingManagementScreen> createState() => _ShippingManagementScreenState();
}

class _ShippingManagementScreenState extends State<ShippingManagementScreen> {
  List<dynamic> shippingRates = [];
  List<dynamic> products = [];
  List<dynamic> users = [];
  bool isLoading = false;
  bool isCreating = false;

  @override
  void initState() {
    super.initState();
    _fetchShippingRates();
    _fetchProductsAndUsers();
  }

  Future<void> _fetchShippingRates() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/api/shipping/all-rates-with-details'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            shippingRates = data['rates'];
          });
        }
      }
    } catch (e) {
      print('Error fetching shipping rates: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _fetchProductsAndUsers() async {
    try {
      final productsResponse = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/api/shipping/products-list'),
      );
      final usersResponse = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/api/shipping/users-list'),
      );
      
      if (productsResponse.statusCode == 200) {
        final data = json.decode(productsResponse.body);
        if (data['success']) {
          setState(() => products = data['products']);
        }
      }
      
      if (usersResponse.statusCode == 200) {
        final data = json.decode(usersResponse.body);
        if (data['success']) {
          setState(() => users = data['users']);
        }
      }
    } catch (e) {
      print('Error fetching products/users: $e');
    }
  }

  void _showCreateEditDialog({dynamic rate}) {
    showDialog(
      context: context,
      builder: (context) => ShippingRateDialog(
        rate: rate,
        products: products,
        users: users,
        onSave: () {
          _fetchShippingRates();
        },
      ),
    );
  }

  Future<void> _deleteRate(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Shipping Rate'),
        content: const Text('Are you sure you want to delete this shipping rate?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final response = await http.delete(
          Uri.parse('${Config.baseNodeApiUrl}/api/shipping/delete-rate/$id'),
        );
        
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Shipping rate deleted successfully')),
          );
          _fetchShippingRates();
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting rate: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shipping Rates Management'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchShippingRates,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: shippingRates.length,
                itemBuilder: (context, index) {
                  final rate = shippingRates[index];
                  return ShippingRateCard(
                    rate: rate,
                    onEdit: () => _showCreateEditDialog(rate: rate),
                    onDelete: () => _deleteRate(rate['id']),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateEditDialog(),
        backgroundColor: Colors.blue[600],
        child: const Icon(Icons.add),
      ),
    );
  }
}

class ShippingRateCard extends StatelessWidget {
  final dynamic rate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const ShippingRateCard({
    super.key,
    required this.rate,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rate['name'] ?? 'Unnamed Rate',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (rate['description'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          rate['description'],
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Row(
                  children: [
                    Chip(
                      label: Text(
                        '₹${rate['rate'] ?? '0'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      backgroundColor: Colors.green[600],
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit, color: Colors.blue),
                    ),
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete, color: Colors.red),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDetailRow('Rate Type', rate['rate_type'] ?? 'fixed'),
            if (rate['product_name'] != null)
              _buildDetailRow('Product', rate['product_name']),
            if (rate['user_name'] != null)
              _buildDetailRow('User', '${rate['user_name']} (${rate['user_email']})'),
            if (rate['min_order_amount'] != null && rate['min_order_amount'] > 0)
              _buildDetailRow('Min Order Amount', '₹${rate['min_order_amount']}'),
            if (rate['max_order_amount'] != null)
              _buildDetailRow('Max Order Amount', '₹${rate['max_order_amount']}'),
            if (rate['city'] != null || rate['state'] != null || rate['pincode'] != null)
              _buildDetailRow('Location', '${rate['city'] ?? ''}, ${rate['state'] ?? ''} ${rate['pincode'] ?? ''}'),
            Row(
              children: [
                Icon(
                  rate['is_active'] == true ? Icons.check_circle : Icons.cancel,
                  color: rate['is_active'] == true ? Colors.green : Colors.red,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  rate['is_active'] == true ? 'Active' : 'Inactive',
                  style: TextStyle(
                    color: rate['is_active'] == true ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ShippingRateDialog extends StatefulWidget {
  final dynamic rate;
  final List<dynamic> products;
  final List<dynamic> users;
  final VoidCallback onSave;

  const ShippingRateDialog({
    super.key,
    this.rate,
    required this.products,
    required this.users,
    required this.onSave,
  });

  @override
  State<ShippingRateDialog> createState() => _ShippingRateDialogState();
}

class _ShippingRateDialogState extends State<ShippingRateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _rateController = TextEditingController();
  final _minOrderController = TextEditingController();
  final _maxOrderController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pincodeController = TextEditingController();

  String _rateType = 'fixed';
  int? _selectedProductId;
  int? _selectedUserId;
  String _userType = 'all';
  bool _isActive = true;
  int _priority = 0;

  @override
  void initState() {
    super.initState();
    if (widget.rate != null) {
      _nameController.text = widget.rate['name'] ?? '';
      _descriptionController.text = widget.rate['description'] ?? '';
      _rateController.text = widget.rate['rate']?.toString() ?? '';
      _rateType = widget.rate['rate_type'] ?? 'fixed';
      _selectedProductId = widget.rate['product_id'];
      _selectedUserId = widget.rate['user_id'];
      _userType = widget.rate['user_type'] ?? 'all';
      _minOrderController.text = widget.rate['min_order_amount']?.toString() ?? '';
      _maxOrderController.text = widget.rate['max_order_amount']?.toString() ?? '';
      _cityController.text = widget.rate['city'] ?? '';
      _stateController.text = widget.rate['state'] ?? '';
      _pincodeController.text = widget.rate['pincode'] ?? '';
      _isActive = widget.rate['is_active'] ?? true;
      _priority = widget.rate['priority'] ?? 0;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _rateController.dispose();
    _minOrderController.dispose();
    _maxOrderController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  Future<void> _saveRate() async {
    if (!_formKey.currentState!.validate()) return;

    final rateData = {
      'name': _nameController.text,
      'description': _descriptionController.text,
      'rate': double.tryParse(_rateController.text) ?? 0.0,
      'rate_type': _rateType,
      'product_id': _selectedProductId,
      'user_id': _selectedUserId,
      'user_type': _userType,
      'min_order_amount': _minOrderController.text.isNotEmpty ? double.tryParse(_minOrderController.text) : 0.0,
      'max_order_amount': _maxOrderController.text.isNotEmpty ? double.tryParse(_maxOrderController.text) : null,
      'city': _cityController.text.isNotEmpty ? _cityController.text : null,
      'state': _stateController.text.isNotEmpty ? _stateController.text : null,
      'pincode': _pincodeController.text.isNotEmpty ? _pincodeController.text : null,
      'priority': _priority,
      'is_active': _isActive,
    };

    try {
      final url = widget.rate != null
          ? '${Config.baseNodeApiUrl}/api/shipping/update-rate/${widget.rate['id']}'
          : '${Config.baseNodeApiUrl}/api/shipping/create-rate';
      
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(rateData),
      );

      if (response.statusCode == 200) {
        Navigator.pop(context);
        widget.onSave();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.rate != null ? 'Rate updated successfully' : 'Rate created successfully'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.9,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              widget.rate != null ? 'Edit Shipping Rate' : 'Create Shipping Rate',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Rate Name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value?.isEmpty == true ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _rateController,
                        decoration: const InputDecoration(
                          labelText: 'Rate (₹)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) => value?.isEmpty == true ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _rateType,
                        decoration: const InputDecoration(
                          labelText: 'Rate Type',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'fixed', child: Text('Fixed Amount')),
                          DropdownMenuItem(value: 'percentage', child: Text('Percentage')),
                        ],
                        onChanged: (value) => setState(() => _rateType = value!),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        value: _selectedProductId,
                        decoration: const InputDecoration(
                          labelText: 'Product (Optional)',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All Products')),
                          ...widget.products.map((product) => DropdownMenuItem(
                            value: product['id'],
                            child: Text(product['name']),
                          )),
                        ],
                        onChanged: (value) => setState(() => _selectedProductId = value),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        value: _selectedUserId,
                        decoration: const InputDecoration(
                          labelText: 'User (Optional)',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All Users')),
                          ...widget.users.map((user) => DropdownMenuItem(
                            value: user['id'],
                            child: Text(user['name']),
                          )),
                        ],
                        onChanged: (value) => setState(() => _selectedUserId = value),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _minOrderController,
                              decoration: const InputDecoration(
                                labelText: 'Min Order Amount',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _maxOrderController,
                              decoration: const InputDecoration(
                                labelText: 'Max Order Amount',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _cityController,
                              decoration: const InputDecoration(
                                labelText: 'City',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _stateController,
                              decoration: const InputDecoration(
                                labelText: 'State',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _pincodeController,
                        decoration: const InputDecoration(
                          labelText: 'Pincode',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Checkbox(
                            value: _isActive,
                            onChanged: (value) => setState(() => _isActive = value!),
                          ),
                          const Text('Active'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _saveRate,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
