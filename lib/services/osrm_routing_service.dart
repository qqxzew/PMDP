import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'osrm_cache_store_stub.dart'
  if (dart.library.html) 'osrm_cache_store_web.dart';

class OsrmRoutingService {
  static const String _cacheVersion = 'v2';
  static const String _baseUrl = 'https://router.project-osrm.org/route/v1';
  static const Distance _distance = Distance();
  static const Duration _requestGap = Duration(milliseconds: 500);

  final Map<String, List<LatLng>> _memoryCache = {};
  Future<void> _requestQueue = Future.value();
  DateTime? _lastNetworkRequestAt;
  bool _loaded = false;

  Future<void> _ensureCacheLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await readOsrmCache();
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! List) continue;
        final points = <LatLng>[];
        for (final pair in value) {
          if (pair is! List || pair.length != 2) continue;
          final lat = (pair[0] as num?)?.toDouble();
          final lon = (pair[1] as num?)?.toDouble();
          if (lat == null || lon == null) continue;
          points.add(LatLng(lat, lon));
        }
        if (points.length >= 2) {
          _memoryCache[entry.key] = points;
        }
      }
    } catch (_) {
      // Keep cache empty on load errors.
    }
  }

  Future<void> _persistCache() async {
    try {
      final payload = <String, dynamic>{};
      for (final entry in _memoryCache.entries) {
        payload[entry.key] = entry.value
            .map((p) => <double>[p.latitude, p.longitude])
            .toList(growable: false);
      }
      await writeOsrmCache(jsonEncode(payload));
    } catch (_) {
      // Best effort only.
    }
  }

  String makeRouteKeyFromStops(
    List<String> stopIds, {
    String profile = 'driving',
    String? lineNumber,
    int? direction,
  }) {
    final linePrefix = (lineNumber != null && lineNumber.isNotEmpty)
        ? 'line:$lineNumber:${direction ?? -1}|'
        : '';
    return '$_cacheVersion|$profile|$linePrefix${stopIds.join('>')}';
  }

  String makeSegmentKey(String fromStopId, String toStopId, {String profile = 'driving'}) {
    return '$_cacheVersion|$profile|$fromStopId>$toStopId';
  }

  /// Invalidate specific route cache (force reload)
  void invalidateRouteCache(String cacheKey) {
    if (_memoryCache.containsKey(cacheKey)) {
      _memoryCache.remove(cacheKey);
      debugPrint('🔄 Инвалидирован кэш маршрута: $cacheKey');
      _persistCache();
    }
  }

  /// Invalidate all routes for specific lines
  void invalidateLineRoutes(List<String> lineNumbers) {
    final keysToRemove = <String>[];
    for (final key in _memoryCache.keys) {
      for (final lineNum in lineNumbers) {
        if (key.contains('line:$lineNum:')) {
          keysToRemove.add(key);
          break;
        }
      }
    }
    for (final key in keysToRemove) {
      _memoryCache.remove(key);
    }
    if (keysToRemove.isNotEmpty) {
      debugPrint('🔄 Инвалидировано ${keysToRemove.length} маршрутов для линий: ${lineNumbers.join(", ")}');
      _persistCache();
    }
  }

  Future<List<LatLng>> getSegmentPolyline({
    required String fromStopId,
    required LatLng from,
    required String toStopId,
    required LatLng to,
    String profile = 'driving',
  }) {
    final key = makeSegmentKey(fromStopId, toStopId, profile: profile);
    return getRoutePolyline(
      cacheKey: key,
      waypoints: [from, to],
      profile: profile,
    );
  }

  Future<T> _runQueuedRequest<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _requestQueue = _requestQueue.then((_) async {
      final lastRequest = _lastNetworkRequestAt;
      if (lastRequest != null) {
        final elapsed = DateTime.now().difference(lastRequest);
        if (elapsed < _requestGap) {
          await Future.delayed(_requestGap - elapsed);
        }
      }

      try {
        final result = await task();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      } finally {
        _lastNetworkRequestAt = DateTime.now();
      }
    });
    return completer.future;
  }

  Future<List<LatLng>> getRoutePolyline({
    required String cacheKey,
    required List<LatLng> waypoints,
    String profile = 'driving',
  }) async {
    if (waypoints.length < 2) return waypoints;
    await _ensureCacheLoaded();

    // КРИТИЧНО: Всегда используем кэш если он есть
    final existing = _memoryCache[cacheKey];
    if (existing != null && existing.length >= 2) {
      debugPrint('✅ Маршрут из кэша: $cacheKey (${existing.length} точек)');
      return existing;
    }

    // Если маршрута нет в кэше, запрашиваем из OSRM ОДИН РАЗ
    debugPrint('🌐 Запрос маршрута OSRM: $cacheKey');

    // Упрощение маршрута: если слишком много точек, берем каждую 2-ю
    List<LatLng> simplifiedWaypoints = waypoints;
    if (waypoints.length > 25) {
      simplifiedWaypoints = [];
      for (int i = 0; i < waypoints.length; i++) {
        if (i == 0 || i == waypoints.length - 1 || i % 2 == 0) {
          simplifiedWaypoints.add(waypoints[i]);
        }
      }
      debugPrint('⚠️ Упрощен маршрут: ${waypoints.length} → ${simplifiedWaypoints.length} точек');
    }

    // OSRM лучше работает с разумным числом точек
    if (simplifiedWaypoints.length > 25) {
      final step = ((simplifiedWaypoints.length - 2) / 23).ceil().clamp(1, simplifiedWaypoints.length);
      final reduced = <LatLng>[simplifiedWaypoints.first];
      for (int i = 1; i < simplifiedWaypoints.length - 1; i += step) {
        reduced.add(simplifiedWaypoints[i]);
      }
      reduced.add(simplifiedWaypoints.last);
      simplifiedWaypoints = reduced;
      debugPrint('⚠️ Дополнительное упрощение: → ${simplifiedWaypoints.length} точек');
    }

    final coordinates = simplifiedWaypoints
        .map((p) => '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}')
        .join(';');
    final fetched = await _runQueuedRequest<List<LatLng>?>(() async {
      final url = Uri.parse(
        '$_baseUrl/$profile/$coordinates?overview=full&geometries=geojson',
      );

      for (int attempt = 1; attempt <= 2; attempt++) {
        try {
          final response = await http.get(url).timeout(const Duration(seconds: 20));
          if (response.statusCode == 200) {
            final body = jsonDecode(response.body);
            final routes = body['routes'];
            if (routes is List && routes.isNotEmpty) {
              final geometry = routes.first['geometry'];
              final coords = geometry?['coordinates'];
              if (coords is List) {
                final decoded = <LatLng>[];
                for (final c in coords) {
                  if (c is List && c.length >= 2) {
                    final lon = (c[0] as num?)?.toDouble();
                    final lat = (c[1] as num?)?.toDouble();
                    if (lat != null && lon != null) {
                      decoded.add(LatLng(lat, lon));
                    }
                  }
                }
                if (decoded.length >= 2) {
                  return decoded;
                }
              }
            }
          } else if (response.statusCode == 429) {
            debugPrint('⚠️ OSRM rate limit (попытка $attempt/2)');
            if (attempt < 2) {
              await Future.delayed(const Duration(seconds: 2));
              continue;
            }
          } else {
            debugPrint('⚠️ OSRM ошибка ${response.statusCode}: ${response.body}');
          }
          break;
        } catch (e) {
          if (attempt == 1) {
            debugPrint('⚠️ OSRM timeout/error (попытка 1/2), retry...');
            await Future.delayed(const Duration(milliseconds: 800));
            continue;
          }
          debugPrint('❌ OSRM routing failed for $cacheKey after 2 attempts: $e');
        }
      }
      return null;
    });

    if (fetched != null && fetched.length >= 2) {
      _memoryCache[cacheKey] = fetched;
      await _persistCache();
      debugPrint('✅ OSRM маршрут сохранен в кэш: $cacheKey (${fetched.length} точек)');
      return fetched;
    }

    // Fallback: возвращаем прямые линии без сохранения в кэш,
    // чтобы следующий запрос снова попытался получить дорогу с OSRM.
    debugPrint('⚠️ Fallback: прямая линия для $cacheKey');
    return waypoints;
  }

  double polylineLengthMeters(List<LatLng> polyline) {
    if (polyline.length < 2) return 0;
    double meters = 0;
    for (int i = 1; i < polyline.length; i++) {
      meters += _distance(polyline[i - 1], polyline[i]);
    }
    return meters;
  }

  LatLng interpolateAlongPolyline(List<LatLng> polyline, double ratio) {
    if (polyline.isEmpty) return const LatLng(0, 0);
    if (polyline.length == 1) return polyline.first;
    final clamped = ratio.clamp(0.0, 1.0);
    if (clamped <= 0) return polyline.first;
    if (clamped >= 1) return polyline.last;

    final total = polylineLengthMeters(polyline);
    if (total <= 0) return polyline.first;
    final target = total * clamped;

    double traversed = 0;
    for (int i = 1; i < polyline.length; i++) {
      final a = polyline[i - 1];
      final b = polyline[i];
      final seg = _distance(a, b);
      if (seg <= 0) continue;
      if (traversed + seg >= target) {
        final local = (target - traversed) / seg;
        return LatLng(
          a.latitude + (b.latitude - a.latitude) * local,
          a.longitude + (b.longitude - a.longitude) * local,
        );
      }
      traversed += seg;
    }

    return polyline.last;
  }
}