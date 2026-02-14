// Service for automatically splitting vehicle jobs into 8-hour driver shifts

import '../models/timetable_models.dart';
import '../models/driver_shift_models.dart';

class ShiftSplitterService {
  static const int maxShiftMinutes = 8 * 60; // 8 hours
  static const int maxWorkingMinutes = 7 * 60 + 30; // 7.5 hours working time (leaves room for breaks)
  
  /// Main algorithm: Split vehicle's 24-hour job list into driver shifts
  static VehicleShiftSchedule splitIntoShifts(
    String vehicleId,
    List<TimetableJob> vehicleJobs, {
    int startDriverId = 1,
  }) {
    if (vehicleJobs.isEmpty) {
      return VehicleShiftSchedule(
        vehicleId: vehicleId,
        shifts: [],
        handovers: [],
      );
    }
    
    // Sort jobs by start time
    final sortedJobs = List<TimetableJob>.from(vehicleJobs)
      ..sort((a, b) => (a.startTime ?? DateTime(0))
          .compareTo(b.startTime ?? DateTime(0)));
    
    final shifts = <DriverShift>[];
    
    int driverCounter = startDriverId;
    int localDriverCounter = 1;
    int currentJobIndex = 0;
    DateTime? shiftStartTime;
    List<TimetableJob> currentShiftJobs = [];
    
    while (currentJobIndex < sortedJobs.length) {
      final job = sortedJobs[currentJobIndex];
      
      // Initialize shift start time
      if (shiftStartTime == null) {
        shiftStartTime = job.startTime ?? DateTime.now();
      }
      
      // Check if adding this job would exceed working time limit (7.5 hours)
      final jobEndTime = job.endTime ?? job.startTime ?? DateTime.now();
      final potentialShiftDuration = jobEndTime.difference(shiftStartTime).inMinutes;
      
      if (potentialShiftDuration <= maxWorkingMinutes) {
        // Add job to current shift
        currentShiftJobs.add(job);
        currentJobIndex++;
        
        // Check if this is the last job
        if (currentJobIndex >= sortedJobs.length) {
          // Finalize last shift
          _finalizeShift(
            shifts: shifts,
            vehicleId: vehicleId,
            driverCounter: driverCounter,
            shiftStartTime: shiftStartTime,
            shiftJobs: currentShiftJobs,
          );
        }
      } else {
        // This job would exceed working time limit - need to split here
        
        // Find the best handover point within the current jobs
        final handoverResult = _findHandoverPoint(
          currentShiftJobs,
          shiftStartTime,
          maxWorkingMinutes, // Use working time limit
        );
        
        if (handoverResult != null) {
          // Finalize current shift
          _finalizeShift(
            shifts: shifts,
            vehicleId: vehicleId,
            driverCounter: driverCounter,
            shiftStartTime: shiftStartTime,
            shiftJobs: currentShiftJobs,
          );
          
          // Start new shift immediately (no handover break)
          driverCounter++;
          localDriverCounter++;
          shiftStartTime = handoverResult.handoverTime;
          currentShiftJobs = [];
        } else {
          // No good handover point found - add job anyway (will be overtime)
          currentShiftJobs.add(job);
          currentJobIndex++;
        }
      }
    }
    
    return VehicleShiftSchedule(
      vehicleId: vehicleId,
      shifts: shifts,
      handovers: [], // No more handovers
    );
  }
  
  /// Find the best handover point (nearest stop before 8-hour limit)
  static _HandoverPoint? _findHandoverPoint(
    List<TimetableJob> jobs,
    DateTime shiftStart,
    int maxMinutes,
  ) {
    TimetableStop? bestStop;
    DateTime? bestTime;
    
    for (final job in jobs) {
      for (final stop in job.stops) {
        final stopTime = stop.arrivalTime ?? stop.departureTime;
        if (stopTime == null) continue;
        
        final minutesFromStart = stopTime.difference(shiftStart).inMinutes;
        
        // Find stop closest to but not exceeding the limit
        if (minutesFromStart <= maxMinutes && minutesFromStart >= maxMinutes - 30) {
          if (bestTime == null || stopTime.isAfter(bestTime)) {
            bestStop = stop;
            bestTime = stopTime;
          }
        }
      }
    }
    
    if (bestStop != null && bestTime != null) {
      return _HandoverPoint(
        stopId: bestStop.stopId,
        stopName: bestStop.name,
        handoverTime: bestTime,
      );
    }
    
    return null;
  }
  
  /// Adjust all times in remaining jobs by adding delay minutes
  static void _adjustSubsequentTimes(
    List<TimetableJob> jobs,
    int startIndex,
    int delayMinutes,
  ) {
    final delay = Duration(minutes: delayMinutes);
    
    for (int i = startIndex; i < jobs.length; i++) {
      final job = jobs[i];
      
      // Create new stops with adjusted times
      final adjustedStops = job.stops.map((stop) {
        return TimetableStop(
          stopId: stop.stopId,
          name: stop.name,
          arrivalTime: stop.arrivalTime?.add(delay),
          departureTime: stop.departureTime?.add(delay),
          isTerminus: stop.isTerminus,
          transfers: stop.transfers,
        );
      }).toList();
      
      // Replace job stops with adjusted ones
      jobs[i] = TimetableJob(
        jobId: job.jobId,
        lineNumber: job.lineNumber,
        vehicleId: job.vehicleId,
        driverId: job.driverId,
        stops: adjustedStops,
      );
    }
  }
  
  /// Finalize and add shift to list
  static void _finalizeShift({
    required List<DriverShift> shifts,
    required String vehicleId,
    required int driverCounter,
    required DateTime shiftStartTime,
    required List<TimetableJob> shiftJobs,
  }) {
    if (shiftJobs.isEmpty) return;
    
    final driverId = 'D${driverCounter.toString().padLeft(3, '0')}';
    final lastJob = shiftJobs.last;
    final shiftEndTime = lastJob.endTime ?? lastJob.startTime ?? shiftStartTime;
    
    // Generate breaks for this shift (30min continuous or 3x10min)
    final breaks = _generateBreaksForShift(shiftJobs, shiftStartTime);
    
    final shift = DriverShift(
      shiftId: '$vehicleId-S$driverCounter',
      driverId: driverId,
      vehicleId: vehicleId,
      startTime: shiftStartTime,
      endTime: shiftEndTime,
      jobs: List.from(shiftJobs),
      breaks: breaks,
      handoverOut: null, // No handovers
    );
    
    shifts.add(shift);
  }
  
  /// Generate driver breaks for a shift (30min continuous OR 3x10min)
  /// Returns list of breaks positioned at good stopping points
  static List<DriverBreak> _generateBreaksForShift(
    List<TimetableJob> shiftJobs,
    DateTime shiftStartTime,
  ) {
    if (shiftJobs.isEmpty) return [];
    
    // Calculate total shift working time
    final lastJob = shiftJobs.last;
    final lastStop = lastJob.stops.isNotEmpty ? lastJob.stops.last : null;
    if (lastStop == null) return [];
    
    final shiftEndTime = lastStop.departureTime ?? lastStop.arrivalTime ?? shiftStartTime;
    final totalMinutes = shiftEndTime.difference(shiftStartTime).inMinutes;
    
    // If shift is short (<3 hours) or invalid, no break needed
    if (totalMinutes < 180 || totalMinutes <= 0) return [];
    
    // Decide break type: use 3x10min for shifts 3-6 hours, 30min for longer shifts
    final use3x10 = totalMinutes < 360; // Less than 6 hours
    
    if (use3x10) {
      return _generate3x10Breaks(shiftJobs, shiftStartTime, totalMinutes);
    } else {
      return _generate30MinBreak(shiftJobs, shiftStartTime, totalMinutes);
    }
  }
  
  /// Generate a single 30-minute continuous break around midpoint
  static List<DriverBreak> _generate30MinBreak(
    List<TimetableJob> shiftJobs,
    DateTime shiftStartTime,
    int totalMinutes,
  ) {
    // Target: around 50% of shift duration
    final targetMinutes = totalMinutes ~/ 2;
    
    // Find a terminus stop near the midpoint
    TimetableStop? breakStop;
    DateTime? breakTime;
    int closestDiff = 999999;
    
    for (final job in shiftJobs) {
      for (final stop in job.stops) {
        if (!stop.isTerminus) continue;
        
        final stopTime = stop.arrivalTime ?? stop.departureTime;
        if (stopTime == null) continue;
        
        final minutesFromStart = stopTime.difference(shiftStartTime).inMinutes;
        final diff = (minutesFromStart - targetMinutes).abs();
        
        if (diff < closestDiff) {
          closestDiff = diff;
          breakStop = stop;
          breakTime = stopTime;
        }
      }
    }
    
    if (breakStop != null && breakTime != null) {
      return [
        DriverBreak(
          type: DriverBreakType.CONTINUOUS_30,
          startTime: breakTime,
          durationMinutes: 30,
          stopId: breakStop.stopId,
          stopName: breakStop.name,
        ),
      ];
    }
    
    return [];
  }
  
  /// Generate 3 separate 10-minute breaks distributed across shift
  static List<DriverBreak> _generate3x10Breaks(
    List<TimetableJob> shiftJobs,
    DateTime shiftStartTime,
    int totalMinutes,
  ) {
    // Target: 25%, 50%, 75% of shift duration
    final targets = [
      totalMinutes ~/ 4,      // 25%
      totalMinutes ~/ 2,      // 50%
      (totalMinutes * 3) ~/ 4, // 75%
    ];
    
    final breaks = <DriverBreak>[];
    
    for (final targetMinutes in targets) {
      TimetableStop? breakStop;
      DateTime? breakTime;
      int closestDiff = 999999;
      
      // Find nearest terminus
      for (final job in shiftJobs) {
        for (final stop in job.stops) {
          if (!stop.isTerminus) continue;
          
          final stopTime = stop.arrivalTime ?? stop.departureTime;
          if (stopTime == null) continue;
          
          final minutesFromStart = stopTime.difference(shiftStartTime).inMinutes;
          final diff = (minutesFromStart - targetMinutes).abs();
          
          if (diff < closestDiff) {
            closestDiff = diff;
            breakStop = stop;
            breakTime = stopTime;
          }
        }
      }
      
      if (breakStop != null && breakTime != null) {
        breaks.add(DriverBreak(
          type: DriverBreakType.SPLIT_3x10,
          startTime: breakTime,
          durationMinutes: 10,
          stopId: breakStop.stopId,
          stopName: breakStop.name,
        ));
      }
    }
    
    return breaks;
  }
  
  /// Fix overtime shifts by adding delays between jobs
  /// Returns new job list with adjusted times, or null if fix failed
  static List<TimetableJob>? fixOvertimeShifts(
    String vehicleId,
    List<TimetableJob> vehicleJobs,
  ) {
    if (vehicleJobs.isEmpty) return vehicleJobs;
    
    // Try different delay amounts (2, 3, 5 minutes)
    for (final delayMinutes in [2, 3, 5]) {
      final adjustedJobs = _addDelaysBetweenJobs(vehicleJobs, delayMinutes);
      
      // Test if this fixes overtime without creating new problems
      final testSchedule = splitIntoShifts(vehicleId, adjustedJobs);
      
      // Check if all shifts are now under 8 hours
      final hasOvertimne = testSchedule.shifts.any((s) => s.isOvertime);
      
      if (!hasOvertimne) {
        // Success! Return adjusted jobs
        return adjustedJobs;
      }
    }
    
    // If simple delays don't work, try adding longer breaks at specific points
    for (final breakMinutes in [5, 10, 15]) {
      final adjustedJobs = _addStrategicBreaks(vehicleJobs, breakMinutes);
      final testSchedule = splitIntoShifts(vehicleId, adjustedJobs);
      
      if (!testSchedule.shifts.any((s) => s.isOvertime)) {
        return adjustedJobs;
      }
    }
    
    // Could not fix - return null to indicate failure
    return null;
  }
  
  /// Add uniform delays between all jobs
  static List<TimetableJob> _addDelaysBetweenJobs(
    List<TimetableJob> jobs,
    int delayMinutes,
  ) {
    final sortedJobs = List<TimetableJob>.from(jobs)
      ..sort((a, b) => (a.startTime ?? DateTime(0))
          .compareTo(b.startTime ?? DateTime(0)));
    
    final adjustedJobs = <TimetableJob>[];
    Duration cumulativeDelay = Duration.zero;
    
    for (int i = 0; i < sortedJobs.length; i++) {
      final job = sortedJobs[i];
      
      // Add cumulative delay to this job
      if (i > 0) {
        cumulativeDelay += Duration(minutes: delayMinutes);
      }
      
      // Create adjusted stops
      final adjustedStops = job.stops.map((stop) {
        return TimetableStop(
          stopId: stop.stopId,
          name: stop.name,
          arrivalTime: stop.arrivalTime?.add(cumulativeDelay),
          departureTime: stop.departureTime?.add(cumulativeDelay),
          isTerminus: stop.isTerminus,
          transfers: stop.transfers,
        );
      }).toList();
      
      adjustedJobs.add(TimetableJob(
        jobId: job.jobId,
        lineNumber: job.lineNumber,
        vehicleId: job.vehicleId,
        driverId: job.driverId,
        stops: adjustedStops,
      ));
    }
    
    return adjustedJobs;
  }
  
  /// Add strategic breaks at points where shifts would exceed 8 hours
  static List<TimetableJob> _addStrategicBreaks(
    List<TimetableJob> jobs,
    int breakMinutes,
  ) {
    final sortedJobs = List<TimetableJob>.from(jobs)
      ..sort((a, b) => (a.startTime ?? DateTime(0))
          .compareTo(b.startTime ?? DateTime(0)));
    
    if (sortedJobs.isEmpty) return jobs;
    
    final adjustedJobs = <TimetableJob>[];
    Duration cumulativeDelay = Duration.zero;
    DateTime? shiftStartTime;
    
    for (int i = 0; i < sortedJobs.length; i++) {
      final job = sortedJobs[i];
      
      if (shiftStartTime == null) {
        shiftStartTime = job.startTime;
      }
      
      // Check if we're approaching 8-hour limit (7.5 hours)
      final jobStartWithDelay = job.startTime?.add(cumulativeDelay);
      if (jobStartWithDelay != null && shiftStartTime != null) {
        final minutesFromStart = jobStartWithDelay.difference(shiftStartTime).inMinutes;
        
        if (minutesFromStart > 450) { // 7.5 hours
          // Add a strategic break before this job
          cumulativeDelay += Duration(minutes: breakMinutes);
          shiftStartTime = null; // Reset shift start
        }
      }
      
      // Create adjusted stops
      final adjustedStops = job.stops.map((stop) {
        return TimetableStop(
          stopId: stop.stopId,
          name: stop.name,
          arrivalTime: stop.arrivalTime?.add(cumulativeDelay),
          departureTime: stop.departureTime?.add(cumulativeDelay),
          isTerminus: stop.isTerminus,
          transfers: stop.transfers,
        );
      }).toList();
      
      adjustedJobs.add(TimetableJob(
        jobId: job.jobId,
        lineNumber: job.lineNumber,
        vehicleId: job.vehicleId,
        driverId: job.driverId,
        stops: adjustedStops,
      ));
    }
    
    return adjustedJobs;
  }
  
  /// Calculate total workload for each driver across all vehicles
  static List<DriverWorkload> calculateDriverWorkloads(
    List<VehicleShiftSchedule> allVehicleSchedules,
  ) {
    final Map<String, List<DriverShift>> driverShiftsMap = {};
    
    for (final schedule in allVehicleSchedules) {
      for (final shift in schedule.shifts) {
        driverShiftsMap
            .putIfAbsent(shift.driverId, () => [])
            .add(shift);
      }
    }
    
    return driverShiftsMap.entries
        .map((e) => DriverWorkload(
              driverId: e.key,
              assignedShifts: e.value,
            ))
        .toList()
      ..sort((a, b) => a.driverId.compareTo(b.driverId));
  }
}

/// Internal helper class for handover point
class _HandoverPoint {
  final String stopId;
  final String stopName;
  final DateTime handoverTime;
  
  _HandoverPoint({
    required this.stopId,
    required this.stopName,
    required this.handoverTime,
  });
}
