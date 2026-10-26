import 'dart:async';

import 'package:flutter/material.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'services/journey_service.dart';
import 'services/theme_service.dart';
import 'services/background_tracking_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundTrackingService.instance.initialize();
  unawaited(AppThemeService.instance.load());
  runApp(const SmartBusGuardian());
}

class SmartBusGuardian extends StatelessWidget {
  final bool? isLoggedIn;

  const SmartBusGuardian({super.key, this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppThemeService.instance.themeMode,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'SmartBus Guardian',
          theme: AppThemeService.instance.lightTheme,
          darkTheme: AppThemeService.instance.darkTheme,
          themeMode: AppThemeService.instance.themeMode.value,
          home: isLoggedIn == null
              ? const _SplashScreen()
              : isLoggedIn!
              ? const HomeScreen()
              : const LoginScreen(),
        );
      },
    );
  }
}

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen> {
  static const _splashDuration = Duration(milliseconds: 1600);

  @override
  void initState() {
    super.initState();
    _prepareApp();
  }

  Future<void> _prepareApp() async {
    final minimumSplash = Future<void>.delayed(_splashDuration);
    unawaited(ApiService.testConnection());

    Map<String, dynamic>? user;
    final userFuture = AuthService.instance.getCurrentUser();
    try {
      await JourneyService.instance.init();
    } catch (error) {
      debugPrint('Journey startup initialization failed: $error');
    }
    try {
      user = await userFuture;
    } catch (error) {
      debugPrint('Session loading failed: $error');
    }

    await minimumSplash;
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => user == null ? const LoginScreen() : const HomeScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeService.instance.pageBackground,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: const Color(0xFF6C4DF6),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.directions_bus_filled_rounded,
                color: Colors.white,
                size: 46,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'SmartBus Guardian',
              style: TextStyle(
                color: AppThemeService.instance.primaryText,
                fontSize: 23,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF6C4DF6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
