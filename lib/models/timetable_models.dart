// Timetable output models matching the required ITimetableJob interface

class TimetableJob {
  final String jobId;
  final String lineNumber;
  final String? vehicleId;
  final String? driverId;
  final List<TimetableStop> stops;

  TimetableJob({
    required this.jobId,
    required this.lineNumber,
    this.vehicleId,
    this.driverId,
    required this.stops,
  });

  Map<String, dynamic> toJson() => {
        'jobId': jobId,
        'lineNumber': lineNumber,
        'vehicleId': vehicleId,
        'driverId': driverId,
        'stops': stops.map((s) => s.toJson()).toList(),
      };

  factory TimetableJob.fromJson(Map<String, dynamic> json) {
    return TimetableJob(
      jobId: json['jobId'] as String,
      lineNumber: json['lineNumber'] as String,
      vehicleId: json['vehicleId'] as String?,
      driverId: json['driverId'] as String?,
      stops: (json['stops'] as List)
          .map((s) => TimetableStop.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  /// First stop departure time
  DateTime? get startTime => stops.firstOrNull?.departureTime;

  /// Last stop arrival time
  DateTime? get endTime => stops.lastOrNull?.arrivalTime;

  /// Direction headsign (last stop name)
  String get direction => stops.isNotEmpty ? stops.last.name : '';
}

class TimetableStop {
  final String stopId;
  final String name;
  final DateTime? arrivalTime;
  final DateTime? departureTime;
  final bool isTerminus;
  final List<Transfer> transfers;

  TimetableStop({
    required this.stopId,
    required this.name,
    this.arrivalTime,
    this.departureTime,
    required this.isTerminus,
    List<Transfer>? transfers,
  }) : transfers = transfers ?? [];

  Map<String, dynamic> toJson() => {
        'stopId': stopId,
        'name': name,
        'arrivalTime': arrivalTime?.toIso8601String(),
        'departureTime': departureTime?.toIso8601String(),
        'isTerminus': isTerminus,
        'transfers': transfers.map((t) => t.toJson()).toList(),
      };

  factory TimetableStop.fromJson(Map<String, dynamic> json) {
    return TimetableStop(
      stopId: json['stopId'] as String,
      name: json['name'] as String,
      arrivalTime: json['arrivalTime'] != null
          ? DateTime.parse(json['arrivalTime'] as String)
          : null,
      departureTime: json['departureTime'] != null
          ? DateTime.parse(json['departureTime'] as String)
          : null,
      isTerminus: json['isTerminus'] as bool,
      transfers: (json['transfers'] as List?)
              ?.map((t) => Transfer.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class Transfer {
  final String jobId;
  final String lineNumber;
  final String direction;
  final DateTime? waitUntil;
  final bool isGuaranteed;
  final int maxWaitMinutes;
  final String status;

  Transfer({
    required this.jobId,
    required this.lineNumber,
    required this.direction,
    this.waitUntil,
    required this.isGuaranteed,
    required this.maxWaitMinutes,
    required this.status,
  });

  Map<String, dynamic> toJson() => {
        'jobId': jobId,
        'lineNumber': lineNumber,
        'direction': direction,
        'waitUntil': waitUntil?.toIso8601String(),
        'isGuaranteed': isGuaranteed,
        'maxWaitMinutes': maxWaitMinutes,
        'status': status,
      };

  factory Transfer.fromJson(Map<String, dynamic> json) {
    return Transfer(
      jobId: json['jobId'] as String,
      lineNumber: json['lineNumber'] as String,
      direction: json['direction'] as String,
      waitUntil: json['waitUntil'] != null
          ? DateTime.parse(json['waitUntil'] as String)
          : null,
      isGuaranteed: json['isGuaranteed'] as bool,
      maxWaitMinutes: json['maxWaitMinutes'] as int,
      status: (json['status'] as String?) ?? 'Sync',
    );
  }
}
