import 'dart:math' as math;

import 'package:uuid/uuid.dart';
import 'package:latlong2/latlong.dart';
import '../models/gtfs_models.dart';
import '../models/timetable_models.dart';
import '../models/transfer_node.dart';
import 'osrm_routing_service.dart';

/// Service for generating emergency timetables
class TimetableGenerator {
  static const _uuid = Uuid();
  static const double _rerouteSpeedKmh = 20.0;

  final OsrmRoutingService? routingService;

  TimetableGenerator({this.routingService});

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
  static const int maxDrivingHours = 8; // Max 8 hours driving per shift
  static const int mandatoryBreakMinutes = 45; // After 4.5 hours
  static const int maxDrivingBeforeBreak = 270; // 4.5 hours in minutes
  static const int minDailyRestHours = 11; // Min daily rest
  static const int maxShiftHours = 8; // Max shift length (EU regulations)

  /// Generate all timetable jobs for all routes
  Future<List<TimetableJob>> generateTimetable({
    required List<RouteData> routes,
    required Map<String, GtfsStop> stops,
    required List<TransferNode> transferNodes,
    required DateTime operationDate,
  }) async {
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
    await _optimizeTransferMeetings(
      allJobs: allJobs,
      transferNodes: enabledTransfers,
      stops: stops,
    );

    // Apply transfer information
    _applyTransfers(allJobs, enabledTransfers, stops);

    // Assign drivers with 8-hour shifts
    _assignDriverShifts(allJobs);

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
    
    // Assign vehicle IDs
    final vehicleIds = List.generate(
        busCount, (i) => 'V${route.route.routeShortName}-${i + 1}');

    // Calculate trip duration for each direction
    final forwardDuration = _calculateTripDuration(route.forwardStopTimes);
    final backwardDuration = _calculateTripDuration(route.backwardStopTimes);
    
    // Turnaround time at terminus (rest/recovery time)
    const turnaroundMinutes = 5;
    
    // Calculate cycle time (round trip time)
    final cycleTime = forwardDuration.inMinutes + backwardDuration.inMinutes + (turnaroundMinutes * 2);
    
    // Service hours (4:00 - 24:00)
    const startHour = 4;
    const endHour = 24;
    const serviceMinutes = (endHour - startHour) * 60;
    
    // Stagger vehicle start times to maintain frequency
    final startTimeOffset = cycleTime ~/ busCount;
    
    // Generate jobs for each vehicle
    for (int busIndex = 0; busIndex < busCount; busIndex++) {
      final vehicleId = vehicleIds[busIndex];
      
      // Staggered start time for this vehicle
      var currentTime = Duration(minutes: startHour * 60 + (busIndex * startTimeOffset));
      var currentDirection = 0; // Start with forward direction
      
      // Generate trips for this vehicle throughout the day
      while (currentTime.inMinutes < endHour * 60) {
        final job = _createJob(
          route: route,
          stops: stops,
          operationDate: operationDate,
          departureOffset: currentTime,
          directionId: currentDirection,
          vehicleId: vehicleId,
        );
        
        if (job != null) {
          jobs.add(job);
          
          // Calculate next departure time
          final tripDuration = currentDirection == 0 ? forwardDuration : backwardDuration;
          currentTime = currentTime + tripDuration + const Duration(minutes: turnaroundMinutes);
          
          // Alternate direction (round trip logic)
          currentDirection = currentDirection == 0 ? 1 : 0;
        } else {
          break;
        }
      }
    }

    return jobs;
  }
  
  /// Calculate trip duration from stop times
  Duration _calculateTripDuration(List<GtfsStopTime> stopTimes) {
    if (stopTimes.isEmpty) return Duration.zero;
    
    final firstStop = stopTimes.first;
    final lastStop = stopTimes.last;
    
    final duration = lastStop.arrivalTime - firstStop.departureTime;
    return duration;
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
                status: waitDuration.inMinutes > 0 ? 'Wait' : 'Sync',
              ));
            }
          }
        }
      }
    }
  }

  Future<void> _optimizeTransferMeetings({
    required List<TimetableJob> allJobs,
    required List<TransferNode> transferNodes,
    required Map<String, GtfsStop> stops,
  }) async {
    for (final transfer in transferNodes) {
      if (!transfer.isSameStop) {
        await _applyReroutingForTransfer(allJobs, transfer, stops);
      }
      _synchronizeTransferPair(allJobs, transfer);
    }
  }

  Future<void> _applyReroutingForTransfer(
    List<TimetableJob> allJobs,
    TransferNode transfer,
    Map<String, GtfsStop> stops,
  ) async {
    // Insert partner stop into Line 1 path
    for (int i = 0; i < allJobs.length; i++) {
      final job = allJobs[i];
      if (job.lineNumber != transfer.lineNumber1) continue;
      if (!job.stops.any((s) => s.stopId == transfer.stopId1)) continue;
      if (job.stops.any((s) => s.stopId == transfer.stopId2)) continue;

      final rerouted = await _insertRerouteStop(
        job: job,
        afterStopId: transfer.stopId1,
        insertedStopId: transfer.stopId2,
        stops: stops,
      );
      allJobs[i] = rerouted;
    }

    // Insert partner stop into Line 2 path
    for (int i = 0; i < allJobs.length; i++) {
      final job = allJobs[i];
      if (job.lineNumber != transfer.lineNumber2) continue;
      if (!job.stops.any((s) => s.stopId == transfer.stopId2)) continue;
      if (job.stops.any((s) => s.stopId == transfer.stopId1)) continue;

      final rerouted = await _insertRerouteStop(
        job: job,
        afterStopId: transfer.stopId2,
        insertedStopId: transfer.stopId1,
        stops: stops,
      );
      allJobs[i] = rerouted;
    }
  }

  Future<TimetableJob> _insertRerouteStop({
    required TimetableJob job,
    required String afterStopId,
    required String insertedStopId,
    required Map<String, GtfsStop> stops,
  }) async {
    final afterIndex = job.stops.indexWhere((s) => s.stopId == afterStopId);
    if (afterIndex < 0) return job;

    final afterStop = job.stops[afterIndex];
    final from = stops[afterStop.stopId];
    final inserted = stops[insertedStopId];
    if (from == null || inserted == null) return job;

    final baseDeparture = afterStop.departureTime ?? afterStop.arrivalTime;
    if (baseDeparture == null) return job;

    double distanceMeters;
    if (routingService != null) {
      final poly = await routingService!.getSegmentPolyline(
        fromStopId: from.stopId,
        from: LatLng(from.stopLat, from.stopLon),
        toStopId: inserted.stopId,
        to: LatLng(inserted.stopLat, inserted.stopLon),
      );
      distanceMeters = routingService!.polylineLengthMeters(poly);
      if (distanceMeters <= 0) {
        distanceMeters = _distanceMeters(
          from.stopLat,
          from.stopLon,
          inserted.stopLat,
          inserted.stopLon,
        );
      }
    } else {
      distanceMeters = _distanceMeters(
        from.stopLat,
        from.stopLon,
        inserted.stopLat,
        inserted.stopLon,
      );
    }
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
    final sourceLineJobs = allJobs
        .where((j) => j.lineNumber == transfer.lineNumber1)
        .where((j) => j.stops.any((s) => s.stopId == transfer.stopId1))
        .toList();
    final targetLineJobs = allJobs
        .where((j) => j.lineNumber == transfer.lineNumber2)
        .where((j) => j.stops.any((s) => s.stopId == transfer.stopId2))
        .toList();

    // Directional sync:
    // Departure(B) = Arrival(A) + gapMinutes
    for (final sourceJob in sourceLineJobs) {
      final sourceStop =
          sourceJob.stops.firstWhere((s) => s.stopId == transfer.stopId1);
      final arrivalA = sourceStop.arrivalTime;
      if (arrivalA == null) continue;

      TimetableJob? partnerB;
      int bestMinutes = 1 << 30;
      for (final targetJob in targetLineJobs) {
        if (targetJob.jobId == sourceJob.jobId) continue;
        final targetStop =
            targetJob.stops.firstWhere((s) => s.stopId == transfer.stopId2);
        final departureB = targetStop.departureTime ?? targetStop.arrivalTime;
        if (departureB == null) continue;
        final diff = (arrivalA.difference(departureB).inMinutes).abs();
        if (diff < bestMinutes) {
          bestMinutes = diff;
          partnerB = targetJob;
        }
      }
      if (partnerB == null) continue;

        final desiredDepartureB =
          arrivalA.add(Duration(minutes: transfer.maxWaitMinutes));

      final updatedTargetJob = _delayFromTransferStop(
        job: partnerB,
        transferStopId: transfer.stopId2,
        meetTime: desiredDepartureB,
      );

      _replaceJob(allJobs, updatedTargetJob);
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

  /// Assign drivers to jobs based on 8-hour shifts
  void _assignDriverShifts(List<TimetableJob> jobs) {
    // Group jobs by vehicle
    final vehicleJobs = <String, List<TimetableJob>>{};
    for (final job in jobs) {
      final vid = job.vehicleId ?? 'unassigned';
      vehicleJobs.putIfAbsent(vid, () => []);
      vehicleJobs[vid]!.add(job);
    }

    const maxShiftMinutes = 8 * 60;
    const handoverMinutes = 20;

    // Process each vehicle's schedule
    for (final entry in vehicleJobs.entries) {
      final vehicleId = entry.key;
      final jobsList = entry.value;

      // Sort by start time
      jobsList.sort((a, b) {
        final aTime = a.startTime ?? DateTime(2099);
        final bTime = b.startTime ?? DateTime(2099);
        return aTime.compareTo(bTime);
      });

      final firstStart = jobsList.first.startTime;
      final lastEnd = jobsList.last.endTime;
      if (firstStart == null || lastEnd == null) continue;

      final totalWindowMinutes =
          math.max(1, lastEnd.difference(firstStart).inMinutes);
      final shiftCount = math.max(1, (totalWindowMinutes / maxShiftMinutes).ceil());
      final segmentMinutes = (totalWindowMinutes / shiftCount).ceil();

      // Driver boundaries split whole daily window into 2-3+ equal segments.
      final boundaries = <DateTime>[];
      for (int i = 1; i < shiftCount; i++) {
        boundaries.add(firstStart.add(Duration(minutes: segmentMinutes * i)));
      }

      int driverNumber = 1;
      int boundaryIdx = 0;
      DateTime? currentDriverWindowStart = firstStart;

      for (int i = 0; i < jobsList.length; i++) {
        var job = jobsList[i];
        var jobStart = job.startTime;
        if (jobStart == null) continue;

        while (boundaryIdx < boundaries.length) {
          final currentStart = jobStart;
          if (currentStart == null || currentStart.isBefore(boundaries[boundaryIdx])) {
            break;
          }
          final previousEnd = i > 0 ? jobsList[i - 1].endTime : null;

          if (previousEnd != null) {
            final handoverTarget = previousEnd.add(const Duration(minutes: handoverMinutes));
            if (currentStart.isBefore(handoverTarget)) {
              final delta = handoverTarget.difference(currentStart);
              _delayJobsFromIndex(jobsList, i, delta, jobs);
              job = jobsList[i];
              jobStart = job.startTime;
              if (jobStart == null) break;
            }
            currentDriverWindowStart = handoverTarget;
          } else {
            currentDriverWindowStart = jobStart;
          }

          driverNumber++;
          boundaryIdx++;
        }

        if (jobStart == null) continue;
        final currentStart = jobStart;

        if (currentDriverWindowStart != null) {
          final workedMinutes = currentStart.difference(currentDriverWindowStart).inMinutes;
          if (workedMinutes >= maxShiftMinutes) {
            final previousEnd = i > 0 ? jobsList[i - 1].endTime : null;
            if (previousEnd != null) {
              final handoverTarget = previousEnd.add(const Duration(minutes: handoverMinutes));
              if (currentStart.isBefore(handoverTarget)) {
                final delta = handoverTarget.difference(currentStart);
                _delayJobsFromIndex(jobsList, i, delta, jobs);
                job = jobsList[i];
                jobStart = job.startTime;
              }
              currentDriverWindowStart = handoverTarget;
            } else {
              currentDriverWindowStart = jobStart;
            }
            driverNumber++;
          }
        }

        // Assign driver ID
        final driverId = 'D-$vehicleId-$driverNumber';

        // Create new job with driverId (jobs are immutable, so we need to replace)
        final updatedJob = TimetableJob(
          jobId: job.jobId,
          lineNumber: job.lineNumber,
          vehicleId: job.vehicleId,
          driverId: driverId,
          stops: job.stops,
        );

        // Replace in the original list
        final originalIndex = jobs.indexWhere((j) => j.jobId == job.jobId);
        if (originalIndex >= 0) {
          jobs[originalIndex] = updatedJob;
        }
      }
    }
  }

  void _delayJobsFromIndex(
    List<TimetableJob> vehicleJobs,
    int startIndex,
    Duration delta,
    List<TimetableJob> allJobs,
  ) {
    if (delta.inMinutes <= 0) return;

    for (int i = startIndex; i < vehicleJobs.length; i++) {
      final oldJob = vehicleJobs[i];
      final shiftedStops = oldJob.stops
          .map(
            (s) => TimetableStop(
              stopId: s.stopId,
              name: s.name,
              arrivalTime: s.arrivalTime?.add(delta),
              departureTime: s.departureTime?.add(delta),
              isTerminus: s.isTerminus,
              transfers: List<Transfer>.from(s.transfers),
            ),
          )
          .toList(growable: false);

      final shiftedJob = TimetableJob(
        jobId: oldJob.jobId,
        lineNumber: oldJob.lineNumber,
        vehicleId: oldJob.vehicleId,
        driverId: oldJob.driverId,
        stops: shiftedStops,
      );

      vehicleJobs[i] = shiftedJob;
      final idx = allJobs.indexWhere((j) => j.jobId == shiftedJob.jobId);
      if (idx >= 0) {
        allJobs[idx] = shiftedJob;
      }
    }
  }

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
