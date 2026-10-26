import 'package:flutter/material.dart';
import 'destination_screen.dart';
import 'history_screen.dart';
import 'map_screen.dart';
import 'sos_screen.dart';
import 'sleep_mode_screen.dart';
import 'profile_screen.dart';
import 'notifications_screen.dart';
import '../services/journey_service.dart';
import '../services/theme_service.dart';
import '../services/auth_service.dart';

const Color kPrimaryPurple = Color(0xFF6C4DF6);
Color get kBackground => AppThemeService.instance.pageBackground;
Color get kCardWhite => AppThemeService.instance.surface;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool sleepMode = false;

  Duration sleepAlarmInterval = const Duration(seconds: 12);

  bool journeyActive = false;

  double? activeRemainingMeters;

  String? activeDestinationName;

  String? userName;
  int? userId;

  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final user = await AuthService.instance.getCurrentUser();
    final active = await JourneyService.instance.getActiveJourney();

    if (mounted) {
      setState(() {
        if (user != null) {
          var rawName = (user['username'] ?? user['name'] ?? user['full_name'])?.toString().trim();
          // Treat placeholder "Passenger" as missing name
          if (rawName != null && rawName.toLowerCase() == 'passenger') {
            userName = null;
          } else {
            userName = rawName;
          }
          userId = user['id'] is int
              ? user['id'] as int
              : int.tryParse(user['id']?.toString() ?? '1') ?? 1;
        }
        if (active != null && active.status == 'IN_PROGRESS') {
          journeyActive = true;
          activeDestinationName = active.destinationName;
          activeRemainingMeters = active.distanceKm != null
              ? active.distanceKm! * 1000
              : null;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              _buildHeader(),

              const SizedBox(height: 24),

              journeyActive
                  ? _buildActiveJourneyCard()
                  : _buildStartJourneyCard(),

              const SizedBox(height: 20),

              _buildSleepModeCard(),

              const SizedBox(height: 24),

              Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppThemeService.instance.primaryText,
                ),
              ),

              const SizedBox(height: 12),

              _buildQuickActionsGrid(),

              const SizedBox(height: 24),

              Text(
                'Saved Destinations',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppThemeService.instance.primaryText,
                ),
              ),

              const SizedBox(height: 12),

              _buildSavedDestinations(),
            ],
          ),
        ),
      ),

      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader() {
    final displayName = (userName != null && userName!.isNotEmpty)
        ? 'Hi, $userName 👋'
        : 'Hi 👋';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,

      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            Text(
              displayName,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppThemeService.instance.primaryText,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              'Stay safe on your journey',
              style: TextStyle(
                fontSize: 13,
                color: AppThemeService.instance.secondaryText,
              ),
            ),
          ],
        ),

        Container(
          decoration: BoxDecoration(
            color: kCardWhite,
            shape: BoxShape.circle,

            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),

          child: IconButton(
            icon: const Icon(
              Icons.notifications_outlined,
              color: kPrimaryPurple,
            ),

            tooltip: 'Notifications',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
          ),
        ),
      ],
    );
  }

  // ============================================================
  // APPLY MAP RESULT
  // ============================================================

  void _applyMapResult(Map<String, dynamic>? result) {
    if (!mounted || result == null) {
      return;
    }

    if (result['journeyCompleted'] == true) {
      setState(() {
        journeyActive = false;
        activeRemainingMeters = null;
        activeDestinationName = null;
      });
      return;
    }

    setState(() {
      journeyActive = true;

      if (result['remainingMeters'] is num) {
        activeRemainingMeters = (result['remainingMeters'] as num).toDouble();
      } else {
        activeRemainingMeters = null;
      }

      final destination = result['destination'];

      if (destination is Destination) {
        activeDestinationName = destination.name;
      } else if (result['destinationName'] != null) {
        activeDestinationName = result['destinationName'].toString();
      } else {
        activeDestinationName = null;
      }
    });
  }

  // ============================================================
  // START JOURNEY
  // ============================================================

  Future<void> _startJourneyFlow() async {
    final plan = await Navigator.push<JourneyPlan>(
      context,
      MaterialPageRoute(builder: (context) => const JourneyPlannerScreen()),
    );

    if (!mounted || plan == null) return;

    final result = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(
        builder: (context) => MapScreen(
          sleepMode: sleepMode,
          sleepInterval: sleepAlarmInterval,
          startingPoint: plan.origin,
          initialDestination: plan.destination,
        ),
      ),
    );

    _applyMapResult(result);
  }

  Future<void> _openLiveJourney() async {
    if (!journeyActive) {
      await _startJourneyFlow();
      return;
    }

    final result = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MapScreen(sleepMode: sleepMode, sleepInterval: sleepAlarmInterval),
      ),
    );

    if (!mounted) return;
    _applyMapResult(result);
  }

  // ============================================================
  // START JOURNEY CARD
  // ============================================================

  Widget _buildStartJourneyCard() {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kPrimaryPurple, Color(0xFF8E7CF3)],

          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),

        borderRadius: BorderRadius.circular(20),

        boxShadow: [
          BoxShadow(
            color: kPrimaryPurple.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          const Row(
            children: [
              Icon(Icons.directions_bus_filled, color: Colors.white, size: 26),

              SizedBox(width: 8),

              Text(
                'No active journey',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          const Text(
            'Choose a FROM point, select a TO destination, and\nstart live route tracking.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,

            child: ElevatedButton.icon(
              onPressed: _startJourneyFlow,

              icon: const Icon(
                Icons.add_location_alt_outlined,
                color: kPrimaryPurple,
              ),

              label: const Text(
                'Start Journey',
                style: TextStyle(
                  color: kPrimaryPurple,
                  fontWeight: FontWeight.w600,
                ),
              ),

              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,

                padding: const EdgeInsets.symmetric(vertical: 14),

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),

                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ACTIVE JOURNEY CARD
  // ============================================================

  Widget _buildActiveJourneyCard() {
    final remainingKm = activeRemainingMeters != null
        ? (activeRemainingMeters! / 1000).toStringAsFixed(1)
        : '--';

    final displayName = activeDestinationName;

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: kCardWhite,

        borderRadius: BorderRadius.circular(20),

        border: Border.all(color: kPrimaryPurple.withValues(alpha: 0.15)),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),

                decoration: BoxDecoration(
                  color: kPrimaryPurple.withValues(alpha: 0.12),

                  shape: BoxShape.circle,
                ),

                child: const Icon(Icons.gps_fixed, color: kPrimaryPurple),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      displayName == null
                          ? 'Journey active'
                          : 'Tracking to $displayName',

                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),

                    const SizedBox(height: 2),
                    Text(
                      'Live journey in progress',
                      style: TextStyle(
                        color: AppThemeService.instance.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),
          Row(
            children: [
              _buildStat('$remainingKm km', 'Remaining'),

              _buildStat('--', 'ETA'),

              _buildStat('Active', 'Status'),
            ],
          ),

          const SizedBox(height: 8),

          ClipRRect(
            borderRadius: BorderRadius.circular(8),

            child: const LinearProgressIndicator(
              value: null,
              minHeight: 6,
              backgroundColor: Color(0x226C4DF6),
              color: kPrimaryPurple,
            ),
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final result = await Navigator.push<Map<String, dynamic>?>(
                      context,

                      MaterialPageRoute(
                        builder: (context) => MapScreen(
                          sleepMode: sleepMode,
                          sleepInterval: sleepAlarmInterval,
                        ),
                      ),
                    );

                    if (!mounted) return;

                    _applyMapResult(result);
                  },

                  style: OutlinedButton.styleFrom(
                    foregroundColor: kPrimaryPurple,

                    side: const BorderSide(color: kPrimaryPurple),

                    padding: const EdgeInsets.symmetric(vertical: 12),

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),

                  child: const Text('View Map'),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await JourneyService.instance.endJourney(
                      completed: true,
                      finalDistanceKm: activeRemainingMeters != null
                          ? activeRemainingMeters! / 1000
                          : 5.0,
                    );

                    if (mounted) {
                      setState(() {
                        journeyActive = false;
                        activeRemainingMeters = null;
                        activeDestinationName = null;
                      });
                      _showMessage('Journey ended and saved to History.');
                    }
                  },

                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,

                    side: const BorderSide(color: Colors.redAccent),

                    padding: const EdgeInsets.symmetric(vertical: 12),

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),

                  child: const Text('End Journey'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STAT
  // ============================================================

  Widget _buildStat(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,

            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),

          const SizedBox(height: 2),

          Text(
            label,

            style: TextStyle(
              fontSize: 11,
              color: AppThemeService.instance.secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SLEEP MODE
  // ============================================================

  Future<void> _openSleepModeSettings() async {
    final result = await Navigator.push<SleepModeSettings>(
      context,

      MaterialPageRoute(
        builder: (context) => SleepModeScreen(
          initialEnabled: sleepMode,
          initialInterval: sleepAlarmInterval,
        ),
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      sleepMode = result.enabled;

      sleepAlarmInterval = result.alarmInterval;
    });
  }

  Widget _buildSleepModeCard() {
    return Material(
      color: kCardWhite,

      borderRadius: BorderRadius.circular(16),

      child: InkWell(
        borderRadius: BorderRadius.circular(16),

        onTap: _openSleepModeSettings,

        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),

          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),

            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),

                blurRadius: 10,

                offset: const Offset(0, 3),
              ),
            ],
          ),

          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),

                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.1),

                  shape: BoxShape.circle,
                ),

                child: Icon(
                  Icons.bedtime_outlined,

                  color: sleepMode
                      ? kPrimaryPurple
                      : AppThemeService.instance.mutedText,
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    const Text(
                      'Sleep Mode',

                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),

                    Text(
                      sleepMode
                          ? 'Alarm repeats every ${sleepAlarmInterval.inSeconds}s · tap to configure'
                          : 'Repeated alarms to wake you before your stop',

                      style: TextStyle(
                        fontSize: 11,
                        color: AppThemeService.instance.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),

              Switch(
                value: sleepMode,

                activeThumbColor: kPrimaryPurple,

                onChanged: (value) {
                  setState(() {
                    sleepMode = value;
                  });
                },
              ),

              Icon(
                Icons.chevron_right,
                color: AppThemeService.instance.mutedText,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // QUICK ACTIONS
  // ============================================================

  Widget _buildQuickActionsGrid() {
    final actions = [
      {'icon': Icons.bookmark_border, 'label': 'Saved\nStops'},
      {'icon': Icons.map_outlined, 'label': 'Live\nMap'},
      {'icon': Icons.sos, 'label': 'Emergency\nSOS'},
    ];

    return GridView.builder(
      shrinkWrap: true,

      physics: const NeverScrollableScrollPhysics(),

      itemCount: actions.length,

      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,

        mainAxisSpacing: 10,

        crossAxisSpacing: 10,

        childAspectRatio: 0.75,
      ),

      itemBuilder: (context, index) {
        final action = actions[index];

        final isSos = action['label'] == 'Emergency\nSOS';

        return InkWell(
          onTap: () async {
            switch (index) {
              case 0:
                await Navigator.push(
                  context,

                  MaterialPageRoute(builder: (_) => const DestinationScreen()),
                );
                break;

              case 1:
                await _openLiveJourney();
                break;

              case 2:
                await Navigator.push(
                  context,

                  MaterialPageRoute(builder: (_) => const SosScreen()),
                );
                break;
            }
          },

          borderRadius: BorderRadius.circular(16),

          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),

            decoration: BoxDecoration(
              color: isSos ? Colors.red.withValues(alpha: 0.08) : kCardWhite,

              borderRadius: BorderRadius.circular(16),

              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),

                  blurRadius: 8,

                  offset: const Offset(0, 3),
                ),
              ],
            ),

            child: Column(
              children: [
                Icon(
                  action['icon'] as IconData,

                  color: isSos ? Colors.redAccent : kPrimaryPurple,
                ),

                const SizedBox(height: 6),

                Text(
                  action['label'] as String,

                  textAlign: TextAlign.center,

                  style: TextStyle(
                    fontSize: 10.5,

                    fontWeight: FontWeight.w500,

                    color: isSos
                        ? Colors.redAccent
                        : AppThemeService.instance.primaryText,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // SAVED DESTINATIONS
  // ============================================================

  Widget _buildSavedDestinations() {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: kCardWhite,

        borderRadius: BorderRadius.circular(16),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),

            blurRadius: 8,

            offset: const Offset(0, 3),
          ),
        ],
      ),

      child: Column(
        children: [
          const Icon(
            Icons.location_on_outlined,
            size: 40,
            color: kPrimaryPurple,
          ),

          const SizedBox(height: 10),

          const Text(
            'No saved destinations',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),

          const SizedBox(height: 5),

          Text(
            'Your saved destinations will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppThemeService.instance.secondaryText,
            ),
          ),

          const SizedBox(height: 14),

          OutlinedButton.icon(
            onPressed: () async {
              await Navigator.push(
                context,

                MaterialPageRoute(builder: (_) => const DestinationScreen()),
              );
            },

            icon: const Icon(Icons.add_location_alt_outlined),

            label: const Text('Add Destination'),

            style: OutlinedButton.styleFrom(
              foregroundColor: kPrimaryPurple,

              side: const BorderSide(color: kPrimaryPurple),

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BOTTOM NAVIGATION
  // ============================================================

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _navIndex,

      onTap: (index) async {
        switch (index) {
          // ----------------------------------------------------
          // HOME
          // ----------------------------------------------------

          case 0:
            setState(() {
              _navIndex = 0;
            });
            break;

          // ----------------------------------------------------
          // JOURNEY
          // ----------------------------------------------------

          case 1:
            await _openLiveJourney();

            if (!mounted) return;

            setState(() {
              _navIndex = 0;
            });

            break;

          // ----------------------------------------------------
          // HISTORY
          // ----------------------------------------------------

          case 2:
            await Navigator.push(
              context,

              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            );

            if (!mounted) return;

            setState(() {
              _navIndex = 0;
            });

            break;

          // ----------------------------------------------------
          // PROFILE
          // ----------------------------------------------------

          case 3:
            await Navigator.push(
              context,

              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            );

            if (!mounted) return;

            setState(() {
              _navIndex = 0;
            });

            break;
        }
      },

      selectedItemColor: kPrimaryPurple,

      unselectedItemColor: AppThemeService.instance.mutedText,

      showUnselectedLabels: true,

      type: BottomNavigationBarType.fixed,

      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),

        BottomNavigationBarItem(
          icon: Icon(Icons.map_outlined),
          label: 'Journey',
        ),

        BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),

        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
      ],
    );
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
