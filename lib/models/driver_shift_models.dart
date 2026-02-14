// Models for driver shift management with automatic 8-hour splitting

import 'timetable_models.dart';

/// Represents a single driver shift (max 8 hours)
class DriverShift {
  final String shiftId;
  final String driverId;
  final String vehicleId;
  final DateTime startTime;
  final DateTime endTime;
  final List<TimetableJob> jobs;
  final List<DriverBreak> breaks; // Driver rest breaks during shift
  final ShiftHandover? handoverOut; // Handover at the end of this shift
  
  DriverShift({
    required this.shiftId,
    required this.driverId,
    required this.vehicleId,
    required this.startTime,
    required this.endTime,
    required this.jobs,
    this.breaks = const [],
    this.handoverOut,
  });
  
  /// Total duration in minutes
  int get durationMinutes => endTime.difference(startTime).inMinutes;
  
  /// Total break time in minutes
  int get breakMinutes => breaks.fold(0, (sum, b) => sum + b.durationMinutes);
  
  /// Working time (duration - breaks)
  int get workingMinutes => durationMinutes - breakMinutes;
  
  /// Duration in hours (rounded)
  double get durationHours => durationMinutes / 60.0;
  
  /// Working hours (excluding breaks)
  double get workingHours => workingMinutes / 60.0;
  
  /// Check if shift violates 8-hour limit (working time only)
  bool get isOvertime => workingMinutes > 480; // 8 hours = 480 minutes
  
  /// Get formatted duration string
  String get formattedDuration {
    final hours = durationMinutes ~/ 60;
    final minutes = durationMinutes % 60;
    return '${hours}h ${minutes}min';
  }
  
  /// Get formatted working time string
  String get formattedWorkingTime {
    final hours = workingMinutes ~/ 60;
    final minutes = workingMinutes % 60;
    return '${hours}h ${minutes}min';
  }
  
  /// Get all stops in this shift
  List<TimetableStop> getAllStops() {
    return jobs.expand((job) => job.stops).toList();
  }
}

/// Break type for driver rest periods during shift
enum DriverBreakType {
  CONTINUOUS_30, // 30 minutes continuous break
  SPLIT_3x10,    // 3 separate 10-minute breaks
}

/// Represents a driver break during a shift
class DriverBreak {
  final DriverBreakType type;
  final DateTime startTime;
  final int durationMinutes;
  final String? stopId;
  final String? stopName;
  
  DriverBreak({
    required this.type,
    required this.startTime,
    required this.durationMinutes,
    this.stopId,
    this.stopName,
  });
  
  /// End time of the break
  DateTime get endTime => startTime.add(Duration(minutes: durationMinutes));
  
  /// Check if this is a continuous 30-minute break
  bool get isContinuous => type == DriverBreakType.CONTINUOUS_30;
  
  /// Check if this is part of a split break
  bool get isSplit => type == DriverBreakType.SPLIT_3x10;
}

/// Represents a handover point between two drivers (20-minute break)
class ShiftHandover {
  final String stopId;
  final String stopName;
  final DateTime handoverTime;
  final String fromDriverId;
  final String toDriverId;
  final int breakDurationMinutes; // Usually 20 minutes
  
  ShiftHandover({
    required this.stopId,
    required this.stopName,
    required this.handoverTime,
    required this.fromDriverId,
    required this.toDriverId,
    this.breakDurationMinutes = 20,
  });
  
  /// End time of the handover break
  DateTime get breakEndTime => handoverTime.add(Duration(minutes: breakDurationMinutes));
}

/// Container for all shifts of a single vehicle for 24 hours
class VehicleShiftSchedule {
  final String vehicleId;
  final List<DriverShift> shifts;
  final List<ShiftHandover> handovers;
  
  VehicleShiftSchedule({
    required this.vehicleId,
    required this.shifts,
    required this.handovers,
  });
  
  /// Total number of drivers needed for this vehicle
  int get driverCount => shifts.length;
  
  /// Check if any shift violates the 8-hour rule
  bool get hasOvertimeShifts => shifts.any((s) => s.isOvertime);
  
  /// Get all unique driver IDs
  Set<String> get driverIds => shifts.map((s) => s.driverId).toSet();
}

/// Summary of driver's total workload across all assigned shifts
class DriverWorkload {
  final String driverId;
  final List<DriverShift> assignedShifts;
  
  DriverWorkload({
    required this.driverId,
    required this.assignedShifts,
  });
  
  /// Total minutes worked across all shifts (working time, excluding breaks)
  int get totalMinutes => assignedShifts.fold(0, (sum, shift) => sum + shift.workingMinutes);
  
  /// Total hours worked (working time)
  double get totalHours => totalMinutes / 60.0;
  
  /// Formatted workload string
  String get formattedWorkload {
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return '${hours}h ${minutes}min';
  }
  
  /// Check if driver is overloaded (>8 hours working time)
  bool get isOverloaded => totalMinutes > 480;
}
