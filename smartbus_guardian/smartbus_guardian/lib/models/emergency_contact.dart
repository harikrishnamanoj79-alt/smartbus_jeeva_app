import 'dart:convert';

class EmergencyContact {
  final int? id;
  final int userId;
  final String name;
  final String phone;
  final String relationship;
  final bool isDefault;

  EmergencyContact({
    this.id,
    this.userId = 1,
    required this.name,
    required this.phone,
    this.relationship = 'Emergency Contact',
    this.isDefault = false,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'userId': userId,
      'name': name,
      'phone': phone,
      'relationship': relationship,
      'isDefault': isDefault ? 1 : 0,
    };
  }

  factory EmergencyContact.fromMap(Map<String, dynamic> map) {
    return EmergencyContact(
      id: map['id'] ?? map['contact_id'],
      userId: map['userId'] ?? map['user_id'] ?? 1,
      name: map['name'] ?? map['contact_name'] ?? '',
      phone: map['phone'] ?? map['contact_phone'] ?? '',
      relationship: map['relationship'] ?? 'Emergency Contact',
      isDefault: (map['isDefault'] == 1 || map['isDefault'] == true),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory EmergencyContact.fromJson(String source) =>
      EmergencyContact.fromMap(jsonDecode(source));
}
