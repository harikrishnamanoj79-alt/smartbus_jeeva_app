import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class SavedDestinationService {
  SavedDestinationService._();
  static final SavedDestinationService instance = SavedDestinationService._();

  String _storageKey(int userId) => 'smartbus_saved_destinations_$userId';

  Future<List<Map<String, dynamic>>> load({
    required int userId,
    bool syncWithBackend = false,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey(userId));
    var destinations = <Map<String, dynamic>>[];
    if (encoded != null && encoded.isNotEmpty) {
      try {
        destinations = List<Map<String, dynamic>>.from(
          (jsonDecode(encoded) as List).map(
            (entry) => Map<String, dynamic>.from(entry as Map),
          ),
        );
      } catch (error) {
        debugPrint('Unable to read saved destinations: $error');
      }
    }

    if (!syncWithBackend) return destinations;
    final remote = await ApiService.getSavedDestinations(userId);
    final merged = <Map<String, dynamic>>[
      ...remote.map(
        (entry) => {
          'destination_id': entry['destination_id'],
          'name': entry['destination_name'],
          'latitude': entry['latitude'],
          'longitude': entry['longitude'],
        },
      ),
    ];
    for (final local in destinations) {
      final exists = merged.any((candidate) => _sameDestination(local, candidate));
      if (exists) continue;
      if (local['destination_id'] == null) {
        final result = await ApiService.addSavedDestination(
          userId: userId,
          name: local['name'].toString(),
          latitude: (local['latitude'] as num).toDouble(),
          longitude: (local['longitude'] as num).toDouble(),
        );
        if (result['success'] == true) {
          local['destination_id'] = result['destination_id'];
        } else {
          debugPrint(
            'Saved destination remains local: '
            '${result['error'] ?? result['message'] ?? 'backend unavailable'}',
          );
        }
      }
      merged.add(local);
    }
    await _save(userId, merged);
    return merged;
  }

  Future<Map<String, dynamic>> add({
    required int userId,
    required String name,
    required double latitude,
    required double longitude,
    bool syncWithBackend = false,
  }) async {
    final destinations = await load(
      userId: userId,
      syncWithBackend: syncWithBackend,
    );
    if (destinations.any(
      (destination) =>
          _sameDestination(destination, {
            'name': name,
            'latitude': latitude,
            'longitude': longitude,
          }),
    )) {
      throw ArgumentError('This destination is already saved.');
    }
    final destination = <String, dynamic>{
      'name': name.trim(),
      'latitude': latitude,
      'longitude': longitude,
    };
    destinations.add(destination);
    await _save(userId, destinations);

    if (syncWithBackend) {
      final result = await ApiService.addSavedDestination(
        userId: userId,
        name: name.trim(),
        latitude: latitude,
        longitude: longitude,
      );
      if (result['success'] == true) {
        destination['destination_id'] = result['destination_id'];
        await _save(userId, destinations);
      } else {
        debugPrint(
          'Saved destination remains local: '
          '${result['error'] ?? result['message'] ?? 'backend unavailable'}',
        );
      }
    }
    return destination;
  }

  Future<void> remove({
    required int userId,
    required Map<String, dynamic> destination,
    bool syncWithBackend = false,
  }) async {
    final destinations = await load(
      userId: userId,
      syncWithBackend: false,
    );
    destinations.removeWhere(
      (entry) =>
          _sameDestination(entry, destination) &&
          entry['destination_id'] == destination['destination_id'],
    );
    await _save(userId, destinations);

    final destinationId = int.tryParse(
      destination['destination_id']?.toString() ?? '',
    );
    if (syncWithBackend && destinationId != null) {
      final deleted = await ApiService.deleteSavedDestination(destinationId);
      if (!deleted) {
        debugPrint('Saved destination was removed locally but not remotely.');
      }
    }
  }

  bool _sameDestination(
    Map<String, dynamic> first,
    Map<String, dynamic> second,
  ) {
    final firstLatitude = (first['latitude'] as num?)?.toDouble();
    final firstLongitude = (first['longitude'] as num?)?.toDouble();
    final secondLatitude = (second['latitude'] as num?)?.toDouble();
    final secondLongitude = (second['longitude'] as num?)?.toDouble();
    return first['name']?.toString().trim().toLowerCase() ==
            second['name']?.toString().trim().toLowerCase() &&
        firstLatitude != null &&
        firstLongitude != null &&
        secondLatitude != null &&
        secondLongitude != null &&
        (firstLatitude - secondLatitude).abs() < 0.0001 &&
        (firstLongitude - secondLongitude).abs() < 0.0001;
  }

  Future<void> _save(
    int userId,
    List<Map<String, dynamic>> destinations,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey(userId),
      jsonEncode(destinations),
    );
  }
}
