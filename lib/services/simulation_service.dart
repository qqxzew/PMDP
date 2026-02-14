import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/timetable_models.dart';
import '../models/gtfs_models.dart';
import 'live_simulation_engine.dart';
import 'osrm_routing_service.dart';

/// Represents the live position and state of one vehicle on the map.
class VehiclePosition {
  final String vehicleId;
  final String lineNumber;
  final LatLng position;
  final String? currentStopName;
  final String? nextStopName;
  final bool isWaiting; // waiting at a transfer node
  final DateTime? waitUntil; // when it will depart after wait
  final double heading; // bearing in degrees (0=N, 90=E)

  const VehiclePosition({
    required this.vehicleId,
    required this.lineNumber,
    required this.position,
    this.currentStopName,
    this.nextStopName,
    this.isWaiting = false,
    this.waitUntil,
    this.heading = 0,
  });
}

/// Service that computes live bus positions based on the generated timetable.
///
/// Runs a timer that ticks every second, interpolating each vehicle's position
/// between stops using stop_times and (if available) OSRM road polylines.
class SimulationService extends ChangeNotifier {
  final LiveSimulationEngine engine;
  final OsrmRoutingService? routingService;

  SimulationService(this.engine, {this.routingService});

  Timer? _timer;
  DateTime _simTime = _getDefaultSimTime();
  double _speedMultiplier = 1.0;
  bool _running = false;

  /// Current vehicle positions, keyed by vehicleId.
  final Map<String, VehiclePosition> positions = {};

  // Время по умолчанию: 4:00 утра сегодня
  static DateTime _getDefaultSimTime() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 4, 0, 0);
  }

  // Inputs set once from AppState before starting.
  Map<String, GtfsStop> _stops = {};
  Map<String, List<TimetableJob>> _vehicleJobs = {};
  final Map<String, List<LatLng>> _segmentPolylines = {};
  final Set<String> _segmentFetchInFlight = {};

  DateTime get simTime => _simTime;
  double get speedMultiplier => _speedMultiplier;
  bool get isRunning => _running;

  /// Initialise simulation data.  Call once after timetable is generated.
  void load({
    required List<TimetableJob> jobs,
    required Map<String, GtfsStop> stops,
    required Map<String, List<TimetableJob>> vehicleJobs,
  }) {
    _stops = stops;
    _vehicleJobs = vehicleJobs;
    _segmentPolylines.clear();
    _segmentFetchInFlight.clear();
    // _buildStopPolylineKeys() removed
  }

  void setSpeed(double multiplier) {
    _speedMultiplier = multiplier.clamp(0.5, 60.0);
    notifyListeners();
  }

  void start() {
    if (_running) return;
    _running = true;
    // Если время еще не установлено, используем 4:00 утра
    _simTime = _getDefaultSimTime();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
    notifyListeners();
  }

  void startAt(DateTime time) {
    _simTime = time;
    if (!_running) {
      _running = true;
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
    }
    notifyListeners();
  }

  void pause() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    positions.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    // Advance simulation time by (real elapsed ≈ 200ms) * speedMultiplier.
    _simTime = _simTime.add(Duration(
      milliseconds: (200 * _speedMultiplier).round(),
    ));
    _updatePositions();
    notifyListeners();
  }

  void _updatePositions() {
    for (final entry in _vehicleJobs.entries) {
      final vid = entry.key;
      final jobs = entry.value;
      final pos = _computeVehiclePosition(vid, jobs);
      if (pos != null) {
        positions[vid] = pos;
      } else {
        positions.remove(vid);
      }
    }
  }

  VehiclePosition? _computeVehiclePosition(
      String vehicleId, List<TimetableJob> jobs) {
    // Find the active job – the one whose time window covers _simTime.
    TimetableJob? activeJob;
    for (final job in jobs) {
      final start = job.startTime;
      final end = job.endTime;
      if (start == null || end == null) continue;
      if (!_simTime.isBefore(start) && _simTime.isBefore(end.add(const Duration(minutes: 2)))) {
        activeJob = job;
        break;
      }
    }
    if (activeJob == null) return null;

    // Find surroundng stops.
    TimetableStop? prevStop;
    TimetableStop? nextStop;
    for (int i = 0; i < activeJob.stops.length; i++) {
      final s = activeJob.stops[i];
      final dep = s.departureTime ?? s.arrivalTime;
      final arr = s.arrivalTime ?? s.departureTime;
      if (dep == null || arr == null) continue;

      if (i + 1 < activeJob.stops.length) {
        final ns = activeJob.stops[i + 1];
        final nArr = ns.arrivalTime ?? ns.departureTime;
        if (nArr == null) continue;

        // Check if vehicle is waiting at this stop (Wait status at transfer)
        if (!_simTime.isBefore(arr) && _simTime.isBefore(dep)) {
          // Vehicle is dwelling at this stop
          final stopGeo = _stops[s.stopId];
          if (stopGeo == null) continue;
          return VehiclePosition(
            vehicleId: vehicleId,
            lineNumber: activeJob.lineNumber,
            position: LatLng(stopGeo.stopLat, stopGeo.stopLon),
            currentStopName: s.name,
            nextStopName: ns.name,
            isWaiting: s.transfers.isNotEmpty && dep.isAfter(arr),
            waitUntil: dep.isAfter(arr) ? dep : null,
          );
        }

        // Between stops: dep of current → arr of next.
        if (!_simTime.isBefore(dep) && _simTime.isBefore(nArr)) {
          prevStop = s;
          nextStop = ns;
          break;
        }
      } else {
        // Last stop – vehicle is at terminus.
        if (!_simTime.isBefore(arr)) {
          final stopGeo = _stops[s.stopId];
          if (stopGeo == null) return null;
          return VehiclePosition(
            vehicleId: vehicleId,
            lineNumber: activeJob.lineNumber,
            position: LatLng(stopGeo.stopLat, stopGeo.stopLon),
            currentStopName: s.name,
            isWaiting: false,
          );
        }
      }
    }

    if (prevStop == null || nextStop == null) {
      // Before first departure – show at first stop.
      final first = activeJob.stops.first;
      final geo = _stops[first.stopId];
      if (geo == null) return null;
      return VehiclePosition(
        vehicleId: vehicleId,
        lineNumber: activeJob.lineNumber,
        position: LatLng(geo.stopLat, geo.stopLon),
        currentStopName: first.name,
        isWaiting: false,
      );
    }

    // Interpolate position between prevStop and nextStop.
    final segStart = prevStop.departureTime!;
    final segEnd = nextStop.arrivalTime!;
    final segDuration = segEnd.difference(segStart).inMilliseconds;
    if (segDuration <= 0) {
      final geo = _stops[nextStop.stopId];
      if (geo == null) return null;
      return VehiclePosition(
        vehicleId: vehicleId,
        lineNumber: activeJob.lineNumber,
        position: LatLng(geo.stopLat, geo.stopLon),
        currentStopName: nextStop.name,
        isWaiting: false,
      );
    }

    final elapsed = _simTime.difference(segStart).inMilliseconds;
    final t = (elapsed / segDuration).clamp(0.0, 1.0);

    final pos = _interpolateByOsrmSegment(
      fromStopId: prevStop.stopId,
      toStopId: nextStop.stopId,
      t: t,
    );

    if (pos == null) return null;

    return VehiclePosition(
      vehicleId: vehicleId,
      lineNumber: activeJob.lineNumber,
      position: pos,
      currentStopName: prevStop.name,
      nextStopName: nextStop.name,
      isWaiting: false,
      heading: 0, // Simplified for now
    );
  }

  LatLng? _interpolateByOsrmSegment({
    required String fromStopId,
    required String toStopId,
    required double t,
  }) {
    final from = _stops[fromStopId];
    final to = _stops[toStopId];
    if (from == null || to == null) return null;

    final p1 = LatLng(from.stopLat, from.stopLon);
    final p2 = LatLng(to.stopLat, to.stopLon);
    final key = '${fromStopId}_$toStopId';

    final cached = _segmentPolylines[key];
    if (cached != null && cached.length >= 2) {
      return routingService?.interpolateAlongPolyline(cached, t) ??
          LatLng(
            p1.latitude + (p2.latitude - p1.latitude) * t,
            p1.longitude + (p2.longitude - p1.longitude) * t,
          );
    }

    if (routingService != null && !_segmentFetchInFlight.contains(key)) {
      _segmentFetchInFlight.add(key);
      unawaited(_fetchSegmentPolyline(
        key: key,
        fromStopId: fromStopId,
        toStopId: toStopId,
        from: p1,
        to: p2,
      ));
    }

    return LatLng(
      p1.latitude + (p2.latitude - p1.latitude) * t,
      p1.longitude + (p2.longitude - p1.longitude) * t,
    );
  }

  Future<void> _fetchSegmentPolyline({
    required String key,
    required String fromStopId,
    required String toStopId,
    required LatLng from,
    required LatLng to,
  }) async {
    try {
      final polyline = await routingService!.getSegmentPolyline(
        fromStopId: fromStopId,
        from: from,
        toStopId: toStopId,
        to: to,
      );
      if (polyline.length >= 2) {
        _segmentPolylines[key] = polyline;
      }
    } finally {
      _segmentFetchInFlight.remove(key);
    }
  }
}

