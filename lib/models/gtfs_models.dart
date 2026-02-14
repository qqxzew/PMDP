// Modely GTFS dat – odpovídají struktuře PMDP GTFS feedu

class GtfsAgency {
  final String agencyId;
  final String agencyName;
  final String agencyUrl;
  final String agencyTimezone;
  final String agencyLang;

  GtfsAgency({
    required this.agencyId,
    required this.agencyName,
    required this.agencyUrl,
    required this.agencyTimezone,
    required this.agencyLang,
  });
}

class GtfsRoute {
  final String routeId;
  final String agencyId;
  final String routeShortName;
  final String routeLongName;
  final int routeType; // 0 = tramvaj, 3 = autobus
  final String dir1From;
  final String dir1To;
  final String dir2From;
  final String dir2To;

  GtfsRoute({
    required this.routeId,
    required this.agencyId,
    required this.routeShortName,
    required this.routeLongName,
    required this.routeType,
    this.dir1From = '',
    this.dir1To = '',
    this.dir2From = '',
    this.dir2To = '',
  });

  String get displayName => '$routeShortName – $routeLongName';

  bool get isTram => routeType == 0;
  bool get isBus => routeType == 3;
  String get typeLabel => isTram ? 'Tramvaj' : 'Autobus';
}

class GtfsStop {
  final String stopId;
  final String stopCode;
  final String stopName;
  final double stopLat;
  final double stopLon;
  final int locationType;
  final int wheelchairBoarding;

  GtfsStop({
    required this.stopId,
    this.stopCode = '',
    required this.stopName,
    required this.stopLat,
    required this.stopLon,
    this.locationType = 0,
    this.wheelchairBoarding = 0,
  });

  bool get isAccessible => wheelchairBoarding == 1;
}

class GtfsTrip {
  final String routeId;
  final String serviceId;
  final String tripId;
  final int directionId;
  final String tripShortName;
  final String? shapeId;

  GtfsTrip({
    required this.routeId,
    required this.serviceId,
    required this.tripId,
    required this.directionId,
    this.tripShortName = '',
    this.shapeId,
  });
}

class GtfsShape {
  final String shapeId;
  final double shapePtLat;
  final double shapePtLon;
  final int shapePtSequence;
  final double? shapeDistTraveled;

  GtfsShape({
    required this.shapeId,
    required this.shapePtLat,
    required this.shapePtLon,
    required this.shapePtSequence,
    this.shapeDistTraveled,
  });
}

class GtfsStopTime {
  final String tripId;
  final Duration arrivalTime;
  final Duration departureTime;
  final String stopId;
  final int stopSequence;
  final int pickupType;
  final int dropOffType;
  final double? shapeDistTraveled;

  GtfsStopTime({
    required this.tripId,
    required this.arrivalTime,
    required this.departureTime,
    required this.stopId,
    required this.stopSequence,
    this.pickupType = 0,
    this.dropOffType = 0,
    this.shapeDistTraveled,
  });

  /// Deadhead stop = no boarding AND no alighting (pickup_type=3, drop_off_type=3)
  bool get isDeadhead => pickupType == 3 && dropOffType == 3;
}

class GtfsCalendar {
  final String serviceId;
  final bool monday;
  final bool tuesday;
  final bool wednesday;
  final bool thursday;
  final bool friday;
  final bool saturday;
  final bool sunday;

  GtfsCalendar({
    required this.serviceId,
    required this.monday,
    required this.tuesday,
    required this.wednesday,
    required this.thursday,
    required this.friday,
    required this.saturday,
    required this.sunday,
  });
}

class GtfsTransfer {
  final String fromStopId;
  final String toStopId;
  final int transferType;
  final int minTransferTime;

  GtfsTransfer({
    required this.fromStopId,
    required this.toStopId,
    required this.transferType,
    required this.minTransferTime,
  });

  int get minTransferTimeMinutes => (minTransferTime / 60).ceil();
}

/// Agregovaná data trasy se zastávkami a jízdními dobami
class RouteData {
  final GtfsRoute route;
  final List<GtfsTrip> trips;
  final Map<String, List<GtfsStopTime>> stopTimesByTrip;
  final int totalTrips;
  int assignedBuses;
  int targetIntervalMinutes;

  List<GtfsStopTime>? _forwardStopTimesCache;
  List<GtfsStopTime>? _backwardStopTimesCache;
  int? _forwardMinutesCache;
  int? _roundTripMinutesCache;

  RouteData({
    required this.route,
    required this.trips,
    required this.stopTimesByTrip,
    this.totalTrips = 0,
    this.assignedBuses = 0,
    this.targetIntervalMinutes = 0,
  });

  /// Zastávky pro směr 0 (tam) – bez přejezdů do/z vozovny
  List<GtfsStopTime> get forwardStopTimes {
    if (_forwardStopTimesCache != null) return _forwardStopTimesCache!;
    for (final trip in trips.where((t) => t.directionId == 0)) {
      final times = stopTimesByTrip[trip.tripId];
      if (times != null && times.isNotEmpty) {
        final sorted = List<GtfsStopTime>.from(times)
          ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
        // Odfiltrovat deadhead zastávky (přejezdy do/z vozovny)
        final revenue = sorted.where((s) => !s.isDeadhead).toList();
        _forwardStopTimesCache = revenue.isNotEmpty ? revenue : sorted;
        return _forwardStopTimesCache!;
      }
    }
    _forwardStopTimesCache = const [];
    return _forwardStopTimesCache!;
  }

  /// Zastávky pro směr 1 (zpět) – bez přejezdů do/z vozovny
  List<GtfsStopTime> get backwardStopTimes {
    if (_backwardStopTimesCache != null) return _backwardStopTimesCache!;
    for (final trip in trips.where((t) => t.directionId == 1)) {
      final times = stopTimesByTrip[trip.tripId];
      if (times != null && times.isNotEmpty) {
        final sorted = List<GtfsStopTime>.from(times)
          ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
        // Odfiltrovat deadhead zastávky (přejezdy do/z vozovny)
        final revenue = sorted.where((s) => !s.isDeadhead).toList();
        _backwardStopTimesCache = revenue.isNotEmpty ? revenue : sorted;
        return _backwardStopTimesCache!;
      }
    }
    _backwardStopTimesCache = const [];
    return _backwardStopTimesCache!;
  }

  /// Jízdní doba jedním směrem v minutách
  int get oneWayMinutes {
    if (_forwardMinutesCache != null) return _forwardMinutesCache!;
    final forward = forwardStopTimes;
    final backward = backwardStopTimes;

    final stops = forward.length >= 2 ? forward : backward;
    if (stops.length < 2) {
      _forwardMinutesCache = 0;
      return _forwardMinutesCache!;
    }
    _forwardMinutesCache =
        (stops.last.arrivalTime - stops.first.departureTime).inMinutes;
    return _forwardMinutesCache!;
  }

  /// Doba oběhu v minutách (tam + zpět + obrat)
  int get roundTripMinutes {
    if (_roundTripMinutesCache != null) return _roundTripMinutesCache!;
    final fwd = forwardStopTimes;
    final bwd = backwardStopTimes;

    final hasFwd = fwd.length >= 2;
    final hasBwd = bwd.length >= 2;
    if (!hasFwd && !hasBwd) {
      _roundTripMinutesCache = 0;
      return _roundTripMinutesCache!;
    }

    final fwdTime = hasFwd
        ? (fwd.last.arrivalTime - fwd.first.departureTime).inMinutes
        : 0;
    final bwdTime = hasBwd
        ? (bwd.last.arrivalTime - bwd.first.departureTime).inMinutes
        : 0;

    // Fallback pro nekonzistentní GTFS směry:
    // když máme jen jeden směr, aproximuj oběh jako 2x dostupný směr + obrat.
    if (hasFwd && hasBwd) {
      _roundTripMinutesCache = fwdTime + bwdTime + 6;
    } else {
      final oneWay = hasFwd ? fwdTime : bwdTime;
      _roundTripMinutesCache = (oneWay * 2) + 6;
    }
    return _roundTripMinutesCache!;
  }

  /// Interval v minutách dle přiřazených vozů
  int get intervalMinutes {
    if (assignedBuses <= 0) return 0;
    return (roundTripMinutes / assignedBuses).ceil();
  }

  /// Počet vozů potřebný pro cílový interval
  int get requiredBusesForTargetInterval {
    if (targetIntervalMinutes <= 0 || roundTripMinutes <= 0) return 0;
    return (roundTripMinutes / targetIntervalMinutes).ceil().clamp(1, 500);
  }

  /// Směrový nápis – tam (z dat trasy dir_1_from → dir_1_to)
  String get forwardHeadsign {
    if (route.dir1To.isNotEmpty) return route.dir1To;
    final parts = route.routeLongName.split(' - ');
    return parts.isNotEmpty ? parts.last : '';
  }

  /// Směrový nápis – zpět (z dat trasy dir_2_from → dir_2_to)
  String get backwardHeadsign {
    if (route.dir2To.isNotEmpty) return route.dir2To;
    final parts = route.routeLongName.split(' - ');
    return parts.isNotEmpty ? parts.first : '';
  }

  /// Všechny stopId používané touto trasou
  Set<String> get allStopIds {
    final ids = <String>{
      ...forwardStopTimes.map((s) => s.stopId),
      ...backwardStopTimes.map((s) => s.stopId),
    };
    return ids;
  }
}
