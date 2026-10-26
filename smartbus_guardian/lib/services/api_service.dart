import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static const String _deviceBaseUrl = 'http://192.168.220.34:5000';
  static String get baseUrl => kIsWeb
      ? '${Uri.base.scheme}://${Uri.base.host}:5000'
      : _deviceBaseUrl;
  static const Duration _timeout = Duration(seconds: 4);

  static String? _jwtToken;

  static void setJwtToken(String? token) {
    _jwtToken = token;
  }

  static Map<String, String> get _headers {
    final headers = {'Content-Type': 'application/json'};
    if (_jwtToken != null) {
      headers['Authorization'] = 'Bearer $_jwtToken';
    }
    return headers;
  }

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
            headers: _headers,
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
            headers: _headers,
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

  static Future<Map<String, dynamic>> updateProfile({
    required int userId,
    required String fullName,
    required String email,
    required String phoneNumber,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/profile/$userId'),
            headers: _headers,
            body: jsonEncode({
              'full_name': fullName,
              'email': email,
              'phone_number': phoneNumber,
            }),
          )
          .timeout(_timeout);
      return jsonDecode(response.body);
    } catch (error) {
      return {'success': false, 'error': 'Cannot connect to server: $error'};
    }
  }

  static Future<Map<String, dynamic>> changePassword({
    required int userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/profile/$userId/password'),
            headers: _headers,
            body: jsonEncode({
              'current_password': currentPassword,
              'new_password': newPassword,
            }),
          )
          .timeout(_timeout);
      return jsonDecode(response.body);
    } catch (error) {
      return {'success': false, 'error': 'Cannot connect to server: $error'};
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
            headers: _headers,
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

  static Future<Map<String, dynamic>> finishJourney({
    required int journeyId,
    required int userId,
    required double distanceTravelledKm,
    required String status,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/journey/$journeyId/finish'),
            headers: _headers,
            body: jsonEncode({
              'user_id': userId,
              'distance_travelled': distanceTravelledKm,
              'status': status,
            }),
          )
          .timeout(_timeout);
      return jsonDecode(response.body);
    } catch (error) {
      return {'success': false, 'error': 'Cannot connect to server: $error'};
    }
  }

  static Future<Map<String, dynamic>> recordMissedStop({
    required int journeyId,
    required double latitude,
    required double longitude,
    required String nearestReturnStop,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/missed-stop'),
            headers: _headers,
            body: jsonEncode({
              'journey_id': journeyId,
              'missed_latitude': latitude,
              'missed_longitude': longitude,
              'nearest_return_stop': nearestReturnStop,
            }),
          )
          .timeout(_timeout);
      return jsonDecode(response.body);
    } catch (error) {
      return {'success': false, 'error': 'Cannot connect to server: $error'};
    }
  }

  static Future<bool> recordJourneyAlert({
    required int journeyId,
    required String alertType,
    required double distanceRemainingMeters,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/alerts'),
            headers: _headers,
            body: jsonEncode({
              'journey_id': journeyId,
              'alert_type': alertType,
              'distance_remaining': distanceRemainingMeters,
            }),
          )
          .timeout(_timeout);
      final decoded = jsonDecode(response.body);
      return response.statusCode == 201 &&
          decoded is Map<String, dynamic> &&
          decoded['success'] == true;
    } catch (error) {
      debugPrint('Journey alert was not synced: $error');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getSavedDestinations(
    int userId,
  ) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/saved-destinations/$userId'), headers: _headers)
          .timeout(_timeout);
      if (response.statusCode != 200) {
        throw StateError('Saved destinations request failed: ${response.body}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['destinations'] as List);
    } catch (error) {
      debugPrint('Unable to fetch saved destinations: $error');
      return [];
    }
  }

  static Future<Map<String, dynamic>> addSavedDestination({
    required int userId,
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/saved-destinations'),
            headers: _headers,
            body: jsonEncode({
              'user_id': userId,
              'destination_name': name,
              'latitude': latitude,
              'longitude': longitude,
            }),
          )
          .timeout(_timeout);
      return jsonDecode(response.body);
    } catch (error) {
      return {'success': false, 'error': 'Cannot connect to server: $error'};
    }
  }

  static Future<bool> deleteSavedDestination(int destinationId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/saved-destinations/$destinationId'),
            headers: _headers,
          )
          .timeout(_timeout);
      return response.statusCode == 200 || response.statusCode == 404;
    } catch (error) {
      debugPrint('Saved destination deletion failed: $error');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getJourneyHistory(
    int userId,
  ) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/journey/history/$userId'), headers: _headers)
          .timeout(_timeout);
      if (response.statusCode != 200) {
        throw StateError('Journey history request failed: ${response.body}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['journeys'] as List);
    } catch (error) {
      debugPrint('Unable to fetch backend journey history: $error');
      return [];
    }
  }

  static Future<bool> deleteJourneyHistory({
    required int userId,
    required int journeyId,
  }) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/journey/history/$userId/$journeyId'),
            headers: _headers,
          )
          .timeout(_timeout);
      return response.statusCode == 200 || response.statusCode == 404;
    } catch (error) {
      debugPrint('Journey history deletion failed: $error');
      return false;
    }
  }

  static Future<bool> clearJourneyHistory(int userId) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/journey/history/$userId'), headers: _headers)
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (error) {
      debugPrint('Journey history clearing failed: $error');
      return false;
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
            headers: _headers,
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
          .get(Uri.parse('$baseUrl/api/contacts/$userId'), headers: _headers)
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
            headers: _headers,
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
          .delete(Uri.parse('$baseUrl/api/contacts/$contactId'), headers: _headers)
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
            headers: _headers,
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
          .get(Uri.parse('$baseUrl/api/sos/$userId'), headers: _headers)
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