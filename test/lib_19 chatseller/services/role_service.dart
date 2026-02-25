import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'local_auth_service.dart';

class RoleService {
  // Get all roles
  static Future<List<dynamic>> getAllRoles() async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/roles'),
        headers: {
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] && data['data'] != null) {
          return data['data'];
        }
      }
      return [];
    } catch (e) {
      print('Error getting all roles: $e');
      return [];
    }
  }

  // Get roles by user ID
  static Future<List<dynamic>> getRolesByUser(int userId) async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/roles/user/$userId'),
        headers: {
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] && data['data'] != null) {
          return data['data'];
        }
      }
      return [];
    } catch (e) {
      print('Error getting roles by user: $e');
      return [];
    }
  }

  // Get roles by website ID
  static Future<List<dynamic>> getRolesByWebsite(int websiteId) async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/roles/website/$websiteId'),
        headers: {
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] && data['data'] != null) {
          return data['data'];
        }
      }
      return [];
    } catch (e) {
      print('Error getting roles by website: $e');
      return [];
    }
  }

  // Assign new role
  static Future<bool> assignRole(Map<String, dynamic> roleData) async {
    try {
      final response = await http.post(
        Uri.parse('${Config.baseNodeApiUrl}/roles'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(roleData),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        return data['success'] ?? false;
      }
      return false;
    } catch (e) {
      print('Error assigning role: $e');
      return false;
    }
  }

  // Update role
  static Future<bool> updateRole(int roleId, Map<String, dynamic> updates) async {
    try {
      final response = await http.put(
        Uri.parse('${Config.baseNodeApiUrl}/roles/$roleId'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(updates),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] ?? false;
      }
      return false;
    } catch (e) {
      print('Error updating role: $e');
      return false;
    }
  }

  // Delete role
  static Future<bool> deleteRole(int roleId) async {
    try {
      final response = await http.delete(
        Uri.parse('${Config.baseNodeApiUrl}/roles/$roleId'),
        headers: {
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] ?? false;
      }
      return false;
    } catch (e) {
      print('Error deleting role: $e');
      return false;
    }
  }

  // Get all users
  static Future<List<dynamic>> getAllUsers() async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/roles/users/all'),
        headers: {
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] && data['data'] != null) {
          return data['data'];
        }
      }
      return [];
    } catch (e) {
      print('Error getting all users: $e');
      return [];
    }
  }

  // Get websites managed by admin
  static Future<List<dynamic>> getAdminWebsites(int adminUserId) async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseNodeApiUrl}/roles/websites/admin/$adminUserId'),
        headers: {
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] && data['data'] != null) {
          return data['data'];
        }
      }
      return [];
    } catch (e) {
      print('Error getting admin websites: $e');
      return [];
    }
  }
}
