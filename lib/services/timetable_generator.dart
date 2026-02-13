import 'dart:math' as math;

import 'package:uuid/uuid.dart';
import '../models/gtfs_models.dart';
import '../models/timetable_models.dart';
import '../models/transfer_node.dart';

/// Service for generating emergency timetables
class TimetableGenerator {
  static const _uuid = Uuid();
  static const int _meetingBufferMinutes = 2;
  static const double _rerouteSpeedKmh = 20.0;

  /// Daily demand multipliers for each hour (0-23)
  /// Represents relative frequency: 1.0 = base interval, 0.5 = double frequency
  static const Map<int, double> demandMultipliers = {
    0: 0.15, // Noc - minimální provoz
    1: 0.10,
    2: 0.10,
    3: 0.10,
    4: 0.20,
    5: 0.50, // Brzy ráno - náběh
    6: 0.85, // Ranní špička
    7: 1.00, // Ranní špička - maximum
    8: 0.90, // Ranní špička
    9: 0.60, // Dopoledne
    10: 0.50,
    11: 0.55,
    12: 0.65, // Polední provoz
    13: 0.70, // Odpolední náběh
    14: 0.80, // Odpoledne
    15: 0.90, // Odpolední špička
    16: 1.00, // Odpolední špička - maximum
    17: 0.90, // Odpolední špička
    18: 0.70, // Podvečer
    19: 0.50, // Večer
    20: 0.40,
    21: 0.30,
    22: 0.25, // Pozdní večer
    23: 0.20, // Noc
  };

  /// Czech driver labor regulations
  static const int maxDrivingHours = 9; // Max 9 hours driving per day
  static const int mandatoryBreakMinutes = 45; // After 4.5 hours
  static const int maxDrivingBeforeBreak = 270; // 4.5 hours in minutes
  static const int minDailyRestHours = 11; // Min daily rest
  static const int maxShiftHours = 13; // Max shift length

  /// Generate all timetable jobs for all routes
  List<TimetableJob> generateTimetable({
    required List<RouteData> routes,
    required Map<String, GtfsStop> stops,
    required List<TransferNode> transferNodes,
    required DateTime operationDate,
  }) {
    final allJobs = <TimetableJob>[];

    for (final route in routes) {
      if (route.assignedBuses <= 0) continue;
      final routeJobs = _generateRouteJobs(
        route: route,
        stops: stops,
        operationDate: operationDate,
      );
      allJobs.addAll(routeJobs);
    }

    final enabledTransfers = transferNodes.where((t) => t.isEnabled).toList();

    // Crisis optimization: rerouting + synchronized meetings with wait buffer.
    _optimizeTransferMeetings(
      allJobs: allJobs,
      transferNodes: enabledTransfers,
      stops: stops,
    );

    // Apply transfer information
    _applyTransfers(allJobs, enabledTransfers, stops);

    return allJobs;
  }

  List<TimetableJob> _generateRouteJobs({
    required RouteData route,
    required Map<String, GtfsStop> stops,
    required DateTime operationDate,
  }) {
    final jobs = <TimetableJob>[];
    final baseInterval = route.intervalMinutes;
    if (baseInterval <= 0) return jobs;

    final busCount = route.assignedBuses;
    final halfBuses = (busCount / 2).ceil();
    final otherHalf = busCount - halfBuses;

    // Assign vehicle IDs
    final vehicleIds = List.generate(
        busCount, (i) => 'V${route.route.routeShortName}-${i + 1}');

    // Generate departures for 24 hours (0:00 - 23:59)
    // First, generate departure times respecting demand
    final forwardDepartures = _generateDepartureTimes(
      baseInterval: baseInterval,
      startHour: 4, // First service at 4:00
      endHour: 24, // Last departure
    );

    final backwardDepartures = _generateDepartureTimes(
      baseInterval: baseInterval,
      startHour: 4,
      endHour: 24,
    );

    // Offset backward departures by half interval for better coverage
    final halfOffset = Duration(minutes: baseInterval ~/ 2);
    final adjustedBackwardDepartures =
        backwardDepartures.map((d) => d + halfOffset).toList();

    // Distribute jobs among vehicles (round-robin)
    int vehicleIndex = 0;
    
    // Forward direction trips
    for (int i = 0; i < forwardDepartures.length; i++) {
      final departure = forwardDepartures[i];
      final vid = vehicleIds[vehicleIndex % halfBuses];
      
      final job = _createJob(
        route: route,
        stops: stops,
        operationDate: operationDate,
        departureOffset: departure,
        directionId: 0,
        vehicleId: vid,
      );
      if (job != null) jobs.add(job);
      
      vehicleIndex++;
    }

    // Backward direction trips
    vehicleIndex = 0;
    for (int i = 0; i < adjustedBackwardDepartures.length; i++) {
      final departure = adjustedBackwardDepartures[i];
      final vid = otherHalf > 0
          ? vehicleIds[halfBuses + (vehicleIndex % otherHalf)]
          : vehicleIds[vehicleIndex % halfBuses];
      
      final job = _createJob(
        route: route,
        stops: stops,
        operationDate: operationDate,
        departureOffset: departure,
        directionId: 1,
        vehicleId: vid,
      );
      if (job != null) jobs.add(job);
      
      vehicleIndex++;
    }

    return jobs;
  }

  /// Generate departure times respecting demand patterns
  List<Duration> _generateDepartureTimes({
    required int baseInterval,
    required int startHour,
    required int endHour,
  }) {
    final departures = <Duration>[];
    var currentMinutes = startHour * 60;
    final endMinutes = endHour * 60;

    while (currentMinutes < endMinutes) {
      departures.add(Duration(minutes: currentMinutes));

      // Calculate interval based on demand at current hour
      final hour = (currentMinutes ~/ 60).clamp(0, 23);
      final demand = demandMultipliers[hour] ?? 0.5;
      
      // Higher demand = shorter interval (more frequent)
      // Lower demand = longer interval (less frequent)
      final adjustedInterval = (baseInterval / demand).round().clamp(baseInterval, baseInterval * 6);
      
      currentMinutes += adjustedInterval;
    }

    return departures;
  }

  TimetableJob? _createJob({
    required RouteData route,
    required Map<String, GtfsStop> stops,
    required DateTime operationDate,
    required Duration departureOffset,
    required int directionId,
    required String vehicleId,
  }) {
    final stopTimes = directionId == 0
        ? route.forwardStopTimes
        : route.backwardStopTimes;
    
    if (stopTimes.isEmpty) return null;

    final baseOffset = stopTimes.first.departureTime;
    final timetableStops = <TimetableStop>[];

    for (int i = 0; i < stopTimes.length; i++) {
      final st = stopTimes[i];
      final stop = stops[st.stopId];
      if (stop == null) continue;

      final relativeArrival = st.arrivalTime - baseOffset;
      final relativeDeparture = st.departureTime - baseOffset;

      final arrivalTime = DateTime(
        operationDate.year,
        operationDate.month,
        operationDate.day,
      ).add(departureOffset + relativeArrival);

      final departureTime = DateTime(
        operationDate.year,
        operationDate.month,
        operationDate.day,
      ).add(departureOffset + relativeDeparture);

      timetableStops.add(TimetableStop(
        stopId: st.stopId,
        name: stop.stopName,
        arrivalTime: arrivalTime,
        departureTime: departureTime,
        isTerminus: i == 0 || i == stopTimes.length - 1,
      ));
    }

    return TimetableJob(
      jobId: _uuid.v4(),
      lineNumber: route.route.routeShortName,
      vehicleId: vehicleId,
      stops: timetableStops,
    );
  }

  /// Apply transfer information to timetable jobs
  void _applyTransfers(
    List<TimetableJob> allJobs,
    List<TransferNode> transferNodes,
    Map<String, GtfsStop> stops,
  ) {
    for (final job in allJobs) {
      for (final stop in job.stops) {
        for (final transfer in transferNodes) {
          // Check if this stop is part of a transfer node
          String? connectingStopId;
          String? connectingLine;

          if (stop.stopId == transfer.stopId1 &&
              job.lineNumber == transfer.lineNumber1) {
            connectingStopId = transfer.stopId2;
            connectingLine = transfer.lineNumber2;
          } else if (stop.stopId == transfer.stopId2 &&
              job.lineNumber == transfer.lineNumber2) {
            connectingStopId = transfer.stopId1;
            connectingLine = transfer.lineNumber1;
          } else if (stop.stopId == transfer.stopId1 &&
              job.lineNumber == transfer.lineNumber2) {
            connectingStopId = transfer.stopId2;
            connectingLine = transfer.lineNumber1;
          } else if (stop.stopId == transfer.stopId2 &&
              job.lineNumber == transfer.lineNumber1) {
            connectingStopId = transfer.stopId1;
            connectingLine = transfer.lineNumber2;
          }

          if (connectingLine == null || connectingStopId == null) continue;
          if (stop.arrivalTime == null) continue;

          // Find connecting jobs at this transfer point
          final connectingJobs = allJobs.where((j) =>
              j.lineNumber == connectingLine &&
              j.jobId != job.jobId &&
              j.stops.any((s) => s.stopId == connectingStopId));

          for (final cj in connectingJobs) {
            final connectingStop = cj.stops.firstWhere(
              (s) => s.stopId == connectingStopId,
            );
            
            if (connectingStop.departureTime == null) continue;

            // Check if connecting departure is within reasonable wait time
            final waitDuration = connectingStop.departureTime!
                .difference(stop.arrivalTime!);
            
            if (waitDuration.inMinutes >= 0 &&
                waitDuration.inMinutes <= transfer.maxWaitMinutes + 5) {
              final waitUntil = stop.arrivalTime!
                  .add(Duration(minutes: transfer.maxWaitMinutes));

              stop.transfers.add(Transfer(
                jobId: cj.jobId,
                lineNumber: cj.lineNumber,
                direction: cj.direction,
                waitUntil: waitUntil,
                isGuaranteed: waitDuration.inMinutes <= transfer.maxWaitMinutes,
                maxWaitMinutes: transfer.maxWaitMinutes,
              ));
            }
          }
        }
      }
    }
  }

  void _optimizeTransferMeetings({
    required List<TimetableJob> allJobs,
    required List<TransferNode> transferNodes,
    required Map<String, GtfsStop> stops,
  }) {
    for (final transfer in transferNodes) {
      if (!transfer.isSameStop) {
        _applyReroutingForTransfer(allJobs, transfer, stops);
      }
      _synchronizeTransferPair(allJobs, transfer);
    }
  }

  void _applyReroutingForTransfer(
    List<TimetableJob> allJobs,
    TransferNode transfer,
    Map<String, GtfsStop> stops,
  ) {
    for (int i = 0; i < allJobs.length; i++) {
      final job = allJobs[i];
      if (job.lineNumber != transfer.lineNumber1) continue;
      if (!job.stops.any((s) => s.stopId == transfer.stopId1)) continue;
      if (job.stops.any((s) => s.stopId == transfer.stopId2)) continue;

      final rerouted = _insertRerouteStop(
        job: job,
        afterStopId: transfer.stopId1,
        insertedStopId: transfer.stopId2,
        stops: stops,
      );
      allJobs[i] = rerouted;
    }
  }

  TimetableJob _insertRerouteStop({
    required TimetableJob job,
    required String afterStopId,
    required String insertedStopId,
    required Map<String, GtfsStop> stops,
  }) {
    final afterIndex = job.stops.indexWhere((s) => s.stopId == afterStopId);
    if (afterIndex < 0) return job;

    final afterStop = job.stops[afterIndex];
    final from = stops[afterStop.stopId];
    final inserted = stops[insertedStopId];
    if (from == null || inserted == null) return job;

    final baseDeparture = afterStop.departureTime ?? afterStop.arrivalTime;
    if (baseDeparture == null) return job;

    final distanceMeters = _distanceMeters(
      from.stopLat,
      from.stopLon,
      inserted.stopLat,
      inserted.stopLon,
    );
    final travelMinutes = math.max(1, (distanceMeters / 1000 / _rerouteSpeedKmh * 60).round());
    final insertedArrival = baseDeparture.add(Duration(minutes: travelMinutes));

    final updatedStops = <TimetableStop>[];
    for (int i = 0; i < job.stops.length; i++) {
      final s = job.stops[i];
      updatedStops.add(TimetableStop(
        stopId: s.stopId,
        name: s.name,
        arrivalTime: s.arrivalTime,
        departureTime: s.departureTime,
        isTerminus: s.isTerminus,
        transfers: List<Transfer>.from(s.transfers),
      ));

      if (i == afterIndex) {
        updatedStops.add(TimetableStop(
          stopId: inserted.stopId,
          name: inserted.stopName,
          arrivalTime: insertedArrival,
          departureTime: insertedArrival,
          isTerminus: false,
        ));
      }
    }

    final delta = Duration(minutes: travelMinutes);
    for (int i = afterIndex + 2; i < updatedStops.length; i++) {
      final s = updatedStops[i];
      updatedStops[i] = TimetableStop(
        stopId: s.stopId,
        name: s.name,
        arrivalTime: s.arrivalTime?.add(delta),
        departureTime: s.departureTime?.add(delta),
        isTerminus: s.isTerminus,
        transfers: List<Transfer>.from(s.transfers),
      );
    }

    return TimetableJob(
      jobId: job.jobId,
      lineNumber: job.lineNumber,
      vehicleId: job.vehicleId,
      stops: updatedStops,
    );
  }

  void _synchronizeTransferPair(
    List<TimetableJob> allJobs,
    TransferNode transfer,
  ) {
    final line1Jobs = allJobs
        .where((j) => j.lineNumber == transfer.lineNumber1)
        .where((j) => j.stops.any((s) => s.stopId == transfer.stopId1))
        .toList();
    final line2Jobs = allJobs
        .where((j) => j.lineNumber == transfer.lineNumber2)
        .where((j) => j.stops.any((s) => s.stopId == transfer.stopId2))
        .toList();

    for (final job1 in line1Jobs) {
      final stop1 = job1.stops.firstWhere((s) => s.stopId == transfer.stopId1);
      final arrival1 = stop1.arrivalTime;
      if (arrival1 == null) continue;

      TimetableJob? partner;
      int bestMinutes = 1 << 30;
      for (final job2 in line2Jobs) {
        if (job2.jobId == job1.jobId) continue;
        final stop2 = job2.stops.firstWhere((s) => s.stopId == transfer.stopId2);
        final arrival2 = stop2.arrivalTime;
        if (arrival2 == null) continue;
        final diff = (arrival1.difference(arrival2).inMinutes).abs();
        if (diff < bestMinutes) {
          bestMinutes = diff;
          partner = job2;
        }
      }
      if (partner == null) continue;

      final partnerStop =
          partner.stops.firstWhere((s) => s.stopId == transfer.stopId2);
      final arrival2 = partnerStop.arrivalTime;
      if (arrival2 == null) continue;

      final tMeet = (arrival1.isAfter(arrival2) ? arrival1 : arrival2)
          .add(const Duration(minutes: _meetingBufferMinutes));

      final updatedJob1 = _delayFromTransferStop(
        job: job1,
        transferStopId: transfer.stopId1,
        meetTime: tMeet,
      );
      final updatedJob2 = _delayFromTransferStop(
        job: partner,
        transferStopId: transfer.stopId2,
        meetTime: tMeet,
      );

      _replaceJob(allJobs, updatedJob1);
      _replaceJob(allJobs, updatedJob2);
    }
  }

  TimetableJob _delayFromTransferStop({
    required TimetableJob job,
    required String transferStopId,
    required DateTime meetTime,
  }) {
    final idx = job.stops.indexWhere((s) => s.stopId == transferStopId);
    if (idx < 0) return job;

    final transferStop = job.stops[idx];
    final originalDeparture = transferStop.departureTime ?? transferStop.arrivalTime;
    if (originalDeparture == null || !meetTime.isAfter(originalDeparture)) return job;

    final delta = meetTime.difference(originalDeparture);
    final updatedStops = <TimetableStop>[];

    for (int i = 0; i < job.stops.length; i++) {
      final s = job.stops[i];
      if (i < idx) {
        updatedStops.add(TimetableStop(
          stopId: s.stopId,
          name: s.name,
          arrivalTime: s.arrivalTime,
          departureTime: s.departureTime,
          isTerminus: s.isTerminus,
          transfers: List<Transfer>.from(s.transfers),
        ));
      } else if (i == idx) {
        updatedStops.add(TimetableStop(
          stopId: s.stopId,
          name: s.name,
          arrivalTime: s.arrivalTime,
          departureTime: meetTime,
          isTerminus: s.isTerminus,
          transfers: List<Transfer>.from(s.transfers),
        ));
      } else {
        updatedStops.add(TimetableStop(
          stopId: s.stopId,
          name: s.name,
          arrivalTime: s.arrivalTime?.add(delta),
          departureTime: s.departureTime?.add(delta),
          isTerminus: s.isTerminus,
          transfers: List<Transfer>.from(s.transfers),
        ));
      }
    }

    return TimetableJob(
      jobId: job.jobId,
      lineNumber: job.lineNumber,
      vehicleId: job.vehicleId,
      stops: updatedStops,
    );
  }

  void _replaceJob(List<TimetableJob> allJobs, TimetableJob updated) {
    final idx = allJobs.indexWhere((j) => j.jobId == updated.jobId);
    if (idx >= 0) {
      allJobs[idx] = updated;
    }
  }

  double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _degToRad(double deg) => deg * math.pi / 180.0;

  /// Get shift assignments respecting driver regulations
  Map<String, List<TimetableJob>> getVehicleShifts(List<TimetableJob> jobs) {
    final shifts = <String, List<TimetableJob>>{};
    
    for (final job in jobs) {
      final vid = job.vehicleId ?? 'unassigned';
      shifts.putIfAbsent(vid, () => []);
      shifts[vid]!.add(job);
    }

    // Sort each vehicle's jobs by start time
    for (final entry in shifts.entries) {
      entry.value.sort((a, b) {
        final aTime = a.startTime ?? DateTime(2099);
        final bTime = b.startTime ?? DateTime(2099);
        return aTime.compareTo(bTime);
      });
    }

    return shifts;
  }

  /// Check if a vehicle's schedule respects driver regulations
  DriverScheduleInfo checkDriverRegulations(List<TimetableJob> vehicleJobs) {
    if (vehicleJobs.isEmpty) {
      return DriverScheduleInfo(
        totalDrivingMinutes: 0,
        totalShiftMinutes: 0,
        needsBreak: false,
        breakAfterJob: null,
        isValid: true,
        warnings: [],
      );
    }

    final sorted = List<TimetableJob>.from(vehicleJobs)
      ..sort((a, b) => (a.startTime ?? DateTime(2099))
          .compareTo(b.startTime ?? DateTime(2099)));

    int totalDriving = 0;
    int consecutiveDriving = 0;
    String? breakAfterJob;
    final warnings = <String>[];

    for (int i = 0; i < sorted.length; i++) {
      final job = sorted[i];
      final start = job.startTime;
      final end = job.endTime;
      if (start == null || end == null) continue;

      final tripMinutes = end.difference(start).inMinutes;
      totalDriving += tripMinutes;
      consecutiveDriving += tripMinutes;

      if (consecutiveDriving >= maxDrivingBeforeBreak && breakAfterJob == null) {
        breakAfterJob = job.jobId;
      }
    }

    final shiftStart = sorted.first.startTime;
    final shiftEnd = sorted.last.endTime;
    final totalShift = shiftStart != null && shiftEnd != null
        ? shiftEnd.difference(shiftStart).inMinutes
        : 0;

    if (totalDriving > maxDrivingHours * 60) {
      warnings.add(
          'Překročen max. čas řízení: ${totalDriving ~/ 60}h ${totalDriving % 60}min / max ${maxDrivingHours}h');
    }
    if (totalShift > maxShiftHours * 60) {
      warnings.add(
          'Překročena max. délka směny: ${totalShift ~/ 60}h ${totalShift % 60}min / max ${maxShiftHours}h');
    }

    return DriverScheduleInfo(
      totalDrivingMinutes: totalDriving,
      totalShiftMinutes: totalShift,
      needsBreak: consecutiveDriving >= maxDrivingBeforeBreak,
      breakAfterJob: breakAfterJob,
      isValid: warnings.isEmpty,
      warnings: warnings,
    );
  }
}

class DriverScheduleInfo {
  final int totalDrivingMinutes;
  final int totalShiftMinutes;
  final bool needsBreak;
  final String? breakAfterJob;
  final bool isValid;
  final List<String> warnings;

  DriverScheduleInfo({
    required this.totalDrivingMinutes,
    required this.totalShiftMinutes,
    required this.needsBreak,
    this.breakAfterJob,
    required this.isValid,
    required this.warnings,
  });
}
