import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_guardian/screens/map_screen.dart';
import 'package:smartbus_guardian/services/emergency_service.dart';

void main() {
  group('Route Deviation and Missed-Stop Logic Tests', () {
    test('isRouteDeviated triggers only beyond 300 meters threshold', () {
      expect(isRouteDeviated(0.0), isFalse);
      expect(isRouteDeviated(150.0), isFalse);
      expect(isRouteDeviated(300.0), isFalse);
      expect(isRouteDeviated(300.1), isTrue);
      expect(isRouteDeviated(500.0), isTrue);
    });

    test('isMissedStopConfirmed requires alert fired, distance >= 400m, and >= 2 increasing fixes', () {
      // Alert not fired yet
      expect(
        isMissedStopConfirmed(
          destinationAlertFired: false,
          distanceMeters: 450.0,
          increasingDistanceFixes: 3,
        ),
        isFalse,
      );

      // Distance below 400m
      expect(
        isMissedStopConfirmed(
          destinationAlertFired: true,
          distanceMeters: 399.0,
          increasingDistanceFixes: 3,
        ),
        isFalse,
      );

      // Fewer than 2 increasing fixes
      expect(
        isMissedStopConfirmed(
          destinationAlertFired: true,
          distanceMeters: 450.0,
          increasingDistanceFixes: 1,
        ),
        isFalse,
      );

      // All conditions satisfied
      expect(
        isMissedStopConfirmed(
          destinationAlertFired: true,
          distanceMeters: 400.0,
          increasingDistanceFixes: 2,
        ),
        isTrue,
      );

      expect(
        isMissedStopConfirmed(
          destinationAlertFired: true,
          distanceMeters: 600.0,
          increasingDistanceFixes: 4,
        ),
        isTrue,
      );
    });
  });

  group('Helpline Filtering & Emergency SMS Formatting Tests', () {
    test('isEmergencyHelplinePhoneNumber identifies national emergency codes', () {
      expect(isEmergencyHelplinePhoneNumber('112'), isTrue);
      expect(isEmergencyHelplinePhoneNumber('100'), isTrue);
      expect(isEmergencyHelplinePhoneNumber('108'), isTrue);
      expect(isEmergencyHelplinePhoneNumber('1091'), isTrue);
      expect(isEmergencyHelplinePhoneNumber('911'), isTrue);
      expect(isEmergencyHelplinePhoneNumber('999'), isTrue);
      expect(isEmergencyHelplinePhoneNumber('000'), isTrue);
      expect(isEmergencyHelplinePhoneNumber('+91 100'), isTrue);
      expect(isEmergencyHelplinePhoneNumber('0091108'), isTrue);
    });

    test('isEmergencyHelplinePhoneNumber does not block valid mobile numbers', () {
      expect(isEmergencyHelplinePhoneNumber('9876543210'), isFalse);
      expect(isEmergencyHelplinePhoneNumber('+919876543210'), isFalse);
      expect(isEmergencyHelplinePhoneNumber('+91 94471 23456'), isFalse);
      expect(isEmergencyHelplinePhoneNumber('919876543210'), isFalse);
      expect(isEmergencyHelplinePhoneNumber('9112345678'), isFalse);
    });

    test('buildSosSmsUri formats correct URI and filters emergency numbers', () {
      final uri = buildSosSmsUri(
        ['100', '9876543210', '+919998887776'],
        'Emergency at GPS 9.93, 76.26',
        platform: TargetPlatform.android,
      );

      expect(uri.scheme, 'sms');
      // Helpline '100' must be filtered out
      expect(uri.path.contains('100'), isFalse);
      expect(uri.path.contains('9876543210'), isTrue);
      expect(uri.queryParameters['body'], 'Emergency at GPS 9.93, 76.26');
    });
  });
}
