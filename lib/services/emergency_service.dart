import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibration/vibration.dart';
import '../models/emergency_contact.dart';
import '../models/sos_record.dart';
import 'alert_service.dart';
import 'api_service.dart';

Uri buildSosSmsUri(
  List<String> phoneNumbers,
  String message, {
  TargetPlatform? platform,
}) {
  final recipients = phoneNumbers
      .map((phone) => phone.replaceAll(RegExp(r'[^0-9+]'), ''))
      .where(
        (phone) => phone.isNotEmpty && !isEmergencyHelplinePhoneNumber(phone),
      )
      .toList();
  final separator = (platform ?? defaultTargetPlatform) == TargetPlatform.iOS
      ? ','
      : ';';
  return Uri.parse(
    'sms:${recipients.join(separator)}?body=${Uri.encodeComponent(message)}',
  );
}

bool isEmergencyHelplinePhoneNumber(String phoneNumber) {
  final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
  const helplineNumbers = {'112', '100', '1091', '108', '911', '999', '000'};

  if (helplineNumbers.contains(digits)) return true;
  if (digits.startsWith('91') &&
      helplineNumbers.contains(digits.substring(2))) {
    return true;
  }
  if (digits.startsWith('0091') &&
      helplineNumbers.contains(digits.substring(4))) {
    return true;
  }
  return false;
}

class EmergencyService {
  EmergencyService._();
  static final EmergencyService instance = EmergencyService._();

  static const String _contactsStorageKey = 'smartbus_emergency_contacts_v2';
  static const String _historyStorageKey = 'smartbus_sos_history_v2';
  String _historyStorageKeyForUser(int userId) =>
      '${_historyStorageKey}_$userId';

  final FlutterTts _tts = FlutterTts();
  Timer? _sirenTimer;
  bool _isSirenActive = false;
  bool _isSosTriggered = false;
  SosRecord? _activeSosRecord;

  final ValueNotifier<bool> sirenNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> sosActiveNotifier = ValueNotifier<bool>(false);

  bool get isSirenActive => _isSirenActive;
  bool get isSosTriggered => _isSosTriggered;
  SosRecord? get activeSosRecord => _activeSosRecord;

  // Default national emergency contacts for quick dialing
  static final List<EmergencyContact> defaultHelplines = [
    EmergencyContact(
      id: 101,
      userId: 0,
      name: 'National Emergency',
      phone: '112',
      relationship: 'All-in-One Helpline',
      isDefault: true,
    ),
    EmergencyContact(
      id: 102,
      userId: 0,
      name: 'Police Control Room',
      phone: '100',
      relationship: 'Police',
      isDefault: true,
    ),
    EmergencyContact(
      id: 103,
      userId: 0,
      name: 'Women Helpline',
      phone: '1091',
      relationship: 'Women Safety',
      isDefault: true,
    ),
    EmergencyContact(
      id: 104,
      userId: 0,
      name: 'Ambulance Service',
      phone: '108',
      relationship: 'Medical Emergency',
      isDefault: true,
    ),
  ];

  Future<void> init() async {
    await AlertService.instance.init();
    try {
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.2);
    } catch (_) {}
  }

  // ============================================================
  // CONTACTS MANAGEMENT
  // ============================================================

  Future<List<EmergencyContact>> loadContacts({required int userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final userStorageKey = '$_contactsStorageKey$userId';
    var raw = prefs.getString(userStorageKey);
    final migrateLegacy = raw == null;
    raw ??= prefs.getString(_contactsStorageKey);
    List<EmergencyContact> list = [];

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        list = decoded
            .map(
              (item) => EmergencyContact.fromMap(item as Map<String, dynamic>),
            )
            .where((contact) => contact.userId == userId)
            .toList();
      } catch (e) {
        debugPrint('Error decoding emergency contacts: $e');
      }
    }

    if (migrateLegacy && list.isNotEmpty) {
      await prefs.setString(
        userStorageKey,
        jsonEncode(list.map((contact) => contact.toMap()).toList()),
      );
    }
    return list;
  }

  Future<void> saveContacts(
    List<EmergencyContact> contacts, {
    int? userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (contacts.isEmpty && userId != null) {
      await prefs.setString('$_contactsStorageKey$userId', '[]');
      return;
    }
    final grouped = <int, List<EmergencyContact>>{};
    for (final contact in contacts) {
      grouped.putIfAbsent(contact.userId, () => []).add(contact);
    }
    for (final entry in grouped.entries) {
      await prefs.setString(
        '$_contactsStorageKey${entry.key}',
        jsonEncode(entry.value.map((contact) => contact.toMap()).toList()),
      );
    }
  }

  Future<void> addContact(EmergencyContact contact) async {
    if (isEmergencyHelplinePhoneNumber(contact.phone)) {
      throw ArgumentError.value(
        contact.phone,
        'contact.phone',
        'Government emergency helpline numbers cannot be saved as trusted contacts.',
      );
    }

    final list = await loadContacts(userId: contact.userId);
    final newId = DateTime.now().millisecondsSinceEpoch % 100000;
    final newContact = EmergencyContact(
      id: contact.id ?? newId,
      userId: contact.userId,
      backendId: contact.backendId,
      name: contact.name,
      phone: contact.phone,
      relationship: contact.relationship,
      isDefault: contact.isDefault,
    );
    list.insert(0, newContact);
    await saveContacts(list, userId: contact.userId);

    // Keep the backend contact ID so later deletions target the right record.
    final result = await ApiService.addEmergencyContact(
      userId: contact.userId,
      name: contact.name,
      phone: contact.phone,
      relationship: contact.relationship,
    );
    final backendId = int.tryParse(result['contact_id']?.toString() ?? '');
    if (result['success'] == true && backendId != null) {
      final saved = EmergencyContact(
        id: newContact.id,
        backendId: backendId,
        userId: newContact.userId,
        name: newContact.name,
        phone: newContact.phone,
        relationship: newContact.relationship,
        isDefault: newContact.isDefault,
      );
      list[0] = saved;
      await saveContacts(list, userId: contact.userId);
    } else {
      debugPrint(
        'Emergency contact was saved locally only: '
        '${result['error'] ?? result['message'] ?? 'backend unavailable'}',
      );
    }
  }

  Future<void> deleteContact(EmergencyContact contact) async {
    final list = await loadContacts(userId: contact.userId);
    list.removeWhere((saved) => saved.id == contact.id);
    await saveContacts(list, userId: contact.userId);

    if (contact.backendId != null) {
      final deleted = await ApiService.deleteEmergencyContact(
        contact.backendId!,
      );
      if (!deleted) {
        debugPrint('Emergency contact deletion failed on backend.');
      }
    }
  }

  // ============================================================
  // LOCATION & MESSAGING
  // ============================================================

  Future<Position?> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) return last;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) return last;
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      debugPrint('Error getting location: $e');
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  String buildMapsUrl(double lat, double lng) {
    return 'https://maps.google.com/?q=$lat,$lng';
  }

  String composeSosMessage({
    required double lat,
    required double lng,
    String? userName,
  }) {
    final mapUrl = buildMapsUrl(lat, lng);
    final sender = (userName != null && userName.trim().isNotEmpty)
        ? userName
        : 'A passenger';
    return '🚨 EMERGENCY SOS ALERT! $sender is in danger / emergency aboard a bus and needs immediate assistance!\n\n📍 Live Location: $mapUrl\nCoordinates: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}\n\n(Sent via SmartBus Guardian App)';
  }

  // ============================================================
  // DIRECT PHONE & SMS LAUNCHERS
  // ============================================================

  Future<bool> makePhoneCall(String phoneNumber) async {
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$cleanNumber');
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        return await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Error making phone call to $cleanNumber: $e');
      try {
        return await launchUrl(uri);
      } catch (_) {
        return false;
      }
    }
  }

  Future<bool> sendDirectSms({
    required String phoneNumber,
    required String message,
    String? contactName,
  }) async {
    if (isEmergencyHelplinePhoneNumber(phoneNumber)) {
      debugPrint('Blocked SMS to emergency helpline number.');
      return false;
    }

    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleanNumber.isEmpty) return false;

    if (kIsWeb) {
      return shareMessageToContact(
        contactName: contactName ?? 'trusted contact',
        phoneNumber: cleanNumber,
        message: message,
      );
    }

    final encodedBody = Uri.encodeComponent(message);
    final uri = Uri.parse('sms:$cleanNumber?body=$encodedBody');

    try {
      if (await canLaunchUrl(uri)) {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return true;
      }
    } catch (e) {
      debugPrint('Error launching SMS: $e');
    }

    return shareMessageToContact(
      contactName: contactName ?? 'trusted contact',
      phoneNumber: cleanNumber,
      message: message,
    );
  }

  Future<bool> shareMessageToContact({
    required String contactName,
    required String phoneNumber,
    required String message,
  }) async {
    if (isEmergencyHelplinePhoneNumber(phoneNumber)) return false;

    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          subject: 'Emergency message for $contactName',
          text: 'To: $contactName ($phoneNumber)\n\n$message',
        ),
      );
      return result.status != ShareResultStatus.unavailable;
    } catch (error) {
      debugPrint('Error opening emergency message share sheet: $error');
      return false;
    }
  }

  Future<bool> shareMessageWithContacts({
    required List<EmergencyContact> contacts,
    required String message,
  }) async {
    final eligibleContacts = contacts
        .where(
          (contact) =>
              contact.phone.trim().isNotEmpty &&
              !isEmergencyHelplinePhoneNumber(contact.phone),
        )
        .toList();
    if (eligibleContacts.isEmpty) return false;

    final recipients = eligibleContacts
        .map((contact) => '${contact.name} (${contact.phone})')
        .join(', ');
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          subject: 'Emergency message for trusted contacts',
          text: 'To: $recipients\n\n$message',
        ),
      );
      return result.status != ShareResultStatus.unavailable;
    } catch (error) {
      debugPrint('Error opening emergency contacts share sheet: $error');
      return false;
    }
  }

  Future<bool> sendSosViaBackend({
    required List<EmergencyContact> contacts,
    required String message,
  }) async {
    final phoneNumbers = contacts
        .map((c) => c.phone.replaceAll(RegExp(r'[^0-9+]'), ''))
        .where((p) => p.isNotEmpty && !isEmergencyHelplinePhoneNumber(p))
        .toList();
    if (phoneNumbers.isEmpty) return false;

    try {
      final result = await ApiService.sendEmergencySms(
        phoneNumbers: phoneNumbers,
        message: message,
      );

      if (result['success'] == true) {
        return true;
      }

      debugPrint(
        'Backend SMS unavailable: ${result['error'] ?? result['message']}',
      );
      return false;
    } catch (error) {
      debugPrint('Error sending SOS through backend: $error');
      return false;
    }
  }

  Future<bool> shareSosToAllContacts({
    required List<EmergencyContact> contacts,
    required String message,
  }) async {
    final phoneNumbers = contacts
        .map((c) => c.phone.replaceAll(RegExp(r'[^0-9+]'), ''))
        .where((p) => p.isNotEmpty && !isEmergencyHelplinePhoneNumber(p))
        .toList();
    if (phoneNumbers.isEmpty) return false;

    if (kIsWeb) {
      return shareMessageWithContacts(contacts: contacts, message: message);
    }

    final uri = buildSosSmsUri(phoneNumbers, message);

    try {
      if (await canLaunchUrl(uri)) {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return true;
      }
    } catch (error) {
      debugPrint('Error launching SOS SMS composer: $error');
    }

    return shareMessageWithContacts(contacts: contacts, message: message);
  }

  // ============================================================
  // TRIGGER EMERGENCY SOS
  // ============================================================

  Future<SosRecord> triggerSos({
    required int userId,
    int? journeyId,
    String? userName,
    Position? position,
    bool backendEnabled = true,
  }) async {
    await init();

    // 1. Fetch current GPS position with quick fallback
    final pos = position ?? await getCurrentLocation();
    if (pos == null) {
      throw StateError('Current GPS location is unavailable.');
    }
    final double lat = pos.latitude;
    final double lng = pos.longitude;

    final record = SosRecord(
      id: DateTime.now().millisecondsSinceEpoch % 1000000,
      userId: userId,
      journeyId: journeyId,
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      status: 'SENT',
      address:
          'GPS Lat: ${lat.toStringAsFixed(5)}, Lng: ${lng.toStringAsFixed(5)}',
    );

    _activeSosRecord = record;
    _isSosTriggered = true;
    sosActiveNotifier.value = true;

    // 2. Save to local history
    await _saveSosToHistory(record);

    // 3. Post to backend
    if (backendEnabled) {
      unawaited(
        ApiService.sendSOS(
          userId: userId,
          journeyId: journeyId,
          latitude: lat,
          longitude: lng,
        ).then((result) {
          if (result['success'] != true) {
            debugPrint(
              'Backend SOS request failed: '
              '${result['error'] ?? result['message'] ?? 'invalid response'}',
            );
          }
        }),
      );
    }

    // 4. Start Loud Audio Siren & Haptic Alert
    startSiren();

    return record;
  }

  Future<void> _saveSosToHistory(SosRecord record) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storageKey = _historyStorageKeyForUser(record.userId);
      final raw = prefs.getString(storageKey);
      List<SosRecord> list = [];
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        list = decoded
            .map((item) => SosRecord.fromMap(item as Map<String, dynamic>))
            .toList();
      }
      list.insert(0, record);
      if (list.length > 50) {
        list = list.sublist(0, 50);
      }
      await prefs.setString(
        storageKey,
        jsonEncode(list.map((r) => r.toMap()).toList()),
      );
    } catch (e) {
      debugPrint('Error saving SOS history: $e');
    }
  }

  Future<List<SosRecord>> loadSosHistory({required int userId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storageKey = _historyStorageKeyForUser(userId);
      final raw =
          prefs.getString(storageKey) ?? prefs.getString(_historyStorageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        final history = decoded
            .map((item) => SosRecord.fromMap(item as Map<String, dynamic>))
            .where((record) => record.userId == userId)
            .toList();
        if (prefs.getString(storageKey) == null) {
          await prefs.setString(
            storageKey,
            jsonEncode(history.map((record) => record.toMap()).toList()),
          );
        }
        return history;
      }
    } catch (e) {
      debugPrint('Error loading local SOS history: $e');
    }
    return [];
  }

  // ============================================================
  // SIREN & HAPTIC ALARM
  // ============================================================

  void startSiren() {
    stopSiren();
    _isSirenActive = true;
    sirenNotifier.value = true;

    const sirenText =
        'Emergency! Emergency! Passenger needs immediate help! Emergency alert activated on SmartBus Guardian!';

    Future<void> fireSirenPulse() async {
      if (!_isSirenActive) return;
      try {
        final hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator == true) {
          Vibration.vibrate(
            pattern: const [0, 600, 150, 600, 150, 1000],
            intensities: const [0, 255, 0, 255, 0, 255],
          );
        }
      } catch (_) {}

      try {
        await _tts.stop();
        await _tts.speak(sirenText);
      } catch (_) {}
    }

    fireSirenPulse();
    _sirenTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_isSirenActive) {
        fireSirenPulse();
      }
    });
  }

  void stopSiren() {
    _isSirenActive = false;
    sirenNotifier.value = false;
    _sirenTimer?.cancel();
    _sirenTimer = null;
    try {
      Vibration.cancel();
      _tts.stop();
    } catch (_) {}
  }

  void resolveSos() {
    stopSiren();
    _isSosTriggered = false;
    sosActiveNotifier.value = false;
    _activeSosRecord = null;
  }
}
