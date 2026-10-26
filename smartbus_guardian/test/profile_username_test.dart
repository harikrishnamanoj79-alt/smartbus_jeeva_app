import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbus_guardian/screens/profile_screen.dart';

void main() {
  testWidgets('profile displays the logged-in username and contact details', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'smartbus_current_user_session_v2': jsonEncode({
        'username': 'Registered Username',
        'name': 'Different Display Name',
        'email': 'registered@example.com',
        'phone': '5551234567',
      }),
    });

    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == 'Profile' &&
            widget.style?.fontSize == 25,
      ),
      findsOneWidget,
    );
    expect(find.text('Registered Username'), findsOneWidget);
    expect(find.text('Different Display Name'), findsNothing);
    expect(find.text('registered@example.com'), findsOneWidget);
    expect(find.text('5551234567'), findsOneWidget);
    expect(find.textContaining('Passenger'), findsNothing);

    final usernameY = tester.getTopLeft(find.text('Registered Username')).dy;
    final emailY = tester.getTopLeft(find.text('registered@example.com')).dy;
    final phoneY = tester.getTopLeft(find.text('5551234567')).dy;
    expect(usernameY, lessThan(emailY));
    expect(emailY, lessThan(phoneY));
  });

  testWidgets('profile skips the Passenger placeholder for account username', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'smartbus_current_user_session_v2': jsonEncode({
        'username': 'Passenger',
        'name': 'Registered Username',
        'email': 'registered@example.com',
        'phone': '5551234567',
      }),
    });

    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Registered Username'), findsOneWidget);
    expect(find.text('Passenger'), findsNothing);
    expect(find.text('registered@example.com'), findsOneWidget);
    expect(find.text('5551234567'), findsOneWidget);
  });

  testWidgets('profile uses the requested username fallback order', (
    tester,
  ) async {
    final fallbackCases = [
      (
        user: {
          'username': '',
          'display_name': 'Display Name',
          'name': 'Authentication Name',
          'email': 'account@example.com',
        },
        expected: 'Display Name',
      ),
      (
        user: {
          'username': 'null',
          'display_name': '',
          'full_name': 'Authentication Name',
          'email': 'account@example.com',
        },
        expected: 'Authentication Name',
      ),
      (
        user: {
          'username': 'undefined',
          'display_name': ' ',
          'name': '',
          'email': 'krishna@gmail.com',
        },
        expected: 'krishna',
      ),
      (
        user: {
          'username': 'Passenger',
          'display_name': '',
          'name': 'null',
          'email': '',
        },
        expected: 'User',
      ),
    ];

    for (var index = 0; index < fallbackCases.length; index++) {
      final fallbackCase = fallbackCases[index];
      SharedPreferences.setMockInitialValues({
        'smartbus_current_user_session_v2': jsonEncode(fallbackCase.user),
      });

      await tester.pumpWidget(
        MaterialApp(home: ProfileScreen(key: ValueKey(index))),
      );
      await tester.pumpAndSettle();

      expect(find.text(fallbackCase.expected), findsOneWidget);
      expect(find.text('Name unavailable'), findsNothing);
      expect(find.text('null'), findsNothing);
      expect(find.text('undefined'), findsNothing);
    }
  });
}
