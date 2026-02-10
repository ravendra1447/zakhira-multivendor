import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/role_service.dart';
import '../../services/local_auth_service.dart';
import '../../config.dart';

class RoleManagementScreen extends StatefulWidget {
  const RoleManagementScreen({super.key});

  @override
  State<RoleManagementScreen> createState() => _RoleManagementScreenState();
}

class _RoleManagementScreenState extends State<RoleManagementScreen> {
  bool isLoading = true;
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> websites = [];
  List<Map<String, dynamic>> allRoles = [];
  String? errorMessage;
  int? currentUserId;
  String searchQuery = '';
  String selectedFilter = 'all'; // all, admin, user, supplier, reseller, delivery, unassigned
  
  // Auto-refresh variables
  Timer? _refreshTimer;
  bool _isAutoRefreshEnabled = true;
  int _refreshInterval = 10; // seconds
  DateTime? _lastRefreshTime;
  bool _isRefreshing = false;

  final List<String> roleTypes = ['user', 'admin', 'supplier', 'reseller', 'delivery'];
  final List<String> platforms = ['WEB', 'APP', 'BOTH'];
  final List<String> statuses = ['active', 'inactive', 'suspended'];

  @override
  void initState() {
    super.initState();
    _loadCachedData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final cachedUsers = prefs.getString('role_mgmt_users');
      final cachedWebsites = prefs.getString('role_mgmt_websites');
      final cachedRoles = prefs.getString('role_mgmt_all_roles');

      if (cachedUsers != null && cachedWebsites != null && cachedRoles != null) {
        setState(() {
          users = List<Map<String, dynamic>>.from(json.decode(cachedUsers));
          websites = List<Map<String, dynamic>>.from(json.decode(cachedWebsites));
          allRoles = List<Map<String, dynamic>>.from(json.decode(cachedRoles));
          isLoading = false;
        });
      }
      
      // Always fetch fresh data
      _loadData(showLoading: isLoading);
    } catch (e) {
      print('Error loading cached data: $e');
      _loadData();
    }
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    }

    try {
      await Future.wait([
        _fetchUsers(),
        _fetchWebsites(),
        _fetchAllRoles(),
      ]);
      await _getCurrentUserId();
      setState(() {
        _lastRefreshTime = DateTime.now();
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load data: $e';
      });
    } finally {
      setState(() {
        isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  // Auto-refresh methods
  void _startAutoRefresh() {
    if (_isAutoRefreshEnabled) {
      _refreshTimer = Timer.periodic(Duration(seconds: _refreshInterval), (timer) {
        if (mounted && !_isRefreshing) {
          _refreshDataSilently();
        }
      });
    }
  }

  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
  }

  void _toggleAutoRefresh() {
    setState(() {
      _isAutoRefreshEnabled = !_isAutoRefreshEnabled;
    });
    
    if (_isAutoRefreshEnabled) {
      _startAutoRefresh();
    } else {
      _stopAutoRefresh();
    }
  }

  Future<void> _refreshDataSilently() async {
    setState(() {
      _isRefreshing = true;
    });
    
    try {
      await Future.wait([
        _fetchUsers(),
        _fetchWebsites(),
        _fetchAllRoles(),
      ]);
      setState(() {
        _lastRefreshTime = DateTime.now();
      });
    } catch (e) {
      print('Error during silent refresh: $e');
    } finally {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  Future<void> _manualRefresh() async {
    setState(() {
      _isRefreshing = true;
    });
    await _loadData(showLoading: false);
  }

  Future<void> _fetchUsers() async {
    try {
      final data = await RoleService.getAllUsers();
      if (mounted) {
        setState(() {
          users = List<Map<String, dynamic>>.from(data);
          isLoading = false;
        });
        
        // Cache data
        final prefs = await SharedPreferences.getInstance();
        prefs.setString('role_mgmt_users', json.encode(users));
      }
    } catch (e) {
      print('Error fetching users: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchAllRoles() async {
    try {
      final data = await RoleService.getAllRoles();
      if (mounted) {
        setState(() {
          allRoles = List<Map<String, dynamic>>.from(data);
        });
        
        // Cache data
        final prefs = await SharedPreferences.getInstance();
        prefs.setString('role_mgmt_all_roles', json.encode(allRoles));
      }
    } catch (e) {
      print('Error fetching all roles: $e');
    }
  }

  Future<void> _fetchWebsites() async {
    try {
      final data = await RoleService.getAdminWebsites(currentUserId ?? 0);
      if (mounted) {
        setState(() {
          websites = List<Map<String, dynamic>>.from(data);
        });
        
        // Cache data
        final prefs = await SharedPreferences.getInstance();
        prefs.setString('role_mgmt_websites', json.encode(websites));
      }
    } catch (e) {
      print('Error fetching websites: $e');
    }
  }

  Future<void> _autoAssignAdminRole() async {
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot assign role: User ID not found')),
      );
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('${Config.baseNodeApiUrl}/roles/auto-assign-admin'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'user_id': currentUserId}),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        if (result['success']) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']),
              backgroundColor: Colors.green,
            ),
          );
          // Refresh websites list
          await _fetchWebsites();
        } else {
          throw Exception(result['message']);
        }
      } else {
        throw Exception('Failed to auto-assign admin role');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _getCurrentUserId() async {
    try {
      final userId = LocalAuthService.getUserId();
      setState(() {
        currentUserId = userId;
      });
    } catch (e) {
      print('Error getting current user ID: $e');
    }
  }

  Future<void> _assignRole(Map<String, dynamic> roleData) async {
    try {
      setState(() {
        isLoading = true;
      });

      final success = await RoleService.assignRole(roleData);

      if (success) {
        await _loadData(showLoading: false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Role assigned successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        throw Exception('Failed to assign role');
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateRole(int roleId, Map<String, dynamic> updates) async {
    try {
      setState(() {
        isLoading = true;
      });

      final success = await RoleService.updateRole(roleId, updates);

      if (success) {
        await _loadData(showLoading: false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Role updated successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        throw Exception('Failed to update role');
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteRole(int roleId) async {
    try {
      setState(() {
        isLoading = true;
      });

      final success = await RoleService.deleteRole(roleId);

      if (success) {
        await _loadData(showLoading: false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Role deleted successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        throw Exception('Failed to delete role');
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAssignRoleDialog() {
    int? selectedUserId;
    int? selectedWebsiteId;
    String selectedRole = 'user';
    String selectedPlatform = 'BOTH';
    String selectedStatus = 'active';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Assign Role'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Select User',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedUserId,
                  items: users.map((user) {
                    return DropdownMenuItem<int>(
                      value: user['user_id'],
                      child: Text('${user['username'] ?? user['email'] ?? 'User ${user['user_id']}'}'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedUserId = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Select Website',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedWebsiteId,
                  items: websites.map((website) {
                    return DropdownMenuItem<int>(
                      value: website['website_id'],
                      child: Text('${website['website_name']}'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedWebsiteId = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Role Type',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedRole,
                  items: roleTypes.map((role) {
                    return DropdownMenuItem<String>(
                      value: role,
                      child: Text(role.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedRole = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Platform',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedPlatform,
                  items: platforms.map((platform) {
                    return DropdownMenuItem<String>(
                      value: platform,
                      child: Text(platform),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedPlatform = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedStatus,
                  items: statuses.map((status) {
                    return DropdownMenuItem<String>(
                      value: status,
                      child: Text(status.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedStatus = value!;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedUserId != null && selectedWebsiteId != null) {
                  Navigator.pop(context);
                  _assignRole({
                    'user_id': selectedUserId,
                    'website_id': selectedWebsiteId,
                    'role': selectedRole,
                    'platform': selectedPlatform,
                    'status': selectedStatus,
                    'assigned_by': currentUserId,
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditRoleDialog(Map<String, dynamic> role) {
    String selectedRole = role['role'] ?? 'user';
    String selectedPlatform = role['platform'] ?? 'BOTH';
    String selectedStatus = role['status'] ?? 'active';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Role'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('User'),
                  subtitle: Text('${role['username'] ?? role['email'] ?? 'User ${role['user_id']}'}'),
                ),
                ListTile(
                  title: const Text('Website'),
                  subtitle: Text('${role['website_name'] ?? role['domain'] ?? 'Website ${role['website_id']}'}'),
                ),
                const Divider(),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Role Type',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedRole,
                  items: roleTypes.map((r) {
                    return DropdownMenuItem<String>(
                      value: r,
                      child: Text(r.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedRole = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Platform',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedPlatform,
                  items: platforms.map((platform) {
                    return DropdownMenuItem<String>(
                      value: platform,
                      child: Text(platform),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedPlatform = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedStatus,
                  items: statuses.map((status) {
                    return DropdownMenuItem<String>(
                      value: status,
                      child: Text(status.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedStatus = value!;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _updateRole(role['role_id'], {
                  'role': selectedRole,
                  'platform': selectedPlatform,
                  'status': selectedStatus,
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, IconData icon) {
    final isSelected = selectedFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14),
            const SizedBox(width: 4),
            Text(label),
          ],
        ),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            selectedFilter = value;
          });
        },
        backgroundColor: Colors.white,
        selectedColor: _getFilterColor(value).withOpacity(0.2),
        labelStyle: TextStyle(
          color: isSelected ? _getFilterColor(value) : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        side: BorderSide(
          color: isSelected ? _getFilterColor(value) : Colors.grey[300]!,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Color _getFilterColor(String filter) {
    switch (filter) {
      case 'admin':
        return Colors.purple;
      case 'user':
        return Colors.blue;
      case 'supplier':
        return Colors.orange;
      case 'reseller':
        return Colors.green;
      case 'delivery':
        return Colors.red;
      case 'unassigned':
        return Colors.grey;
      default:
        return Colors.indigo;
    }
  }

  // Helper method to format time
  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  List<Map<String, dynamic>> get filteredUsers {
    List<Map<String, dynamic>> filtered = users;
    
    // Apply role filter
    if (selectedFilter != 'all') {
      if (selectedFilter == 'unassigned') {
        filtered = filtered.where((user) {
          return !allRoles.any((role) => role['user_id'] == user['user_id']);
        }).toList();
      } else {
        filtered = filtered.where((user) {
          return allRoles.any((role) => 
            role['user_id'] == user['user_id'] && 
            role['role'] == selectedFilter
          );
        }).toList();
      }
    }
    
    // Apply search filter
    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((user) {
        final name = user['username']?.toString().toLowerCase() ?? '';
        final email = user['email']?.toString().toLowerCase() ?? '';
        final phone = user['phone']?.toString().toLowerCase() ?? '';
        final query = searchQuery.toLowerCase();
        return name.contains(query) || email.contains(query) || phone.contains(query);
      }).toList();
    }
    
    return filtered;
  }

  void _showAssignRoleToUserDialog(Map<String, dynamic> user) {
    int? selectedWebsiteId;
    String selectedRole = 'user';
    String selectedPlatform = 'BOTH';
    String selectedStatus = 'active';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Assign Role to ${user['username'] ?? user['name'] ?? 'User'}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Select Website',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedWebsiteId,
                  items: websites.map((website) {
                    return DropdownMenuItem<int>(
                      value: website['website_id'],
                      child: Text('${website['website_name']}'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedWebsiteId = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Role Type',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedRole,
                  items: roleTypes.map((role) {
                    return DropdownMenuItem<String>(
                      value: role,
                      child: Text(role.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedRole = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Platform',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedPlatform,
                  items: platforms.map((platform) {
                    return DropdownMenuItem<String>(
                      value: platform,
                      child: Text(platform),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedPlatform = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedStatus,
                  items: statuses.map((status) {
                    return DropdownMenuItem<String>(
                      value: status,
                      child: Text(status.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedStatus = value!;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedWebsiteId != null) {
                  Navigator.pop(context);
                  _assignRole({
                    'user_id': user['user_id'],
                    'website_id': selectedWebsiteId,
                    'role': selectedRole,
                    'platform': selectedPlatform,
                    'status': selectedStatus,
                    'assigned_by': currentUserId,
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select a website first'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
  }

  void _showUserRolesDialog(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => UserRolesDialog(
        user: user,
        websites: websites,
        roleTypes: roleTypes,
        platforms: platforms,
        statuses: statuses,
        currentUserId: currentUserId,
        onAssignRole: _assignRole,
        onUpdateRole: _updateRole,
        onDeleteRole: _deleteRole,
      ),
    );
  }

  IconData _getRoleIcon(String? role) {
    switch (role?.toLowerCase()) {
      case 'admin':
        return Icons.admin_panel_settings;
      case 'supplier':
        return Icons.inventory;
      case 'reseller':
        return Icons.store;
      case 'delivery':
        return Icons.delivery_dining;
      default:
        return Icons.person;
    }
  }

  Color _getRoleColor(String? role) {
    switch (role?.toLowerCase()) {
      case 'admin':
        return Colors.purple;
      case 'supplier':
        return Colors.blue;
      case 'reseller':
        return Colors.orange;
      case 'delivery':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'inactive':
        return Colors.grey;
      case 'suspended':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Flexible(
              child: Text(
                'Role Management',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.black,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (_isAutoRefreshEnabled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.autorenew,
                      size: 14,
                      color: Colors.green[700],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Auto',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 2,
        centerTitle: true,
        iconTheme: const IconThemeData(
          color: Colors.black,
        ),
        actions: [
          // Auto-refresh toggle
          IconButton(
            icon: Icon(
              _isAutoRefreshEnabled ? Icons.autorenew : Icons.autorenew_outlined,
              color: _isAutoRefreshEnabled ? Colors.green : Colors.grey,
            ),
            onPressed: _toggleAutoRefresh,
            tooltip: _isAutoRefreshEnabled ? 'Disable Auto-refresh' : 'Enable Auto-refresh',
          ),
          // Manual refresh
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.blue),
              onPressed: _manualRefresh,
              tooltip: 'Refresh',
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text(
                        errorMessage!,
                        style: TextStyle(color: Colors.red[700]),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    if (websites.isEmpty)
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.warning_amber, color: Colors.orange),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'You don\'t have any websites assigned. Please contact super admin to assign websites to you first.',
                                    style: TextStyle(color: Colors.orange[800]),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: _autoAssignAdminRole,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Auto-Assign Admin Role (Testing)'),
                            ),
                          ],
                        ),
                      ),
                    // Filter Chips with improved design
                    Container(
                      height: 70,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Filters',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (_lastRefreshTime != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Updated: ${_formatTime(_lastRefreshTime!)}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.blue[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                _buildFilterChip('All', 'all', Icons.people),
                                _buildFilterChip('Admin', 'admin', Icons.admin_panel_settings),
                                _buildFilterChip('User', 'user', Icons.person),
                                _buildFilterChip('Supplier', 'supplier', Icons.inventory),
                                _buildFilterChip('Reseller', 'reseller', Icons.store),
                                _buildFilterChip('Delivery', 'delivery', Icons.delivery_dining),
                                _buildFilterChip('Unassigned', 'unassigned', Icons.person_off),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Enhanced Search Bar
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: TextField(
                          onChanged: (value) {
                            setState(() {
                              searchQuery = value;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search users by name, email, or phone...',
                            prefixIcon: Container(
                              padding: const EdgeInsets.all(10),
                              child: Icon(Icons.search, color: Colors.grey[600], size: 20),
                            ),
                            suffixIcon: searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.clear, color: Colors.grey[600], size: 20),
                                    onPressed: () {
                                      setState(() {
                                        searchQuery = '';
                                      });
                                    },
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  )
                                : Container(
                                    padding: const EdgeInsets.all(10),
                                    child: Icon(Icons.filter_list, color: Colors.grey[400], size: 20),
                                  ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            isDense: true,
                          ),
                        ),
                      ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _manualRefresh,
                        color: Colors.blue,
                        backgroundColor: Colors.white,
                        displacement: 40,
                        child: users.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(24),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(50),
                                      ),
                                      child: Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
                                    ),
                                    const SizedBox(height: 20),
                                    Text(
                                      'No users found',
                                      style: TextStyle(
                                        fontSize: 20,
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Try adjusting your filters or search query',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: filteredUsers.length,
                                itemBuilder: (context, index) {
                                  final user = filteredUsers[index];
                                  final userRoles = allRoles.where((role) => role['user_id'] == user['user_id']).toList();
                                  final hasRoles = userRoles.isNotEmpty;
                                  
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 10,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                      border: Border.all(
                                        color: hasRoles 
                                            ? _getRoleColor(userRoles.first['role']).withOpacity(0.2)
                                            : Colors.grey.withOpacity(0.1),
                                        width: 1,
                                      ),
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () {
                                          if (hasRoles) {
                                            _showUserRolesDialog(user);
                                          } else {
                                            _showAssignRoleToUserDialog(user);
                                          }
                                        },
                                        splashColor: _getRoleColor(userRoles.isNotEmpty ? userRoles.first['role'] : null).withOpacity(0.1),
                                        highlightColor: _getRoleColor(userRoles.isNotEmpty ? userRoles.first['role'] : null).withOpacity(0.05),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
    Hero(
      tag: 'user_${user['user_id'] ?? "unknown_$index"}',
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: hasRoles 
              ? _getRoleColor(userRoles.first['role']).withOpacity(0.15)
              : Colors.grey.withOpacity(0.15),
          shape: BoxShape.circle,
          border: Border.all(
            color: hasRoles 
                ? _getRoleColor(userRoles.first['role']).withOpacity(0.3)
                : Colors.grey.withOpacity(0.3),
            width: 2,
          ),
          image: user['profile_image'] != null && user['profile_image'].toString().isNotEmpty
              ? DecorationImage(
                  image: CachedNetworkImageProvider(
                    user['profile_image'].toString().startsWith('http') 
                        ? user['profile_image'] 
                        : 'https://bangkokmart.in${user['profile_image']}',
                  ),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: user['profile_image'] != null && user['profile_image'].toString().isNotEmpty
            ? null
            : Icon(
                hasRoles ? _getRoleIcon(userRoles.first['role']) : Icons.person_outline,
                color: hasRoles ? _getRoleColor(userRoles.first['role']) : Colors.grey[600],
                size: 24,
              ),
      ),
    ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          user['username'] ?? user['name'] ?? 'User ${user['user_id']}',
                                                          style: const TextStyle(
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 16,
                                                            color: Colors.black87,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 2),
                                                        if (user['email'] != null)
                                                          Text(
                                                            user['email'],
                                                            style: TextStyle(
                                                              color: Colors.grey[600],
                                                              fontSize: 13,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  Column(
                                                    crossAxisAlignment: CrossAxisAlignment.end,
                                                    children: [
                                                      if (hasRoles)
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                          decoration: BoxDecoration(
                                                            color: _getRoleColor(userRoles.first['role']).withOpacity(0.15),
                                                            borderRadius: BorderRadius.circular(16),
                                                            border: Border.all(
                                                              color: _getRoleColor(userRoles.first['role']).withOpacity(0.3),
                                                              width: 1,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            userRoles.first['role']?.toUpperCase() ?? 'USER',
                                                            style: TextStyle(
                                                              color: _getRoleColor(userRoles.first['role']),
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        )
                                                      else
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                          decoration: BoxDecoration(
                                                            color: Colors.grey.withOpacity(0.15),
                                                            borderRadius: BorderRadius.circular(16),
                                                            border: Border.all(
                                                              color: Colors.grey.withOpacity(0.3),
                                                              width: 1,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            'UNASSIGNED',
                                                            style: TextStyle(
                                                              color: Colors.grey[600]!,
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        ),
                                                      const SizedBox(height: 8),
                                                      Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Container(
                                                            width: 32,
                                                            height: 32,
                                                            decoration: BoxDecoration(
                                                              color: Colors.purple.withOpacity(0.15),
                                                              borderRadius: BorderRadius.circular(10),
                                                              border: Border.all(
                                                                color: Colors.purple.withOpacity(0.3),
                                                                width: 1,
                                                              ),
                                                            ),
                                                            child: IconButton(
                                                              icon: Icon(Icons.add_circle, color: Colors.purple, size: 18),
                                                              onPressed: () => _showAssignRoleToUserDialog(user),
                                                              padding: EdgeInsets.zero,
                                                              tooltip: 'Assign Role',
                                                            ),
                                                          ),
                                                          const SizedBox(width: 8),
                                                          Container(
                                                            width: 32,
                                                            height: 32,
                                                            decoration: BoxDecoration(
                                                              color: Colors.blue.withOpacity(0.15),
                                                              borderRadius: BorderRadius.circular(10),
                                                              border: Border.all(
                                                                color: Colors.blue.withOpacity(0.3),
                                                                width: 1,
                                                              ),
                                                            ),
                                                            child: IconButton(
                                                              icon: Icon(Icons.visibility, color: Colors.blue, size: 18),
                                                              onPressed: () => _showUserRolesDialog(user),
                                                              padding: EdgeInsets.zero,
                                                              tooltip: 'View Details',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              if (userRoles.length > 1)
                                                Container(
                                                  margin: const EdgeInsets.only(top: 8),
                                                  child: Wrap(
                                                    spacing: 4,
                                                    runSpacing: 4,
                                                    children: userRoles.skip(1).map((role) {
                                                      return Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: _getRoleColor(role['role']).withOpacity(0.15),
                                                          borderRadius: BorderRadius.circular(10),
                                                          border: Border.all(
                                                            color: _getRoleColor(role['role']).withOpacity(0.3),
                                                            width: 1,
                                                          ),
                                                        ),
                                                        child: Text(
                                                          '+${role['role']?.toUpperCase()}',
                                                          style: TextStyle(
                                                            color: _getRoleColor(role['role']),
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      );
                                                    }).toList(),
                                                  ),
                                                ),
                                              if (user['phone'] != null)
                                                Container(
                                                  margin: const EdgeInsets.only(top: 8),
                                                  child: Row(
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.all(4),
                                                        decoration: BoxDecoration(
                                                          color: Colors.green.withOpacity(0.1),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Icon(Icons.phone, size: 14, color: Colors.green[700]),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        user['phone'],
                                                        style: TextStyle(
                                                          color: Colors.grey[700],
                                                          fontSize: 12,
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
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

// User Roles Dialog Widget
class UserRolesDialog extends StatefulWidget {
  final Map<String, dynamic> user;
  final List<Map<String, dynamic>> websites;
  final List<String> roleTypes;
  final List<String> platforms;
  final List<String> statuses;
  final int? currentUserId;
  final Function(Map<String, dynamic>) onAssignRole;
  final Function(int, Map<String, dynamic>) onUpdateRole;
  final Function(int) onDeleteRole;

  const UserRolesDialog({
    super.key,
    required this.user,
    required this.websites,
    required this.roleTypes,
    required this.platforms,
    required this.statuses,
    required this.currentUserId,
    required this.onAssignRole,
    required this.onUpdateRole,
    required this.onDeleteRole,
  });

  @override
  State<UserRolesDialog> createState() => _UserRolesDialogState();
}

class _UserRolesDialogState extends State<UserRolesDialog> {
  List<Map<String, dynamic>> userRoles = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.user['roles'] != null) {
      userRoles = (widget.user['roles'] as List<dynamic>).cast<Map<String, dynamic>>();
      isLoading = false;
    }
    _fetchUserRoles();
  }

  Future<void> _fetchUserRoles() async {
    try {
      final data = await RoleService.getRolesByUser(widget.user['user_id']);
      if (mounted) {
        setState(() {
          userRoles = List<Map<String, dynamic>>.from(data);
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching user roles: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Color _getRoleColor(String? role) {
    switch (role?.toLowerCase()) {
      case 'admin':
        return Colors.purple;
      case 'supplier':
        return Colors.blue;
      case 'reseller':
        return Colors.orange;
      case 'delivery':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'inactive':
        return Colors.grey;
      case 'suspended':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  void _showAddRoleDialog() {
    int? selectedWebsiteId;
    String selectedRole = 'user';
    String selectedPlatform = 'BOTH';
    String selectedStatus = 'active';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Assign New Role'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Select Website',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedWebsiteId,
                  items: widget.websites.isEmpty
                    ? [DropdownMenuItem<int>(value: null, child: Text('No websites available'))]
                    : widget.websites.map((website) {
                        return DropdownMenuItem<int>(
                          value: website['website_id'],
                          child: Text('${website['website_name']}'),
                        );
                      }).toList(),
                  onChanged: widget.websites.isEmpty ? null : (value) {
                    setDialogState(() {
                      selectedWebsiteId = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Role Type',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedRole,
                  items: widget.roleTypes.map((role) {
                    return DropdownMenuItem<String>(
                      value: role,
                      child: Text(role.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedRole = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Platform',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedPlatform,
                  items: widget.platforms.map((platform) {
                    return DropdownMenuItem<String>(
                      value: platform,
                      child: Text(platform),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedPlatform = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedStatus,
                  items: widget.statuses.map((status) {
                    return DropdownMenuItem<String>(
                      value: status,
                      child: Text(status.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedStatus = value!;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedWebsiteId != null) {
                  Navigator.pop(context);
                  widget.onAssignRole({
                    'user_id': widget.user['user_id'],
                    'website_id': selectedWebsiteId,
                    'role': selectedRole,
                    'platform': selectedPlatform,
                    'status': selectedStatus,
                    'assigned_by': widget.currentUserId,
                  });
                  // Small delay to allow the parent to refresh
                  Future.delayed(const Duration(milliseconds: 500), () {
                    _fetchUserRoles();
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select a website first'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditRoleDialog(Map<String, dynamic> role) {
    String selectedRole = role['role'] ?? 'user';
    String selectedPlatform = role['platform'] ?? 'BOTH';
    String selectedStatus = role['status'] ?? 'active';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Role'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Website'),
                  subtitle: Text('${role['website_name'] ?? role['domain'] ?? 'Website ${role['website_id']}'}'),
                ),
                const Divider(),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Role Type',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedRole,
                  items: widget.roleTypes.map((r) {
                    return DropdownMenuItem<String>(
                      value: r,
                      child: Text(r.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedRole = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Platform',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedPlatform,
                  items: widget.platforms.map((platform) {
                    return DropdownMenuItem<String>(
                      value: platform,
                      child: Text(platform),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedPlatform = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedStatus,
                  items: widget.statuses.map((status) {
                    return DropdownMenuItem<String>(
                      value: status,
                      child: Text(status.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedStatus = value!;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                widget.onUpdateRole(role['role_id'], {
                  'role': selectedRole,
                  'platform': selectedPlatform,
                  'status': selectedStatus,
                });
                // Small delay to allow the parent to refresh
                Future.delayed(const Duration(milliseconds: 500), () {
                  _fetchUserRoles();
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.user['username'] ?? widget.user['name'] ?? 'User'} - Roles'),
      content: SizedBox(
        width: double.maxFinite,
        child: isLoading
            ? const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              )
            : userRoles.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.assignment_ind, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No roles assigned',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: userRoles.length,
                    itemBuilder: (context, index) {
                      final role = userRoles[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            role['website_name'] ?? role['domain'] ?? 'Website ${role['website_id']}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _getRoleColor(role['role']).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  (role['role'] ?? 'USER').toUpperCase(),
                                  style: TextStyle(
                                    color: _getRoleColor(role['role']),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(role['status']).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  (role['status'] ?? 'ACTIVE').toUpperCase(),
                                  style: TextStyle(
                                    color: _getStatusColor(role['status']),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') {
                                _showEditRoleDialog(role);
                              } else if (value == 'delete') {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Delete Role'),
                                    content: const Text('Are you sure you want to delete this role?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          widget.onDeleteRole(role['role_id']);
                                          // Small delay to allow the parent to refresh
                                          Future.delayed(const Duration(milliseconds: 500), () {
                                            _fetchUserRoles();
                                          });
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit, color: Colors.blue),
                                    SizedBox(width: 8),
                                    Text('Edit'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('Delete'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        ElevatedButton(
          onPressed: _showAddRoleDialog,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple,
            foregroundColor: Colors.white,
          ),
          child: const Text('Add Role'),
        ),
      ],
    );
  }
}
