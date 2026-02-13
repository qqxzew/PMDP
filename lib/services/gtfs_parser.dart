import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/gtfs_models.dart';

/// Služba pro načítání GTFS dat PMDP ze souborů v assets
class GtfsParser {
  Map<String, GtfsStop> stops = {};
  List<GtfsRoute> routes = [];
  List<GtfsTrip> trips = [];
  List<GtfsStopTime> stopTimes = [];
  List<GtfsCalendar> calendars = [];
  List<GtfsAgency> agencies = [];
  List<GtfsTransfer> gtfsTransfers = [];

  Future<void> loadAll() async {
    await Future.wait([
      _loadAgencies(),
      _loadStops(),
      _loadRoutes(),
      _loadTrips(),
      _loadStopTimes(),
      _loadCalendars(),
      _loadTransfers(),
    ]);
  }

  /// Detekuje pozice sloupců z hlavičky CSV
  Map<String, int> _getColumnMap(List<dynamic> headerRow) {
    final map = <String, int>{};
    for (int i = 0; i < headerRow.length; i++) {
      map[headerRow[i].toString().trim().toLowerCase()] = i;
    }
    return map;
  }

  String _col(List<dynamic> row, Map<String, int> cols, String name, [String defaultVal = '']) {
    final idx = cols[name];
    if (idx == null || idx >= row.length) return defaultVal;
    return row[idx].toString().trim();
  }

  Future<List<List<dynamic>>> _loadCsv(String filename) async {
    var content = await rootBundle.loadString('assets/gtfs/$filename');
    // Strip UTF-8 BOM if present
    if (content.startsWith('\uFEFF')) {
      content = content.substring(1);
    }
    // Normalize line endings (CRLF → LF)
    content = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
        .convert(content);
  }

  Future<void> _loadAgencies() async {
    final rows = await _loadCsv('agency.txt');
    if (rows.length <= 1) return;
    final cols = _getColumnMap(rows[0]);
    for (int i = 1; i < rows.length; i++) {
      final r = rows[i];
      agencies.add(GtfsAgency(
        agencyId: _col(r, cols, 'agency_id'),
        agencyName: _col(r, cols, 'agency_name'),
        agencyUrl: _col(r, cols, 'agency_url'),
        agencyTimezone: _col(r, cols, 'agency_timezone'),
        agencyLang: _col(r, cols, 'agency_lang'),
      ));
    }
  }

  Future<void> _loadStops() async {
    final rows = await _loadCsv('stops.txt');
    if (rows.length <= 1) return;
    final cols = _getColumnMap(rows[0]);
    for (int i = 1; i < rows.length; i++) {
      final r = rows[i];
      final stop = GtfsStop(
        stopId: _col(r, cols, 'stop_id'),
        stopCode: _col(r, cols, 'stop_code'),
        stopName: _col(r, cols, 'stop_name'),
        stopLat: double.tryParse(_col(r, cols, 'stop_lat')) ?? 0,
        stopLon: double.tryParse(_col(r, cols, 'stop_lon')) ?? 0,
        locationType: int.tryParse(_col(r, cols, 'location_type', '0')) ?? 0,
        wheelchairBoarding: int.tryParse(_col(r, cols, 'wheelchair_boarding', '0')) ?? 0,
      );
      stops[stop.stopId] = stop;
    }
  }

  Future<void> _loadRoutes() async {
    final rows = await _loadCsv('routes.txt');
    if (rows.length <= 1) return;
    final cols = _getColumnMap(rows[0]);
    for (int i = 1; i < rows.length; i++) {
      final r = rows[i];
      routes.add(GtfsRoute(
        routeId: _col(r, cols, 'route_id'),
        agencyId: _col(r, cols, 'agency_id'),
        routeShortName: _col(r, cols, 'route_short_name'),
        routeLongName: _col(r, cols, 'route_long_name'),
        routeType: int.tryParse(_col(r, cols, 'route_type', '3')) ?? 3,
        dir1From: _col(r, cols, 'dir_1_from'),
        dir1To: _col(r, cols, 'dir_1_to'),
        dir2From: _col(r, cols, 'dir_2_from'),
        dir2To: _col(r, cols, 'dir_2_to'),
      ));
    }
  }

  Future<void> _loadTrips() async {
    final rows = await _loadCsv('trips.txt');
    if (rows.length <= 1) return;
    final cols = _getColumnMap(rows[0]);
    for (int i = 1; i < rows.length; i++) {
      final r = rows[i];
      trips.add(GtfsTrip(
        routeId: _col(r, cols, 'route_id'),
        serviceId: _col(r, cols, 'service_id'),
        tripId: _col(r, cols, 'trip_id'),
        directionId: int.tryParse(_col(r, cols, 'direction_id', '0')) ?? 0,
        tripShortName: _col(r, cols, 'trip_short_name'),
      ));
    }
  }

  Future<void> _loadStopTimes() async {
    final rows = await _loadCsv('stop_times.txt');
    if (rows.length <= 1) return;
    final cols = _getColumnMap(rows[0]);
    for (int i = 1; i < rows.length; i++) {
      final r = rows[i];
      stopTimes.add(GtfsStopTime(
        tripId: _col(r, cols, 'trip_id'),
        arrivalTime: _parseDuration(_col(r, cols, 'arrival_time')),
        departureTime: _parseDuration(_col(r, cols, 'departure_time')),
        stopId: _col(r, cols, 'stop_id'),
        stopSequence: int.tryParse(_col(r, cols, 'stop_sequence', '0')) ?? 0,
        pickupType: int.tryParse(_col(r, cols, 'pickup_type', '0')) ?? 0,
        dropOffType: int.tryParse(_col(r, cols, 'drop_off_type', '0')) ?? 0,
      ));
    }
  }

  Future<void> _loadCalendars() async {
    final rows = await _loadCsv('calendar.txt');
    if (rows.length <= 1) return;
    final cols = _getColumnMap(rows[0]);
    for (int i = 1; i < rows.length; i++) {
      final r = rows[i];
      calendars.add(GtfsCalendar(
        serviceId: _col(r, cols, 'service_id'),
        monday: _col(r, cols, 'monday') == '1',
        tuesday: _col(r, cols, 'tuesday') == '1',
        wednesday: _col(r, cols, 'wednesday') == '1',
        thursday: _col(r, cols, 'thursday') == '1',
        friday: _col(r, cols, 'friday') == '1',
        saturday: _col(r, cols, 'saturday') == '1',
        sunday: _col(r, cols, 'sunday') == '1',
      ));
    }
  }

  Future<void> _loadTransfers() async {
    try {
      final rows = await _loadCsv('transfers.txt');
      if (rows.length <= 1) return;
      final cols = _getColumnMap(rows[0]);
      for (int i = 1; i < rows.length; i++) {
        final r = rows[i];
        gtfsTransfers.add(GtfsTransfer(
          fromStopId: _col(r, cols, 'from_stop_id'),
          toStopId: _col(r, cols, 'to_stop_id'),
          transferType: int.tryParse(_col(r, cols, 'transfer_type', '0')) ?? 0,
          minTransferTime: int.tryParse(_col(r, cols, 'min_transfer_time', '0')) ?? 0,
        ));
      }
    } catch (e) {
      debugPrint('Soubor transfers.txt nenalezen: $e');
    }
  }

  Duration _parseDuration(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length != 3) return Duration.zero;
    return Duration(
      hours: int.tryParse(parts[0]) ?? 0,
      minutes: int.tryParse(parts[1]) ?? 0,
      seconds: int.tryParse(parts[2]) ?? 0,
    );
  }

  List<GtfsStopTime> _revenueStops(List<GtfsStopTime> times) {
    final revenue = times.where((s) => !s.isDeadhead).toList();
    return revenue.isNotEmpty ? revenue : times;
  }

  bool _nameMatches(String expected, String actual) {
    final e = expected.trim().toLowerCase();
    final a = actual.trim().toLowerCase();
    if (e.isEmpty || a.isEmpty) return false;
    return a == e || a.contains(e) || e.contains(a);
  }

  int _tripScore({
    required List<GtfsStopTime> times,
    required String expectedFrom,
    required String expectedTo,
  }) {
    final revenue = _revenueStops(times);
    if (revenue.length < 2) return -1000;

    final fromName = stops[revenue.first.stopId]?.stopName ?? '';
    final toName = stops[revenue.last.stopId]?.stopName ?? '';

    var score = 0;
    if (_nameMatches(expectedFrom, fromName)) score += 10;
    if (_nameMatches(expectedTo, toName)) score += 10;
    score += revenue.length;
    return score;
  }

  /// Sestaví agregovaná data tras – pro každou trasu použije jen 
  /// reprezentativní spoj (trip) na směr, aby se zbytečně neprošlo 
  /// všech 130K stop_times
  List<RouteData> buildRouteData() {
    // Předindexujeme stop_times podle trip_id pro rychlý přístup
    final stopTimeIndex = <String, List<GtfsStopTime>>{};
    for (final st in stopTimes) {
      stopTimeIndex.putIfAbsent(st.tripId, () => []).add(st);
    }
    // Seřadíme jednou
    for (final list in stopTimeIndex.values) {
      list.sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
    }

    final result = <RouteData>[];
    for (final route in routes) {
      final routeTrips = trips.where((t) => t.routeId == route.routeId).toList();
      final routeTripCountFromStopTimes = routeTrips
          .where((t) => (stopTimeIndex[t.tripId]?.isNotEmpty ?? false))
          .length;
      
      // Pro výpočet jízdní doby stačí jeden reprezentativní spoj na směr
      final representativeStopTimes = <String, List<GtfsStopTime>>{};
      
      GtfsTrip? bestForwardTrip;
      int bestForwardScore = -99999;
      GtfsTrip? bestBackwardTrip;
      int bestBackwardScore = -99999;

      for (final trip in routeTrips) {
        final times = stopTimeIndex[trip.tripId];
        if (times == null || times.isEmpty) continue;

        if (trip.directionId == 0) {
          final score = _tripScore(
            times: times,
            expectedFrom: route.dir1From,
            expectedTo: route.dir1To,
          );
          if (score > bestForwardScore) {
            bestForwardScore = score;
            bestForwardTrip = trip;
          }
        } else if (trip.directionId == 1) {
          final score = _tripScore(
            times: times,
            expectedFrom: route.dir2From,
            expectedTo: route.dir2To,
          );
          if (score > bestBackwardScore) {
            bestBackwardScore = score;
            bestBackwardTrip = trip;
          }
        }
      }

      if (bestForwardTrip != null) {
        representativeStopTimes[bestForwardTrip.tripId] =
            stopTimeIndex[bestForwardTrip.tripId]!;
      }
      if (bestBackwardTrip != null) {
        representativeStopTimes[bestBackwardTrip.tripId] =
            stopTimeIndex[bestBackwardTrip.tripId]!;
      }
      
      // Pokud nemáme oba směry, zkusíme alespoň jeden
      if (representativeStopTimes.isEmpty) {
        for (final trip in routeTrips) {
          final times = stopTimeIndex[trip.tripId];
          if (times != null && times.isNotEmpty) {
            representativeStopTimes[trip.tripId] = times;
            break;
          }
        }
      }

      result.add(RouteData(
        route: route,
        trips: routeTrips,
        stopTimesByTrip: representativeStopTimes,
        totalTrips: routeTripCountFromStopTimes,
      ));
    }
    return result;
  }
}
