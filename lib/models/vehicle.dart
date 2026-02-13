// Vehicle and driver models

class Vehicle {
  final String id;
  final String name;
  String? currentLineNumber;
  String? currentDirection;
  String? currentStopName;
  int delayMinutes;
  VehicleStatus status;
  List<String> assignedJobIds;

  Vehicle({
    required this.id,
    required this.name,
    this.currentLineNumber,
    this.currentDirection,
    this.currentStopName,
    this.delayMinutes = 0,
    this.status = VehicleStatus.idle,
    List<String>? assignedJobIds,
  }) : assignedJobIds = assignedJobIds ?? [];

  String get statusLabel {
    switch (status) {
      case VehicleStatus.inService:
        return 'V provozu';
      case VehicleStatus.idle:
        return 'Stojí';
      case VehicleStatus.outOfService:
        return 'Mimo provoz';
      case VehicleStatus.onBreak:
        return 'Přestávka';
    }
  }
}

enum VehicleStatus { inService, idle, outOfService, onBreak }

class DispatchMessage {
  final String id;
  final String vehicleId;
  final String vehicleName;
  final String content;
  final DateTime timestamp;
  final MessageDirection direction;
  final bool isRead;

  DispatchMessage({
    required this.id,
    required this.vehicleId,
    required this.vehicleName,
    required this.content,
    required this.timestamp,
    required this.direction,
    this.isRead = false,
  });

  DispatchMessage copyWith({bool? isRead}) {
    return DispatchMessage(
      id: id,
      vehicleId: vehicleId,
      vehicleName: vehicleName,
      content: content,
      timestamp: timestamp,
      direction: direction,
      isRead: isRead ?? this.isRead,
    );
  }
}

enum MessageDirection { incoming, outgoing }
