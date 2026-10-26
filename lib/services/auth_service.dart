import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// AuthService handles user session management, registration data persistence,
/// profile updates, password changes, and logout functionality.
class AuthService {
  AuthService._privateConstructor();
  static final AuthService instance = AuthService._privateConstructor();

  // Keys used for SharedPreferences storage.
  static const String _sessionKey = 'smartbus_current_user_session_v2';
  static const String _storageKey = 'smartbus_registered_users_v2';

  // Private helper methods for user storage.
  Future<Map<String, dynamic>> _loadUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveUsers(Map<String, dynamic> users) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(users));
  }

  // Public API.
  Future<Map<String, dynamic>?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_sessionKey);
    if (jsonString == null) return null;
    try {
      return json.decode(jsonString) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> setCurrentUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, json.encode(user));
  }

  Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  Future<bool> updateProfile({required String name, required String email, required String phone}) async {
    final current = await getCurrentUser();
    if (current == null) return false;
    final users = await _loadUsers();
    final oldEmail = current['email']?.toString().toLowerCase() ?? '';
    final newEmail = email.trim().toLowerCase();
    final updated = {
      'id': current['id'] ?? 1,
      'username': name.trim(),
      'name': name.trim(),
      'email': newEmail,
      'phone': phone.trim(),
      'password': current['password'] ?? '',
    };
    if (oldEmail.isNotEmpty && oldEmail != newEmail) {
      users.remove(oldEmail);
    }
    users[newEmail] = updated;
    await _saveUsers(users);
    await setCurrentUser(updated);
    return true;
  }

  Future<String?> changePassword({required String currentPassword, required String newPassword}) async {
    final current = await getCurrentUser();
    if (current == null) return 'No active user found';
    if (current['password'] != null &&
        current['password'].toString().isNotEmpty &&
        current['password'] != currentPassword.trim()) {
      return 'Current password does not match';
    }
    final users = await _loadUsers();
    final email = current['email']?.toString().toLowerCase() ?? '';
    current['password'] = newPassword.trim();
    if (email.isNotEmpty && users.containsKey(email)) {
      users[email] = current;
      await _saveUsers(users);
    }
    await setCurrentUser(current);
    return null;
  }

  Future<void> logout() async => await clearUser();
}
