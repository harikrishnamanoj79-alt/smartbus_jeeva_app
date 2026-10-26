import 'package:flutter/material.dart';
import '../services/alert_service.dart';
import '../services/theme_service.dart';
import 'login_screen.dart'; // for kPrimaryPurple, kBackground, kCardWhite

/// Sleep Mode configuration returned to whoever pushed this screen
/// (HomeScreen), which then threads it through to MapScreen.
class SleepModeSettings {
  final bool enabled;
  final Duration alarmInterval;

  const SleepModeSettings({required this.enabled, required this.alarmInterval});

  static const List<Duration> availableIntervals = [
    Duration(seconds: 8),
    Duration(seconds: 12),
    Duration(seconds: 20),
    Duration(seconds: 30),
  ];
}

class SleepModeScreen extends StatefulWidget {
  final bool initialEnabled;
  final Duration initialInterval;

  const SleepModeScreen({
    super.key,
    this.initialEnabled = false,
    this.initialInterval = const Duration(seconds: 12),
  });

  @override
  State<SleepModeScreen> createState() => _SleepModeScreenState();
}

class _SleepModeScreenState extends State<SleepModeScreen> {
  late bool _enabled;
  late Duration _interval;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.initialEnabled;
    _interval = widget.initialInterval;
    AlertService.instance.init();
  }

  Future<void> _testAlarm() async {
    setState(() => _testing = true);
    await AlertService.instance.testAlert();
    if (!mounted) return;
    setState(() => _testing = false);
  }

  void _save() {
    Navigator.pop(
      context,
      SleepModeSettings(enabled: _enabled, alarmInterval: _interval),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        elevation: 0,
        iconTheme: IconThemeData(color: AppThemeService.instance.primaryText),
        title: Text(
          'Sleep Mode',
          style: TextStyle(
            color: AppThemeService.instance.primaryText,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ---- Enable toggle ----
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: kCardWhite,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kPrimaryPurple.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.bedtime_outlined,
                      color: _enabled
                          ? kPrimaryPurple
                          : AppThemeService.instance.mutedText,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Enable Sleep Mode',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppThemeService.instance.primaryText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Repeated alarms wake you before your stop',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppThemeService.instance.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _enabled,
                    activeThumbColor: kPrimaryPurple,
                    onChanged: (val) => setState(() => _enabled = val),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ---- Alarm interval ----
            Text(
              'Alarm repeat interval',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppThemeService.instance.primaryText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "How often the alarm repeats once you're near your stop, "
              "until you confirm you're awake.",
              style: TextStyle(
                fontSize: 12,
                color: AppThemeService.instance.secondaryText,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: SleepModeSettings.availableIntervals.map((d) {
                final selected = d == _interval;
                return ChoiceChip(
                  label: Text('${d.inSeconds}s'),
                  selected: selected,
                  onSelected: _enabled
                      ? (_) => setState(() => _interval = d)
                      : null,
                  selectedColor: kPrimaryPurple,
                  labelStyle: TextStyle(
                    color: selected
                        ? Colors.white
                        : AppThemeService.instance.primaryText,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: kCardWhite,
                );
              }).toList(),
            ),

            const SizedBox(height: 28),

            // ---- Test alarm ----
            OutlinedButton.icon(
              onPressed: _enabled && !_testing ? _testAlarm : null,
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.volume_up_outlined),
              label: Text(_testing ? 'Testing…' : 'Test Alarm'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kPrimaryPurple,
                side: const BorderSide(color: kPrimaryPurple),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryPurple,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Save',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
