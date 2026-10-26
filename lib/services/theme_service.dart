import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeService {
  AppThemeService._();

  static final AppThemeService instance = AppThemeService._();
  static const _preferenceKey = 'smartbus_theme_mode_v1';

  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    themeMode.value = _parseMode(preferences.getString(_preferenceKey));
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, _modeName(mode));
  }

  ThemeMode _parseMode(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  String _modeName(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };

  bool get isDark {
    final mode = themeMode.value;
    if (mode == ThemeMode.dark) return true;
    if (mode == ThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  Color get pageBackground =>
      isDark ? const Color(0xFF11151D) : const Color(0xFFEAF2FB);

  Color get surface =>
      isDark ? const Color(0xFF202631) : const Color(0xFFF7F3FB);

  Color get primaryText =>
      isDark ? const Color(0xFFF4F6FA) : const Color(0xFF202124);

  Color get secondaryText =>
      isDark ? const Color(0xFFB8C0CC) : const Color(0xFF5F6368);

  Color get mutedText =>
      isDark ? const Color(0xFF929CAB) : const Color(0xFF777B82);

  ThemeData get lightTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6C4DF6),
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFEAF2FB),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFEAF2FB),
        foregroundColor: Color(0xFF202124),
      ),
    );
  }

  ThemeData get darkTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF9C8AFF),
      brightness: Brightness.dark,
      surface: const Color(0xFF202631),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF11151D),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF11151D),
        foregroundColor: Color(0xFFF4F6FA),
      ),
    );
  }
}
