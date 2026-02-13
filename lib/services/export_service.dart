import 'dart:convert';
import '../models/timetable_models.dart';

/// Service for exporting timetable data
class ExportService {
  /// Export all jobs as JSON string
  static String exportAsJson(List<TimetableJob> jobs) {
    final jsonData = jobs.map((j) => j.toJson()).toList();
    return const JsonEncoder.withIndent('  ').convert(jsonData);
  }

  /// Export jobs for a specific vehicle
  static String exportVehicleJson(
      List<TimetableJob> jobs, String vehicleId) {
    final vehicleJobs =
        jobs.where((j) => j.vehicleId == vehicleId).toList();
    return exportAsJson(vehicleJobs);
  }

  /// Export as raw response format (dates as strings)
  static List<Map<String, dynamic>> exportAsRawResponse(
      List<TimetableJob> jobs) {
    return jobs.map((j) => j.toJson()).toList();
  }

  /// Generate a simple text timetable for printing
  static String exportAsText(List<TimetableJob> jobs, String lineNumber) {
    final lineJobs = jobs
        .where((j) => j.lineNumber == lineNumber)
        .toList()
      ..sort((a, b) => (a.startTime ?? DateTime(2099))
          .compareTo(b.startTime ?? DateTime(2099)));

    final buffer = StringBuffer();
    buffer.writeln('==========================================');
    buffer.writeln('NOUZOVÝ JÍZDNÍ ŘÁD - LINKA $lineNumber');
    buffer.writeln('==========================================');
    buffer.writeln();

    for (final job in lineJobs) {
      buffer.writeln(
          '--- Jízda: ${job.vehicleId ?? "?"} | Směr: ${job.direction} ---');
      for (final stop in job.stops) {
        final arrival = stop.arrivalTime != null
            ? '${stop.arrivalTime!.hour.toString().padLeft(2, '0')}:${stop.arrivalTime!.minute.toString().padLeft(2, '0')}'
            : '--:--';
        final departure = stop.departureTime != null
            ? '${stop.departureTime!.hour.toString().padLeft(2, '0')}:${stop.departureTime!.minute.toString().padLeft(2, '0')}'
            : '--:--';
        final terminus = stop.isTerminus ? ' [T]' : '';
        buffer.writeln(
            '  $arrival - $departure  ${stop.name}$terminus');
        
        for (final transfer in stop.transfers) {
          buffer.writeln(
              '    -> Přestup: Linka ${transfer.lineNumber} směr ${transfer.direction}');
        }
      }
      buffer.writeln();
    }

    return buffer.toString();
  }
}
