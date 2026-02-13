import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/timetable_models.dart';
import '../models/gtfs_models.dart';
import '../services/osrm_service.dart';

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
  SimulationService();

  Timer? _timer;
  DateTime _simTime = DateTime.now();
  double _speedMultiplier = 1.0;
  bool _running = false;

  /// Current vehicle positions, keyed by vehicleId.
  final Map<String, VehiclePosition> positions = {};

  // Inputs set once from AppState before starting.
  List<TimetableJob> _jobs = [];
  Map<String, GtfsStop> _stops = {};
  Map<String, List<TimetableJob>> _vehicleJobs = {};

  DateTime get simTime => _simTime;
  double get speedMultiplier => _speedMultiplier;
  bool get isRunning => _running;

  /// Initialise simulation data.  Call once after timetable is generated.
  void load({
    required List<TimetableJob> jobs,
    required Map<String, GtfsStop> stops,
    required Map<String, List<TimetableJob>> vehicleJobs,
  }) {
    _jobs = jobs;
    _stops = stops;
    _vehicleJobs = vehicleJobs;
    _buildStopPolylineKeys();
  }

  // Pre-request OSRM for every active route segment so polylines are cached
  // by the time we need them.
  void _buildStopPolylineKeys() {
    // group jobs by lineNumber + direction to avoid duplicate requests
    final seen = <String>{};
    for (final job in _jobs) {
      final dirKey = '${job.lineNumber}-${job.direction}';
      if (seen.contains(dirKey)) continue;
      seen.add(dirKey);

      final points = <LatLng>[];
      for (final stop in job.stops) {
        final s = _stops[stop.stopId];
        if (s != null && s.stopLat != 0 && s.stopLon != 0) {
          points.add(LatLng(s.stopLat, s.stopLon));
        }
      }
      if (points.length >= 2) {
        OsrmService.instance.fetch('sim-$dirKey', points);
      }
    }
  }

  void setSpeed(double multiplier) {
    _speedMultiplier = multiplier.clamp(0.5, 60.0);
    notifyListeners();
  }

  void start() {
    if (_running) return;
    _running = true;
    _simTime = DateTime.now();
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

    // Try to use road polyline.
    final dirKey = 'sim-${activeJob.lineNumber}-${activeJob.direction}';
    final roadPoly = OsrmService.instance.has(dirKey)
        ? OsrmService.instance.getPolyline(dirKey, [])
        : null;

    LatLng pos;
    double heading = 0;

    if (roadPoly != null && roadPoly.length >= 2) {
      // Find sub-segment of road polyline between prevStop and nextStop coords.
      final p1 = _stops[prevStop.stopId];
      final p2 = _stops[nextStop.stopId];
      if (p1 != null && p2 != null) {
        final seg = _extractSubPolyline(
          roadPoly,
          LatLng(p1.stopLat, p1.stopLon),
          LatLng(p2.stopLat, p2.stopLon),
        );
        if (seg.length >= 2) {
          pos = OsrmService.interpolateAlong(seg, t);
          // Compute heading from nearby point.
          final t2 = (t + 0.01).clamp(0.0, 1.0);
          final next = OsrmService.interpolateAlong(seg, t2);
          heading = _bearing(pos, next);
        } else {
          pos = _lerp(
            LatLng(p1.stopLat, p1.stopLon),
            LatLng(p2.stopLat, p2.stopLon),
            t,
          );
          heading = _bearing(
            LatLng(p1.stopLat, p1.stopLon),
            LatLng(p2.stopLat, p2.stopLon),
          );
        }
      } else {
        pos = const LatLng(0, 0);
      }
    } else {
      final p1 = _stops[prevStop.stopId];
      final p2 = _stops[nextStop.stopId];
      if (p1 == null || p2 == null) return null;
      pos = _lerp(
        LatLng(p1.stopLat, p1.stopLon),
        LatLng(p2.stopLat, p2.stopLon),
        t,
      );
      heading = _bearing(
        LatLng(p1.stopLat, p1.stopLon),
        LatLng(p2.stopLat, p2.stopLon),
      );
    }

    return VehiclePosition(
      vehicleId: vehicleId,
      lineNumber: activeJob.lineNumber,
      position: pos,
      currentStopName: prevStop.name,
      nextStopName: nextStop.name,
      isWaiting: false,
      heading: heading,
    );
  }

  /// Extract the sub-section of [poly] closest to [from] → [to].
  List<LatLng> _extractSubPolyline(
      List<LatLng> poly, LatLng from, LatLng to) {
    int nearestFrom = 0;
    int nearestTo = poly.length - 1;
    double minD1 = double.infinity, minD2 = double.infinity;
    const dist = Distance();
    for (int i = 0; i < poly.length; i++) {
      final d1 = dist.as(LengthUnit.Meter, poly[i], from);
      if (d1 < minD1) {
        minD1 = d1;
        nearestFrom = i;
      }
      final d2 = dist.as(LengthUnit.Meter, poly[i], to);
      if (d2 < minD2) {
        minD2 = d2;
        nearestTo = i;
      }
    }
    if (nearestFrom > nearestTo) {
      final tmp = nearestFrom;
      nearestFrom = nearestTo;
      nearestTo = tmp;
    }
    if (nearestTo - nearestFrom < 1) return [from, to];
    return poly.sublist(nearestFrom, nearestTo + 1);
  }

  LatLng _lerp(LatLng a, LatLng b, double t) {
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  double _bearing(LatLng from, LatLng to) {
    final dLon = _deg2rad(to.longitude - from.longitude);
    final y = math.sin(dLon) * math.cos(_deg2rad(to.latitude));
    final x = math.cos(_deg2rad(from.latitude)) *
            math.sin(_deg2rad(to.latitude)) -
        math.sin(_deg2rad(from.latitude)) *
            math.cos(_deg2rad(to.latitude)) *
            math.cos(dLon);
    return (_rad2deg(math.atan2(y, x)) + 360) % 360;
  }

  double _deg2rad(double d) => d * math.pi / 180;
  double _rad2deg(double r) => r * 180 / math.pi;
}
