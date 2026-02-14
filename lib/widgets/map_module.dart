import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/gtfs_models.dart';
import '../services/live_simulation_engine.dart';
import '../services/transfer_manager.dart';

class MapModule extends StatefulWidget {
  final LiveSimulationEngine simulationEngine;
  final TransferManager transferManager;
  final List<Polyline> visibleShapes;
  final LatLng center;
  final double zoom;

  const MapModule({
    super.key,
    required this.simulationEngine,
    required this.transferManager,
    this.visibleShapes = const [],
    this.center = const LatLng(49.7475, 13.3776), // Default Plzen
    this.zoom = 13.0,
  });

  @override
  State<MapModule> createState() => _MapModuleState();
}

class _MapModuleState extends State<MapModule> {
  late final MapController _mapController;
  Timer? _simulationTimer;
  final Map<String, LatLng> _vehiclePositions = {};

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    // Simulate active trips for demo purposes if none provided
    _startSimulation();
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _startSimulation() {
    // 30 FPS update loop
    // In a real app, this would query a global SimulationState provider for all running trips
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
        if (!mounted) return;
        
        // This is where we'd ask the engine "Where is everyone?".
        // Since we don't have the list of active trips passed in, we can't implement this fully yet.
        // Assuming parent widget or provider handles state updates and passes new positions?
        // Or MapModule pulls from simulationEngine directly?
        
        // Let's assume the parent rebuilds MapModule with new data, or we use a stream.
        // If we use a stream, we'd subscribe.
        // For now, keep it simple.
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.center,
            initialZoom: widget.zoom,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.blackout_dispatch',
            ),
            
            // Shapes Layer
            PolylineLayer(
              polylines: widget.visibleShapes,
            ),

            // Vehicles Layer - TODO: Populate _vehiclePositions or pass as prop
            MarkerLayer(
              markers: _vehiclePositions.entries.map((e) {
                return Marker(
                  point: e.value,
                  width: 30,
                  height: 30,
                  child: const Icon(Icons.directions_bus, color: Colors.blue),
                );
              }).toList(),
            ),
          ],
        ),
        
        // Transfer Node Button / Overlay
        Positioned(
          top: 10,
          right: 10,
          child: FloatingActionButton(
            mini: true,
            child: const Icon(Icons.sync_alt),
            onPressed: () {
                // Open Transfer Management Split View
                // This callback should probably be passed in or handled via Navigator
            },
          ),
        ),
      ],
    );
  }
}
