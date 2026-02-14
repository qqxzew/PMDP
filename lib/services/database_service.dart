import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'dart:io';
import '../models/driver_models.dart';

/// SQLite database service for managing drivers and timetable assignments
class DatabaseService {
  static Database? _database;
  static const String _dbName = 'pmdp_dispatch.db';

  /// Initialize database for desktop (Windows)
  static Future<void> initialize() async {
    try {
      // Check if we can access Platform (not available on web)
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
    } catch (e) {
      // Platform not available (web or other), use default factory
      // sqfliteFfiInit is only needed for desktop platforms
      print('Platform check failed, using default database factory: $e');
    }
  }

  /// Get database instance
  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    await initialize();

    final dbPath = await databaseFactory.getDatabasesPath();
    final path = join(dbPath, _dbName);

    return await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: _onCreate,
      ),
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Create drivers table
    await db.execute('''
      CREATE TABLE drivers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // Create timetable assignments table
    await db.execute('''
      CREATE TABLE timetable_assignments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        driver_id TEXT NOT NULL,
        timetable_json TEXT NOT NULL,
        assigned_at TEXT NOT NULL,
        retrieved_at TEXT,
        is_retrieved INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (driver_id) REFERENCES drivers(id)
      )
    ''');

    // Create index for faster lookups
    await db.execute('''
      CREATE INDEX idx_driver_id ON timetable_assignments(driver_id)
    ''');

    // Insert test drivers
    await _insertTestDrivers(db);
  }

  static Future<void> _insertTestDrivers(Database db) async {
    final testDrivers = [
      Driver(id: 'D1234', name: 'Jan Novák', phone: '+420123456789'),
      Driver(id: 'D5678', name: 'Eva Svobodová', phone: '+420987654321'),
      Driver(id: 'D9012', name: 'Petr Dvořák', phone: '+420111222333'),
      Driver(id: 'D3456', name: 'Marie Procházková', phone: '+420444555666'),
      Driver(id: 'D7890', name: 'Tomáš Černý', phone: '+420777888999'),
    ];

    for (final driver in testDrivers) {
      await db.insert('drivers', driver.toMap());
    }
  }

  // ========== DRIVER OPERATIONS ==========

  /// Get all drivers
  static Future<List<Driver>> getAllDrivers() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('drivers');
    return List.generate(maps.length, (i) => Driver.fromMap(maps[i]));
  }

  /// Get active drivers
  static Future<List<Driver>> getActiveDrivers() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'drivers',
      where: 'is_active = ?',
      whereArgs: [1],
    );
    return List.generate(maps.length, (i) => Driver.fromMap(maps[i]));
  }

  /// Get driver by ID
  static Future<Driver?> getDriver(String driverId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'drivers',
      where: 'id = ?',
      whereArgs: [driverId],
    );
    if (maps.isEmpty) return null;
    return Driver.fromMap(maps.first);
  }

  /// Insert or update driver
  static Future<void> upsertDriver(Driver driver) async {
    final db = await database;
    await db.insert(
      'drivers',
      driver.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Delete driver
  static Future<void> deleteDriver(String driverId) async {
    final db = await database;
    await db.delete(
      'drivers',
      where: 'id = ?',
      whereArgs: [driverId],
    );
  }

  // ========== TIMETABLE ASSIGNMENT OPERATIONS ==========

  /// Assign timetable to driver
  static Future<int> assignTimetable({
    required String driverId,
    required String timetableJson,
  }) async {
    final db = await database;
    final assignment = TimetableAssignment(
      driverId: driverId,
      timetableJson: timetableJson,
      assignedAt: DateTime.now(),
    );

    return await db.insert('timetable_assignments', assignment.toMap());
  }

  /// Get latest assignment for driver
  static Future<TimetableAssignment?> getLatestAssignment(
      String driverId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'timetable_assignments',
      where: 'driver_id = ?',
      whereArgs: [driverId],
      orderBy: 'assigned_at DESC',
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return TimetableAssignment.fromMap(maps.first);
  }

  /// Get all assignments for driver
  static Future<List<TimetableAssignment>> getDriverAssignments(
      String driverId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'timetable_assignments',
      where: 'driver_id = ?',
      whereArgs: [driverId],
      orderBy: 'assigned_at DESC',
    );

    return List.generate(
        maps.length, (i) => TimetableAssignment.fromMap(maps[i]));
  }

  /// Mark assignment as retrieved
  static Future<void> markAsRetrieved(int assignmentId) async {
    final db = await database;
    await db.update(
      'timetable_assignments',
      {
        'is_retrieved': 1,
        'retrieved_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [assignmentId],
    );
  }

  /// Get all assignments (for admin view)
  static Future<List<TimetableAssignment>> getAllAssignments() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'timetable_assignments',
      orderBy: 'assigned_at DESC',
    );

    return List.generate(
        maps.length, (i) => TimetableAssignment.fromMap(maps[i]));
  }

  /// Delete old assignments (cleanup)
  static Future<void> deleteOldAssignments(Duration olderThan) async {
    final db = await database;
    final threshold = DateTime.now().subtract(olderThan);
    await db.delete(
      'timetable_assignments',
      where: 'assigned_at < ?',
      whereArgs: [threshold.toIso8601String()],
    );
  }

  /// Close database
  static Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
