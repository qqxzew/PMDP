import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'distribution_manager.dart';
import 'database_service.dart';

/// HTTP server for distributing timetables to client applications
class TimetableServer {
  HttpServer? _server;
  int _port = 8080;
  String? _ipAddress;

  bool get isRunning => _server != null;
  int get port => _port;
  String? get ipAddress => _ipAddress;

  /// Start the HTTP server
  Future<bool> start({int port = 8080}) async {
    if (_server != null) {
      print('Server already running');
      return false;
    }

    _port = port;

    try {
      // Get local IP address
      _ipAddress = await _getLocalIpAddress();

      final router = _createRouter();
      final handler = const Pipeline()
          .addMiddleware(logRequests())
          .addMiddleware(_corsHeaders())
          .addHandler(router.call);

      // Try to start server - only works on platforms with dart:io support
      try {
        _server = await shelf_io.serve(
          handler,
          InternetAddress.anyIPv4,
          _port,
        );
        print('🚀 Timetable server running on http://$_ipAddress:$_port');
        return true;
      } catch (e) {
        print('❌ Platform does not support HTTP server: $e');
        return false;
      }
    } catch (e) {
      print('❌ Error starting server: $e');
      return false;
    }
  }

  /// Stop the server
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    print('Server stopped');
  }

  /// Create router with API endpoints
  Router _createRouter() {
    final router = Router();

    // Health check
    router.get('/health', (Request request) {
      return Response.ok(
        json.encode({'status': 'ok', 'timestamp': DateTime.now().toIso8601String()}),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // Get server info
    router.get('/api/info', (Request request) async {
      final stats = await DistributionManager.getStatistics();
      return Response.ok(
        json.encode({
          'server': 'PMDP Timetable Distribution Server',
          'version': '1.0.0',
          'ip': _ipAddress,
          'port': _port,
          'statistics': stats,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // Get timetable for specific driver
    router.get('/api/timetable/<driverId>', (Request request, String driverId) async {
      try {
        final timetable = await DistributionManager.getTimetableForDriver(driverId);
        
        if (timetable == null) {
          return Response.notFound(
            json.encode({
              'error': 'No timetable assigned',
              'driver_id': driverId,
              'message': 'Žádný jízdní řád není přiřazen tomuto řidiči',
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }

        return Response.ok(
          json.encode(timetable),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: json.encode({'error': 'Server error', 'details': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // Get all drivers
    router.get('/api/drivers', (Request request) async {
      try {
        final drivers = await DatabaseService.getAllDrivers();
        return Response.ok(
          json.encode(drivers.map((d) => d.toJson()).toList()),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: json.encode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // Get drivers with assignment status
    router.get('/api/drivers/status', (Request request) async {
      try {
        final status = await DistributionManager.getDriversWithStatus();
        return Response.ok(
          json.encode(status),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: json.encode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // Get statistics
    router.get('/api/statistics', (Request request) async {
      try {
        final stats = await DistributionManager.getStatistics();
        return Response.ok(
          json.encode(stats),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: json.encode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    return router;
  }

  /// Add CORS headers middleware
  Middleware _corsHeaders() {
    return (Handler handler) {
      return (Request request) async {
        final response = await handler(request);
        return response.change(headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Origin, Content-Type',
        });
      };
    };
  }

  /// Get local IP address
  Future<String> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          // Skip loopback
          if (addr.address.startsWith('127.')) continue;
          // Prefer 192.168.x.x addresses (common for local networks)
          if (addr.address.startsWith('192.168.')) {
            return addr.address;
          }
        }
      }

      // Fallback to first non-loopback address
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.address.startsWith('127.')) {
            return addr.address;
          }
        }
      }

      return 'localhost';
    } catch (e) {
      print('Error getting IP: $e');
      return 'localhost';
    }
  }
}
