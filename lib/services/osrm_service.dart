import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Shared OSRM routing service – fetches road-following polylines
/// and caches them for reuse across screens.
class OsrmService {
  OsrmService._();
  static final OsrmService instance = OsrmService._();

  final Map<String, List<LatLng>> _cache = {};
  final Set<String> _pending = {};
  final Map<String, List<VoidCallback>> _listeners = {};

  /// Returns cached polyline or null. If null, fires an async fetch
  /// and calls [onReady] when done.
  List<LatLng>? getPolyline(String key, List<LatLng> waypoints,
      {VoidCallback? onReady}) {
    if (_cache.containsKey(key)) return _cache[key];
    _requestIfNeeded(key, waypoints, onReady);
    return null;
  }

  bool has(String key) => _cache.containsKey(key);

  /// Force-fetch and cache.  Returns road points or null.
  Future<List<LatLng>?> fetch(String key, List<LatLng> waypoints) async {
    if (_cache.containsKey(key)) return _cache[key];
    final result = await _fetchRoadPolyline(waypoints);
    if (result != null && result.length >= 2) {
      _cache[key] = result;
    }
    return result;
  }

  void _requestIfNeeded(
      String key, List<LatLng> waypoints, VoidCallback? onReady) {
    if (_cache.containsKey(key)) return;
    if (waypoints.length < 2) return;

    if (onReady != null) {
      _listeners.putIfAbsent(key, () => []).add(onReady);
    }

    if (_pending.contains(key)) return;
    _pending.add(key);

    _fetchRoadPolyline(waypoints).then((roadPoints) {
      _pending.remove(key);
      if (roadPoints != null && roadPoints.length >= 2) {
        _cache[key] = roadPoints;
      }
      final cbs = _listeners.remove(key);
      if (cbs != null) {
        for (final cb in cbs) {
          cb();
        }
      }
    });
  }

  Future<List<LatLng>?> _fetchRoadPolyline(List<LatLng> original) async {
    try {
      final points = _downsample(original, 90);
      final coordinates =
          points.map((p) => '${p.longitude},${p.latitude}').join(';');
      final uri = Uri.parse(
        'https://router.project-osrm.org/match/v1/driving/$coordinates'
        '?geometries=geojson&overview=full&tidy=true',
      );

      final response =
          await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final matchings = data['matchings'] as List<dynamic>?;
      if (matchings == null || matchings.isEmpty) return null;

      final roadPoints = <LatLng>[];
      for (final match in matchings) {
        final geometry =
            (match as Map<String, dynamic>)['geometry'] as Map<String, dynamic>?;
        final coords = geometry?['coordinates'] as List<dynamic>?;
        if (coords == null) continue;
        for (final c in coords) {
          final pair = c as List<dynamic>;
          if (pair.length < 2) continue;
          roadPoints
              .add(LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble()));
        }
      }
      return roadPoints;
    } catch (e) {
      debugPrint('OSRM fetch error: $e');
      return null;
    }
  }

  List<LatLng> _downsample(List<LatLng> points, int maxPoints) {
    if (points.length <= maxPoints) return points;
    final result = <LatLng>[];
    final step = (points.length - 1) / (maxPoints - 1);
    for (int i = 0; i < maxPoints; i++) {
      final idx = (i * step).round().clamp(0, points.length - 1);
      result.add(points[idx]);
    }
    return result;
  }

  /// Interpolate position along a polyline at fraction t ∈ [0,1].
  static LatLng interpolateAlong(List<LatLng> polyline, double t) {
    if (polyline.isEmpty) return const LatLng(0, 0);
    if (polyline.length == 1 || t <= 0) return polyline.first;
    if (t >= 1) return polyline.last;

    // Total distance
    final distances = <double>[0];
    double total = 0;
    for (int i = 1; i < polyline.length; i++) {
      total += const Distance().as(LengthUnit.Meter, polyline[i - 1], polyline[i]);
      distances.add(total);
    }
    if (total == 0) return polyline.first;

    final target = t * total;
    for (int i = 1; i < distances.length; i++) {
      if (distances[i] >= target) {
        final segStart = distances[i - 1];
        final segEnd = distances[i];
        final segLen = segEnd - segStart;
        final segT = segLen > 0 ? (target - segStart) / segLen : 0.0;
        final p1 = polyline[i - 1];
        final p2 = polyline[i];
        return LatLng(
          p1.latitude + (p2.latitude - p1.latitude) * segT,
          p1.longitude + (p2.longitude - p1.longitude) * segT,
        );
      }
    }
    return polyline.last;
  }
}
