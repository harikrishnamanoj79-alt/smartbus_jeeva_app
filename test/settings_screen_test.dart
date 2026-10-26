import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbus_guardian/screens/profile_screen.dart';
import 'package:smartbus_guardian/services/theme_service.dart';

void main() {
  testWidgets('profile opens Settings and back returns to Profile', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
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

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings & Preferences'), findsOneWidget);
    expect(find.text('System default'), findsOneWidget);
    expect(find.text('Notification Center'), findsOneWidget);
    expect(find.text('Saved Destinations'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(themes.themeMode.value, ThemeMode.dark);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Passenger Profile'), findsOneWidget);

    await themes.setThemeMode(ThemeMode.system);
  });
}
