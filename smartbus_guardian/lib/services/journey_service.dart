import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/journey_record.dart';
import 'api_service.dart';

class JourneyService {
  JourneyService._();
  static final JourneyService instance = JourneyService._();

  static const String _historyKey = 'smartbus_journey_history_v2';
  static const String _activeJourneyKey = 'smartbus_active_journey_v2';

  final ValueNotifier<JourneyRecord?> activeJourneyNotifier =
      ValueNotifier<JourneyRecord?>(null);

  /// Initializes and loads active journey if any
  Future<void> init() async {
    final active = await getActiveJourney();
    activeJourneyNotifier.value = active;
  }

  /// Starts a new journey and saves it as active
  Future<JourneyRecord> startJourney({
    required int userId,
    String sourceLocation = 'Current Location',
    required String destinationName,
    String? destinationAddress,
    double? startLatitude,
    double? startLongitude,
    double? destLatitude,
    double? destLongitude,
    double? estimatedDistanceKm,
    bool sleepModeEnabled = false,
    bool syncWithBackend = true,
  }) async {
    final journeyId = 'JRN_${DateTime.now().millisecondsSinceEpoch}';

    var journey = JourneyRecord(
      id: journeyId,
      userId: userId,
      sourceLocation: sourceLocation,
      destinationName: destinationName,
      destinationAddress: destinationAddress,
      startLatitude: startLatitude,
      startLongitude: startLongitude,
      destLatitude: destLatitude,
      destLongitude: destLongitude,
      startTime: DateTime.now(),
      distanceKm: estimatedDistanceKm,
      status: 'IN_PROGRESS',
      sleepModeEnabled: sleepModeEnabled,
    );

    // Save as active journey
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeJourneyKey, journey.toJson());
    activeJourneyNotifier.value = journey;

    if (syncWithBackend && destLatitude != null && destLongitude != null) {
      final result = await ApiService.startJourney(
        userId: userId,
        sourceLocation: sourceLocation,
        destinationLocation: destinationName,
        destinationLatitude: destLatitude,
        destinationLongitude: destLongitude,
        sleepModeEnabled: sleepModeEnabled,
      );
      final backendId = int.tryParse(result['journey_id']?.toString() ?? '');
      if (result['success'] == true && backendId != null) {
        journey = journey.copyWith(backendId: backendId);
        await prefs.setString(_activeJourneyKey, journey.toJson());
        activeJourneyNotifier.value = journey;
      } else {
        debugPrint(
          'Backend journey start was not completed: '
          '${result['error'] ?? result['message'] ?? 'invalid response'}',
        );
      }
    }

    return journey;
  }

  /// Ends the active journey (or specified journey) and archives it in history
  Future<JourneyRecord?> endJourney({
    bool completed = true,
    bool missed = false,
    double? finalDistanceKm,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    JourneyRecord? current =
        activeJourneyNotifier.value ?? await getActiveJourney();

    if (current == null) return null;

    final finishedJourney = current.copyWith(
      endTime: DateTime.now(),
      status: completed
          ? 'COMPLETED'
          : missed
          ? 'MISSED'
          : 'CANCELLED',
      distanceKm: finalDistanceKm ?? current.distanceKm,
    );

    if ((completed || missed) && current.backendId != null) {
      final result = await ApiService.finishJourney(
        journeyId: current.backendId!,
        userId: current.userId,
        distanceTravelledKm: finishedJourney.distanceKm ?? 0,
        status: missed ? 'MISSED' : 'COMPLETED',
      );
      if (result['success'] != true) {
        debugPrint(
          'Backend journey completion failed: '
          '${result['error'] ?? result['message'] ?? 'invalid response'}',
        );
      }
    }

    // Add to history list
    final history = await _loadStoredHistory();
    history.insert(0, finishedJourney);
    await _saveHistoryList(history);

    // Remove active journey
    await prefs.remove(_activeJourneyKey);
    activeJourneyNotifier.value = null;

    return finishedJourney;
  }

  Future<bool> recordMissedStop({
    required double latitude,
    required double longitude,
    required String nearestReturnStop,
  }) async {
    final current = activeJourneyNotifier.value ?? await getActiveJourney();
    if (current?.backendId == null) {
      debugPrint('Missed stop was not synced: no backend journey is active.');
      return false;
    }
    final result = await ApiService.recordMissedStop(
      journeyId: current!.backendId!,
      latitude: latitude,
      longitude: longitude,
      nearestReturnStop: nearestReturnStop,
    );
    if (result['success'] != true) {
      debugPrint(
        'Missed-stop record failed: '
        '${result['error'] ?? result['message'] ?? 'invalid response'}',
      );
    }
    return result['success'] == true;
  }

  /// Get currently active ongoing journey
  Future<JourneyRecord?> getActiveJourney() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activeJourneyKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        return JourneyRecord.fromJson(raw);
      } catch (e) {
        debugPrint('Error parsing active journey: $e');
      }
    }
    return null;
  }

  /// Get list of all saved journeys
  Future<List<JourneyRecord>> getJourneyHistory({
    int? userId,
    bool syncWithBackend = false,
  }) async {
    final stored = await _loadStoredHistory();
    final local = userId == null
        ? stored
        : stored.where((journey) => journey.userId == userId).toList();
    if (userId == null || !syncWithBackend) return local;

    final backendRows = await ApiService.getJourneyHistory(userId);
    final remote = backendRows.map(JourneyRecord.fromMap).toList();
    final remoteIds = remote.map((journey) => journey.backendId).toSet();
    final combined = [
      ...remote,
      ...local.where(
        (journey) =>
            journey.backendId == null || !remoteIds.contains(journey.backendId),
      ),
    ]..sort((first, second) => second.startTime.compareTo(first.startTime));
    return combined;
  }

  Future<void> _saveHistoryList(List<JourneyRecord> list) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(list.map((j) => j.toMap()).toList());
    await prefs.setString(_historyKey, encoded);
  }

  /// Deletes a specific journey from history
  Future<void> deleteJourney(
    String id, {
    int? userId,
    bool syncWithBackend = false,
  }) async {
    final history = await _loadStoredHistory();
    final removed = history
        .where(
          (journey) =>
              journey.id == id && (userId == null || journey.userId == userId),
        )
        .toList();
    history.removeWhere(
      (journey) =>
          journey.id == id && (userId == null || journey.userId == userId),
    );
    await _saveHistoryList(history);
    int? backendId;
    for (final journey in removed) {
      if (journey.backendId != null) {
        backendId = journey.backendId;
        break;
      }
    }
    if (syncWithBackend && userId != null && backendId != null) {
      final deleted = await ApiService.deleteJourneyHistory(
        userId: userId,
        journeyId: backendId,
      );
      if (!deleted) {
        debugPrint('The journey was removed locally but not on the backend.');
      }
    }
  }

  /// Clears all journey history
  Future<void> clearAllHistory({
    int? userId,
    bool syncWithBackend = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (userId == null) {
      await prefs.remove(_historyKey);
      return;
    }
    final history = await _loadStoredHistory();
    history.removeWhere((journey) => journey.userId == userId);
    await _saveHistoryList(history);
    if (syncWithBackend) {
      final cleared = await ApiService.clearJourneyHistory(userId);
      if (!cleared) {
        debugPrint(
          'Journey history was cleared locally but not on the backend.',
        );
      }
    }
  }

  Future<List<JourneyRecord>> _loadStoredHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => JourneyRecord.fromMap(item as Map<String, dynamic>))
          .toList();
    } catch (error) {
      debugPrint('Error parsing journey history: $error');
      return [];
    }
  }
}
