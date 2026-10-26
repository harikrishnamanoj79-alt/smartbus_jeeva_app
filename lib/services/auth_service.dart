import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_service.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _storageKey = 'smartbus_registered_users_v2';
  static const _sessionKey = 'smartbus_current_user_session_v2';
  static const _passwordIterations = 10000;
  static const _secureStorage = FlutterSecureStorage();
  
  static const _jwtKey = 'smartbus_jwt_token';

  Future<void> _saveJwt(String token) async {
    await _secureStorage.write(key: _jwtKey, value: token);
    ApiService.setJwtToken(token);
  }

  Future<void> _clearJwt() async {
    await _secureStorage.delete(key: _jwtKey);
    ApiService.setJwtToken(null);
  }

  Future<void> _loadJwt() async {
    final token = await _secureStorage.read(key: _jwtKey);
    ApiService.setJwtToken(token);
  }

  Future<Map<String, dynamic>> _loadUsers() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (error) {
      debugPrint('Unable to read locally registered users: $error');
      return {};
    }
  }

  Future<void> _saveUsers(Map<String, dynamic> users) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(users));
  }

  Map<String, dynamic> _passwordFields(String password) {
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    return {
      'password_salt': base64Encode(salt),
      'password_hash': _derivePasswordHash(password, salt, _passwordIterations),
      'password_iterations': _passwordIterations,
    };
  }

  String _derivePasswordHash(String password, List<int> salt, int iterations) {
    final key = utf8.encode(password);
    final hmac = Hmac(sha256, key);
    final block = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    var result = List<int>.from(block);
    var current = block;
    for (var iteration = 1; iteration < iterations; iteration++) {
      current = hmac.convert(current).bytes;
      for (var index = 0; index < result.length; index++) {
        result[index] ^= current[index];
      }
    }
    return base64Encode(result);
  }

  bool _matchesPassword(Map<String, dynamic> user, String password) {
    final encodedSalt = user['password_salt']?.toString();
    final encodedHash = user['password_hash']?.toString();
    if (encodedSalt != null && encodedHash != null) {
      try {
        final salt = base64Decode(encodedSalt);
        final iterations =
            (user['password_iterations'] as num?)?.toInt() ??
            _passwordIterations;
        if (iterations < 10000 || iterations > 250000) return false;
        return _derivePasswordHash(password, salt, iterations) == encodedHash;
      } on FormatException {
        return false;
      }
    }

    return user['password']?.toString() == password;
  }

  Map<String, dynamic> _sessionUser(Map<String, dynamic> user) {
    final session = Map<String, dynamic>.from(user)
      ..remove('password')
      ..remove('password_hash')
      ..remove('password_salt')
      ..remove('password_iterations');
    return session;
  }

  Future<void> _setCurrentUser(Map<String, dynamic> user) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_sessionKey, jsonEncode(_sessionUser(user)));
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    await _loadJwt();
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_sessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final user = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (user.containsKey('password')) {
        final email = user['email']?.toString().toLowerCase() ?? '';
        final users = await _loadUsers();
        final stored = Map<String, dynamic>.from(users[email] as Map? ?? user);
        final legacyPassword = stored.remove('password')?.toString();
        if (legacyPassword != null && !stored.containsKey('password_hash')) {
          stored.addAll(_passwordFields(legacyPassword));
          users[email] = stored;
          await _saveUsers(users);
        }
      }
      if (user.keys.any(
        (key) => const {
          'password',
          'password_hash',
          'password_salt',
          'password_iterations',
        }.contains(key),
      )) {
        await _setCurrentUser(user);
      }
      return _sessionUser(user);
    } catch (error) {
      debugPrint('Unable to read current user session: $error');
      return null;
    }
  }

  String? _usernameFrom(Map<String, dynamic> user) {
    for (final key in const ['username', 'name', 'full_name']) {
      final value = user[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

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
      (value) =>
          (value as Map<String, dynamic>)['phone']?.toString() ==
          normalizedPhone,
    );
    if (phoneTaken) return 'An account with this phone number already exists';

    final user = <String, dynamic>{
      'id': (DateTime.now().millisecondsSinceEpoch % 100000) + 1,
      'username': name.trim(),
      'name': name.trim(),
      'email': normalizedEmail,
      'phone': normalizedPhone,
      ..._passwordFields(password.trim()),
    };
    users[normalizedEmail] = user;
    await _saveUsers(users);
    await _setCurrentUser(user);

    ApiService.registerUser(
      fullName: name.trim(),
      email: normalizedEmail,
      phoneNumber: normalizedPhone,
      passwordHash: password.trim(),
    ).then((result) async {
      if (result['success'] == true && result['user_id'] != null) {
        if (result['access_token'] != null) {
          await _saveJwt(result['access_token']);
        }
        user['id'] = result['user_id'];
        user['backend_synced'] = true;
        final latestUsers = await _loadUsers();
        latestUsers[normalizedEmail] = user;
        await _saveUsers(latestUsers);
        final current = await getCurrentUser();
        if (current?['email'] == normalizedEmail) {
          await _setCurrentUser(user);
        }
      } else {
        debugPrint(
          'Backend registration was not completed: '
          '${result['error'] ?? result['message'] ?? 'unknown response'}',
        );
      }
    });

    return null;
  }

  Future<String?> login({
    required String identifier,
    required String password,
  }) async {
    final users = await _loadUsers();
    final normalizedIdentifier = identifier.trim().toLowerCase();
    final normalizedPassword = password.trim();

    Map<String, dynamic>? matchedUser;
    String? matchedEmail;
    for (final entry in users.entries) {
      final user = Map<String, dynamic>.from(entry.value as Map);
      if (entry.key.toLowerCase() == normalizedIdentifier ||
          user['phone']?.toString() == identifier.trim()) {
        matchedUser = user;
        matchedEmail = entry.key;
        break;
      }
    }

    if (matchedUser != null &&
        !_matchesPassword(matchedUser, normalizedPassword)) {
      return 'Email/phone and password do not match';
    }

    if (matchedUser == null) {
      final apiResult = await ApiService.loginUser(
        email: identifier.trim(),
        passwordHash: normalizedPassword,
      );
      if (apiResult['success'] == true && apiResult['user'] is Map) {
        if (apiResult['access_token'] != null) {
          await _saveJwt(apiResult['access_token']);
        }
        final backendUser = Map<String, dynamic>.from(apiResult['user'] as Map);
        final username = _usernameFrom(backendUser) ?? identifier.trim();
        matchedUser = {
          'id': backendUser['user_id'] ?? backendUser['id'],
          'username': username,
          'name': username,
          'email': (backendUser['email'] ?? normalizedIdentifier)
              .toString()
              .toLowerCase(),
          'phone': backendUser['phone_number'] ?? backendUser['phone'] ?? '',
          ..._passwordFields(normalizedPassword),
          'backend_synced': true,
        };
        matchedEmail = matchedUser['email']?.toString();
        if (matchedEmail != null) users[matchedEmail] = matchedUser;
      }
    } else if (!matchedUser.containsKey('password_hash')) {
      matchedUser.remove('password');
      matchedUser.addAll(_passwordFields(normalizedPassword));
      users[matchedEmail!] = matchedUser;
    }

    if (matchedUser == null) {
      return 'Email/phone and password do not match';
    }

    await _saveUsers(users);
    await _setCurrentUser(matchedUser);
    return null;
  }

  Future<bool> updateProfile({
    required String name,
    required String email,
    required String phone,
  }) async {
    final current = await getCurrentUser();
    if (current == null) return false;
    final users = await _loadUsers();
    final oldEmail = current['email']?.toString().toLowerCase() ?? '';
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) return false;
    if (normalizedEmail != oldEmail && users.containsKey(normalizedEmail)) {
      return false;
    }

    final userId = int.tryParse(current['id']?.toString() ?? '');
    if (current['backend_synced'] == true && userId != null) {
      final response = await ApiService.updateProfile(
        userId: userId,
        fullName: name.trim(),
        email: normalizedEmail,
        phoneNumber: phone.trim(),
      );
      if (response['success'] != true) {
        debugPrint(
          'Backend profile update failed: '
          '${response['error'] ?? response['message'] ?? 'invalid response'}',
        );
        return false;
      }
    }

    final stored = Map<String, dynamic>.from(
      users[oldEmail] as Map? ?? current,
    );
    final updated = <String, dynamic>{
      ...stored,
      'id': current['id'] ?? stored['id'],
      'username': name.trim(),
      'name': name.trim(),
      'email': normalizedEmail,
      'phone': phone.trim(),
    };
    if (oldEmail.isNotEmpty && oldEmail != normalizedEmail) {
      users.remove(oldEmail);
    }
    users[normalizedEmail] = updated;
    await _saveUsers(users);
    await _setCurrentUser(updated);
    return true;
  }

  Future<String?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final current = await getCurrentUser();
    if (current == null) return 'No active user found';
    final users = await _loadUsers();
    final email = current['email']?.toString().toLowerCase() ?? '';
    final storedUser = Map<String, dynamic>.from(
      users[email] as Map? ?? current,
    );
    if (!_matchesPassword(storedUser, currentPassword.trim())) {
      return 'Current password does not match';
    }
    final userId = int.tryParse(current['id']?.toString() ?? '');
    if (current['backend_synced'] == true && userId != null) {
      final response = await ApiService.changePassword(
        userId: userId,
        currentPassword: currentPassword.trim(),
        newPassword: newPassword.trim(),
      );
      if (response['success'] != true) {
        return response['error']?.toString() ??
            'The backend could not update your password';
      }
    }
    storedUser.remove('password');
    storedUser
      ..remove('password_hash')
      ..remove('password_salt')
      ..remove('password_iterations')
      ..addAll(_passwordFields(newPassword.trim()));
    users[email] = storedUser;
    await _saveUsers(users);
    await _setCurrentUser(storedUser);
    return null;
  }

  Future<bool> accountExists(String email) async {
    final users = await _loadUsers();
    return users.containsKey(email.trim().toLowerCase());
  }

  Future<void> logout() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_sessionKey);
    await _clearJwt();
  }
}
