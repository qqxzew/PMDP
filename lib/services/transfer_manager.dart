import 'dart:math' as math;

import 'package:uuid/uuid.dart';
import '../models/gtfs_models.dart';
import '../models/transfer_node.dart';

/// Service for managing transfer nodes between lines
class TransferManager {
  static const _uuid = Uuid();
  static const double _parallelThresholdMeters = 300;

  /// Automatically detect transfer nodes where lines share stops
  List<TransferNode> detectAutomaticTransfers({
    required List<RouteData> routes,
    required Map<String, GtfsStop> stops,
  }) {
    final transfers = <TransferNode>[];
    final seen = <String>{};

    for (int i = 0; i < routes.length; i++) {
      for (int j = i + 1; j < routes.length; j++) {
        final route1 = routes[i];
        final route2 = routes[j];

        // Find shared stops
        final sharedStopIds =
            route1.allStopIds.intersection(route2.allStopIds);

        for (final stopId in sharedStopIds) {
          final key = _makeKey(
            route1.route.routeShortName,
            route2.route.routeShortName,
            stopId,
            stopId,
          );
          if (seen.contains(key)) continue;
          seen.add(key);

          final stop = stops[stopId];
          if (stop == null) continue;

          transfers.add(TransferNode(
            id: _uuid.v4(),
            stopId1: stopId,
            stopName1: stop.stopName,
            lineNumber1: route1.route.routeShortName,
            stopId2: stopId,
            stopName2: stop.stopName,
            lineNumber2: route2.route.routeShortName,
            isAutomatic: true,
            maxWaitMinutes: 2,
          ));
        }

        if (sharedStopIds.isEmpty) {
          final nearPair = _findNearestStopPair(
            route1StopIds: route1.allStopIds,
            route2StopIds: route2.allStopIds,
            stops: stops,
          );

          if (nearPair != null && nearPair.distanceMeters <= _parallelThresholdMeters) {
            final key = _makeKey(
              route1.route.routeShortName,
              route2.route.routeShortName,
              nearPair.stopId1,
              nearPair.stopId2,
            );
            if (!seen.contains(key)) {
              seen.add(key);
              transfers.add(TransferNode(
                id: _uuid.v4(),
                stopId1: nearPair.stopId1,
                stopName1: nearPair.stopName1,
                lineNumber1: route1.route.routeShortName,
                stopId2: nearPair.stopId2,
                stopName2: nearPair.stopName2,
                lineNumber2: route2.route.routeShortName,
                isAutomatic: true,
                maxWaitMinutes: 2,
              ));
            }
          }
        }
      }
    }

    return transfers;
  }

  /// Create a manual (custom) transfer node
  TransferNode createManualTransfer({
    required String stopId1,
    required String stopName1,
    required String lineNumber1,
    required String stopId2,
    required String stopName2,
    required String lineNumber2,
    int maxWaitMinutes = 5,
  }) {
    return TransferNode(
      id: _uuid.v4(),
      stopId1: stopId1,
      stopName1: stopName1,
      lineNumber1: lineNumber1,
      stopId2: stopId2,
      stopName2: stopName2,
      lineNumber2: lineNumber2,
      isAutomatic: false,
      maxWaitMinutes: maxWaitMinutes,
    );
  }

  String _makeKey(String line1, String line2, String stop1, String stop2) {
    final lines = [line1, line2]..sort();
    final stops = [stop1, stop2]..sort();
    return '${lines[0]}_${lines[1]}_${stops[0]}_${stops[1]}';
  }

  _NearStopPair? _findNearestStopPair({
    required Set<String> route1StopIds,
    required Set<String> route2StopIds,
    required Map<String, GtfsStop> stops,
  }) {
    _NearStopPair? best;

    for (final stopId1 in route1StopIds) {
      final s1 = stops[stopId1];
      if (s1 == null || s1.stopLat == 0 || s1.stopLon == 0) continue;

      for (final stopId2 in route2StopIds) {
        final s2 = stops[stopId2];
        if (s2 == null || s2.stopLat == 0 || s2.stopLon == 0) continue;

        final d = _distanceMeters(s1.stopLat, s1.stopLon, s2.stopLat, s2.stopLon);
        if (best == null || d < best.distanceMeters) {
          best = _NearStopPair(
            stopId1: stopId1,
            stopName1: s1.stopName,
            stopId2: stopId2,
            stopName2: s2.stopName,
            distanceMeters: d,
          );
        }
      }
    }

    return best;
  }

  double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
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
}

class _NearStopPair {
  final String stopId1;
  final String stopName1;
  final String stopId2;
  final String stopName2;
  final double distanceMeters;

  _NearStopPair({
    required this.stopId1,
    required this.stopName1,
    required this.stopId2,
    required this.stopName2,
    required this.distanceMeters,
  });
}
