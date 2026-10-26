import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import '../models/emergency_contact.dart';
import '../models/sos_record.dart';
import '../services/emergency_service.dart';
import '../services/theme_service.dart';
import 'auth_screen.dart';

const Color kPrimaryPurple = Color(0xFF6C4DF6);
Color get kBackground => AppThemeService.instance.pageBackground;
Color get kCardWhite => AppThemeService.instance.surface;
const Color kSosRed = Color(0xFFE53935);
const Color kSosRedLight = Color(0xFFFFEBEE);
const Color kSosRedGlow = Color(0xFFFF1744);
const Color kSafeGreen = Color(0xFF2E7D32);

String buildLocationShareMessage(double latitude, double longitude) {
  final coordinates =
      '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';
  final mapsUrl = Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': coordinates,
  });
  return 'My current location: $mapsUrl\nCoordinates: $coordinates';
}

class SosScreen extends StatefulWidget {
  final int? journeyId;
  final int userId;

  const SosScreen({super.key, this.journeyId, this.userId = 1});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen>
    with SingleTickerProviderStateMixin {
  final EmergencyService _emergencyService = EmergencyService.instance;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  Position? _currentPosition;
  bool _isLoadingLocation = false;
  bool _isSharingLocation = false;
  String? _locationError;

  List<EmergencyContact> _contacts = [];
  bool _isLoadingContacts = true;

  bool _isSosActive = false;
  bool _isSirenActive = false;

  // Accidental press countdown
  Timer? _countdownTimer;
  int _countdownSeconds = 3;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _isSosActive = _emergencyService.isSosTriggered;
    _isSirenActive = _emergencyService.isSirenActive;

    _emergencyService.sirenNotifier.addListener(_onSirenStateChanged);
    _emergencyService.sosActiveNotifier.addListener(_onSosStateChanged);

    _initData();
  }

  void _onSirenStateChanged() {
    if (mounted) {
      setState(() {
        _isSirenActive = _emergencyService.sirenNotifier.value;
      });
    }
  }

  void _onSosStateChanged() {
    if (mounted) {
      setState(() {
        _isSosActive = _emergencyService.sosActiveNotifier.value;
      });
    }
  }

  Future<void> _initData() async {
    await _emergencyService.init();
    await Future.wait([_fetchLocation(), _loadContacts()]);
  }

  Future<void> _fetchLocation() async {
    if (!mounted) return;
    setState(() {
      _isLoadingLocation = true;
      _locationError = null;
    });

    try {
      final pos = await _emergencyService.getCurrentLocation();
      if (mounted) {
        setState(() {
          _currentPosition = pos;
          _isLoadingLocation = false;
          if (pos == null) {
            _locationError =
                'Could not fetch GPS. Please ensure Location is ON.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          _locationError = 'GPS Error: $e';
        });
      }
    }
  }

  Future<void> _shareCurrentLocation() async {
    if (_isSharingLocation) return;
    setState(() {
      _isSharingLocation = true;
      _locationError = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Turn on GPS/location services and try again.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission was denied.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Location permission is disabled. Enable it in app settings.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;

      setState(() {
        _currentPosition = position;
        _locationError = null;
      });

      final result = await SharePlus.instance.share(
        ShareParams(
          text: buildLocationShareMessage(
            position.latitude,
            position.longitude,
          ),
        ),
      );

      if (result.status == ShareResultStatus.unavailable && mounted) {
        setState(() {
          _locationError = 'No sharing options are available on this device.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _locationError = error.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isSharingLocation = false);
    }
  }

  Future<void> _loadContacts({int? uid}) async {
    setState(() => _isLoadingContacts = true);
    try {
      final user = await AuthService.instance.getCurrentUser();
      final currentUid =
          uid ??
          (user?['id'] is int
              ? user!['id'] as int
              : (int.tryParse(user?['id']?.toString() ?? '${widget.userId}') ??
                    widget.userId));
      final list = await _emergencyService.loadContacts(userId: currentUid);
      if (mounted) {
        setState(() {
          _contacts = list;
          _isLoadingContacts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingContacts = false);
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _countdownTimer?.cancel();
    _emergencyService.sirenNotifier.removeListener(_onSirenStateChanged);
    _emergencyService.sosActiveNotifier.removeListener(_onSosStateChanged);
    super.dispose();
  }

  // ============================================================
  // SOS TRIGGER FLOW (WITH SAFETY COUNTDOWN)
  // ============================================================

  void _startSosCountdown() {
    HapticFeedback.heavyImpact();
    _countdownTimer?.cancel();
    _countdownSeconds = 3;

    StateSetter? dialogSetState;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds > 1) {
        _countdownSeconds--;
        if (dialogSetState != null) {
          dialogSetState!(() {});
        }
        if (mounted) setState(() {});
        HapticFeedback.mediumImpact();
      } else {
        timer.cancel();
        _countdownTimer = null;
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        _executeSosTrigger();
      }
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            dialogSetState = setDialogState;

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              backgroundColor: Colors.white,
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: kSosRed, size: 30),
                  SizedBox(width: 10),
                  Text(
                    'Triggering SOS!',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: kSosRed,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Emergency alert and siren will activate in:',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppThemeService.instance.primaryText,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: kSosRed.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: kSosRed, width: 3),
                    ),
                    child: Center(
                      child: Text(
                        '$_countdownSeconds',
                        style: const TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.bold,
                          color: kSosRed,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tap Cancel immediately if pressed by accident.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppThemeService.instance.secondaryText,
                    ),
                  ),
                ],
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          _countdownTimer?.cancel();
                          _countdownTimer = null;
                          Navigator.of(
                            dialogContext,
                            rootNavigator: true,
                          ).pop();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppThemeService.instance.primaryText,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('CANCEL'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          _countdownTimer?.cancel();
                          _countdownTimer = null;
                          Navigator.of(
                            dialogContext,
                            rootNavigator: true,
                          ).pop();
                          _executeSosTrigger();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kSosRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'TRIGGER NOW',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<Position?> _captureFreshGpsForSos() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('GPS is off. Emergency location cannot be shared.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission is required to share your GPS.');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _locationError = null;
        });
      }
      return position;
    } catch (error) {
      if (mounted) {
        setState(() {
          _locationError = error.toString().replaceFirst('Exception: ', '');
        });
      }
      return null;
    }
  }

  Future<void> _executeSosTrigger() async {
    final user = await AuthService.instance.getCurrentUser();
    final passengerName =
        (user?['username'] ?? user?['name'] ?? user?['full_name'])
            ?.toString() ??
        'Passenger';
    final uid = user?['id'] is int
        ? user!['id'] as int
        : (int.tryParse(user?['id']?.toString() ?? '${widget.userId}') ??
              widget.userId);

    final freshPosition = await _captureFreshGpsForSos();
    final record = await _emergencyService.triggerSos(
      userId: uid,
      journeyId: widget.journeyId,
      userName: passengerName,
      position: freshPosition,
    );

    if (!mounted) return;

    setState(() {
      _isSosActive = true;
      _isSirenActive = true;
      _currentPosition = Position(
        longitude: record.longitude,
        latitude: record.latitude,
        timestamp: record.timestamp,
        accuracy: 10,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );
    });

    await _loadContacts(uid: uid);
    if (!mounted) return;

    var contactDeliveryMessage = 'SOS is active.';
    final trustedContacts = _contacts
        .where(
          (contact) =>
              contact.phone.trim().isNotEmpty &&
              !isEmergencyHelplinePhoneNumber(contact.phone),
        )
        .toList();

    if (freshPosition == null) {
      contactDeliveryMessage =
          'SOS is active, but GPS was unavailable, so no location message was prepared.';
    } else if (trustedContacts.isEmpty) {
      contactDeliveryMessage =
          'SOS is active, but there are no eligible trusted contacts. Emergency helplines are excluded from SMS.';
    } else {
      final message = _emergencyService.composeSosMessage(
        lat: record.latitude,
        lng: record.longitude,
        userName: passengerName,
      );

      final backendSent = await _emergencyService.sendSosViaBackend(
        contacts: trustedContacts,
        message: message,
      );

      if (backendSent) {
        contactDeliveryMessage =
            'SOS SMS was sent through the backend to ${trustedContacts.length} trusted contact(s).';
      } else {
        final composerOpened = await _emergencyService.shareSosToAllContacts(
          contacts: trustedContacts,
          message: message,
        );
        contactDeliveryMessage = composerOpened
            ? 'The emergency message is ready for ${trustedContacts.length} trusted contact(s). Review recipients and send it in the opened app.'
            : 'SOS is active, but no messaging or sharing app could be opened. Use Send Emergency SMS below.';
      }
    }

    if (!mounted) return;
    _showSosTriggeredModal(
      record,
      userName: passengerName,
      contactDeliveryMessage: contactDeliveryMessage,
    );
  }

  void _showSosTriggeredModal(
    SosRecord record, {
    required String userName,
    required String contactDeliveryMessage,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final message = _emergencyService.composeSosMessage(
          lat: record.latitude,
          lng: record.longitude,
          userName: userName,
        );

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.shield, color: kSosRed, size: 28),
                  SizedBox(width: 10),
                  Text(
                    'SOS Activated & Broadcasting',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: kSosRed,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                contactDeliveryMessage,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kSosRedLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kSosRed.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '📍 Captured Emergency GPS Coordinates:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${record.latitude.toStringAsFixed(6)}, ${record.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: kSosRed,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Instant Action Options:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _emergencyService.makePhoneCall('112');
                },
                icon: const Icon(Icons.call, color: Colors.white),
                label: const Text('Call National Police / Emergency 112'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kSosRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (_contacts.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _emergencyService.shareSosToAllContacts(
                      contacts: _contacts,
                      message: message,
                    );
                  },
                  icon: const Icon(Icons.sms_outlined, color: kPrimaryPurple),
                  label: Text(
                    'Send Emergency SMS to ${_contacts.length} Contacts',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kPrimaryPurple,
                    side: const BorderSide(color: kPrimaryPurple, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Dismiss & Keep Siren Active'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _resolveEmergency() {
    _emergencyService.resolveSos();
    setState(() {
      _isSosActive = false;
      _isSirenActive = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 10),
            Text('SOS Alert marked as Resolved. Stay safe!'),
          ],
        ),
        backgroundColor: kSafeGreen,
      ),
    );
  }

  // ============================================================
  // DIRECT HELPLINES CALLING
  // ============================================================

  void _callHelpline(String number, String name) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Call $name?'),
        content: Text('Dialing $number directly from your phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _emergencyService.makePhoneCall(number);
            },
            icon: const Icon(Icons.call),
            label: Text('Call $number'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kSosRed,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // EMERGENCY CONTACTS CRUD
  // ============================================================

  void _showAddContactDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String selectedRelation = 'Parent';
    final relations = [
      'Parent',
      'Guardian',
      'Spouse',
      'Sibling',
      'Friend',
      'Colleague',
      'Other',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Add Emergency Contact',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'This person will receive your live GPS link when you trigger SOS.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Contact Name',
                        hintText: 'e.g. Mom, Dad, Priya',
                        prefixIcon: const Icon(Icons.person_outline),
                        filled: true,
                        fillColor: kBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Phone Number',
                        hintText: 'e.g. 9876543210',
                        prefixIcon: const Icon(Icons.phone_outlined),
                        filled: true,
                        fillColor: kBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Relationship',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: relations.map((rel) {
                        final isSel = rel == selectedRelation;
                        return ChoiceChip(
                          label: Text(rel),
                          selected: isSel,
                          onSelected: (val) {
                            if (val) {
                              setModalState(() => selectedRelation = rel);
                            }
                          },
                          selectedColor: kPrimaryPurple,
                          labelStyle: TextStyle(
                            color: isSel ? Colors.white : Colors.black87,
                            fontSize: 12,
                          ),
                          backgroundColor: kBackground,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        final phone = phoneCtrl.text.trim();
                        if (name.isEmpty || phone.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please enter both name and phone number',
                              ),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                          return;
                        }
                        if (isEmergencyHelplinePhoneNumber(phone)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Emergency helpline numbers cannot be saved as trusted contacts.',
                              ),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                          return;
                        }

                        Navigator.pop(modalCtx);

                        final newContact = EmergencyContact(
                          userId: widget.userId,
                          name: name,
                          phone: phone,
                          relationship: selectedRelation,
                        );

                        await _emergencyService.addContact(newContact);
                        await _loadContacts();

                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('$name added to Emergency Contacts'),
                            backgroundColor: kSafeGreen,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Save Emergency Contact',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteContact(EmergencyContact contact) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Contact?'),
        content: Text(
          'Remove ${contact.name} from your emergency contacts list?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && contact.id != null) {
      await _emergencyService.deleteContact(contact.id!);
      await _loadContacts();
    }
  }

  Future<void> _sendSmsToContact(EmergencyContact contact) async {
    if (isEmergencyHelplinePhoneNumber(contact.phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SMS to emergency helpline numbers is disabled.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final position = await _emergencyService.getCurrentLocation();
    if (!mounted) return;

    final message = position == null
        ? 'Emergency alert from SmartBus Guardian. I need assistance. My current location is unavailable.'
        : _emergencyService.composeSosMessage(
            lat: position.latitude,
            lng: position.longitude,
          );
    final opened = await _emergencyService.sendDirectSms(
      phoneNumber: contact.phone,
      contactName: contact.name,
      message: message,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? 'Emergency message prepared for ${contact.name}. Review and send it in the opened app.'
              : 'Could not open a messaging or sharing app.',
        ),
      ),
    );
  }

  Future<void> _shareLocationToContact(EmergencyContact contact) async {
    if (isEmergencyHelplinePhoneNumber(contact.phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sharing to emergency helpline numbers is disabled.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final position = await _emergencyService.getCurrentLocation();
    if (!mounted) return;
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Current location is unavailable. Turn on GPS and retry.'),
        ),
      );
      return;
    }

    setState(() => _currentPosition = position);
    final locationMessage =
        'My current location: ${_emergencyService.buildMapsUrl(position.latitude, position.longitude)}\n'
        'Coordinates: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
    final opened = await _emergencyService.sendDirectSms(
      phoneNumber: contact.phone,
      contactName: contact.name,
      message: locationMessage,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? 'Location message prepared for ${contact.name}. Review and send it in the opened app.'
              : 'Could not open a messaging or sharing app.',
        ),
      ),
    );
  }

  Future<void> _broadcastSmsToAllContacts() async {
    if (_contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No emergency contacts found. Add one below!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final position = await _emergencyService.getCurrentLocation();
    if (!mounted) return;
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Current location is unavailable. Turn on GPS and retry.'),
        ),
      );
      return;
    }

    setState(() => _currentPosition = position);
    final message = _emergencyService.composeSosMessage(
      lat: position.latitude,
      lng: position.longitude,
    );
    final opened = await _emergencyService.shareSosToAllContacts(
      contacts: _contacts,
      message: message,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? 'Emergency message prepared. Review recipients and send it in the opened app.'
              : 'Could not open a messaging or sharing app.',
        ),
      ),
    );
  }

  // ============================================================
  // BUILD METHOD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: _isSosActive ? kSosRed : kBackground,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: _isSosActive
                ? Colors.white
                : AppThemeService.instance.primaryText,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Emergency SOS',
          style: TextStyle(
            color: _isSosActive
                ? Colors.white
                : AppThemeService.instance.primaryText,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.history,
              color: _isSosActive
                  ? Colors.white
                  : AppThemeService.instance.primaryText,
            ),
            tooltip: 'SOS History',
            onPressed: _showSosHistoryDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. ACTIVE SOS BANNER (IF ACTIVE)
              if (_isSosActive) _buildActiveSosBanner(),

              // 2. LIVE GPS LOCATION CARD
              _buildLiveGpsCard(),

              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSharingLocation ? null : _shareCurrentLocation,
                  icon: _isSharingLocation
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.share_location_outlined),
                  label: Text(
                    _isSharingLocation
                        ? 'Getting location...'
                        : 'Send Location',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 3. BIG PULSING SOS PANIC BUTTON
              _buildPanicSosButton(),

              const SizedBox(height: 24),

              // 4. LOUD SIREN & FLASH ALERT TRIGGER
              _buildSirenControlCard(),

              const SizedBox(height: 24),

              // 5. QUICK DIRECT HELPLINES (112, 100, 1091, 108)
              _buildHelplineSection(),

              const SizedBox(height: 24),

              // 6. EMERGENCY CONTACTS SECTION (WITH CRUD & BROADCAST)
              _buildEmergencyContactsSection(),

              const SizedBox(height: 24),

              // 7. BUS SAFETY TIPS CARD
              _buildBusSafetyTipsCard(),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // WIDGET: ACTIVE SOS BANNER
  // ============================================================

  Widget _buildActiveSosBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSosRed,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: kSosRed.withValues(alpha: 0.4),
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
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning, color: kSosRed, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'SOS BROADCAST ACTIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Loud emergency alarm is active and your GPS location is being shared.',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _resolveEmergency,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('I AM SAFE (DISMISS SOS)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: kSafeGreen,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // WIDGET: LIVE GPS CARD
  // ============================================================

  Widget _buildLiveGpsCard() {
    final lat = _currentPosition?.latitude;
    final lng = _currentPosition?.longitude;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCardWhite,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kPrimaryPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.my_location,
              color: kPrimaryPurple,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Live GPS Location',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppThemeService.instance.primaryText,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.verified_user, size: 14, color: Colors.green),
                  ],
                ),
                const SizedBox(height: 4),
                if (_isLoadingLocation)
                  Text(
                    'Acquiring satellite lock...',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppThemeService.instance.secondaryText,
                    ),
                  )
                else if (lat != null && lng != null)
                  Text(
                    'Lat: ${lat.toStringAsFixed(5)}, Lng: ${lng.toStringAsFixed(5)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: kPrimaryPurple,
                      fontFamily: 'monospace',
                    ),
                  )
                else
                  Text(
                    _locationError ?? 'Location unavailable',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.redAccent,
                    ),
                  ),
                if (_locationError != null && lat != null && lng != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _locationError!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: _isLoadingLocation
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kPrimaryPurple,
                    ),
                  )
                : const Icon(Icons.refresh, color: kPrimaryPurple),
            tooltip: 'Refresh Location',
            onPressed: _fetchLocation,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // WIDGET: BIG PANIC SOS BUTTON
  // ============================================================

  Widget _buildPanicSosButton() {
    return Center(
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _isSosActive ? _pulseAnimation.value : 1.0,
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _isSosActive
                            ? kSosRedGlow.withValues(alpha: 0.5)
                            : kSosRed.withValues(alpha: 0.25),
                        blurRadius: _isSosActive ? 35 : 20,
                        spreadRadius: _isSosActive ? 10 : 2,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _isSosActive
                          ? _resolveEmergency
                          : _startSosCountdown,
                      splashColor: Colors.white30,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: _isSosActive
                                ? [kSosRedGlow, const Color(0xFFB71C1C)]
                                : [const Color(0xFFFF5252), kSosRed],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.8),
                            width: 4,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isSosActive
                                  ? Icons.check_circle_outline
                                  : Icons.sos,
                              size: 54,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _isSosActive ? 'I AM SAFE' : 'EMERGENCY\nSOS',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            _isSosActive
                ? 'Tap to stop siren and mark as safe'
                : 'Tap to trigger immediate SOS Broadcast',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _isSosActive
                  ? kSosRed
                  : AppThemeService.instance.secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // WIDGET: LOUD SIREN CONTROL CARD
  // ============================================================

  Widget _buildSirenControlCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isSirenActive ? kSosRedLight : kCardWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _isSirenActive ? kSosRed : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isSirenActive
                  ? kSosRed.withValues(alpha: 0.15)
                  : Colors.orange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isSirenActive ? Icons.volume_up : Icons.notifications_active,
              color: _isSirenActive ? kSosRed : Colors.orange.shade800,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isSirenActive ? 'Siren is Blaring!' : 'Loud Audio Siren',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: _isSirenActive
                        ? kSosRed
                        : AppThemeService.instance.primaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isSirenActive
                      ? 'Looping emergency alarm & vibration'
                      : 'Plays loud voice alarm to alert nearby passengers',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppThemeService.instance.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (_isSirenActive) {
                _emergencyService.stopSiren();
              } else {
                _emergencyService.startSiren();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _isSirenActive
                  ? AppThemeService.instance.primaryText
                  : Colors.orange.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: Text(
              _isSirenActive ? 'Stop' : 'Start',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // WIDGET: NATIONAL HELPLINES SECTION
  // ============================================================

  Widget _buildHelplineSection() {
    final helplines = [
      {
        'title': 'National Emergency',
        'number': '112',
        'icon': Icons.security,
        'color': const Color(0xFFE53935),
      },
      {
        'title': 'Police Control',
        'number': '100',
        'icon': Icons.local_police,
        'color': const Color(0xFF1E88E5),
      },
      {
        'title': 'Women Safety',
        'number': '1091',
        'icon': Icons.support_agent,
        'color': const Color(0xFF8E24AA),
      },
      {
        'title': 'Ambulance',
        'number': '108',
        'icon': Icons.medical_services,
        'color': const Color(0xFF43A047),
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Emergency Helplines (Direct Dial)',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppThemeService.instance.primaryText,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: helplines.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.8,
          ),
          itemBuilder: (context, index) {
            final item = helplines[index];
            final color = item['color'] as Color;
            final number = item['number'] as String;
            final title = item['title'] as String;
            final icon = item['icon'] as IconData;

            return InkWell(
              onTap: () => _callHelpline(number, title),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: kCardWhite,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            number,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppThemeService.instance.secondaryText,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ============================================================
  // WIDGET: EMERGENCY CONTACTS SECTION
  // ============================================================

  Widget _buildEmergencyContactsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Trusted Emergency Contacts',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppThemeService.instance.primaryText,
              ),
            ),
            TextButton.icon(
              onPressed: _showAddContactDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add New'),
              style: TextButton.styleFrom(
                foregroundColor: kPrimaryPurple,
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isLoadingContacts)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: kPrimaryPurple),
            ),
          )
        else if (_contacts.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: kCardWhite,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.group_off_outlined,
                    size: 40,
                    color: AppThemeService.instance.mutedText,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No emergency contacts added yet.',
                    style: TextStyle(
                      color: AppThemeService.instance.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _showAddContactDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryPurple,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('+ Add Contact'),
                  ),
                ],
              ),
            ),
          )
        else ...[
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _contacts.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final contact = _contacts[index];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kCardWhite,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: kPrimaryPurple.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          contact.name.isNotEmpty
                              ? contact.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: kPrimaryPurple,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  contact.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kBackground,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    contact.relationship,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppThemeService
                                          .instance
                                          .secondaryText,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            contact.phone,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppThemeService.instance.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.call, color: Colors.green),
                      tooltip: 'Call Contact',
                      onPressed: () =>
                          _emergencyService.makePhoneCall(contact.phone),
                    ),
                    IconButton(
                      icon: const Icon(Icons.sms, color: kPrimaryPurple),
                      tooltip: 'Send Emergency SMS',
                      onPressed: () => _sendSmsToContact(contact),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.location_on_outlined,
                        color: Colors.blue,
                      ),
                      tooltip: 'Share current location',
                      onPressed: () => _shareLocationToContact(contact),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      tooltip: 'Delete Contact',
                      onPressed: () => _deleteContact(contact),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _broadcastSmsToAllContacts,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Broadcast Emergency SMS to All Contacts'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kPrimaryPurple,
                side: const BorderSide(color: kPrimaryPurple),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ============================================================
  // WIDGET: BUS SAFETY TIPS
  // ============================================================

  Widget _buildBusSafetyTipsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF3E5F5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.purple.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: Colors.purple.shade700),
              const SizedBox(width: 8),
              Text(
                'Night & Solo Bus Safety Guide',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.purple.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '• Sit near the driver or conductor during night travel.\n'
            '• Enable Sleep Mode alert so you do not miss your stop.\n'
            '• If you feel unsafe, tap the Panic button or turn on the Loud Siren to immediately attract attention.',
            style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SOS HISTORY DIALOG
  // ============================================================

  void _showSosHistoryDialog() async {
    final history = await _emergencyService.loadSosHistory(
      userId: widget.userId,
    );

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.history, color: kPrimaryPurple),
                  SizedBox(width: 10),
                  Text(
                    'Emergency SOS History',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text(
                      'No past SOS records found. Stay safe!',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: history.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final item = history[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: kSosRedLight,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.warning,
                            color: kSosRed,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          'SOS Triggered at ${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          '${item.timestamp.day}/${item.timestamp.month}/${item.timestamp.year} • Lat: ${item.latitude.toStringAsFixed(4)}, Lng: ${item.longitude.toStringAsFixed(4)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.status,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
