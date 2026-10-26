import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'alert_service.dart';
import 'journey_service.dart';

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Init necessary services inside isolate
  await AlertService.instance.init();

  String destinationName = '';
  double? destLat;
  double? destLng;
  int? journeyId;
  bool isSleepMode = false;

  service.on('updateDestination').listen((event) {
    if (event != null) {
      destinationName = event['destinationName'] ?? '';
      destLat = event['destLat'];
      destLng = event['destLng'];
      journeyId = event['journeyId'];
      isSleepMode = event['isSleepMode'] ?? false;
    }
  });

  // Start listening to GPS
  const LocationSettings locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10,
  );

  StreamSubscription<Position>? positionStream;

  positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "SmartBus Guardian is active",
        content: "Tracking journey to $destinationName",
      );
    }

    if (destLat != null && destLng != null) {
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        destLat!,
        destLng!,
      );

      // Check arrival (100 meters default)
      if (distance <= 100) {
        if (isSleepMode) {
          AlertService.instance.startSleepAlarm(
            destinationName: destinationName,
            journeyId: journeyId,
          );
        } else {
          AlertService.instance.fireDestinationAlert(
            destinationName: destinationName,
            distanceMeters: distance,
            journeyId: journeyId,
          );
        }
        
        // Stop tracking in background after arrived
        positionStream?.cancel();
        service.stopSelf();
      }
    }
  });
}

class BackgroundTrackingService {
  BackgroundTrackingService._();
  static final BackgroundTrackingService instance = BackgroundTrackingService._();

  final FlutterBackgroundService _service = FlutterBackgroundService();

  Future<void> initialize() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'tracking_service',
      'Journey Tracking Service',
      description: 'Maintains active journey tracking in the background.',
      importance: Importance.low,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    if (DefaultTargetPlatform.android == TargetPlatform.android) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'tracking_service',
        initialNotificationTitle: 'SmartBus Guardian',
        initialNotificationContent: 'Initializing Tracking Service',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: (ServiceInstance service) {
          return true; // continue executing
        },
      ),
    );
  }

  Future<void> startTracking({
    required String destinationName,
    required double destLat,
    required double destLng,
    int? journeyId,
    bool isSleepMode = false,
  }) async {
    final isRunning = await _service.isRunning();
    if (!isRunning) {
      await _service.startService();
    }
    
    // Give isolate time to spin up
    await Future.delayed(const Duration(milliseconds: 500));
    
    _service.invoke('updateDestination', {
      'destinationName': destinationName,
      'destLat': destLat,
      'destLng': destLng,
      'journeyId': journeyId,
      'isSleepMode': isSleepMode,
    });
  }

  Future<void> stopTracking() async {
    final isRunning = await _service.isRunning();
    if (isRunning) {
      _service.invoke('stopService');
    }
  }
}
