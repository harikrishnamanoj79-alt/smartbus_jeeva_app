import 'dart:convert';

class SosRecord {
  final int? id;
  final int userId;
  final int? journeyId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String status;
  final String? address;

  SosRecord({
    this.id,
    required this.userId,
    this.journeyId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.status = 'SENT',
    this.address,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'userId': userId,
      if (journeyId != null) 'journeyId': journeyId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
      'status': status,
      if (address != null) 'address': address,
    };
  }

  factory SosRecord.fromMap(Map<String, dynamic> map) {
    return SosRecord(
      id: map['id'] ?? map['sos_id'],
      userId: map['userId'] ?? map['user_id'] ?? 0,
      journeyId: map['journeyId'] ?? map['journey_id'],
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now()
          : map['sent_at'] != null
          ? DateTime.tryParse(map['sent_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      status: map['status'] ?? 'SENT',
      address: map['address'],
    );
  }

  String toJson() => jsonEncode(toMap());

  factory SosRecord.fromJson(String source) =>
      SosRecord.fromMap(jsonDecode(source));
}
