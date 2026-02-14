// Vehicle and driver models

import 'dart:math' as math;

class Vehicle {
  final String id;
  final String name;
  String? currentLineNumber;
  String? currentDirection;
  String? currentStopName;
  int delayMinutes;
  VehicleStatus status;
  List<String> assignedJobIds;
  
  // Інформація про зміну водія
  DriverShiftInfo? driverShift;

  Vehicle({
    required this.id,
    required this.name,
    this.currentLineNumber,
    this.currentDirection,
    this.currentStopName,
    this.delayMinutes = 0,
    this.status = VehicleStatus.idle,
    List<String>? assignedJobIds,
    this.driverShift,
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

/// Інформація про зміну водія (генерується випадково для реалістичності)
class DriverShiftInfo {
  final String driverId;
  final DateTime shiftStart;
  final int shiftDurationMinutes; // Зазвичай 8 годин (480 хвилин)
  
  DriverShiftInfo({
    required this.driverId,
    required this.shiftStart,
    this.shiftDurationMinutes = 480, // 8 годин
  });
  
  /// Обчислює скільки хвилин водій вже працює
  int getWorkedMinutes(DateTime currentTime) {
    return currentTime.difference(shiftStart).inMinutes.clamp(0, shiftDurationMinutes);
  }
  
  /// Обчислює скільки хвилин залишилось до кінця зміни
  int getRemainingMinutes(DateTime currentTime) {
    final worked = getWorkedMinutes(currentTime);
    return (shiftDurationMinutes - worked).clamp(0, shiftDurationMinutes);
  }
  
  /// Чи зміна закінчилась
  bool isShiftEnded(DateTime currentTime) {
    return getRemainingMinutes(currentTime) <= 0;
  }
  
  /// Форматований текст для відображення
  String getFormattedWorked(DateTime currentTime) {
    final worked = getWorkedMinutes(currentTime);
    final hours = worked ~/ 60;
    final minutes = worked % 60;
    return '${hours}h ${minutes}min';
  }
  
  String getFormattedRemaining(DateTime currentTime) {
    final remaining = getRemainingMinutes(currentTime);
    final hours = remaining ~/ 60;
    final minutes = remaining % 60;
    return '${hours}h ${minutes}min';
  }
  
  /// Генерує випадкову зміну для водія (для реалістичності)
  static DriverShiftInfo generateRandom(String vehicleId, DateTime operationDate) {
    final random = math.Random(vehicleId.hashCode); // Використовуємо hash для консистентності
    
    // Зміна починається від 4:00 до 8:00 ранку
    final startHour = 4 + random.nextInt(5); // 4-8 години
    final startMinute = random.nextInt(60);
    
    // Водій вже пропрацював від 0 до 3 годин на початок
    final alreadyWorkedMinutes = random.nextInt(180); // 0-3 години
    
    final shiftStart = DateTime(
      operationDate.year,
      operationDate.month,
      operationDate.day,
      startHour,
      startMinute,
    ).subtract(Duration(minutes: alreadyWorkedMinutes));
    
    return DriverShiftInfo(
      driverId: 'D-$vehicleId',
      shiftStart: shiftStart,
    );
  }
}

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
