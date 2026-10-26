import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _storageKey = 'smartbus_registered_users_v2';
  static const _sessionKey = 'smartbus_current_user_session_v2';

  Future<Map<String, dynamic>> _loadUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error loading users: $e');
      return {};
    }
  }

  Future<void> _saveUsers(Map<String, dynamic> users) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(users));
  }

  /// Returns the currently logged in user or null if not logged in.
  Future<Map<String, dynamic>?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final username = _usernameFrom(data);
        if (username != null && data['username'] != username) {
          data['username'] = username;
          data['name'] ??= username;
          await prefs.setString(_sessionKey, jsonEncode(data));
        }
        return data;
      } catch (e) {
        debugPrint('Error loading current user session: $e');
      }
    }
    return null;
  }

  String? _usernameFrom(Map<String, dynamic> user) {
    for (final key in const ['username', 'name', 'full_name']) {
      final value = user[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  /// Sets the currently active session user.
  Future<void> _setCurrentUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode(user));
  }

  /// Registers a new user. Returns an error message, or null on success.
  Future<String?> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    final users = await _loadUsers();
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedPhone = phone.trim();

    if (users.containsKey(normalizedEmail)) {
      return 'An account with this email already exists';
    }

    final phoneTaken = users.values.any(
      (u) => (u as Map<String, dynamic>)['phone'] == normalizedPhone,
    );
    if (phoneTaken) {
      return 'An account with this phone number already exists';
    }

    final userId = (DateTime.now().millisecondsSinceEpoch % 100000) + 1;

    final userData = {
      'id': userId,
      'username': name.trim(),
      'name': name.trim(),
      'email': normalizedEmail,
      'phone': normalizedPhone,
      'password': password.trim(),
    };

    users[normalizedEmail] = userData;
    await _saveUsers(users);

    // Also auto-save as the active user session so profile has data immediately
    await _setCurrentUser(userData);

    // Sync with backend API in background if server is running
    ApiService.registerUser(
      fullName: name.trim(),
      email: normalizedEmail,
      phoneNumber: normalizedPhone,
      passwordHash: password.trim(),
    ).catchError((e) {
      debugPrint('Backend register fallback: $e');
      return {'success': false};
    });

    return null;
  }

  /// Logs in using either the email or the phone number as the identifier.
  /// Returns an error message, or null on success.
  Future<String?> login({
    required String identifier,
    required String password,
  }) async {
    final users = await _loadUsers();
    final normalizedIdentifier = identifier.trim().toLowerCase();
    final normalizedPassword = password.trim();

    Map<String, dynamic>? matchedUser;

    if (users.containsKey(normalizedIdentifier)) {
      matchedUser = users[normalizedIdentifier] as Map<String, dynamic>;
    } else {
      for (final value in users.values) {
        final user = value as Map<String, dynamic>;
        if (user['phone'] == identifier.trim() ||
            user['email']?.toString().toLowerCase() == normalizedIdentifier) {
          matchedUser = user;
          break;
        }
      }
    }

    // Try backend if not found locally or verify credentials
    if (matchedUser == null) {
      try {
        final apiResult = await ApiService.loginUser(
          email: identifier.trim(),
          passwordHash: normalizedPassword,
        );
        if (apiResult['success'] == true && apiResult['user'] != null) {
          final backendUser = apiResult['user'] as Map<String, dynamic>;
          final backendUsername = _usernameFrom(backendUser);
          matchedUser = {
            'id':
                backendUser['id'] ??
                (DateTime.now().millisecondsSinceEpoch % 100000),
            'username': backendUsername ?? identifier.trim(),
            'name': backendUsername ?? identifier.trim(),
            'email': backendUser['email'] ?? normalizedIdentifier,
            'phone': backendUser['phone_number'] ?? backendUser['phone'] ?? '',
            'password': normalizedPassword,
          };
          final emailKey =
              matchedUser['email']?.toString() ?? normalizedIdentifier;
          users[emailKey] = matchedUser;
          await _saveUsers(users);
        }
      } catch (_) {}
    }

    if (matchedUser == null || matchedUser['password'] != normalizedPassword) {
      // If no users registered at all, allow creating guest/demo user for smooth testing
      if (users.isEmpty) {
        final emailKey = normalizedIdentifier.contains('@')
            ? normalizedIdentifier
            : 'user@smartbus.com';
        final demoUsername = normalizedIdentifier.contains('@')
            ? normalizedIdentifier.split('@').first
            : identifier.trim();
        final demoUser = {
          'id': 1,
          'username': demoUsername,
          'name': demoUsername,
          'email': emailKey,
          'phone': normalizedIdentifier.contains('@')
              ? '9876543210'
              : identifier.trim(),
          'password': normalizedPassword,
        };
        users[emailKey] = demoUser;
        await _saveUsers(users);
        await _setCurrentUser(demoUser);
        return null;
      }
      return 'Email/phone and password do not match';
    }

    final username = _usernameFrom(matchedUser);
    if (username != null) {
      matchedUser['username'] = username;
      matchedUser['name'] = username;
    }

    // Save session
    await _setCurrentUser(matchedUser);
    return null;
  }

  /// Updates profile details for currently logged in user.
  Future<bool> updateProfile({
    required String name,
    required String email,
    required String phone,
  }) async {
    final current = await getCurrentUser();
    final users = await _loadUsers();
    final oldEmail = current?['email']?.toString().toLowerCase() ?? '';
    final newEmail = email.trim().toLowerCase();

    final updatedUser = {
      'id': current?['id'] ?? 1,
      'username': name.trim(),
      'name': name.trim(),
      'email': newEmail,
      'phone': phone.trim(),
      'password': current?['password'] ?? '',
    };

    if (oldEmail.isNotEmpty && oldEmail != newEmail) {
      users.remove(oldEmail);
    }
    users[newEmail] = updatedUser;

    await _saveUsers(users);
    await _setCurrentUser(updatedUser);
    return true;
  }

  /// Change password for current logged in user.
  Future<String?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
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
    await _setCurrentUser(current);
    return null;
  }

  /// Returns true if an account exists for this email.
  Future<bool> accountExists(String email) async {
    final users = await _loadUsers();
    return users.containsKey(email.trim().toLowerCase());
  }

  /// Resets the password for the account matching this email.
  Future<String?> resetPassword({
    required String identifier,
    required String newPassword,
  }) async {
    final users = await _loadUsers();
    final input = identifier.trim();
    String? matchedEmail;

    if (input.contains('@')) {
      final normalizedEmail = input.toLowerCase();
      if (users.containsKey(normalizedEmail)) {
        matchedEmail = normalizedEmail;
      }
    } else {
      final normalizedPhone = input.replaceAll(RegExp(r'\D'), '');
      for (final entry in users.entries) {
        final user = entry.value as Map<String, dynamic>;
        final phone = user['phone']?.toString().replaceAll(RegExp(r'\D'), '');
        if (phone == normalizedPhone) {
          matchedEmail = entry.key;
          break;
        }
      }
    }

    if (matchedEmail == null) {
      return 'No registered account found with this email or phone number';
    }

    final user = users[matchedEmail] as Map<String, dynamic>;
    user['password'] = newPassword.trim();
    users[matchedEmail] = user;
    await _saveUsers(users);

    final current = await getCurrentUser();
    if (current != null &&
        current['email']?.toString().toLowerCase() == matchedEmail) {
      current['password'] = newPassword.trim();
      await _setCurrentUser(current);
    }

    return null;
  }

  /// Logs out current user session.
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }
}
