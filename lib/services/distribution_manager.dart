import 'dart:convert';
import '../models/timetable_models.dart';
import 'database_service.dart';
import 'export_service.dart';

/// Service for managing distribution of timetables to drivers
class DistributionManager {
  /// Assign timetable jobs to a specific driver
  static Future<bool> assignTimetableToDriver({
    required String driverId,
    required List<TimetableJob> jobs,
  }) async {
    try {
      // Check if driver exists
      final driver = await DatabaseService.getDriver(driverId);
      if (driver == null) {
        return false;
      }

      // Convert jobs to JSON
      final timetableJson = ExportService.exportAsJson(jobs);

      // Save assignment to database
      await DatabaseService.assignTimetable(
        driverId: driverId,
        timetableJson: timetableJson,
      );

      return true;
    } catch (e) {
      print('Error assigning timetable: $e');
      return false;
    }
  }

  /// Get timetable for driver (for API response)
  static Future<Map<String, dynamic>?> getTimetableForDriver(
      String driverId) async {
    try {
      final assignment = await DatabaseService.getLatestAssignment(driverId);
      if (assignment == null) {
        return null;
      }

      // Mark as retrieved if not already
      if (!assignment.isRetrieved && assignment.assignmentId != null) {
        await DatabaseService.markAsRetrieved(assignment.assignmentId!);
      }

      return {
        'driver_id': driverId,
        'assigned_at': assignment.assignedAt.toIso8601String(),
        'timetable': json.decode(assignment.timetableJson),
      };
    } catch (e) {
      print('Error getting timetable: $e');
      return null;
    }
  }

  /// Get all drivers with their assignment status
  static Future<List<Map<String, dynamic>>> getDriversWithStatus() async {
    try {
      final drivers = await DatabaseService.getAllDrivers();
      final result = <Map<String, dynamic>>[];

      for (final driver in drivers) {
        final assignment =
            await DatabaseService.getLatestAssignment(driver.id);
        result.add({
          'driver': driver.toJson(),
          'has_assignment': assignment != null,
          'assigned_at': assignment?.assignedAt.toIso8601String(),
          'retrieved': assignment?.isRetrieved ?? false,
        });
      }

      return result;
    } catch (e) {
      print('Error getting drivers with status: $e');
      return [];
    }
  }

  /// Clear assignment for driver
  static Future<bool> clearDriverAssignment(String driverId) async {
    try {
      // We don't actually delete, just mark as old by assigning empty timetable
      // This keeps history
      await DatabaseService.assignTimetable(
        driverId: driverId,
        timetableJson: json.encode([]),
      );
      return true;
    } catch (e) {
      print('Error clearing assignment: $e');
      return false;
    }
  }

  /// Get assignment statistics
  static Future<Map<String, int>> getStatistics() async {
    try {
      final drivers = await DatabaseService.getAllDrivers();
      final activeDrivers = await DatabaseService.getActiveDrivers();
      final assignments = await DatabaseService.getAllAssignments();

      final assignedDrivers = <String>{};
      final retrievedCount = assignments.where((a) => a.isRetrieved).length;

      for (final assignment in assignments) {
        assignedDrivers.add(assignment.driverId);
      }

      return {
        'total_drivers': drivers.length,
        'active_drivers': activeDrivers.length,
        'assigned_drivers': assignedDrivers.length,
        'total_assignments': assignments.length,
        'retrieved_assignments': retrievedCount,
      };
    } catch (e) {
      print('Error getting statistics: $e');
      return {};
    }
  }
}
