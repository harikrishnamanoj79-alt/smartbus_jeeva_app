import 'dart:convert';

class JourneyRecord {
  final String id;
  final int? backendId;
  final int userId;
  final String sourceLocation;
  final String destinationName;
  final String? destinationAddress;
  final double? startLatitude;
  final double? startLongitude;
  final double? destLatitude;
  final double? destLongitude;
  final DateTime startTime;
  final DateTime? endTime;
  final double? distanceKm;
  final String status; // 'COMPLETED', 'CANCELLED', 'IN_PROGRESS'
  final bool sleepModeEnabled;

  JourneyRecord({
    required this.id,
    this.backendId,
    required this.userId,
    this.sourceLocation = 'Current Location',
    required this.destinationName,
    this.destinationAddress,
    this.startLatitude,
    this.startLongitude,
    this.destLatitude,
    this.destLongitude,
    required this.startTime,
    this.endTime,
    this.distanceKm,
    this.status = 'IN_PROGRESS',
    this.sleepModeEnabled = false,
  });

  int get durationMinutes {
    final end = endTime ?? DateTime.now();
    final diff = end.difference(startTime).inMinutes;
    return diff <= 0 ? 1 : diff;
  }

  JourneyRecord copyWith({
    String? id,
    int? backendId,
    int? userId,
    String? sourceLocation,
    String? destinationName,
    String? destinationAddress,
    double? startLatitude,
    double? startLongitude,
    double? destLatitude,
    double? destLongitude,
    DateTime? startTime,
    DateTime? endTime,
    double? distanceKm,
    String? status,
    bool? sleepModeEnabled,
  }) {
    return JourneyRecord(
      id: id ?? this.id,
      backendId: backendId ?? this.backendId,
      userId: userId ?? this.userId,
      sourceLocation: sourceLocation ?? this.sourceLocation,
      destinationName: destinationName ?? this.destinationName,
      destinationAddress: destinationAddress ?? this.destinationAddress,
      startLatitude: startLatitude ?? this.startLatitude,
      startLongitude: startLongitude ?? this.startLongitude,
      destLatitude: destLatitude ?? this.destLatitude,
      destLongitude: destLongitude ?? this.destLongitude,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      distanceKm: distanceKm ?? this.distanceKm,
      status: status ?? this.status,
      sleepModeEnabled: sleepModeEnabled ?? this.sleepModeEnabled,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      if (backendId != null) 'backendId': backendId,
      'userId': userId,
      'sourceLocation': sourceLocation,
      'destinationName': destinationName,
      'destinationAddress': destinationAddress,
      'startLatitude': startLatitude,
      'startLongitude': startLongitude,
      'destLatitude': destLatitude,
      'destLongitude': destLongitude,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'distanceKm': distanceKm,
      'status': status,
      'sleepModeEnabled': sleepModeEnabled ? 1 : 0,
    };
  }

  factory JourneyRecord.fromMap(Map<String, dynamic> map) {
    return JourneyRecord(
      id:
          map['id']?.toString() ??
          map['journey_id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      backendId: ((map['backendId'] ?? map['journey_id']) as num?)?.toInt(),
      userId: map['userId'] is int
          ? map['userId']
          : int.tryParse((map['userId'] ?? map['user_id'])?.toString() ?? '') ??
                0,
      sourceLocation:
          map['sourceLocation'] ?? map['source_location'] ?? 'Starting Point',
      destinationName:
          map['destinationName'] ??
          map['destination_location'] ??
          'Destination',
      destinationAddress:
          map['destinationAddress'] ?? map['destination_location'],
      startLatitude: (map['startLatitude'] as num?)?.toDouble(),
      startLongitude: (map['startLongitude'] as num?)?.toDouble(),
      destLatitude: (map['destLatitude'] ?? map['dest_latitude'] as num?)
          ?.toDouble(),
      destLongitude: (map['destLongitude'] ?? map['dest_longitude'] as num?)
          ?.toDouble(),
      startTime: (map['startTime'] ?? map['start_time']) != null
          ? DateTime.tryParse(
                  (map['startTime'] ?? map['start_time']).toString(),
                ) ??
                DateTime.now()
          : DateTime.now(),
      endTime: (map['endTime'] ?? map['end_time']) != null
          ? DateTime.tryParse((map['endTime'] ?? map['end_time']).toString())
          : null,
      distanceKm: (map['distanceKm'] ?? map['distance_travelled'] as num?)
          ?.toDouble(),
      status:
          (map['status'] ?? map['journey_status'])?.toString() ?? 'COMPLETED',
      sleepModeEnabled:
          map['sleepModeEnabled'] == 1 ||
          map['sleepModeEnabled'] == true ||
          map['sleep_mode_enabled'] == 1,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory JourneyRecord.fromJson(String source) =>
      JourneyRecord.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
