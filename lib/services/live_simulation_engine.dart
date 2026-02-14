import 'package:latlong2/latlong.dart';
import '../models/gtfs_models.dart';
import 'gtfs_parser.dart';

class LiveSimulationEngine {
  final GtfsParser parser;
  
  // Cache for trip shapes (to avoid re-searching every frame)
  final Map<String, List<GtfsShape>> _tripShapes = {};
  final Map<String, List<GtfsStopTime>> _tripStopTimes = {};
  
  // Cache for total shape distance if needed
  final Map<String, double> _shapeDistances = {};

  LiveSimulationEngine(this.parser);

  /// Main function to get position of a vehicle at a given time
  LatLng? getVehiclePosition(GtfsTrip trip, Duration currentTime) {
    final stopTimes = _getStopTimes(trip.tripId);
    if (stopTimes.isEmpty) return null;

    // 1. Find the active segment (between two stops)
    GtfsStopTime? prevStop;
    GtfsStopTime? nextStop;

    for (int i = 0; i < stopTimes.length - 1; i++) {
      if (currentTime >= stopTimes[i].departureTime && currentTime < stopTimes[i + 1].arrivalTime) {
        prevStop = stopTimes[i];
        nextStop = stopTimes[i + 1];
        break;
      }
      // Handle dwelling at a stop
      if (currentTime >= stopTimes[i].arrivalTime && currentTime < stopTimes[i].departureTime) {
        // Vehicle is at stop i
        final stop = parser.stops[stopTimes[i].stopId];
        return stop != null ? LatLng(stop.stopLat, stop.stopLon) : null;
      }
    }

    // Checking if we are before first stop or after last stop
    if (prevStop == null) {
        if (currentTime < stopTimes.first.arrivalTime) {
            // Before start - return first stop
            final stop = parser.stops[stopTimes.first.stopId];
            return stop != null ? LatLng(stop.stopLat, stop.stopLon) : null;
        }
        if (currentTime >= stopTimes.last.departureTime) {
            // After end - return last stop
             final stop = parser.stops[stopTimes.last.stopId];
            return stop != null ? LatLng(stop.stopLat, stop.stopLon) : null;
        }
        // Fallback
        return null;
    }

    // 2. Calculate interpolation factor (0.0 to 1.0) between stops
    // Total duration of travel between stops
    final duration = nextStop!.arrivalTime.inSeconds - prevStop.departureTime.inSeconds;
    if (duration <= 0) {
        // Instant teleport or data error, just return next stop
         final stop = parser.stops[nextStop.stopId];
         return stop != null ? LatLng(stop.stopLat, stop.stopLon) : null;
    }
    
    final elapsed = currentTime.inSeconds - prevStop.departureTime.inSeconds;
    final t = elapsed / duration; // 0.0 to 1.0

    // 3. Map t to physical shape
    return _interpolateOnShape(trip, prevStop, nextStop, t);
  }

  LatLng? _interpolateOnShape(GtfsTrip trip, GtfsStopTime from, GtfsStopTime to, double t) {
      if (trip.shapeId == null) {
          // No shape, just straight line between stops
          final startStop = parser.stops[from.stopId];
          final endStop = parser.stops[to.stopId];
          if (startStop == null || endStop == null) return null;
          
          final lat = startStop.stopLat + (endStop.stopLat - startStop.stopLat) * t;
          final lon = startStop.stopLon + (endStop.stopLon - startStop.stopLon) * t;
          return LatLng(lat, lon);
      }

      final shapePoints = _getShape(trip.shapeId!);
      if (shapePoints.isEmpty) return null;

      // Ideally we use shape_dist_traveled
      double? startDist = _getStopDist(from, shapePoints);
      double? endDist = _getStopDist(to, shapePoints);

      if (startDist != null && endDist != null) {
          final totalDist = endDist - startDist;
          final currentDist = startDist + (totalDist * t); // t is 0.0 to 1.0 (time progress)
          return _getPointAtDist(shapePoints, currentDist);
      }
      
      // Fallback
      final startStop = parser.stops[from.stopId];
      final endStop = parser.stops[to.stopId];
      if (startStop == null || endStop == null) return null;

      final lat = startStop.stopLat + (endStop.stopLat - startStop.stopLat) * t;
      final lon = startStop.stopLon + (endStop.stopLon - startStop.stopLon) * t;
      return LatLng(lat, lon);
  }

  // Helper to get distance along shape
  double? _getStopDist(GtfsStopTime stopTime, List<GtfsShape> shapePoints) {
      if (stopTime.shapeDistTraveled != null) return stopTime.shapeDistTraveled;
      
      final stop = parser.stops[stopTime.stopId];
      if (stop == null) return null;

      // Find closest shape point
      double minDst = double.infinity;
      double bestShapeDist = 0.0;
      bool found = false;

      for (final sp in shapePoints) {
          final dist = (sp.shapePtLat - stop.stopLat).abs() + (sp.shapePtLon - stop.stopLon).abs();
          if (dist < minDst) {
              minDst = dist;
              bestShapeDist = sp.shapeDistTraveled ?? 0.0;
              found = true;
          }
      }
      return found ? bestShapeDist : null;
  }

  LatLng? _getPointAtDist(List<GtfsShape> points, double dist) {
      // Find segment
      if (points.isEmpty) return null;
      // Find segment
      if (points.isEmpty) return null;
      if (dist <= (points.first.shapeDistTraveled ?? 0)) return LatLng(points.first.shapePtLat, points.first.shapePtLon);
      if (dist >= (points.last.shapeDistTraveled ?? 0)) return LatLng(points.last.shapePtLat, points.last.shapePtLon);

      // Binary search for segment could be faster
      int low = 0;
      int high = points.length - 2;
      
      while (low <= high) {
          int mid = (low + high) ~/ 2;
          final p1 = points[mid];
          final p2 = points[mid + 1];
          final d1 = p1.shapeDistTraveled ?? 0;
          final d2 = p2.shapeDistTraveled ?? 0;
          
          if (dist >= d1 && dist <= d2) {
              final val = d2 - d1;
              if (val == 0) return LatLng(p1.shapePtLat, p1.shapePtLon);
              final t = (dist - d1) / val;
              final lat = p1.shapePtLat + (p2.shapePtLat - p1.shapePtLat) * t;
              final lon = p1.shapePtLon + (p2.shapePtLon - p1.shapePtLon) * t;
              return LatLng(lat, lon);
          } else if (dist < d1) {
              high = mid - 1;
          } else {
              low = mid + 1;
          }
      }
      return LatLng(points.last.shapePtLat, points.last.shapePtLon);
  }

  // Removed old method signature to avoid conflict
  // LatLng? _interpolateOnShape(GtfsTrip trip, GtfsStopTime from, GtfsStopTime to, double t) <-- replaced entirely
  
  List<GtfsStopTime> _getStopTimes(String tripId) {
      if (!_tripStopTimes.containsKey(tripId)) {
          _tripStopTimes[tripId] = parser.stopTimes.where((st) => st.tripId == tripId).toList()
            ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
      }
      return _tripStopTimes[tripId]!;
  }

  List<GtfsShape> _getShape(String shapeId) {
      return parser.shapes[shapeId] ?? [];
  }
}
