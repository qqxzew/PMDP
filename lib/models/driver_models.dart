/// Models for driver and timetable assignment management

class Driver {
  final String id; // Format: D1234
  final String name;
  final String? phone;
  final bool isActive;

  Driver({
    required this.id,
    required this.name,
    this.phone,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'is_active': isActive ? 1 : 0,
    };
  }

  factory Driver.fromMap(Map<String, dynamic> map) {
    return Driver(
      id: map['id'] as String,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      isActive: (map['is_active'] as int) == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'isActive': isActive,
    };
  }
}

class TimetableAssignment {
  final int? assignmentId;
  final String driverId;
  final String timetableJson;
  final DateTime assignedAt;
  final DateTime? retrievedAt;
  final bool isRetrieved;

  TimetableAssignment({
    this.assignmentId,
    required this.driverId,
    required this.timetableJson,
    required this.assignedAt,
    this.retrievedAt,
    this.isRetrieved = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': assignmentId,
      'driver_id': driverId,
      'timetable_json': timetableJson,
      'assigned_at': assignedAt.toIso8601String(),
      'retrieved_at': retrievedAt?.toIso8601String(),
      'is_retrieved': isRetrieved ? 1 : 0,
    };
  }

  factory TimetableAssignment.fromMap(Map<String, dynamic> map) {
    return TimetableAssignment(
      assignmentId: map['id'] as int?,
      driverId: map['driver_id'] as String,
      timetableJson: map['timetable_json'] as String,
      assignedAt: DateTime.parse(map['assigned_at'] as String),
      retrievedAt: map['retrieved_at'] != null
          ? DateTime.parse(map['retrieved_at'] as String)
          : null,
      isRetrieved: (map['is_retrieved'] as int) == 1,
    );
  }

  TimetableAssignment copyWith({
    int? assignmentId,
    String? driverId,
    String? timetableJson,
    DateTime? assignedAt,
    DateTime? retrievedAt,
    bool? isRetrieved,
  }) {
    return TimetableAssignment(
      assignmentId: assignmentId ?? this.assignmentId,
      driverId: driverId ?? this.driverId,
      timetableJson: timetableJson ?? this.timetableJson,
      assignedAt: assignedAt ?? this.assignedAt,
      retrievedAt: retrievedAt ?? this.retrievedAt,
      isRetrieved: isRetrieved ?? this.isRetrieved,
    );
  }
}
