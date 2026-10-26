import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smartbus_guardian/screens/map_screen.dart';
import 'package:smartbus_guardian/services/api_service.dart';
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

  group('Phone Number Matching & Contact Sync Tests', () {
    test('matchesPhoneNumber matches identical and formatted numbers', () {
      expect(matchesPhoneNumber('9876543210', '9876543210'), isTrue);
      expect(matchesPhoneNumber('+91 98765 43210', '9876543210'), isTrue);
      expect(matchesPhoneNumber('9876543210', '+919876543210'), isTrue);
    });

    test('matchesPhoneNumber rejects empty, invalid, and short suffix numbers', () {
      expect(matchesPhoneNumber('', ''), isFalse);
      expect(matchesPhoneNumber('abc', 'def'), isFalse);
      expect(matchesPhoneNumber('', '9876543210'), isFalse);
      expect(matchesPhoneNumber('9876543210', ''), isFalse);
      // '100' must NOT match '9876543100' because '100' is < 7 digits
      expect(matchesPhoneNumber('100', '9876543100'), isFalse);
      expect(matchesPhoneNumber('9876543100', '100'), isFalse);
    });
  });

  group('ApiService 401 Authorization Hook Tests', () {
    test('onUnauthorized hook is NOT called on 401 for login or register endpoints', () {
      bool hookCalled = false;
      ApiService.onUnauthorized = () {
        hookCalled = true;
      };
      ApiService.setJwtToken('test-token');

      final response401 = http.Response('{"error": "Invalid credentials"}', 401);

      // Auth endpoint call (login / register)
      ApiService.checkResponseForTesting(response401, isAuthEndpoint: true);
      expect(hookCalled, isFalse);
      // Token must not be cleared
      expect(ApiService.jwtToken, 'test-token');

      // Clean up
      ApiService.setJwtToken(null);
      ApiService.onUnauthorized = null;
    });

    test('onUnauthorized hook is NOT called on 401 when no token was provided', () {
      bool hookCalled = false;
      ApiService.onUnauthorized = () {
        hookCalled = true;
      };
      ApiService.setJwtToken(null);

      final response401 = http.Response('{"error": "Unauthorized"}', 401);

      ApiService.checkResponseForTesting(response401, isAuthEndpoint: false);
      expect(hookCalled, isFalse);

      ApiService.onUnauthorized = null;
    });

    test('onUnauthorized hook IS called on 401 for authenticated endpoints with active token', () {
      bool hookCalled = false;
      ApiService.onUnauthorized = () {
        hookCalled = true;
      };
      ApiService.setJwtToken('expired-valid-token');

      final response401 = http.Response('{"error": "Token expired"}', 401);

      ApiService.checkResponseForTesting(response401, isAuthEndpoint: false);
      expect(hookCalled, isTrue);
      // Token must be cleared
      expect(ApiService.jwtToken, isNull);

      ApiService.onUnauthorized = null;
    });
  });
}
