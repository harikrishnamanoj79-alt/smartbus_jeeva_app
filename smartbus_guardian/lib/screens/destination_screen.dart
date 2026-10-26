import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'login_screen.dart'; // for kPrimaryPurple, kBackground, kCardWhite
import '../services/auth_service.dart';
import '../services/saved_destination_service.dart';
import '../services/theme_service.dart';

class Destination {
  final String name;
  final String subtitle;
  final IconData icon;
  // Nullable: a freeform typed destination has no known coordinates yet.
  // When null, MapScreen falls back to manual tap-to-select.
  final double? latitude;
  final double? longitude;
  final int? savedId;

  const Destination({
    required this.name,
    required this.subtitle,
    required this.icon,
    this.latitude,
    this.longitude,
    this.savedId,
  });

  bool get hasCoordinates => latitude != null && longitude != null;
}

class JourneyPlan {
  final Destination origin;
  final Destination destination;

  const JourneyPlan({required this.origin, required this.destination});
}

Future<List<Destination>> nearbyBusStopsAt(
  LatLng location, {
  int radiusMeters = 800,
}) async {
  final query =
      '[out:json][timeout:15];('
      'node(around:$radiusMeters,${location.latitude},${location.longitude})[highway=bus_stop];'
      'way(around:$radiusMeters,${location.latitude},${location.longitude})[highway=bus_stop];'
      'node(around:$radiusMeters,${location.latitude},${location.longitude})[public_transport=platform][bus=yes];'
      'way(around:$radiusMeters,${location.latitude},${location.longitude})[public_transport=platform][bus=yes];'
      ');out center tags;';

  try {
    final uri = Uri.https('overpass-api.de', '/api/interpreter', {
      'data': query,
    });
    final response = await http
        .get(uri, headers: const {'User-Agent': 'SmartBusGuardian/1.0'})
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final elements = data['elements'] as List<dynamic>? ?? [];
    final stops = <Destination>[];
    final seen = <String>{};

    for (final element in elements) {
      final item = element as Map<String, dynamic>;
      final tags = item['tags'] as Map<String, dynamic>? ?? {};
      final center = item['center'] as Map<String, dynamic>?;
      final latitude = (item['lat'] ?? center?['lat']) as num?;
      final longitude = (item['lon'] ?? center?['lon']) as num?;
      if (latitude == null || longitude == null) continue;

      final lat = latitude.toDouble();
      final lon = longitude.toDouble();
      final distance = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        lat,
        lon,
      );
      if (distance > radiusMeters) continue;

      final name = (tags['name'] ?? tags['name:en'] ?? 'Bus stop').toString();
      final key = '${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';
      if (!seen.add(key)) continue;

      stops.add(
        Destination(
          name: name,
          subtitle: distance < 1000
              ? '${distance.round()} m away'
              : '${(distance / 1000).toStringAsFixed(1)} km away',
          icon: Icons.directions_bus_outlined,
          latitude: lat,
          longitude: lon,
        ),
      );
    }

    stops.sort((first, second) {
      final firstDistance = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        first.latitude!,
        first.longitude!,
      );
      final secondDistance = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        second.latitude!,
        second.longitude!,
      );
      return firstDistance.compareTo(secondDistance);
    });

    return stops.take(8).toList();
  } catch (_) {
    return [];
  }
}

List<Destination> _sortByDistance(
  List<Destination> places,
  Position? position,
) {
  final sorted = [...places];
  if (position == null) return sorted;

  sorted.sort((first, second) {
    final firstDistance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      first.latitude!,
      first.longitude!,
    );
    final secondDistance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      second.latitude!,
      second.longitude!,
    );
    return firstDistance.compareTo(secondDistance);
  });

  return sorted.map((place) {
    final meters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      place.latitude!,
      place.longitude!,
    );
    final distance = meters < 1000
        ? '${meters.round()} m away'
        : '${(meters / 1000).toStringAsFixed(1)} km away';
    return Destination(
      name: place.name,
      subtitle: distance,
      icon: place.icon,
      latitude: place.latitude,
      longitude: place.longitude,
    );
  }).toList();
}

class DestinationScreen extends StatefulWidget {
  const DestinationScreen({super.key});

  @override
  State<DestinationScreen> createState() => _DestinationScreenState();
}

class _DestinationScreenState extends State<DestinationScreen> {
  final _searchController = TextEditingController();
  final List<Destination> _savedDestinations = [];
  List<Destination> _nearbyStops = [];
  String _query = '';
  Destination? _selected;
  int? _userId;
  bool _syncWithBackend = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedDestinations());
    unawaited(_loadCurrentPosition());
  }

  Future<void> _loadSavedDestinations() async {
    final user = await AuthService.instance.getCurrentUser();
    final rawId = user?['id'];
    _userId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    _syncWithBackend = user?['backend_synced'] == true;
    if (_userId == null) return;
    final saved = await SavedDestinationService.instance.load(
      userId: _userId!,
      syncWithBackend: _syncWithBackend,
    );
    if (!mounted) return;
    setState(() {
      _savedDestinations
        ..clear()
        ..addAll(
          saved.map(
            (item) => Destination(
              name: item['name'].toString(),
              subtitle: 'Saved destination',
              icon: Icons.bookmark_outline,
              latitude: (item['latitude'] as num).toDouble(),
              longitude: (item['longitude'] as num).toDouble(),
              savedId: int.tryParse(item['destination_id']?.toString() ?? ''),
            ),
          ),
        );
    });
  }

  Future<void> _saveSelectedDestination() async {
    final candidate =
        _selected ??
        (_query.trim().isEmpty
            ? null
            : Destination(
                name: _query.trim(),
                subtitle: 'Search result',
                icon: Icons.bookmark_outline,
              ));
    if (candidate == null) {
      _showMessage('Select or search for a destination to save.');
      return;
    }
    if (_userId == null) {
      _showMessage('Log in to save destinations.');
      return;
    }

    try {
      var latitude = candidate.latitude;
      var longitude = candidate.longitude;
      if (latitude == null || longitude == null) {
        final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
          'q': candidate.name,
          'format': 'jsonv2',
          'limit': '1',
        });
        final response = await http
            .get(
              uri,
              headers: const {
                'User-Agent': 'SmartBusGuardian/1.0',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) {
          throw StateError('Place search failed with ${response.statusCode}.');
        }
        final results = jsonDecode(response.body) as List<dynamic>;
        if (results.isEmpty) {
          throw StateError('No matching place was found.');
        }
        final result = results.first as Map<String, dynamic>;
        latitude = double.parse(result['lat'].toString());
        longitude = double.parse(result['lon'].toString());
      }
      final saved = await SavedDestinationService.instance.add(
        userId: _userId!,
        name: candidate.name,
        latitude: latitude,
        longitude: longitude,
        syncWithBackend: _syncWithBackend,
      );
      if (!mounted) return;
      setState(() {
        _savedDestinations.removeWhere(
          (destination) =>
              destination.name.toLowerCase() == candidate.name.toLowerCase(),
        );
        _savedDestinations.add(
          Destination(
            name: candidate.name,
            subtitle: 'Saved destination',
            icon: Icons.bookmark_outline,
            latitude: latitude,
            longitude: longitude,
            savedId: int.tryParse(saved['destination_id']?.toString() ?? ''),
          ),
        );
      });
      _showMessage('${candidate.name} saved.');
    } catch (error) {
      if (mounted) _showMessage('Could not save destination: $error');
    }
  }

  Future<void> _removeSavedDestination(Destination destination) async {
    if (_userId == null) return;
    final record = <String, dynamic>{
      'name': destination.name,
      'latitude': destination.latitude,
      'longitude': destination.longitude,
      if (destination.savedId != null) 'destination_id': destination.savedId,
    };
    await SavedDestinationService.instance.remove(
      userId: _userId!,
      destination: record,
      syncWithBackend: _syncWithBackend,
    );
    if (!mounted) return;
    setState(() => _savedDestinations.remove(destination));
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadCurrentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        final stops = await nearbyBusStopsAt(
          LatLng(position.latitude, position.longitude),
        );
        if (mounted) setState(() => _nearbyStops = stops);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Destination> get _sortedNearbyStops => _nearbyStops;

  List<Destination> get _allDestinations => [
    ..._savedDestinations,
    ..._sortedNearbyStops,
  ];

  List<Destination> _filter(List<Destination> list) {
    if (_query.trim().isEmpty) return list;
    final q = _query.trim().toLowerCase();
    return list
        .where(
          (d) =>
              d.name.toLowerCase().contains(q) ||
              d.subtitle.toLowerCase().contains(q),
        )
        .toList();
  }

  void _selectDestination(Destination destination) {
    setState(() => _selected = destination);
  }

  void _confirmSelection() {
    if (_selected == null) return;
    // Return the chosen destination (with coordinates, when known) to
    // whichever screen pushed this one.
    Navigator.pop(context, _selected);
  }

  @override
  Widget build(BuildContext context) {
    // While searching, show a single filtered list combining both sections.
    final isSearching = _query.trim().isNotEmpty;
    final filteredSaved = _filter(_savedDestinations);
    final filteredNearby = _filter(_sortedNearbyStops);
    final filteredAll = _filter(_allDestinations);

    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                      color: AppThemeService.instance.primaryText,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Plan Your Journey',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppThemeService.instance.primaryText,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Save selected destination',
                    onPressed: _saveSelectedDestination,
                    icon: const Icon(Icons.bookmark_add_outlined),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'STEP 2 OF 2',
                        style: TextStyle(
                          color: kPrimaryPurple,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'TO',
                        style: TextStyle(
                          color: AppThemeService.instance.secondaryText,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  const LinearProgressIndicator(
                    value: 1,
                    minHeight: 4,
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                    color: kPrimaryPurple,
                    backgroundColor: Color(0x226C4DF6),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Where are you going?',
                    style: TextStyle(
                      color: AppThemeService.instance.primaryText,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Search for a place or choose a suggestion.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppThemeService.instance.secondaryText,
                    ),
                  ),
                ],
              ),
            ),

            // Search field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Where are you going?',
                  prefixIcon: Icon(
                    Icons.search,
                    color: AppThemeService.instance.secondaryText,
                  ),
                  filled: true,
                  fillColor: kCardWhite,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  if (isSearching) ...[
                    if (filteredAll.isEmpty)
                      _buildTile(
                        Destination(
                          name: _query.trim(),
                          subtitle:
                              'Use as destination (pick exact spot on map)',
                          icon: Icons.edit_location_alt_outlined,
                        ),
                      )
                    else ...[
                      ...filteredAll.map(_buildTile),
                      const SizedBox(height: 8),
                      _buildTile(
                        Destination(
                          name: _query.trim(),
                          subtitle:
                              'Use as destination (pick exact spot on map)',
                          icon: Icons.edit_location_alt_outlined,
                        ),
                      ),
                    ],
                  ] else ...[
                    if (filteredSaved.isNotEmpty) ...[
                      const _SectionLabel('Saved Destinations'),
                      ...filteredSaved.map(_buildTile),
                      const SizedBox(height: 16),
                    ],
                    if (filteredNearby.isNotEmpty) ...[
                      const _SectionLabel('Nearby Stops'),
                      ...filteredNearby.map(_buildTile),
                    ],
                  ],
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selected == null ? null : _confirmSelection,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryPurple,
                disabledBackgroundColor: kPrimaryPurple.withValues(alpha: 0.45),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 0,
              ),
              child: Text(
                _selected == null
                    ? 'Select a destination'
                    : 'Continue to ${_selected!.name}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTile(Destination destination) {
    return DestinationOptionTile(
      destination: destination,
      selected: _selected?.name == destination.name,
      onTap: () => _selectDestination(destination),
      trailing: destination.savedId == null
          ? null
          : IconButton(
              tooltip: 'Remove saved destination',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _removeSavedDestination(destination),
            ),
    );
  }
}

class StartingPointScreen extends StatefulWidget {
  const StartingPointScreen({super.key});

  @override
  State<StartingPointScreen> createState() => _StartingPointScreenState();
}

class _StartingPointScreenState extends State<StartingPointScreen> {
  List<Destination> _savedDestinations = [];
  List<Destination> _nearbyStops = [];
  Position? _currentPosition;
  Destination? _selected;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedDestinations());
    unawaited(_loadCurrentPosition());
  }

  Future<void> _loadSavedDestinations() async {
    final user = await AuthService.instance.getCurrentUser();
    final rawId = user?['id'];
    final userId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    if (userId == null) return;
    final saved = await SavedDestinationService.instance.load(
      userId: userId,
      syncWithBackend: user?['backend_synced'] == true,
    );
    if (!mounted) return;
    setState(() {
      _savedDestinations = saved
          .map(
            (item) => Destination(
              name: item['name'].toString(),
              subtitle: 'Saved destination',
              icon: Icons.bookmark_outline,
              latitude: (item['latitude'] as num).toDouble(),
              longitude: (item['longitude'] as num).toDouble(),
              savedId: int.tryParse(item['destination_id']?.toString() ?? ''),
            ),
          )
          .toList();
    });
  }

  Future<void> _loadCurrentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() => _currentPosition = position);
        final stops = await nearbyBusStopsAt(
          LatLng(position.latitude, position.longitude),
        );
        if (mounted) setState(() => _nearbyStops = stops);
      }
    } catch (_) {}
  }

  Destination get _currentLocation => Destination(
    name: 'Current Location',
    subtitle: _currentPosition == null
        ? 'Use live GPS location'
        : 'Your current GPS position',
    icon: Icons.my_location,
    latitude: _currentPosition?.latitude,
    longitude: _currentPosition?.longitude,
  );

  @override
  Widget build(BuildContext context) {
    final nearbyStops = _sortByDistance(_nearbyStops, _currentPosition);
    final nearbyPlaces = _sortByDistance(_savedDestinations, _currentPosition);

    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                      color: AppThemeService.instance.primaryText,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Plan Your Journey',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppThemeService.instance.primaryText,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'STEP 1 OF 2',
                        style: TextStyle(
                          color: kPrimaryPurple,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'FROM',
                        style: TextStyle(
                          color: AppThemeService.instance.secondaryText,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  const LinearProgressIndicator(
                    value: 0.5,
                    minHeight: 4,
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                    color: kPrimaryPurple,
                    backgroundColor: Color(0x226C4DF6),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Where does your journey start?',
                    style: TextStyle(
                      color: AppThemeService.instance.primaryText,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Choose a nearby stop, place, or your current location.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppThemeService.instance.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  const _SectionLabel('FROM'),
                  DestinationOptionTile(
                    destination: _currentLocation,
                    selected: _selected?.name == 'Current Location',
                    onTap: () => setState(() => _selected = _currentLocation),
                  ),
                  const SizedBox(height: 12),
                  const _SectionLabel('Nearby Bus Stops'),
                  ...nearbyStops.map(_buildTile),
                  const SizedBox(height: 8),
                  const _SectionLabel('Nearby Places'),
                  ...nearbyPlaces.map(_buildTile),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selected == null
                  ? null
                  : () => Navigator.pop(context, _selected),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryPurple,
                disabledBackgroundColor: kPrimaryPurple.withValues(alpha: 0.45),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 0,
              ),
              child: Text(
                _selected == null
                    ? 'Select a starting point'
                    : 'Continue from ${_selected!.name}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTile(Destination destination) {
    return DestinationOptionTile(
      destination: destination,
      selected: _selected?.name == destination.name,
      onTap: () => setState(() => _selected = destination),
    );
  }
}

class DestinationOptionTile extends StatelessWidget {
  final Destination destination;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  const DestinationOptionTile({
    super.key,
    required this.destination,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: selected ? kPrimaryPurple.withValues(alpha: 0.12) : kCardWhite,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: selected
                  ? Border.all(color: kPrimaryPurple, width: 1.4)
                  : null,
            ),
            child: Row(
              children: [
                Icon(destination.icon, color: kPrimaryPurple, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destination.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppThemeService.instance.primaryText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        destination.subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppThemeService.instance.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                trailing ??
                    Icon(
                      selected ? Icons.check_circle : Icons.chevron_right,
                      color: selected
                          ? kPrimaryPurple
                          : AppThemeService.instance.mutedText,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: AppThemeService.instance.primaryText,
        ),
      ),
    );
  }
}

class JourneyPlannerScreen extends StatefulWidget {
  const JourneyPlannerScreen({super.key});

  @override
  State<JourneyPlannerScreen> createState() => _JourneyPlannerScreenState();
}

class _JourneyPlannerScreenState extends State<JourneyPlannerScreen> {
  final _fromController = TextEditingController();
  final _toController = TextEditingController();
  Timer? _fromDebounce;
  Timer? _toDebounce;

  Destination? _currentLocation;
  Destination? _selectedOrigin;
  Destination? _selectedDestination;
  List<Destination> _fromSuggestions = [];
  List<Destination> _toSuggestions = [];
  bool _searchingFrom = false;
  bool _searchingTo = false;
  String? _fromError;
  String? _toError;
  int _fromSearchId = 0;
  int _toSearchId = 0;

  @override
  void initState() {
    super.initState();
    _currentLocation = const Destination(
      name: 'Current Location',
      subtitle: 'Getting your GPS position...',
      icon: Icons.my_location,
    );
    _selectedOrigin = _currentLocation;
    _loadCurrentLocation();
  }

  @override
  void dispose() {
    _fromDebounce?.cancel();
    _toDebounce?.cancel();
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _setCurrentLocationError('Turn on GPS to use your current location.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _setCurrentLocationError(
          'Allow location access or search for a FROM location.',
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;

      setState(() {
        _currentLocation = Destination(
          name: 'Current Location',
          subtitle: 'Your current GPS position',
          icon: Icons.my_location,
          latitude: position.latitude,
          longitude: position.longitude,
        );
        if (_selectedOrigin?.name == 'Current Location') {
          _selectedOrigin = _currentLocation;
        }
      });
    } catch (_) {
      _setCurrentLocationError(
        'Unable to get GPS. Search for a FROM location.',
      );
    }
  }

  void _setCurrentLocationError(String message) {
    if (!mounted) return;
    setState(() {
      _currentLocation = Destination(
        name: 'Current Location',
        subtitle: message,
        icon: Icons.my_location,
      );
      if (_selectedOrigin?.name == 'Current Location') {
        _selectedOrigin = _currentLocation;
      }
    });
  }

  void _onSearchChanged(String query, {required bool isFrom}) {
    final debounce = isFrom ? _fromDebounce : _toDebounce;
    debounce?.cancel();

    if (isFrom) {
      setState(() {
        _selectedOrigin = null;
        _fromError = null;
        _fromSuggestions = [];
      });
    } else {
      setState(() {
        _selectedDestination = null;
        _toError = null;
        _toSuggestions = [];
      });
    }

    if (query.trim().length < 3) {
      setState(() {
        if (isFrom) {
          _searchingFrom = false;
        } else {
          _searchingTo = false;
        }
      });
      return;
    }

    final timer = Timer(const Duration(milliseconds: 450), () {
      _searchPlaces(query.trim(), isFrom: isFrom);
    });
    if (isFrom) {
      _fromDebounce = timer;
    } else {
      _toDebounce = timer;
    }
  }

  Future<void> _searchPlaces(String query, {required bool isFrom}) async {
    final searchId = isFrom ? ++_fromSearchId : ++_toSearchId;
    if (mounted) {
      setState(() {
        if (isFrom) {
          _searchingFrom = true;
        } else {
          _searchingTo = true;
        }
      });
    }

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'addressdetails': '1',
        'limit': '5',
      });
      final response = await http
          .get(uri, headers: const {'User-Agent': 'SmartBusGuardian/1.0'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw const FormatException('Location search is unavailable.');
      }

      final results = jsonDecode(response.body) as List<dynamic>;
      final suggestions = results.map((result) {
        final place = result as Map<String, dynamic>;
        final latitude = double.parse(place['lat'].toString());
        final longitude = double.parse(place['lon'].toString());
        final displayName = place['display_name']?.toString() ?? query;
        final shortName = place['name']?.toString().trim();
        return Destination(
          name: shortName == null || shortName.isEmpty
              ? displayName.split(',').first.trim()
              : shortName,
          subtitle: displayName,
          icon: isFrom ? Icons.trip_origin : Icons.location_on_outlined,
          latitude: latitude,
          longitude: longitude,
        );
      }).toList();

      if (!mounted || searchId != (isFrom ? _fromSearchId : _toSearchId)) {
        return;
      }
      setState(() {
        if (isFrom) {
          _fromSuggestions = suggestions;
          _fromError = suggestions.isEmpty ? 'No matching places found.' : null;
        } else {
          _toSuggestions = suggestions;
          _toError = suggestions.isEmpty ? 'No matching places found.' : null;
        }
      });
    } catch (_) {
      if (!mounted || searchId != (isFrom ? _fromSearchId : _toSearchId)) {
        return;
      }
      setState(() {
        if (isFrom) {
          _fromError = 'Could not search locations. Check your connection.';
        } else {
          _toError = 'Could not search locations. Check your connection.';
        }
      });
    } finally {
      if (mounted && searchId == (isFrom ? _fromSearchId : _toSearchId)) {
        setState(() {
          if (isFrom) {
            _searchingFrom = false;
          } else {
            _searchingTo = false;
          }
        });
      }
    }
  }

  Future<Destination> _resolvePlace(
    Destination? selected,
    String query, {
    required bool isFrom,
  }) async {
    if (selected?.hasCoordinates == true) return selected!;
    if (selected?.name == 'Current Location' && query.trim().isEmpty) {
      throw const FormatException(
        'Current location is unavailable. Enter a starting place instead.',
      );
    }
    if (query.trim().length < 3) {
      throw const FormatException(
        'Enter a place name with at least 3 letters.',
      );
    }

    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query.trim(),
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '1',
    });
    final response = await http
        .get(uri, headers: const {'User-Agent': 'SmartBusGuardian/1.0'})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw const FormatException('Location search is unavailable.');
    }

    final results = jsonDecode(response.body) as List<dynamic>;
    if (results.isEmpty) {
      throw FormatException(
        'No matching ${isFrom ? 'starting place' : 'destination'} found.',
      );
    }

    final place = results.first as Map<String, dynamic>;
    final latitude = double.tryParse(place['lat'].toString());
    final longitude = double.tryParse(place['lon'].toString());
    if (latitude == null || longitude == null) {
      throw const FormatException('The selected place has no coordinates.');
    }

    final displayName = place['display_name']?.toString() ?? query.trim();
    final shortName = place['name']?.toString().trim();
    return Destination(
      name: shortName == null || shortName.isEmpty
          ? displayName.split(',').first.trim()
          : shortName,
      subtitle: displayName,
      icon: isFrom ? Icons.trip_origin : Icons.location_on_outlined,
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<void> _showRoute() async {
    _fromDebounce?.cancel();
    _toDebounce?.cancel();
    _fromSearchId++;
    _toSearchId++;

    setState(() {
      _searchingFrom = _selectedOrigin?.hasCoordinates != true;
      _searchingTo = false;
      _fromError = null;
      _toError = null;
    });

    Destination origin;
    try {
      origin = await _resolvePlace(
        _selectedOrigin,
        _fromController.text,
        isFrom: true,
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _fromError = error.message.toString());
      return;
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _fromError = 'Could not search locations. Check your connection.',
      );
      return;
    } finally {
      if (mounted) setState(() => _searchingFrom = false);
    }

    if (mounted) {
      setState(() {
        _searchingTo = _selectedDestination?.hasCoordinates != true;
      });
    }

    Destination destination;
    try {
      destination = await _resolvePlace(
        _selectedDestination,
        _toController.text,
        isFrom: false,
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _toError = error.message.toString());
      return;
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _toError = 'Could not search locations. Check your connection.',
      );
      return;
    } finally {
      if (mounted) setState(() => _searchingTo = false);
    }

    if (!mounted) return;
    Navigator.pop(
      context,
      JourneyPlan(origin: origin, destination: destination),
    );
  }

  void _selectPlace(Destination place, {required bool isFrom}) {
    FocusScope.of(context).unfocus();
    setState(() {
      if (isFrom) {
        _selectedOrigin = place;
        _fromController.text = place.name;
        _fromSuggestions = [];
        _fromError = null;
      } else {
        _selectedDestination = place;
        _toController.text = place.name;
        _toSuggestions = [];
        _toError = null;
      }
    });
  }

  void _useCurrentLocation() {
    setState(() {
      _selectedOrigin = _currentLocation;
      _fromController.clear();
      _fromSuggestions = [];
      _fromError = null;
    });
  }

  Widget _buildPlaceSuggestions(
    List<Destination> suggestions, {
    required bool isFrom,
  }) {
    return Column(
      children: suggestions
          .map(
            (place) => DestinationOptionTile(
              destination: place,
              selected: false,
              onTap: () => _selectPlace(place, isFrom: isFrom),
            ),
          )
          .toList(),
    );
  }

  Widget _buildSearchField({required bool isFrom}) {
    final controller = isFrom ? _fromController : _toController;
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onChanged: (query) => _onSearchChanged(query, isFrom: isFrom),
      decoration: InputDecoration(
        hintText: isFrom
            ? 'Enter/Search another starting location'
            : 'Enter/Search destination',
        prefixIcon: Icon(
          Icons.search,
          color: AppThemeService.instance.secondaryText,
        ),
        suffixIcon: (isFrom ? _searchingFrom : _searchingTo)
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
        filled: true,
        fillColor: kCardWhite,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildSearchStatus({required bool isFrom}) {
    final message = isFrom ? _fromError : _toError;
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 6, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          message,
          style: TextStyle(
            color: AppThemeService.instance.secondaryText,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final origin = _selectedOrigin;
    final destination = _selectedDestination;
    final canShowRoute =
        (origin?.hasCoordinates == true ||
            _fromController.text.trim().length >= 3) &&
        (destination?.hasCoordinates == true ||
            _toController.text.trim().length >= 3);

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: AppThemeService.instance.primaryText,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Start Journey',
          style: TextStyle(
            color: AppThemeService.instance.primaryText,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              'Choose your route',
              style: TextStyle(
                color: AppThemeService.instance.primaryText,
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            const _SectionLabel('FROM'),
            DestinationOptionTile(
              destination: _currentLocation!,
              selected: origin?.name == 'Current Location',
              onTap: _useCurrentLocation,
            ),
            _buildSearchField(isFrom: true),
            _buildSearchStatus(isFrom: true),
            _buildPlaceSuggestions(_fromSuggestions, isFrom: true),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Icon(Icons.south, color: kPrimaryPurple),
            ),
            const _SectionLabel('TO / DESTINATION'),
            if (destination != null)
              DestinationOptionTile(
                destination: destination,
                selected: true,
                onTap: () => setState(() => _selectedDestination = null),
              ),
            _buildSearchField(isFrom: false),
            _buildSearchStatus(isFrom: false),
            _buildPlaceSuggestions(_toSuggestions, isFrom: false),
            const SizedBox(height: 12),
            if (!canShowRoute)
              Text(
                'Select a FROM and TO location to view your route.',
                style: TextStyle(
                  color: AppThemeService.instance.secondaryText,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: canShowRoute ? _showRoute : null,
              icon: const Icon(Icons.alt_route),
              label: const Text('Show Route'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryPurple,
                foregroundColor: Colors.white,
                disabledBackgroundColor: kPrimaryPurple.withValues(alpha: 0.4),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
