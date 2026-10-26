import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbus_guardian/main.dart';
import 'package:smartbus_guardian/screens/destination_screen.dart';
import 'package:smartbus_guardian/screens/map_screen.dart';
import 'package:smartbus_guardian/screens/profile_screen.dart';
import 'package:smartbus_guardian/screens/auth_screen.dart';
import 'package:smartbus_guardian/screens/sos_screen.dart';
import 'package:smartbus_guardian/services/alert_service.dart';
import 'package:smartbus_guardian/services/emergency_service.dart';
import 'package:smartbus_guardian/services/theme_service.dart';

void main() {
  testWidgets('signed-out app opens the login screen', (tester) async {
    await tester.pumpWidget(const SmartBusGuardian(isLoggedIn: false));

    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.text('LogIn'), findsOneWidget);
  });

  testWidgets('journey planner shows searchable FROM and TO fields', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: JourneyPlannerScreen()));

    expect(find.text('FROM'), findsOneWidget);
    expect(find.text('TO / DESTINATION'), findsOneWidget);
    expect(find.text('Current Location'), findsOneWidget);

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(
      fields.map((field) => field.decoration?.hintText),
      containsAll([
        'Enter/Search another starting location',
        'Enter/Search destination',
      ]),
    );
  });

  testWidgets('profile displays the active registered username', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'smartbus_current_user_session_v2': jsonEncode({
        'id': 7,
        'name': 'Registered Username',
        'email': 'registered@example.com',
        'phone': '5551234567',
      }),
    });

    final themes = AppThemeService.instance;
    await themes.setThemeMode(ThemeMode.system);
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: themes.themeMode,
        builder: (context, _) => MaterialApp(
          theme: themes.lightTheme,
          darkTheme: themes.darkTheme,
          themeMode: themes.themeMode.value,
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsWidgets);
    expect(find.text('Registered Username'), findsWidgets);
    expect(find.textContaining('Passenger'), findsNothing);

    final user = await AuthService.instance.getCurrentUser();
    expect(user?['username'], 'Registered Username');
  });

  test('remaining road distance decreases along the route', () {
    final route = [
      const LatLng(0, 0),
      const LatLng(0, 0.01),
      const LatLng(0, 0.02),
    ];

    final before = estimateRemainingRoadDistanceMeters(
      currentLocation: const LatLng(0, 0),
      routePoints: route,
      totalRoadDistanceMeters: 2500,
    );
    final after = estimateRemainingRoadDistanceMeters(
      currentLocation: const LatLng(0, 0.01),
      routePoints: route,
      totalRoadDistanceMeters: 2500,
    );

    expect(before, greaterThan(after));
    expect(after, closeTo(1250, 5));
  });

  test('destination alert threshold is 100 meters', () {
    expect(isWithinDestinationAlertThreshold(100), isTrue);
    expect(isWithinDestinationAlertThreshold(99), isTrue);
    expect(isWithinDestinationAlertThreshold(101), isFalse);
  });

  test('stop arrival and route deviation use GPS distance thresholds', () {
    expect(isWithinBusStopArrivalRadius(100), isTrue);
    expect(isWithinBusStopArrivalRadius(101), isFalse);
    expect(isOutsideRouteDeviationThreshold(150), isFalse);
    expect(isOutsideRouteDeviationThreshold(151), isTrue);
  });

  test('notification history persists alerts and read state', () async {
    SharedPreferences.setMockInitialValues({});

    await AlertService.instance.recordNotification(
      title: 'Destination Approaching',
      body: 'About 80 meters remaining.',
    );

    final unread = await AlertService.instance.getNotificationHistory();
    expect(unread, hasLength(1));
    expect(unread.single.title, 'Destination Approaching');
    expect(unread.single.isRead, isFalse);

    await AlertService.instance.markAllNotificationsRead();
    final read = await AlertService.instance.getNotificationHistory();
    expect(read.single.isRead, isTrue);
  });

  test('registration and login keep each account username separate', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService.instance;

    expect(
      await auth.register(
        name: 'First Registered Name',
        email: 'first@example.com',
        phone: '5550000001',
        password: 'first123',
      ),
      isNull,
    );
    expect(
      await auth.register(
        name: 'Second Registered Name',
        email: 'second@example.com',
        phone: '5550000002',
        password: 'second123',
      ),
      isNull,
    );

    expect(
      await auth.login(identifier: 'first@example.com', password: 'first123'),
      isNull,
    );
    expect((await auth.getCurrentUser())?['username'], 'First Registered Name');

    expect(
      await auth.login(identifier: 'second@example.com', password: 'second123'),
      isNull,
    );
    expect(
      (await auth.getCurrentUser())?['username'],
      'Second Registered Name',
    );
  });

  test('shared SOS location contains coordinates and a map link', () {
    final message = buildLocationShareMessage(12.3456789, 76.5432109);

    expect(message, contains('https://www.google.com/maps/search/'));
    expect(message, contains('12.345679,76.543211'));
  });

  test('SOS contact message includes the captured GPS location', () {
    final message = EmergencyService.instance.composeSosMessage(
      lat: 12.345678,
      lng: 76.543210,
      userName: 'Rider Name',
    );

    expect(message, contains('Rider Name'));
    expect(message, contains('https://maps.google.com/?q=12.345678,76.54321'));
    expect(message, contains('12.345678, 76.543210'));
  });

  test('SOS SMS keeps saved contacts as separate recipients', () {
    final androidUri = buildSosSmsUri(
      ['+1 (555) 111-2222', '+1 (555) 333-4444', '112', '+91 100'],
      'SOS location: https://maps.google.com/?q=12,76',
      platform: TargetPlatform.android,
    );
    final iosUri = buildSosSmsUri(
      ['+1 (555) 111-2222', '+1 (555) 333-4444', '112', '+91 100'],
      'SOS location',
      platform: TargetPlatform.iOS,
    );

    expect(androidUri.path, '+15551112222;+15553334444');
    expect(iosUri.path, '+15551112222,+15553334444');
    expect(androidUri.queryParameters['body'], contains('12,76'));
    expect(isEmergencyHelplinePhoneNumber('112'), isTrue);
    expect(isEmergencyHelplinePhoneNumber('+91 100'), isTrue);
    expect(isEmergencyHelplinePhoneNumber('9876543210'), isFalse);
  });

  test('emergency contacts do not seed sample phone numbers', () async {
    SharedPreferences.setMockInitialValues({});

    final contacts = await EmergencyService.instance.loadContacts(userId: 7);

    expect(contacts, isEmpty);
  });

  test('theme mode selection persists across reloads', () async {
    SharedPreferences.setMockInitialValues({});
    final themes = AppThemeService.instance;

    await themes.setThemeMode(ThemeMode.dark);
    expect(themes.themeMode.value, ThemeMode.dark);

    themes.themeMode.value = ThemeMode.system;
    await themes.load();
    expect(themes.themeMode.value, ThemeMode.dark);

    await themes.setThemeMode(ThemeMode.light);
    expect(themes.themeMode.value, ThemeMode.light);

    await themes.setThemeMode(ThemeMode.system);
  });

  test('selected theme mode persists across app restarts', () async {
    SharedPreferences.setMockInitialValues({});
    final themes = AppThemeService.instance;

    await themes.setThemeMode(ThemeMode.dark);
    expect(themes.themeMode.value, ThemeMode.dark);

    themes.themeMode.value = ThemeMode.system;
    await themes.load();
    expect(themes.themeMode.value, ThemeMode.dark);

    await themes.setThemeMode(ThemeMode.light);
    expect(themes.themeMode.value, ThemeMode.light);
  });
}
