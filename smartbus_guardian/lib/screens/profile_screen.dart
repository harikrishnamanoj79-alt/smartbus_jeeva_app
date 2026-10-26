import 'package:flutter/material.dart';

import 'destination_screen.dart';
import 'history_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import '../services/theme_service.dart';
import '../services/auth_service.dart';

const Color kProfilePurple = Color(0xFF6C4DF6);
const Color _pageBlue = Color(0xFFEAF3FC);
const Color _navy = Color(0xFF10275D);
const Color _muted = Color(0xFF8196B5);
const Color _teal = Color(0xFF16A69A);
const Color _logoutRed = Color(0xFFFF365A);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? fullName;
  String? email;
  String? phoneNumber;
  int? userId;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final user = await AuthService.instance.getCurrentUser();
      if (!mounted) return;

      setState(() {
        if (user != null) {
          fullName = _profileUsername(user);
          email = _firstNonEmpty(user, ['email']);
          phoneNumber = _firstNonEmpty(user, ['phone', 'phone_number']);
          final rawId = user['id'];
          userId = rawId is int ? rawId : int.tryParse('$rawId');
        } else {
          fullName = null;
          email = null;
          phoneNumber = null;
          userId = null;
          _loadError = 'No logged-in user found. Please log in again.';
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Could not load your profile. Please try again.';
      });
    }
  }

  String? _firstNonEmpty(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String _profileUsername(Map<String, dynamic> user) {
    String? usableName(String? value) {
      final name = value?.trim();
      if (name == null ||
          name.isEmpty ||
          const {
            'passenger',
            'null',
            'undefined',
          }.contains(name.toLowerCase())) {
        return null;
      }
      return name;
    }

    String? accountName(List<String> keys) {
      return usableName(_firstNonEmpty(user, keys));
    }

    final email = accountName(['email']);
    return accountName(['username']) ??
        accountName(['display_name', 'displayName']) ??
        accountName(['name', 'full_name']) ??
        usableName(email?.split('@').first) ??
        'User';
  }

  @override
  Widget build(BuildContext context) {
    final background = _pageBackground();

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: kProfilePurple),
              )
            : RefreshIndicator(
                color: kProfilePurple,
                onRefresh: _loadUserProfile,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _buildHeader(),
                          const SizedBox(height: 22),
                          if (_loadError != null) ...[
                            _buildErrorCard(),
                            const SizedBox(height: 16),
                          ],
                          _buildProfileCard(),
                          const SizedBox(height: 26),
                          _buildMenuCard(),
                          const SizedBox(height: 22),
                          Center(
                            child: TextButton.icon(
                              onPressed: _logout,
                              icon: const Icon(
                                Icons.logout,
                                color: _logoutRed,
                                size: 22,
                              ),
                              label: const Text(
                                'Log Out of SmartBus Guardian',
                                style: TextStyle(
                                  color: _logoutRed,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
      ),
      bottomNavigationBar: _buildBottomNavigation(),
    );
  }

  Color _pageBackground() {
    try {
      return AppThemeService.instance.pageBackground;
    } catch (_) {
      return _pageBlue;
    }
  }

  Color _surfaceColor() {
    try {
      return AppThemeService.instance.surface;
    } catch (_) {
      return Colors.white;
    }
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Profile',
            style: TextStyle(
              color: _primaryText(),
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Settings',
          onPressed: _openSettings,
          icon: Icon(Icons.settings_outlined, color: _primaryText(), size: 30),
        ),
      ],
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: kProfilePurple),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_loadError!, style: TextStyle(color: _primaryText())),
          ),
          TextButton(onPressed: _loadUserProfile, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    final name = fullName?.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 25),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFECE6FF),
                ),
                child: Icon(Icons.person, size: 64, color: kProfilePurple),
              ),
              Positioned(
                right: -2,
                bottom: 0,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    color: _teal,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 21),
                ),
              ),
            ],
          ),
          const SizedBox(height: 23),
          Text(
            name == null || name.isEmpty ? 'User' : name,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _primaryText(),
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _displayOrUnavailable(email),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 17),
          ),
          const SizedBox(height: 7),
          Text(
            _displayOrUnavailable(phoneNumber),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 16),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              const Expanded(
                child: _ProfileStat(value: '—', label: 'Trips', color: _teal),
              ),
              const _StatDivider(),
              const Expanded(
                child: _ProfileStat(
                  value: '—',
                  label: 'Total Distance',
                  color: _navy,
                ),
              ),
              const _StatDivider(),
              const Expanded(
                child: _ProfileStat(
                  value: '—',
                  label: 'Safe Arrival',
                  color: _teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.center,
            child: OutlinedButton.icon(
              onPressed: _editProfile,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit Profile'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kProfilePurple,
                side: const BorderSide(color: kProfilePurple),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _displayOrUnavailable(String? value) {
    if (value == null || value.trim().isEmpty) return 'Not provided';
    return value.trim();
  }

  Widget _buildMenuCard() {
    return Container(
      decoration: _cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _MenuRow(
            icon: Icons.map_outlined,
            title: 'All Journeys History',
            subtitle: 'Review routes, missed stops & durations',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),
          const _MenuDivider(),
          _MenuRow(
            icon: Icons.lock_outline,
            title: 'Change Password',
            subtitle: 'Update your account password',
            onTap: _changePassword,
          ),
          const _MenuDivider(),
          _MenuRow(
            icon: Icons.bookmark_border,
            title: 'Saved Destinations',
            subtitle: 'Manage home, office & transit stops',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DestinationScreen()),
              );
            },
          ),
          const _MenuDivider(),
          _MenuRow(
            icon: Icons.notifications_none,
            title: 'Notification Center',
            subtitle: 'Arrival alerts and wake-up logs',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
          ),
          const _MenuDivider(),
          _MenuRow(
            icon: Icons.tune,
            title: 'Settings & Preferences',
            subtitle: 'Theme, notifications & app preferences',
            onTap: _openSettings,
            last: true,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: _surfaceColor(),
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
            _BottomNavItem(
              icon: Icons.home_filled,
              label: 'Home',
              selected: false,
              onTap: () =>
                  Navigator.popUntil(context, (route) => route.isFirst),
            ),
            _BottomNavItem(
              icon: Icons.map_outlined,
              label: 'Journeys',
              selected: false,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              ),
            ),
            _BottomNavItem(
              icon: Icons.bookmark_border,
              label: 'Saved Places',
              selected: false,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DestinationScreen()),
              ),
            ),
            _BottomNavItem(
              icon: Icons.person_outline,
              label: 'Profile',
              selected: true,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: _surfaceColor(),
      borderRadius: BorderRadius.circular(28),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF294A70).withValues(alpha: 0.07),
          blurRadius: 18,
          offset: const Offset(0, 7),
        ),
      ],
    );
  }

  Color _primaryText() {
    try {
      return AppThemeService.instance.primaryText;
    } catch (_) {
      return _navy;
    }
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  Future<void> _editProfile() async {
    final nameController = TextEditingController(text: fullName ?? '');
    final emailController = TextEditingController(text: email ?? '');
    final phoneController = TextEditingController(text: phoneNumber ?? '');
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Profile'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  validator: (value) => value == null || value.trim().length < 2
                      ? 'Enter your full name'
                      : null,
                  decoration: const InputDecoration(labelText: 'Full Name'),
                ),
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) =>
                      value == null ||
                          !RegExp(
                            r'^[\w.-]+@[\w.-]+\.[A-Za-z]{2,}$',
                          ).hasMatch(value.trim())
                      ? 'Enter a valid email address'
                      : null,
                  decoration: const InputDecoration(labelText: 'Email Address'),
                ),
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  validator: (value) =>
                      value == null || value.trim().length < 10
                      ? 'Enter a valid phone number'
                      : null,
                  decoration: const InputDecoration(labelText: 'Phone Number'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        final updatedName = nameController.text.trim();
        final updatedEmail = emailController.text.trim();
        final updatedPhone = phoneController.text.trim();

        final success = await AuthService.instance.updateProfile(
          name: updatedName,
          email: updatedEmail,
          phone: updatedPhone,
        );

        if (!mounted) return;
        if (success) {
          setState(() {
            fullName = updatedName;
            email = updatedEmail;
            phoneNumber = updatedPhone;
          });
          _showMessage('Profile updated successfully.');
        } else {
          _showMessage('Could not update profile.', isError: true);
        }
      } catch (e) {
        if (mounted) {
          _showMessage('Could not update profile.', isError: true);
        }
      }
    }

    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
  }

  Future<void> _changePassword() async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Change Password'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: currentController,
                  obscureText: true,
                  validator: (value) => value == null || value.isEmpty
                      ? 'Enter current password'
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Current Password',
                  ),
                ),
                TextFormField(
                  controller: newController,
                  obscureText: true,
                  validator: (value) => value == null || value.length < 6
                      ? 'Use at least 6 characters'
                      : null,
                  decoration: const InputDecoration(labelText: 'New Password'),
                ),
                TextFormField(
                  controller: confirmController,
                  obscureText: true,
                  validator: (value) => value != newController.text
                      ? 'Passwords do not match'
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Confirm Password',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final error = await AuthService.instance.changePassword(
                currentPassword: currentController.text,
                newPassword: newController.text,
              );
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (error != null) {
                _showMessage(error, isError: true);
              } else {
                _showMessage('Password changed successfully.');
              }
            },
            child: const Text('Update Password'),
          ),
        ],
      ),
    );

    currentController.dispose();
    newController.dispose();
    confirmController.dispose();
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text(
          'Are you sure you want to log out of SmartBus Guardian?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await AuthService.instance.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.redAccent : Colors.green.shade700,
        ),
      );
  }
}

class _ProfileStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _ProfileStat({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontSize: 13),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 45,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      color: const Color(0xFFD7E1F3),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool last;

  const _MenuRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 17),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0EBFF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, color: kProfilePurple, size: 29),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(color: _muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: _muted, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, thickness: 1, color: Color(0xFFE2EAF7));
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? kProfilePurple : _muted;
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
                color: selected ? kProfilePurple : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
