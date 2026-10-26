import 'package:flutter/material.dart';

import '../services/theme_service.dart';
import 'destination_screen.dart';
import 'history_screen.dart';
import 'notifications_screen.dart';

const Color _settingsPurple = Color(0xFF6C4DF6);

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeService.instance;

    return Scaffold(
      backgroundColor: theme.pageBackground,
      appBar: AppBar(
        backgroundColor: theme.pageBackground,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back, color: theme.primaryText),
        ),
        title: Text(
          'Settings & Preferences',
          style: TextStyle(
            color: theme.primaryText,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _SettingsSection(
              title: 'Appearance',
              child: ValueListenableBuilder<ThemeMode>(
                valueListenable: theme.themeMode,
                builder: (context, mode, _) => Column(
                  children: [
                    _ThemeOption(
                      title: 'System default',
                      icon: Icons.settings_suggest_outlined,
                      selected: mode == ThemeMode.system,
                      onTap: () => _setTheme(context, ThemeMode.system),
                    ),
                    const Divider(height: 1),
                    _ThemeOption(
                      title: 'Light',
                      icon: Icons.light_mode_outlined,
                      selected: mode == ThemeMode.light,
                      onTap: () => _setTheme(context, ThemeMode.light),
                    ),
                    const Divider(height: 1),
                    _ThemeOption(
                      title: 'Dark',
                      icon: Icons.dark_mode_outlined,
                      selected: mode == ThemeMode.dark,
                      onTap: () => _setTheme(context, ThemeMode.dark),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            _SettingsSection(
              title: 'Your app',
              child: Column(
                children: [
                  _SettingsLink(
                    icon: Icons.notifications_outlined,
                    title: 'Notification Center',
                    subtitle: 'Review arrival alerts and wake-up logs',
                    onTap: () =>
                        _openScreen(context, const NotificationsScreen()),
                  ),
                  const Divider(height: 1),
                  _SettingsLink(
                    icon: Icons.bookmark_border,
                    title: 'Saved Destinations',
                    subtitle: 'Manage your saved places',
                    onTap: () =>
                        _openScreen(context, const DestinationScreen()),
                  ),
                  const Divider(height: 1),
                  _SettingsLink(
                    icon: Icons.history,
                    title: 'Journey History',
                    subtitle: 'Review your previous journeys',
                    onTap: () => _openScreen(context, const HistoryScreen()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _SettingsBottomNavigation(theme: theme),
    );
  }

  Future<void> _setTheme(BuildContext context, ThemeMode mode) async {
    try {
      await AppThemeService.instance.setThemeMode(mode);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Could not save the appearance preference: $error'),
            backgroundColor: Colors.redAccent,
          ),
        );
    }
  }

  void _openScreen(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _SettingsSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeService.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title,
            style: TextStyle(
              color: theme.secondaryText,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(color: Colors.transparent, child: child),
        ),
      ],
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeService.instance;
    return ListTile(
      leading: Icon(icon, color: _settingsPurple),
      title: Text(title, style: TextStyle(color: theme.primaryText)),
      trailing: selected
          ? const Icon(Icons.check_circle, color: _settingsPurple)
          : Icon(Icons.circle_outlined, color: theme.mutedText),
      onTap: onTap,
    );
  }
}

class _SettingsLink extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsLink({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeService.instance;
    return ListTile(
      leading: Icon(icon, color: _settingsPurple),
      title: Text(
        title,
        style: TextStyle(color: theme.primaryText, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle, style: TextStyle(color: theme.secondaryText)),
      trailing: Icon(Icons.chevron_right, color: theme.mutedText),
      onTap: onTap,
    );
  }
}

class _SettingsBottomNavigation extends StatelessWidget {
  final AppThemeService theme;

  const _SettingsBottomNavigation({required this.theme});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _BottomNavigationItem(
              icon: Icons.home_filled,
              label: 'Home',
              onTap: () =>
                  Navigator.popUntil(context, (route) => route.isFirst),
            ),
            _BottomNavigationItem(
              icon: Icons.map_outlined,
              label: 'Journeys',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const HistoryScreen()),
              ),
            ),
            _BottomNavigationItem(
              icon: Icons.bookmark_border,
              label: 'Saved Places',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const DestinationScreen(),
                ),
              ),
            ),
            _BottomNavigationItem(
              icon: Icons.person_outline,
              label: 'Profile',
              selected: true,
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavigationItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BottomNavigationItem({
    required this.icon,
    required this.label,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? _settingsPurple
        : AppThemeService.instance.mutedText;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 27),
            const SizedBox(height: 5),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 5),
            Container(
              width: selected ? 34 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: selected ? _settingsPurple : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
