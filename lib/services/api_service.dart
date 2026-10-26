import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static const String _deviceBaseUrl = 'http://192.168.220.34:5000';
  static String get baseUrl => kIsWeb
      ? '${Uri.base.scheme}://${Uri.base.host}:5000'
      : _deviceBaseUrl;
  static const Duration _timeout = Duration(seconds: 4);

  // Test backend connection
  static Future<bool> testConnection() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/'))
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      // Backend not running or unreachable
      return false;
    }
  }

  // Register user
  static Future<Map<String, dynamic>> registerUser({
    required String fullName,
    required String email,
    required String phoneNumber,
    required String passwordHash,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'full_name': fullName,
              'email': email,
              'phone_number': phoneNumber,
              'password_hash': passwordHash,
            }),
          )
          .timeout(_timeout);

      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Cannot connect to server: $e'};
    }
  }

  // Login user
  static Future<Map<String, dynamic>> loginUser({
    required String email,
    required String passwordHash,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'identifier': email,
              'password_hash': passwordHash,
            }),
          )
          .timeout(_timeout);

      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Cannot connect to server: $e'};
    }
  }

  // Start journey
  static Future<Map<String, dynamic>> startJourney({
    required int userId,
    required String sourceLocation,
    required String destinationLocation,
    required double destinationLatitude,
    required double destinationLongitude,
    bool sleepModeEnabled = false,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/journey/start'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': userId,
              'source_location': sourceLocation,
              'destination_location': destinationLocation,
              'dest_latitude': destinationLatitude,
              'dest_longitude': destinationLongitude,
              'sleep_mode_enabled': sleepModeEnabled ? 1 : 0,
            }),
          )
          .timeout(_timeout);

      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Cannot connect to server: $e'};
    }
  }

  // Send SOS
  static Future<Map<String, dynamic>> sendSOS({
    required int userId,
    int? journeyId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/sos'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': userId,
              'journey_id': journeyId,
              'latitude': latitude,
              'longitude': longitude,
            }),
          )
          .timeout(_timeout);

      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Cannot connect to server: $e'};
    }
  }

  // Fetch Emergency Contacts
  static Future<List<Map<String, dynamic>>> getEmergencyContacts(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/contacts/$userId'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['contacts'] != null) {
          return List<Map<String, dynamic>>.from(data['contacts']);
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // Add Emergency Contact
  static Future<Map<String, dynamic>> addEmergencyContact({
    required int userId,
    required String name,
    required String phone,
    required String relationship,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/contacts'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': userId,
              'contact_name': name,
              'contact_phone': phone,
              'relationship': relationship,
            }),
          )
          .timeout(_timeout);

      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Cannot connect to server: $e'};
    }
  }

  // Delete Emergency Contact
  static Future<bool> deleteEmergencyContact(int contactId) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/contacts/$contactId'))
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Send emergency SMS via backend when configured; falls back to device SMS if unavailable.
  static Future<Map<String, dynamic>> sendEmergencySms({
    required List<String> phoneNumbers,
    required String message,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/sms/send'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phones': phoneNumbers,
              'message': message,
            }),
          )
          .timeout(_timeout);

      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {'success': false, 'fallback': 'device', 'error': 'Invalid response'};
    } catch (e) {
      return {'success': false, 'fallback': 'device', 'error': 'Cannot connect to server: $e'};
    }
  }

  // Get SOS History
  static Future<List<Map<String, dynamic>>> getSosHistory(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/sos/$userId'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['alerts'] != null) {
          return List<Map<String, dynamic>>.from(data['alerts']);
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}