import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.isRead = false,
  });

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    title: title,
    body: body,
    createdAt: createdAt,
    isRead: isRead ?? this.isRead,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'body': body,
    'createdAt': createdAt.toIso8601String(),
    'isRead': isRead,
  };

  factory AppNotification.fromMap(Map<String, dynamic> map) => AppNotification(
    id: map['id']?.toString() ?? '',
    title: map['title']?.toString() ?? 'Notification',
    body: map['body']?.toString() ?? '',
    createdAt:
        DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now(),
    isRead: map['isRead'] == true,
  );
}

/// Backs the Smart Destination Alert Module and the Sleep Protection
/// Module from the project synopsis: voice announcements, vibration, and
/// full-screen/alarm-style notifications — fired once for a normal
/// journey, or repeated on an interval for Sleep Mode until the passenger
/// dismisses it.
class AlertService {
  AlertService._();
  static final AlertService instance = AlertService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final FlutterTts _tts = FlutterTts();

  bool _initialized = false;
  Timer? _repeatTimer;
  int _notificationId = 1000;
  static const _historyKey = 'smartbus_notification_history_v1';

  /// Call once (e.g. in MapScreen.initState) before firing any alerts.
  /// Safe to call multiple times — only initializes once.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _notifications.initialize(initSettings);

    // Android 13+ requires runtime notification permission.
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
  }

  Future<void> _showNotification({
    required String title,
    required String body,
  }) async {
    await recordNotification(title: title, body: body);

    const androidDetails = AndroidNotificationDetails(
      'destination_alerts',
      'Destination Alerts',
      channelDescription: 'Alerts when approaching your selected bus stop',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      ),
    );
    await _notifications.show(_notificationId++, title, body, details);
  }

  Future<List<AppNotification>> getNotificationHistory() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_historyKey);
    if (encoded == null || encoded.isEmpty) return [];

    try {
      final decoded = jsonDecode(encoded) as List<dynamic>;
      return decoded
          .map(
            (entry) => AppNotification.fromMap(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList();
    } catch (error) {
      debugPrint('Unable to read notification history: $error');
      return [];
    }
  }

  Future<void> recordNotification({
    required String title,
    required String body,
  }) async {
    try {
      final history = await getNotificationHistory();
      history.insert(
        0,
        AppNotification(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: title,
          body: body,
          createdAt: DateTime.now(),
        ),
      );
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _historyKey,
        jsonEncode(history.take(100).map((item) => item.toMap()).toList()),
      );
    } catch (error) {
      debugPrint('Unable to save notification history: $error');
    }
  }

  Future<void> markAllNotificationsRead() async {
    final history = await getNotificationHistory();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _historyKey,
      jsonEncode(
        history.map((item) => item.copyWith(isRead: true).toMap()).toList(),
      ),
    );
  }

  Future<void> clearNotificationHistory() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_historyKey);
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _vibrateOnce() async {
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(pattern: const [0, 400, 200, 400, 200, 600]);
    }
  }

  /// Fires voice + vibration + a full-screen notification once. Used for
  /// normal (non-Sleep-Mode) journeys.
  Future<void> fireDestinationAlert({
    required String destinationName,
    required double distanceMeters,
  }) async {
    final message =
        'Approaching $destinationName. About ${distanceMeters.toStringAsFixed(0)} meters remaining.';
    await _vibrateOnce();
    await _speak(message);
    await _showNotification(title: 'Destination Approaching', body: message);
  }

  /// Sleep Protection Module: fires the same alert immediately, then keeps
  /// repeating voice + vibration + notification every [interval] until
  /// [stopRepeatingAlert] is called (e.g. the passenger dismisses the
  /// wake-up dialog). Only one repeat cycle runs at a time — starting a
  /// new one cancels any previous one first.
  void startSleepAlarm({
    required String destinationName,
    Duration interval = const Duration(seconds: 12),
  }) {
    stopRepeatingAlert();
    final message = 'Wake up! Approaching $destinationName. Please get ready.';

    Future<void> fireOnce() async {
      await _vibrateOnce();
      await _speak(message);
      await _showNotification(
        title: 'Wake Up — Destination Approaching',
        body: message,
      );
    }

    fireOnce();
    _repeatTimer = Timer.periodic(interval, (_) => fireOnce());
  }

  /// Fires a single, non-repeating preview alert (voice + vibration +
  /// notification) so the user can check what the Sleep Mode alarm will
  /// feel/sound like before relying on it during a journey.
  Future<void> testAlert() async {
    await _vibrateOnce();
    await _speak('This is a test of your SmartBus Guardian alarm.');
    await _showNotification(
      title: 'Test Alarm',
      body: 'This is what your Sleep Mode alarm will sound like.',
    );
  }

  /// Stops a Sleep Mode repeat cycle (if any) and silences any in-flight
  /// vibration/speech. Always safe to call even if nothing is running.
  void stopRepeatingAlert() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    Vibration.cancel();
    _tts.stop();
  }

  void dispose() {
    stopRepeatingAlert();
  }
}
