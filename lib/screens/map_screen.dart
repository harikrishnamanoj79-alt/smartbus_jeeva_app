import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../services/alert_service.dart';
import '../services/journey_service.dart';
import '../services/theme_service.dart';
import 'auth_screen.dart';
import 'destination_screen.dart';
import 'sos_screen.dart';

const Color kPrimaryPurple = Color(0xFF6C4DF6);
Color get kBackground => AppThemeService.instance.pageBackground;

const double kAlertThresholdMeters = 100;
const double kBusStopArrivalRadiusMeters = 100;
const double kRouteDeviationThresholdMeters = 150;

bool isWithinDestinationAlertThreshold(double distanceMeters) =>
    distanceMeters <= kAlertThresholdMeters;

bool isWithinBusStopArrivalRadius(double distanceMeters) =>
    distanceMeters <= kBusStopArrivalRadiusMeters;

bool isOutsideRouteDeviationThreshold(double distanceMeters) =>
    distanceMeters > kRouteDeviationThresholdMeters;

double distanceToRouteMeters({
  required LatLng currentLocation,
  required List<LatLng> routePoints,
}) {
  if (routePoints.isEmpty) return double.infinity;
  return routePoints
      .map(
        (point) => Geolocator.distanceBetween(
          currentLocation.latitude,
          currentLocation.longitude,
          point.latitude,
          point.longitude,
        ),
      )
      .reduce((first, second) => first < second ? first : second);
}

double estimateRemainingRoadDistanceMeters({
  required LatLng currentLocation,
  required List<LatLng> routePoints,
  required double totalRoadDistanceMeters,
}) {
  if (routePoints.length < 2 || totalRoadDistanceMeters <= 0) {
    return 0;
  }

  var routeGeometryMeters = 0.0;
  var nearestPointIndex = 0;
  var nearestDistanceMeters = double.infinity;

  for (var index = 0; index < routePoints.length; index++) {
    final point = routePoints[index];
    final distanceToPoint = Geolocator.distanceBetween(
      currentLocation.latitude,
      currentLocation.longitude,
      point.latitude,
      point.longitude,
    );
    if (distanceToPoint < nearestDistanceMeters) {
      nearestDistanceMeters = distanceToPoint;
      nearestPointIndex = index;
    }

    if (index > 0) {
      final previousPoint = routePoints[index - 1];
      routeGeometryMeters += Geolocator.distanceBetween(
        previousPoint.latitude,
        previousPoint.longitude,
        point.latitude,
        point.longitude,
      );
    }
  }

  if (routeGeometryMeters <= 0) return 0;

  var remainingGeometryMeters = 0.0;
  for (var index = nearestPointIndex + 1; index < routePoints.length; index++) {
    final previousPoint = routePoints[index - 1];
    final point = routePoints[index];
    remainingGeometryMeters += Geolocator.distanceBetween(
      previousPoint.latitude,
      previousPoint.longitude,
      point.latitude,
      point.longitude,
    );
  }

  final roadScale = totalRoadDistanceMeters / routeGeometryMeters;
  return (remainingGeometryMeters * roadScale)
      .clamp(0.0, totalRoadDistanceMeters)
      .toDouble();
}

class MapScreen extends StatefulWidget {
  final bool sleepMode;
  final Duration sleepInterval;
  final Destination? startingPoint;
  final Destination? initialDestination;

  const MapScreen({
    super.key,
    this.sleepMode = false,
    this.sleepInterval = const Duration(seconds: 12),
    this.startingPoint,
    this.initialDestination,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController mapController = MapController();

  final TextEditingController searchController = TextEditingController();

  StreamSubscription<Position>? _positionStream;

  Position? currentPosition;
  LatLng? routeOrigin;
  String? originLabel;

  // IMPORTANT:
  // These are NULL when the screen opens.
  // No destination is selected by default.
  LatLng? selectedLocation;
  String? destinationLabel;
  String? destinationAddress;

  List<LatLng> routePoints = [];

  double? remainingDistanceMeters;
  double? routeDistanceMeters;
  double? routeDurationSeconds;
  List<Destination> nearbyBusStops = [];
  Destination? reachedBusStop;
  double? reachedBusStopDistanceMeters;
  String? routeStatusMessage;

  bool isTracking = false;
  bool isSearching = false;
  bool isRouting = false;
  bool isReplanning = false;
  bool alertFired = false;
  int _consecutiveRouteDeviationFixes = 0;

  String? errorMessage;

  // Prevent excessive OSRM requests.
  DateTime? _lastRouteUpdate;
  DateTime? _lastNearbyStopLookup;
  LatLng? _lastNearbyStopLookupLocation;
  DateTime? _lastDeviationRecalculation;

  @override
  void initState() {
    super.initState();

    AlertService.instance.init();

    _initializeMap();
  }

  Future<void> _initializeMap() async {
    final startingPoint = widget.startingPoint;
    if (startingPoint != null) {
      originLabel = startingPoint.name;
      if (startingPoint.hasCoordinates) {
        routeOrigin = LatLng(startingPoint.latitude!, startingPoint.longitude!);
      }
    }

    final destination = widget.initialDestination;
    if (destination != null && destination.hasCoordinates) {
      setState(() {
        selectedLocation = LatLng(
          destination.latitude!,
          destination.longitude!,
        );
        destinationLabel = destination.name;
        destinationAddress = destination.subtitle;
      });
    }

    unawaited(getCurrentLocation());
    if (!mounted || destination == null) return;

    if (!destination.hasCoordinates) {
      searchController.text = destination.name;
      await searchDestination();
    } else {
      await getRoute(force: true);
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    searchController.dispose();

    AlertService.instance.stopRepeatingAlert();

    super.dispose();
  }

  // ============================================================
  // CURRENT LOCATION
  // ============================================================

  Future<void> getCurrentLocation() async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        _showMessage('Please turn on GPS/location services.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showMessage('Location permission is required.');
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;

      setState(() {
        currentPosition = position;
        errorMessage = null;
      });

      if (selectedLocation != null && routeOrigin == null && !isTracking) {
        unawaited(getRoute(force: true));
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        mapController.move(LatLng(position.latitude, position.longitude), 15);
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage = 'Unable to get current location.';
      });

      _showMessage('Unable to get current location.');
    }
  }

  // ============================================================
  // NOMINATIM SEARCH
  // ============================================================

  Future<void> searchDestination() async {
    final String query = searchController.text.trim();

    if (query.isEmpty) {
      _showMessage('Please enter a destination.');
      return;
    }

    if (isSearching) return;

    FocusScope.of(context).unfocus();

    setState(() {
      isSearching = true;
      errorMessage = null;
    });

    try {
      final Uri uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'limit': '1',
        'addressdetails': '1',
        'countrycodes': 'in',
      });

      final http.Response response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'SmartBusGuardian/1.0 (student project)',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Place search failed.');
      }

      final List<dynamic> results = jsonDecode(response.body);

      if (results.isEmpty) {
        throw Exception('Destination not found. Try another search.');
      }

      final Map<String, dynamic> result = results.first as Map<String, dynamic>;

      final double latitude = double.parse(result['lat'].toString());

      final double longitude = double.parse(result['lon'].toString());

      final String displayName =
          result['display_name']?.toString().trim() ?? '';

      if (displayName.isEmpty) {
        throw Exception('The selected place has no name.');
      }

      final LatLng destination = LatLng(latitude, longitude);

      if (!mounted) return;

      setState(() {
        selectedLocation = destination;

        // This is created ONLY after the user searches.
        destinationLabel = query;

        destinationAddress = displayName;

        routePoints = [];

        routeDistanceMeters = null;

        routeDurationSeconds = null;

        remainingDistanceMeters = null;

        alertFired = false;

        routeStatusMessage = null;

        _consecutiveRouteDeviationFixes = 0;

        _lastRouteUpdate = null;
      });

      // Move to the searched place.
      mapController.move(destination, 14);

      await getRoute(force: true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      });

      _showMessage(errorMessage!);
    } finally {
      if (mounted) {
        setState(() {
          isSearching = false;
        });
      }
    }
  }

  // ============================================================
  // OSRM ROAD ROUTING
  // ============================================================

  Future<void> getRoute({bool force = false}) async {
    final Position? position = currentPosition;

    final LatLng? destination = selectedLocation;

    final LatLng? start = isTracking
        ? position == null
              ? null
              : LatLng(position.latitude, position.longitude)
        : routeOrigin ??
              (position == null
                  ? null
                  : LatLng(position.latitude, position.longitude));

    if (start == null || destination == null) {
      return;
    }

    // Don't request OSRM too frequently.
    if (!force && _lastRouteUpdate != null) {
      final Duration difference = DateTime.now().difference(_lastRouteUpdate!);

      if (difference.inSeconds < 30) {
        return;
      }
    }

    if (isRouting) return;

    setState(() {
      isRouting = true;
    });

    try {
      final double startLongitude = start.longitude;
      final double startLatitude = start.latitude;

      final double destinationLongitude = destination.longitude;

      final double destinationLatitude = destination.latitude;

      final String coordinates =
          '$startLongitude,$startLatitude;'
          '$destinationLongitude,$destinationLatitude';

      final Uri uri = Uri.parse(
        'https://router.project-osrm.org/'
        'route/v1/driving/'
        '$coordinates'
        '?overview=full'
        '&geometries=geojson'
        '&steps=false',
      );

      final http.Response response = await http
          .get(
            uri,
            headers: const {
              'User-Agent': 'SmartBusGuardian/1.0 (student project)',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Unable to create road route.');
      }

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (data['code'] != 'Ok') {
        throw Exception('No road route was found.');
      }

      final List<dynamic> routes = data['routes'] as List<dynamic>;

      if (routes.isEmpty) {
        throw Exception('No route found.');
      }

      final Map<String, dynamic> route = routes.first as Map<String, dynamic>;

      final double distance = (route['distance'] as num).toDouble();

      final double duration = (route['duration'] as num).toDouble();

      final Map<String, dynamic> geometry =
          route['geometry'] as Map<String, dynamic>;

      final List<dynamic> coordinatesList =
          geometry['coordinates'] as List<dynamic>;

      final List<LatLng> points = coordinatesList.map<LatLng>((coordinate) {
        final List<dynamic> pair = coordinate as List<dynamic>;

        final double longitude = (pair[0] as num).toDouble();

        final double latitude = (pair[1] as num).toDouble();

        return LatLng(latitude, longitude);
      }).toList();

      if (!mounted) return;

      setState(() {
        routeDistanceMeters = distance;

        routeDurationSeconds = duration;

        routePoints = points;
        remainingDistanceMeters = isTracking && currentPosition != null
            ? estimateRemainingRoadDistanceMeters(
                currentLocation: LatLng(
                  currentPosition!.latitude,
                  currentPosition!.longitude,
                ),
                routePoints: points,
                totalRoadDistanceMeters: distance,
              )
            : distance;

        _lastRouteUpdate = DateTime.now();
      });

      // Fit the initial route; while tracking, keep the camera following GPS.
      if (!isTracking && points.length >= 2) {
        final LatLngBounds bounds = LatLngBounds.fromPoints(points);

        mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)),
        );
      }
    } catch (e) {
      debugPrint('OSRM route error: $e');

      if (mounted) {
        setState(() {
          errorMessage = 'Unable to calculate the route.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          isRouting = false;
        });
      }
    }
  }

  Future<void> _refreshNearbyBusStops(
    Position position, {
    bool force = false,
  }) async {
    final now = DateTime.now();
    final lookupLocation = LatLng(position.latitude, position.longitude);
    final movedSinceLookup = _lastNearbyStopLookupLocation == null
        ? double.infinity
        : Geolocator.distanceBetween(
            lookupLocation.latitude,
            lookupLocation.longitude,
            _lastNearbyStopLookupLocation!.latitude,
            _lastNearbyStopLookupLocation!.longitude,
          );
    if (!force &&
        _lastNearbyStopLookup != null &&
        now.difference(_lastNearbyStopLookup!).inSeconds < 60 &&
        movedSinceLookup < 300) {
      return;
    }
    _lastNearbyStopLookup = now;
    _lastNearbyStopLookupLocation = lookupLocation;

    final stops = await nearbyBusStopsAt(lookupLocation);
    if (!mounted) return;

    setState(() => nearbyBusStops = stops);
    final latestPosition = currentPosition ?? position;
    _updateStopProximity(latestPosition);
  }

  void _updateStopProximity(Position position) {
    if (nearbyBusStops.isEmpty) {
      if (reachedBusStop != null) {
        setState(() {
          reachedBusStop = null;
          reachedBusStopDistanceMeters = null;
        });
      }
      return;
    }

    Destination? closestStop;
    var closestDistance = double.infinity;
    for (final stop in nearbyBusStops) {
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        stop.latitude!,
        stop.longitude!,
      );
      if (distance < closestDistance) {
        closestStop = stop;
        closestDistance = distance;
      }
    }

    final nextReachedStop = isWithinBusStopArrivalRadius(closestDistance)
        ? closestStop
        : null;
    if (reachedBusStop?.name == nextReachedStop?.name &&
        reachedBusStopDistanceMeters?.round() == closestDistance.round()) {
      return;
    }

    setState(() {
      reachedBusStop = nextReachedStop;
      reachedBusStopDistanceMeters = closestDistance;
    });
  }

  void _checkRouteDeviation(Position position) {
    if (!isTracking || routePoints.length < 2 || isReplanning) return;

    final deviation = distanceToRouteMeters(
      currentLocation: LatLng(position.latitude, position.longitude),
      routePoints: routePoints,
    );
    if (isOutsideRouteDeviationThreshold(deviation)) {
      _consecutiveRouteDeviationFixes++;
    } else {
      _consecutiveRouteDeviationFixes = 0;
      return;
    }

    if (_consecutiveRouteDeviationFixes < 2 && reachedBusStop == null) return;
    if (isRouting) return;
    final lastRecalculation = _lastDeviationRecalculation;
    if (lastRecalculation != null &&
        DateTime.now().difference(lastRecalculation).inSeconds < 30) {
      return;
    }

    unawaited(_recalculateAlternativeRoute());
  }

  Future<void> _recalculateAlternativeRoute() async {
    if (isReplanning || !isTracking || selectedLocation == null) return;

    final previousUpdate = _lastRouteUpdate;
    _lastDeviationRecalculation = DateTime.now();
    _consecutiveRouteDeviationFixes = 0;
    setState(() {
      isReplanning = true;
      routeStatusMessage = reachedBusStop != null
          ? 'You appear to be at a different stop. Finding a route to $destinationLabel...'
          : 'You are off the planned route. Finding an alternative...';
    });

    await getRoute(force: true);
    if (!mounted) return;

    final routeUpdated =
        _lastRouteUpdate != previousUpdate && routePoints.length >= 2;
    setState(() {
      isReplanning = false;
      routeStatusMessage = routeUpdated
          ? 'Alternative route to $destinationLabel updated.'
          : 'Unable to update the route. Keep moving toward $destinationLabel and retrying GPS updates.';
    });
  }

  // ============================================================
  // START LIVE TRACKING
  // ============================================================

  Future<void> startTracking() async {
    if (selectedLocation == null) {
      _showMessage('Please search for a destination first.');
      return;
    }

    await getCurrentLocation();

    if (currentPosition == null) {
      return;
    }

    await _positionStream?.cancel();

    setState(() {
      isTracking = true;
      _lastRouteUpdate = null;
      _lastDeviationRecalculation = null;
      _consecutiveRouteDeviationFixes = 0;
      routeStatusMessage = null;
      remainingDistanceMeters = Geolocator.distanceBetween(
        currentPosition!.latitude,
        currentPosition!.longitude,
        selectedLocation!.latitude,
        selectedLocation!.longitude,
      );
    });

    unawaited(getRoute(force: true));
    unawaited(_refreshNearbyBusStops(currentPosition!, force: true));

    const LocationSettings settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
          (Position position) async {
            if (!mounted || selectedLocation == null) {
              return;
            }

            currentPosition = position;

            _updateStopProximity(position);
            unawaited(_refreshNearbyBusStops(position));
            _checkRouteDeviation(position);

            // Calculate live straight-line distance.
            final double distance = Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              selectedLocation!.latitude,
              selectedLocation!.longitude,
            );

            final routeDistance = routeDistanceMeters;
            final route = routePoints;
            final remaining = routeDistance != null && route.length >= 2
                ? estimateRemainingRoadDistanceMeters(
                    currentLocation: LatLng(
                      position.latitude,
                      position.longitude,
                    ),
                    routePoints: route,
                    totalRoadDistanceMeters: routeDistance,
                  )
                : distance;

            setState(() {
              remainingDistanceMeters = remaining;
            });

            // Keep current location visible.
            mapController.move(
              LatLng(position.latitude, position.longitude),
              mapController.camera.zoom,
            );

            // Refresh OSRM only when needed.
            await getRoute();

            // Destination alert.
            if (isWithinDestinationAlertThreshold(distance) && !alertFired) {
              alertFired = true;

              triggerDestinationAlert(distance);
            }
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() => isTracking = false);
            _showMessage('Live GPS tracking stopped: $error');
          },
        );

    // Persist started journey in JourneyService
    try {
      final user = await AuthService.instance.getCurrentUser();
      final int uid = user != null && user['id'] != null
          ? (user['id'] is int
                ? user['id'] as int
                : int.tryParse(user['id'].toString()) ?? 1)
          : 1;

      final double? distanceInKm = routeDistanceMeters != null
          ? routeDistanceMeters! / 1000
          : (remainingDistanceMeters != null
                ? remainingDistanceMeters! / 1000
                : null);

      await JourneyService.instance.startJourney(
        userId: uid,
        sourceLocation: originLabel ?? 'Current GPS Location',
        destinationName: destinationLabel ?? 'Destination Stop',
        destinationAddress: destinationAddress,
        startLatitude: routeOrigin?.latitude ?? currentPosition?.latitude,
        startLongitude: routeOrigin?.longitude ?? currentPosition?.longitude,
        destLatitude: selectedLocation?.latitude,
        destLongitude: selectedLocation?.longitude,
        estimatedDistanceKm: distanceInKm,
        sleepModeEnabled: widget.sleepMode,
      );
    } catch (e) {
      debugPrint('Error starting journey record: $e');
    }
  }
  // ============================================================
  // STOP TRACKING
  // ============================================================

  Future<void> stopTracking() async {
    await _positionStream?.cancel();

    _positionStream = null;

    AlertService.instance.stopRepeatingAlert();

    if (!mounted) return;

    setState(() {
      isTracking = false;
    });
  }

  // ============================================================
  // DESTINATION ALERT
  // ============================================================

  void triggerDestinationAlert(double distance) {
    // No default destination name.
    if (destinationLabel == null || destinationLabel!.trim().isEmpty) {
      return;
    }

    final String name = destinationLabel!;

    if (widget.sleepMode) {
      AlertService.instance.startSleepAlarm(
        destinationName: name,
        interval: widget.sleepInterval,
      );
    } else {
      AlertService.instance.fireDestinationAlert(
        destinationName: name,
        distanceMeters: distance,
      );
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(
            widget.sleepMode ? 'Wake Up!' : 'Destination Approaching!',
          ),
          content: Text(
            widget.sleepMode
                ? "You're about "
                      "${distance.toStringAsFixed(0)} meters "
                      "from $name."
                : "You are about "
                      "${distance.toStringAsFixed(0)} meters "
                      "from $name. "
                      "Get ready to get down.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                AlertService.instance.stopRepeatingAlert();

                Navigator.of(dialogContext).pop();
              },
              child: Text(widget.sleepMode ? "I'm Awake — Stop Alarm" : 'OK'),
            ),
          ],
        );
      },
    );
  }
  // ============================================================
  // MOVE TO CURRENT LOCATION
  // ============================================================

  Future<void> moveToCurrentLocation() async {
    if (currentPosition == null) {
      await getCurrentLocation();
      return;
    }

    mapController.move(
      LatLng(currentPosition!.latitude, currentPosition!.longitude),
      16,
    );
  }

  // ============================================================
  // CLEAR DESTINATION
  // ============================================================

  Future<void> clearDestination() async {
    await stopTracking();

    if (!mounted) return;

    setState(() {
      // IMPORTANT:
      // Destination becomes completely NULL.
      selectedLocation = null;

      destinationLabel = null;

      destinationAddress = null;

      routePoints = [];

      routeDistanceMeters = null;

      routeDurationSeconds = null;

      remainingDistanceMeters = null;

      alertFired = false;

      routeStatusMessage = null;

      isReplanning = false;

      _consecutiveRouteDeviationFixes = 0;

      _lastRouteUpdate = null;

      errorMessage = null;

      searchController.clear();
    });

    moveToCurrentLocation();
  }

  // ============================================================
  // FORMAT DISTANCE
  // ============================================================

  String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    }

    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  // ============================================================
  // FORMAT TIME
  // ============================================================

  String formatDuration(double seconds) {
    final int minutes = (seconds / 60).round();

    if (minutes < 60) {
      return '$minutes min';
    }

    final int hours = minutes ~/ 60;

    final int remainingMinutes = minutes % 60;

    if (remainingMinutes == 0) {
      return '$hours hr';
    }

    return '$hours hr '
        '$remainingMinutes min';
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

  // ============================================================
  // FINISH JOURNEY
  // ============================================================

  Future<void> finishJourney({bool completed = true}) async {
    final double distanceInKm =
        (routeDistanceMeters ?? remainingDistanceMeters ?? 5.0) / 1000;

    await JourneyService.instance.endJourney(
      completed: completed,
      finalDistanceKm: distanceInKm,
    );

    await _positionStream?.cancel();
    _positionStream = null;
    AlertService.instance.stopRepeatingAlert();

    if (!mounted) return;

    _showMessage(
      completed
          ? 'Journey completed! Saved to History.'
          : 'Journey finished and saved to History.',
    );

    Navigator.pop(context, <String, dynamic>{
      'journeyCompleted': completed,
      'destinationName': destinationLabel,
      'remainingMeters': 0.0,
    });
  }

  // ============================================================
  // EXIT
  // ============================================================

  Future<void> _exitAndReport() async {
    await _positionStream?.cancel();

    _positionStream = null;

    AlertService.instance.stopRepeatingAlert();

    if (!mounted) return;

    Navigator.pop(
      context,
      selectedLocation != null
          ? <String, dynamic>{
              'destination': selectedLocation,

              'destinationName': destinationLabel,

              'remainingMeters': remainingDistanceMeters,
            }
          : null,
    );
  }

  // ============================================================
  // DESTINATION CARD
  // ============================================================

  Widget _buildDestinationCard() {
    final String? name = destinationLabel;

    if (selectedLocation == null || name == null || name.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final String remaining = remainingDistanceMeters != null
        ? formatDistance(remainingDistanceMeters!)
        : '--';

    return Positioned(
      left: 15,
      right: 15,
      bottom: 75,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.red),

                const SizedBox(width: 8),

                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: clearDestination,
                ),
              ],
            ),

            if (destinationAddress != null && destinationAddress!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Text(
                  destinationAddress!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppThemeService.instance.secondaryText,
                  ),
                ),
              ),

            const SizedBox(height: 8),

            Row(
              children: [
                const Icon(Icons.near_me, size: 18),

                const SizedBox(width: 6),

                Text(
                  'Remaining: $remaining',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),

            if (routeDistanceMeters != null) ...[
              const SizedBox(height: 5),

              Row(
                children: [
                  const Icon(Icons.route, size: 18),

                  const SizedBox(width: 6),

                  Text(
                    '${isTracking ? "Road remaining: " : "Road route: "}'
                    '${formatDistance(routeDistanceMeters!)}'
                    '${routeDurationSeconds != null ? " • ${formatDuration(routeDurationSeconds!)}" : ""}',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppThemeService.instance.secondaryText,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isRouting
                    ? null
                    : isTracking
                    ? stopTracking
                    : startTracking,
                icon: Icon(isTracking ? Icons.stop : Icons.navigation),
                label: Text(isTracking ? 'Stop Tracking' : 'Start Tracking'),
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

            if (isTracking) ...[
              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => finishJourney(completed: true),
                  icon: const Icon(
                    Icons.check_circle_outline,
                    color: Colors.green,
                  ),
                  label: const Text(
                    'Finish Journey & Save',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ERROR MESSAGE
  // ============================================================

  Widget _buildErrorMessage() {
    if (errorMessage == null || errorMessage!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 80,
      left: 15,
      right: 15,
      child: Material(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade700),

              const SizedBox(width: 8),

              Expanded(
                child: Text(
                  errorMessage!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                ),
              ),

              IconButton(
                onPressed: () {
                  setState(() {
                    errorMessage = null;
                  });
                },
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrackingNotices() {
    final position = currentPosition;
    final stopsByDistance =
        position == null
              ? <MapEntry<Destination, double>>[]
              : nearbyBusStops
                    .where((stop) => stop.hasCoordinates)
                    .map(
                      (stop) => MapEntry(
                        stop,
                        Geolocator.distanceBetween(
                          position.latitude,
                          position.longitude,
                          stop.latitude!,
                          stop.longitude!,
                        ),
                      ),
                    )
                    .toList()
          ..sort((first, second) => first.value.compareTo(second.value));
    final showNearbyStops = isTracking && stopsByDistance.isNotEmpty;
    if (routeStatusMessage == null && !showNearbyStops) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: errorMessage == null ? 80 : 145,
      left: 15,
      right: 15,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (routeStatusMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 8),
                ],
              ),
              child: Row(
                children: [
                  if (isReplanning)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.alt_route, color: kPrimaryPurple),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          routeStatusMessage!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!isReplanning && routeDistanceMeters != null)
                          Text(
                            'Updated road distance: ${formatDistance(routeDistanceMeters!)}',
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
            ),
          if (showNearbyStops)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 8),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.directions_bus_outlined,
                        color: kPrimaryPurple,
                        size: 19,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          reachedBusStop == null
                              ? 'Nearby Bus Stops on Your Route'
                              : 'You are near ${reachedBusStop!.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...stopsByDistance.take(3).map((entry) {
                    final stop = entry.key;
                    final distance = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(top: 3, left: 27),
                      child: Text(
                        '${stop.name} · ${formatDistance(distance)} away'
                        '${stop.subtitle.isEmpty ? '' : ' · ${stop.subtitle}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppThemeService.instance.secondaryText,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // MAP
  // ============================================================

  Widget _buildMap() {
    final LatLng? currentLocation = currentPosition == null
        ? null
        : LatLng(currentPosition!.latitude, currentPosition!.longitude);

    return FlutterMap(
      mapController: mapController,

      options: MapOptions(
        initialCenter:
            currentLocation ??
            routeOrigin ??
            selectedLocation ??
            const LatLng(0, 0),
        initialZoom: 15,
      ),

      children: [
        // ========================================================
        // OPENSTREETMAP TILES
        // ========================================================
        TileLayer(
          urlTemplate:
              'https://tile.openstreetmap.org/'
              '{z}/{x}/{y}.png',

          userAgentPackageName: 'com.smartbusguardian.app',
        ),

        // ========================================================
        // ROAD ROUTE FROM THE CURRENT ROUTING ORIGIN TO DESTINATION
        // ========================================================
        if (routePoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(points: routePoints, strokeWidth: 5, color: Colors.blue),
            ],
          ),

        // ========================================================
        // MARKERS
        // ========================================================
        MarkerLayer(
          markers: [
            // Current location marker.
            if (currentLocation != null)
              Marker(
                point: currentLocation,
                width: 45,
                height: 45,
                child: const Icon(
                  Icons.my_location,
                  color: Colors.blue,
                  size: 35,
                ),
              ),

            if (!isTracking && routeOrigin != null)
              Marker(
                point: routeOrigin!,
                width: 45,
                height: 45,
                child: const Icon(
                  Icons.trip_origin,
                  color: Colors.green,
                  size: 32,
                ),
              ),

            // Destination marker.
            // Only exists after the user searches.
            if (selectedLocation != null)
              Marker(
                point: selectedLocation!,
                width: 50,
                height: 50,
                child: const Icon(
                  Icons.location_pin,
                  color: Colors.red,
                  size: 45,
                ),
              ),
          ],
        ),

        // ========================================================
        // OPENSTREETMAP ATTRIBUTION
        // ========================================================
        RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }

  // ============================================================
  // SEARCH BOX
  // ============================================================

  Widget _buildSearchBox() {
    return Positioned(
      top: 10,
      left: 15,
      right: 15,
      child: SafeArea(
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(14),
          child: TextField(
            controller: searchController,

            textInputAction: TextInputAction.search,

            onSubmitted: (_) {
              searchDestination();
            },

            decoration: InputDecoration(
              hintText: 'Search destination',

              prefixIcon: const Icon(Icons.search),

              suffixIcon: isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: searchDestination,
                    ),

              filled: true,

              fillColor: Colors.white,

              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // CURRENT LOCATION BUTTON
  // ============================================================

  Widget _buildCurrentLocationButton() {
    return Positioned(
      right: 15,
      bottom: selectedLocation != null ? 250 : 25,
      child: FloatingActionButton(
        mini: true,
        heroTag: 'currentLocationButton',
        backgroundColor: Colors.white,
        onPressed: moveToCurrentLocation,
        child: const Icon(Icons.my_location, color: Colors.blue),
      ),
    );
  }

  // ============================================================
  // MAIN BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (!didPop) {
          await _exitAndReport();
        }
      },
      child: Scaffold(
        backgroundColor: kBackground,

        appBar: AppBar(
          backgroundColor: kBackground,
          elevation: 0,

          leading: IconButton(
            icon: Icon(
              Icons.arrow_back,
              color: AppThemeService.instance.primaryText,
            ),
            onPressed: _exitAndReport,
          ),

          title: Text(
            isTracking && destinationLabel != null
                ? 'Tracking to '
                      '$destinationLabel'
                : 'SmartBus Map',

            style: TextStyle(
              color: AppThemeService.instance.primaryText,
              fontWeight: FontWeight.bold,
            ),

            overflow: TextOverflow.ellipsis,
          ),

          actions: [
            IconButton(
              tooltip: 'Emergency SOS',
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.sos, color: Colors.red, size: 22),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SosScreen()),
                );
              },
            ),
            if (selectedLocation != null)
              IconButton(
                tooltip: 'Clear destination',
                onPressed: clearDestination,
                icon: Icon(
                  Icons.clear,
                  color: AppThemeService.instance.primaryText,
                ),
              ),
          ],
        ),

        body:
            currentPosition == null &&
                routeOrigin == null &&
                selectedLocation == null
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  _buildMap(),

                  _buildSearchBox(),

                  _buildErrorMessage(),

                  _buildTrackingNotices(),

                  _buildCurrentLocationButton(),

                  _buildDestinationCard(),
                ],
              ),
      ),
    );
  }
}
