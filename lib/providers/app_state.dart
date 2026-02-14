import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/gtfs_models.dart';
import '../models/timetable_models.dart';
import '../models/transfer_node.dart';
import '../models/vehicle.dart';
import '../models/driver_models.dart';
import '../services/gtfs_parser.dart';
import '../services/timetable_generator.dart';
import '../services/transfer_manager.dart';
import '../services/database_service.dart';
import '../services/timetable_server.dart';
import '../services/distribution_manager.dart';

/// Central application state
class AppState extends ChangeNotifier {
  static const _uuid = Uuid();
  static const _line4BonusCoefficient = 1.5;

  final GtfsParser _parser = GtfsParser();
  final TimetableGenerator _generator = TimetableGenerator();
  final TransferManager _transferManager = TransferManager();
  final TimetableServer _server = TimetableServer();

  // GTFS data
  Map<String, GtfsStop> stops = {};
  List<RouteData> routes = [];
  bool isLoading = true;

  // Configuration
  int totalAvailableBuses = 130;

  // Transfer nodes
  List<TransferNode> transferNodes = [];

  // Generated timetable
  List<TimetableJob> generatedJobs = [];
  bool isTimetableGenerated = false;
  bool isGeneratingTimetable = false;
  String? generationError;

  // Vehicles
  List<Vehicle> vehicles = [];

  // Messages
  List<DispatchMessage> messages = [];
  int get unreadCount => messages.where((m) => !m.isRead && m.direction == MessageDirection.incoming).length;

  // Distribution server
  bool get isServerRunning => _server.isRunning;
  String? get serverIpAddress => _server.ipAddress;
  int get serverPort => _server.port;

  // Drivers
  List<Driver> drivers = [];
  List<Map<String, dynamic>> driverStatuses = [];

  // Statistics
  int get totalTrips => generatedJobs.length;
  int get assignedBuses => routes.fold(0, (sum, r) => sum + r.assignedBuses);
  int get unassignedBuses => totalAvailableBuses - assignedBuses;
  int get activeLines => routes.where((r) => r.assignedBuses > 0).length;
  int get totalTransfers => transferNodes.where((t) => t.isEnabled).length;
  int get activeVehicles =>
      vehicles.where((v) => v.status == VehicleStatus.inService).length;

  // Error message for UI display
  String? loadError;

  void _invalidateGeneratedTimetable() {
    if (isGeneratingTimetable) return;
    isTimetableGenerated = false;
    generatedJobs = [];
    vehicles = [];
    generationError = null;
  }
  
  /// Initialize - load GTFS data
  Future<void> initialize() async {
    isLoading = true;
    loadError = null;
    notifyListeners();

    try {
      // Initialize database (only on desktop platforms)
      try {
        await DatabaseService.initialize();
        await _loadDrivers();
      } catch (e) {
        debugPrint('Database initialization skipped (not a desktop platform): $e');
        // Continue without database on non-desktop platforms
      }

      await _parser.loadAll();
      stops = _parser.stops;
      debugPrint('GTFS loaded: ${_parser.routes.length} routes, ${_parser.trips.length} trips, ${_parser.stopTimes.length} stopTimes, ${stops.length} stops');
      final allRoutes = _parser.buildRouteData();
      debugPrint('buildRouteData returned ${allRoutes.length} routes');

      // Nouzové linky: 4, 16, 33 a všechny noční (N*)
      const emergencyLines = {'4', '16', '33'};
      final filtered = allRoutes.where((r) {
        final name = r.route.routeShortName;
        return emergencyLines.contains(name) || name.startsWith('N');
      }).toList();
      debugPrint('After filter: ${filtered.length} routes');

      // Deduplikace podle route_short_name (ponechat jen první výskyt)
      final seen = <String>{};
      routes = filtered.where((r) => seen.add(r.route.routeShortName)).toList();
      debugPrint('After dedup: ${routes.length} routes');

      // Seřadit: nejdříve čísla, pak N-linky
      routes.sort((a, b) {
        final aName = a.route.routeShortName;
        final bName = b.route.routeShortName;
        final aIsN = aName.startsWith('N');
        final bIsN = bName.startsWith('N');
        if (aIsN != bIsN) return aIsN ? 1 : -1;
        final aNum = int.tryParse(aName.replaceFirst('N', ''));
        final bNum = int.tryParse(bName.replaceFirst('N', ''));
        if (aNum != null && bNum != null) return aNum.compareTo(bNum);
        return aName.compareTo(bName);
      });

      // Auto-detect transfers
      transferNodes = _transferManager.detectAutomaticTransfers(
        routes: routes,
        stops: stops,
      );

      // Generate demo messages
      _generateDemoMessages();
    } catch (e, stack) {
      loadError = 'Chyba načítání GTFS: $e';
      debugPrint('Error loading GTFS data: $e');
      debugPrint('Stack: $stack');
    }

    isLoading = false;
    notifyListeners();
  }

  /// Set total available buses
  void setTotalBuses(int count) {
    totalAvailableBuses = count.clamp(1, 999);
    _invalidateGeneratedTimetable();
    notifyListeners();
  }

  /// Set buses for a specific route
  void setRouteBuses(String routeId, int count) {
    final route = routes.firstWhere((r) => r.route.routeId == routeId);
    final currentTotal =
        routes.fold(0, (int sum, r) => sum + r.assignedBuses) -
            route.assignedBuses;
    final maxForRoute = totalAvailableBuses - currentTotal;
    route.assignedBuses = count.clamp(0, maxForRoute);
    _invalidateGeneratedTimetable();
    notifyListeners();
  }

  void setRouteTargetInterval(String routeId, int minutes) {
    final route = routes.firstWhere((r) => r.route.routeId == routeId);
    route.targetIntervalMinutes = minutes.clamp(0, 180);

    if (route.targetIntervalMinutes > 0 && route.roundTripMinutes > 0) {
      final needed = route.requiredBusesForTargetInterval;
      final currentTotal =
          routes.fold(0, (int sum, r) => sum + r.assignedBuses) - route.assignedBuses;
      final maxForRoute = totalAvailableBuses - currentTotal;
      route.assignedBuses = needed.clamp(0, maxForRoute);
    }

    _invalidateGeneratedTimetable();
    notifyListeners();
  }

  int autoAssignBusesByPriority() {
    if (routes.isEmpty || totalAvailableBuses <= 0) {
      for (final route in routes) {
        route.assignedBuses = 0;
      }
      _invalidateGeneratedTimetable();
      notifyListeners();
      return 0;
    }

    final assigned = <RouteData, int>{for (final route in routes) route: 0};
    final weights = <RouteData, double>{};
    var totalWeights = 0.0;

    for (final route in routes) {
      final baseWeight = route.totalTrips > 0 ? route.totalTrips.toDouble() : 1.0;
      final coefficient = route.route.routeShortName == '4' ? _line4BonusCoefficient : 1.0;
      final weight = baseWeight * coefficient;
      weights[route] = weight;
      totalWeights += weight;
    }

    if (totalWeights <= 0) {
      totalWeights = routes.length.toDouble();
      for (final route in routes) {
        weights[route] = 1.0;
      }
    }

    var used = 0;
    final remainders = <MapEntry<RouteData, double>>[];

    for (final route in routes) {
      final weight = weights[route] ?? 1.0;
      final exact = totalAvailableBuses * (weight / totalWeights);
      final buses = exact.floor();
      assigned[route] = buses;
      used += buses;
      remainders.add(MapEntry(route, exact - buses));
    }

    var leftover = totalAvailableBuses - used;
    remainders.sort((a, b) => b.value.compareTo(a.value));
    var idx = 0;
    while (leftover > 0 && remainders.isNotEmpty) {
      final route = remainders[idx % remainders.length].key;
      assigned[route] = (assigned[route] ?? 0) + 1;
      leftover--;
      idx++;
    }

    for (final route in routes) {
      route.assignedBuses = assigned[route] ?? 0;
    }

    _invalidateGeneratedTimetable();
    notifyListeners();
    return routes.fold(0, (sum, r) => sum + r.assignedBuses);
  }

  /// Add a manual transfer node
  void addManualTransfer({
    required String stopId1,
    required String stopName1,
    required String lineNumber1,
    required String stopId2,
    required String stopName2,
    required String lineNumber2,
    int maxWaitMinutes = 5,
  }) {
    final transfer = _transferManager.createManualTransfer(
      stopId1: stopId1,
      stopName1: stopName1,
      lineNumber1: lineNumber1,
      stopId2: stopId2,
      stopName2: stopName2,
      lineNumber2: lineNumber2,
      maxWaitMinutes: maxWaitMinutes,
    );
    transferNodes.add(transfer);
    _invalidateGeneratedTimetable();
    notifyListeners();
  }

  /// Update transfer node
  void updateTransfer(String id, {int? maxWaitMinutes, bool? isEnabled, TransferPriority? priority}) {
    final index = transferNodes.indexWhere((t) => t.id == id);
    if (index >= 0) {
      transferNodes[index] = transferNodes[index].copyWith(
        maxWaitMinutes: maxWaitMinutes,
        isEnabled: isEnabled,
        priority: priority,
      );
      _invalidateGeneratedTimetable();
      notifyListeners();
    }
  }

  /// Remove transfer node
  void removeTransfer(String id) {
    transferNodes.removeWhere((t) => t.id == id);
    _invalidateGeneratedTimetable();
    notifyListeners();
  }

  /// Generate timetable
  Future<int> generateTimetable() async {
    if (isGeneratingTimetable) return generatedJobs.length;
    if (assignedBuses <= 0) {
      generationError = 'Nejsou přiřazeny žádné autobusy k linkám.';
      notifyListeners();
      return 0;
    }

    isGeneratingTimetable = true;
    generationError = null;
    notifyListeners();

    final now = DateTime.now();
    final operationDate = DateTime(now.year, now.month, now.day);

    try {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      generatedJobs = _generator.generateTimetable(
        routes: routes,
        stops: stops,
        transferNodes: transferNodes,
        operationDate: operationDate,
      );

      // Add test line TT (internal test line)
      _addTestLineTT();

      isTimetableGenerated = generatedJobs.isNotEmpty;
      _updateVehicles();
      return generatedJobs.length;
    } catch (e, stack) {
      generationError = 'Chyba generování: $e';
      debugPrint('Timetable generation error: $e');
      debugPrint('Stack: $stack');
      rethrow;
    } finally {
      isGeneratingTimetable = false;
      notifyListeners();
    }
  }

  /// Add internal test line TT with test stops
  void _addTestLineTT() {
    // Register test stops if not already present
    _ensureTestStops();

    // Create test line TT job
    final testJob = TimetableJob(
      jobId: 'J-16001',
      lineNumber: 'TT',
      vehicleId: 'T-199',
      stops: [
        TimetableStop(
          stopId: 'S001',
          name: 'Suka',
          arrivalTime: null,
          departureTime: DateTime.parse('2026-02-13T19:15:00'),
          isTerminus: true,
          transfers: [],
        ),
        TimetableStop(
          stopId: 'S002',
          name: 'Pizdec',
          arrivalTime: DateTime.parse('2026-02-13T19:16:00'),
          departureTime: DateTime.parse('2026-02-13T19:16:00'),
          isTerminus: false,
          transfers: [
            Transfer(
              jobId: 'T-40055',
              lineNumber: '4',
              direction: 'Bory → Doubravka',
              waitUntil: DateTime.parse('2026-02-13T19:18:00'),
              isGuaranteed: true,
              maxWaitMinutes: 2,
            ),
          ],
        ),
        TimetableStop(
          stopId: 'S003',
          name: 'Blyat',
          arrivalTime: DateTime.parse('2026-02-13T19:17:00'),
          departureTime: DateTime.parse('2026-02-13T19:17:00'),
          isTerminus: false,
          transfers: [],
        ),
        TimetableStop(
          stopId: 'S004',
          name: 'Ebat',
          arrivalTime: DateTime.parse('2026-02-13T19:18:00'),
          departureTime: null,
          isTerminus: true,
          transfers: [],
        ),
      ],
    );

    // Add only if not already present (prevent duplicates)
    if (!generatedJobs.any((j) => j.jobId == 'J-16001')) {
      generatedJobs.add(testJob);
      debugPrint('Test line TT added: ${testJob.jobId}');
    }
  }

  /// Ensure test stops are registered in the stops map
  void _ensureTestStops() {
    final testStops = [
      GtfsStop(
        stopId: 'S001',
        stopName: 'Suka',
        stopLat: 49.729277,
        stopLon: 13.408736,
      ),
      GtfsStop(
        stopId: 'S002',
        stopName: 'Pizdec',
        stopLat: 49.729353,
        stopLon: 13.408916,
      ),
      GtfsStop(
        stopId: 'S003',
        stopName: 'Blyat',
        stopLat: 49.729290,
        stopLon: 13.409138,
      ),
      GtfsStop(
        stopId: 'S004',
        stopName: 'Ebat',
        stopLat: 49.729313,
        stopLon: 13.409241,
      ),
    ];

    for (final stop in testStops) {
      if (!stops.containsKey(stop.stopId)) {
        stops[stop.stopId] = stop;
      }
    }
  }

  void _updateVehicles() {
    final vehicleShifts = _generator.getVehicleShifts(generatedJobs);
    vehicles = vehicleShifts.entries.map((entry) {
      final firstJob =
          entry.value.isNotEmpty ? entry.value.first : null;
      return Vehicle(
        id: entry.key,
        name: 'Vůz ${entry.key}',
        currentLineNumber: firstJob?.lineNumber,
        currentDirection: firstJob?.direction,
        currentStopName:
            firstJob?.stops.firstOrNull?.name,
        status: VehicleStatus.idle,
        assignedJobIds: entry.value.map((j) => j.jobId).toList(),
      );
    }).toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    // Simulate some vehicles as in service
    for (int i = 0; i < vehicles.length && i < (vehicles.length * 0.7).ceil(); i++) {
      vehicles[i].status = VehicleStatus.inService;
      vehicles[i].delayMinutes = (i * 3) % 7; // Simulated delays
    }
  }

  /// Get jobs for a specific vehicle
  List<TimetableJob> getVehicleJobs(String vehicleId) {
    return generatedJobs
        .where((j) => j.vehicleId == vehicleId)
        .toList()
      ..sort((a, b) => (a.startTime ?? DateTime(2099))
          .compareTo(b.startTime ?? DateTime(2099)));
  }

  /// Get jobs for a specific line
  List<TimetableJob> getLineJobs(String lineNumber) {
    return generatedJobs
        .where((j) => j.lineNumber == lineNumber)
        .toList()
      ..sort((a, b) => (a.startTime ?? DateTime(2099))
          .compareTo(b.startTime ?? DateTime(2099)));
  }

  /// Check driver regulations for a vehicle
  DriverScheduleInfo checkVehicleRegulations(String vehicleId) {
    final jobs = getVehicleJobs(vehicleId);
    return _generator.checkDriverRegulations(jobs);
  }

  /// Send message to vehicle
  void sendMessage(String vehicleId, String content) {
    final vehicle = vehicles.firstWhere((v) => v.id == vehicleId,
        orElse: () => Vehicle(id: vehicleId, name: vehicleId));
    messages.add(DispatchMessage(
      id: _uuid.v4(),
      vehicleId: vehicleId,
      vehicleName: vehicle.name,
      content: content,
      timestamp: DateTime.now(),
      direction: MessageDirection.outgoing,
    ));
    notifyListeners();
  }

  /// Mark message as read
  void markMessageRead(String messageId) {
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index >= 0) {
      messages[index] = messages[index].copyWith(isRead: true);
      notifyListeners();
    }
  }

  /// Mark all messages as read
  void markAllRead() {
    messages = messages.map((m) => m.copyWith(isRead: true)).toList();
    notifyListeners();
  }

  void _generateDemoMessages() {
    final demoMessages = [
      ('V1-1', 'Vůz 1-1', 'Hlásím poruchu vytápění ve voze.', -45),
      ('V2-1', 'Vůz 2-1', 'Silný provoz na Náměstí Republiky, zpoždění cca 5 min.', -30),
      ('V1-2', 'Vůz 1-2', 'Zastávka Bory je zablokována, objíždím.', -20),
      ('V3-1', 'Vůz 3-1', 'Potvrzuji nástup do směny.', -15),
      ('V5-1', 'Vůz 5-1', 'Dotaz: mám pokračovat na lince i po 22:00?', -5),
    ];

    for (final (vid, vname, content, minAgo) in demoMessages) {
      messages.add(DispatchMessage(
        id: _uuid.v4(),
        vehicleId: vid,
        vehicleName: vname,
        content: content,
        timestamp: DateTime.now().add(Duration(minutes: minAgo)),
        direction: MessageDirection.incoming,
      ));
    }
  }

  /// Get export data as JSON
  String exportJsonData() {
    return generatedJobs
        .map((j) => j.toJson())
        .toList()
        .toString();
  }

  // ========== DRIVER & DISTRIBUTION MANAGEMENT ==========

  Future<void> _loadDrivers() async {
    try {
      drivers = await DatabaseService.getAllDrivers();
      await _refreshDriverStatuses();
    } catch (e) {
      debugPrint('Error loading drivers: $e');
    }
  }

  Future<void> _refreshDriverStatuses() async {
    try {
      driverStatuses = await DistributionManager.getDriversWithStatus();
      notifyListeners();
    } catch (e) {
      debugPrint('Error refreshing driver statuses: $e');
    }
  }

  /// Start distribution server
  Future<bool> startServer({int port = 8080}) async {
    final started = await _server.start(port: port);
    notifyListeners();
    return started;
  }

  /// Stop distribution server
  Future<void> stopServer() async {
    await _server.stop();
    notifyListeners();
  }

  /// Assign timetable to driver
  Future<bool> assignTimetableToDriver(String driverId, String vehicleId) async {
    if (!isTimetableGenerated) return false;
    
    try {
      final jobs = getVehicleJobs(vehicleId);
      if (jobs.isEmpty) return false;

      final success = await DistributionManager.assignTimetableToDriver(
        driverId: driverId,
        jobs: jobs,
      );

      if (success) {
        await _refreshDriverStatuses();
      }

      return success;
    } catch (e) {
      debugPrint('Error assigning timetable: $e');
      return false;
    }
  }

  /// Refresh driver data
  Future<void> refreshDrivers() async {
    await _loadDrivers();
  }
}
