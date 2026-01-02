import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';
import '../models/profile_setting.dart';
import 'package:whatsappchat/services/local_auth_service.dart';

class ApiService {
  // Updated Base URL
  static const baseUrl = "http://184.168.126.71/api";

  static final _authBox = Hive.box("authBox");

  /// ================= AUTH ================= ///

  /// Send OTP
  static Future<Map<String, dynamic>> sendOtp(String phone) async {
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/send_otp.php"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"phone": phone}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {"success": false, "message": "Server error: $e"};
    }
  }

  /// Verify OTP
  static Future<Map<String, dynamic>> verifyOtp(String phone, String otp) async {
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/verify_otp.php"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"phone": phone, "otp": otp}),
      );

      final data = jsonDecode(res.body);
      if (data["success"] == true) {
        // ✅ Use consistent key 'userId' (same as LocalAuthService)
        await _authBox.put("userId", data["user_id"]);
        await _authBox.put("user_id", data["user_id"]); // Keep both for compatibility
        await _authBox.put("phone", phone);
      }
      return data;
    } catch (e) {
      return {"success": false, "message": "Server error: $e"};
    }
  }

  /// Set MPIN
  static Future<Map<String, dynamic>> setMpin(String mpin) async {
    try {
      final userId = LocalAuthService.getUserId();
      final res = await http.post(
        Uri.parse("$baseUrl/set_mpin.php"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": userId, "mpin": mpin}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {"success": false, "message": "Server error: $e"};
    }
  }

  /// Verify MPIN
  static Future<Map<String, dynamic>> verifyMpin(String mpin) async {
    try {
      final userId = LocalAuthService.getUserId();
      final res = await http.post(
        Uri.parse("$baseUrl/verify_mpin.php"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": userId, "mpin": mpin}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {"success": false, "message": "Server error: $e"};
    }
  }

  static bool isLoggedIn() => LocalAuthService.isLoggedIn();
  static Future<void> logout() async => _authBox.clear();

  /// ================= PROFILE ================= ///

  /// Insert Profile
  static Future<Map<String, dynamic>> insertProfile(ProfileSetting profile) async {
    try {
      final userId = LocalAuthService.getUserId();
      final res = await http.post(
        Uri.parse("$baseUrl/insert_profile.php"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(profile.toJson()..["user_id"] = userId),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {"success": false, "message": "Server error: $e"};
    }
  }

  /// Update Profile
  static Future<Map<String, dynamic>> updateProfile(ProfileSetting profile) async {
    try {
      final userId = LocalAuthService.getUserId();
      final res = await http.post(
        Uri.parse("$baseUrl/update_profile.php"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(profile.toJson()
          ..["user_id"] = userId
          ..["id"] = profile.id),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {"success": false, "message": "Server error: $e"};
    }
  }

  /// Get Profile - Fetch from users table using get_user_by_id.php
  static Future<ProfileSetting?> getProfile() async {
    try {
      // ✅ Use LocalAuthService to get user ID (consistent with other services)
      final userId = LocalAuthService.getUserId();
      if (userId == null) {
        print("❌ User ID is null - User not logged in");
        return null;
      }
      
      // Use get_user_by_id.php (server API)
      final res = await http.get(
        Uri.parse("$baseUrl/get_user_by_id.php?user_id=$userId"),
      );
      
      if (res.statusCode != 200) {
        print("❌ API returned status: ${res.statusCode}");
        return null;
      }
      
      final data = jsonDecode(res.body);
      print("📥 API Response: $data");
      
      if (data["success"] == true && data["user"] != null) {
        final user = data["user"];
        print("✅ User data found - Name: ${user["name"]}, Address: ${user["address"]}");
        
        // Convert users table data to ProfileSetting format
        return ProfileSetting(
          userId: userId,
          name: user["name"] ?? "",
          address: user["address"] ?? "",
          profileImage: user["profile_photo_url"],
          userPhone: user["phone"] ?? "",
          userName: user["name"] ?? "",
        );
      } else {
        print("❌ API returned success=false or user is null");
        return null;
      }
    } catch (e) {
      print("❌ Error fetching profile: $e");
      return null;
    }
  }
}