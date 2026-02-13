import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/vehicle.dart';
import '../models/timetable_models.dart';
import '../models/gtfs_models.dart';
import '../models/transfer_node.dart';

class VehicleMapScreen extends StatefulWidget {
  const VehicleMapScreen({super.key});

  @override
  State<VehicleMapScreen> createState() => _VehicleMapScreenState();
}

class _VehicleMapScreenState extends State<VehicleMapScreen> {
  String? _selectedVehicleId;
  bool _showMap = true;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        if (!state.isTimetableGenerated || state.vehicles.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.map_outlined,
                    size: 64, color: AppTheme.textMuted),
                SizedBox(height: 16),
                Text(
                  'Žádná vozidla',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Nejprve vygenerujte jízdní řády.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        final selectedVehicle = _selectedVehicleId != null
            ? state.vehicles.where((v) => v.id == _selectedVehicleId).firstOrNull
            : null;

        return Row(
          children: [
            // Panel se seznamem vozidel
            SizedBox(
              width: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Mapa vozů',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${state.vehicles.length} vozidel celkem, '
                          '${state.activeVehicles} v provozu',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        _StatusDot(
                          color: const Color(0xFF68D391),
                          label:
                              'V provozu (${state.vehicles.where((v) => v.status == VehicleStatus.inService).length})',
                        ),
                        const SizedBox(width: 12),
                        _StatusDot(
                          color: const Color(0xFFA0AEC0),
                          label:
                              'Stojí (${state.vehicles.where((v) => v.status == VehicleStatus.idle).length})',
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: state.vehicles.length,
                      itemBuilder: (context, index) {
                        final vehicle = state.vehicles[index];
                        return _VehicleListItem(
                          vehicle: vehicle,
                          isSelected:
                              _selectedVehicleId == vehicle.id,
                          onTap: () => setState(
                              () => _selectedVehicleId = vehicle.id),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Container(width: 1, color: AppTheme.border),
            Expanded(
              child: selectedVehicle != null
                  ? Column(
                      children: [
                        // Přepínač Mapa / Detail
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: AppTheme.borderLight)),
                          ),
                          child: Row(
                            children: [
                              _TabButton(
                                label: 'Mapa',
                                icon: Icons.map_outlined,
                                isSelected: _showMap,
                                onTap: () => setState(() => _showMap = true),
                              ),
                              const SizedBox(width: 8),
                              _TabButton(
                                label: 'Detail a jízdy',
                                icon: Icons.list_alt,
                                isSelected: !_showMap,
                                onTap: () => setState(() => _showMap = false),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: _showMap
                              ? _VehicleMapView(
                                  vehicle: selectedVehicle,
                                  stops: state.stops,
                                  allVehicles: state.vehicles,
                                  getVehicleJobs: state.getVehicleJobs,
                                  routes: state.routes,
                                  transferNodes: state.transferNodes,
                                )
                              : _VehicleDetail(
                                  vehicle: selectedVehicle,
                                  jobs: state.getVehicleJobs(selectedVehicle.id),
                                  onSendMessage: (msg) {
                                    state.sendMessage(selectedVehicle.id, msg);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Zpráva odeslána'),
                                        backgroundColor: AppTheme.success,
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    )
                  : const Center(
                      child: Text(
                        'Vyberte vozidlo ze seznamu',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _VehicleListItem extends StatelessWidget {
  final Vehicle vehicle;
  final bool isSelected;
  final VoidCallback onTap;

  const _VehicleListItem({
    required this.vehicle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    switch (vehicle.status) {
      case VehicleStatus.inService:
        statusColor = const Color(0xFF68D391);
        break;
      case VehicleStatus.onBreak:
        statusColor = const Color(0xFFF6AD55);
        break;
      case VehicleStatus.outOfService:
        statusColor = const Color(0xFFFC8181);
        break;
      case VehicleStatus.idle:
        statusColor = const Color(0xFFA0AEC0);
        break;
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accent.withValues(alpha: 0.08) : null,
          border: Border(
            left: BorderSide(
              color: isSelected ? AppTheme.accent : Colors.transparent,
              width: 3,
            ),
            bottom: const BorderSide(color: AppTheme.borderLight),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicle.id,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  if (vehicle.currentLineNumber != null)
                    Text(
                      'Linka ${vehicle.currentLineNumber} | ${vehicle.statusLabel}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (vehicle.delayMinutes > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.dangerLight,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '+${vehicle.delayMinutes}\'',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.danger,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VehicleDetail extends StatefulWidget {
  final Vehicle vehicle;
  final List<TimetableJob> jobs;
  final ValueChanged<String> onSendMessage;

  const _VehicleDetail({
    required this.vehicle,
    required this.jobs,
    required this.onSendMessage,
  });

  @override
  State<_VehicleDetail> createState() => _VehicleDetailState();
}

class _VehicleDetailState extends State<_VehicleDetail> {
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.vehicle;
    final jobs = widget.jobs;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hlavička vozidla
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.directions_bus,
                    color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle.id,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      vehicle.statusLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (vehicle.delayMinutes > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Zpoždění: +${vehicle.delayMinutes} min',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.danger,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Informační dlaždice
          Row(
            children: [
              _InfoTile(
                label: 'Linka',
                value: vehicle.currentLineNumber ?? '--',
              ),
              const SizedBox(width: 12),
              _InfoTile(
                label: 'Směr',
                value: vehicle.currentDirection ?? '--',
              ),
              const SizedBox(width: 12),
              _InfoTile(
                label: 'Aktuální zastávka',
                value: vehicle.currentStopName ?? '--',
              ),
              const SizedBox(width: 12),
              _InfoTile(
                label: 'Celkem jízd',
                value: '${jobs.length}',
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Odeslání zprávy
          const Text(
            'Odeslat hlášení / zprávu',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    hintText: 'Napište zprávu pro řidiče...',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  if (_messageController.text.trim().isNotEmpty) {
                    widget.onSendMessage(_messageController.text.trim());
                    _messageController.clear();
                  }
                },
                child: const Text('Odeslat'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Všechny jízdy - rozbalovací
          Text(
            'Jízdní řád vozu (${jobs.length} jízd)',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...jobs.map((job) => _ExpandableJobRow(job: job)),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;

  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceWhite,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandableJobRow extends StatefulWidget {
  final TimetableJob job;

  const _ExpandableJobRow({required this.job});

  @override
  State<_ExpandableJobRow> createState() => _ExpandableJobRowState();
}

class _ExpandableJobRowState extends State<_ExpandableJobRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final first = job.stops.firstOrNull;
    final last = job.stops.lastOrNull;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      job.lineNumber,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _formatTime(first?.departureTime),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const Text(' – ', style: TextStyle(color: AppTheme.textMuted)),
                  Text(
                    _formatTime(last?.arrivalTime),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${first?.name ?? "?"} → ${last?.name ?? "?"}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${job.stops.length} zast.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 18,
                    color: AppTheme.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: job.stops.map((stop) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 50,
                          child: Text(
                            _formatTime(stop.departureTime ?? stop.arrivalTime),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: stop.isTerminus ? FontWeight.w600 : FontWeight.w400,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        Icon(
                          stop.isTerminus ? Icons.radio_button_checked : Icons.circle,
                          size: stop.isTerminus ? 10 : 6,
                          color: stop.isTerminus ? AppTheme.primary : AppTheme.accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            stop.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: stop.isTerminus ? FontWeight.w600 : FontWeight.w400,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// Mapový pohled na vozidla – OpenStreetMap s trasami a zastávkami
class _VehicleMapView extends StatefulWidget {
  final Vehicle vehicle;
  final Map<String, GtfsStop> stops;
  final List<Vehicle> allVehicles;
  final List<TimetableJob> Function(String) getVehicleJobs;
  final List<RouteData> routes;
  final List<TransferNode> transferNodes;

  const _VehicleMapView({
    required this.vehicle,
    required this.stops,
    required this.allVehicles,
    required this.getVehicleJobs,
    required this.routes,
    required this.transferNodes,
  });

  @override
  State<_VehicleMapView> createState() => _VehicleMapViewState();
}

class _VehicleMapViewState extends State<_VehicleMapView> {
  late final MapController _mapController;
  final Map<String, List<LatLng>> _roadPolylineCache = {};
  final Set<String> _pendingRoadRequests = {};

  // Distinct colors for route lines
  static const _routeColors = [
    Color(0xFFE53E3E), // red
    Color(0xFF3182CE), // blue
    Color(0xFF38A169), // green
    Color(0xFFD69E2E), // yellow
    Color(0xFF805AD5), // purple
    Color(0xFFDD6B20), // orange
    Color(0xFF319795), // teal
    Color(0xFFD53F8C), // pink
    Color(0xFF2B6CB0), // dark blue
    Color(0xFF276749), // dark green
    Color(0xFFB83280), // magenta
    Color(0xFF9C4221), // brown
  ];

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Center of Plzeň
    const plzenCenter = LatLng(49.7475, 13.3776);

    // Build route polylines
    final polylines = <Polyline>[];
    final allRoutes = widget.routes;

    for (int i = 0; i < allRoutes.length; i++) {
      final route = allRoutes[i];
      final color = _routeColors[i % _routeColors.length];

      // Forward direction
      final fwdStops = route.forwardStopTimes;
      if (fwdStops.length >= 2) {
        final fallbackPoints = _stopTimesToPoints(fwdStops);
        final roadKey = '${route.route.routeId}-0';
        final points = _roadPolylineCache[roadKey] ?? fallbackPoints;
        _requestRoadPolylineIfNeeded(roadKey, fallbackPoints);
        if (points.length >= 2) {
          polylines.add(Polyline(
            points: points,
            color: color,
            strokeWidth: 4.0,
          ));
        }
      }

      // Backward direction
      final bwdStops = route.backwardStopTimes;
      if (bwdStops.length >= 2) {
        final fallbackPoints = _stopTimesToPoints(bwdStops);
        final roadKey = '${route.route.routeId}-1';
        final points = _roadPolylineCache[roadKey] ?? fallbackPoints;
        _requestRoadPolylineIfNeeded(roadKey, fallbackPoints);
        if (points.length >= 2) {
          polylines.add(Polyline(
            points: points,
            color: color.withValues(alpha: 0.5),
            strokeWidth: 3.0,
            pattern: const StrokePattern.dotted(),
          ));
        }
      }
    }

    // Build stop markers (for all routes)
    final activeStopIds = <String>{};
    for (final route in allRoutes) {
      activeStopIds.addAll(route.allStopIds);
    }

    final stopMarkers = <Marker>[];
    for (final stopId in activeStopIds) {
      final stop = widget.stops[stopId];
      if (stop == null || stop.stopLat == 0 || stop.stopLon == 0) continue;
      stopMarkers.add(Marker(
        point: LatLng(stop.stopLat, stop.stopLon),
        width: 14,
        height: 14,
        child: Tooltip(
          message: stop.stopName,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF4299E1), width: 2),
            ),
            child: const Center(
              child: Icon(Icons.circle, size: 5, color: Color(0xFF4299E1)),
            ),
          ),
        ),
      ));
    }

    // Build vehicle markers
    final vehicleMarkers = <Marker>[];
    for (final v in widget.allVehicles) {
      if (v.currentStopName == null) continue;
      final stopMatch = widget.stops.values
          .where((s) => s.stopName == v.currentStopName)
          .firstOrNull;
      if (stopMatch == null || stopMatch.stopLat == 0) continue;

      final isSelected = v.id == widget.vehicle.id;
      vehicleMarkers.add(Marker(
        point: LatLng(stopMatch.stopLat, stopMatch.stopLon),
        width: isSelected ? 60 : 44,
        height: isSelected ? 36 : 28,
        child: _VehicleMarkerWidget(
          vehicleId: v.id,
          lineNumber: v.currentLineNumber,
          isSelected: isSelected,
          isInService: v.status == VehicleStatus.inService,
          delay: v.delayMinutes,
        ),
      ));
    }

    // Build transfer-node links and markers
    final nodePolylines = <Polyline>[];
    final nodeMarkers = <Marker>[];
    final enabledNodes = widget.transferNodes.where((t) => t.isEnabled).toList();

    for (final node in enabledNodes) {
      final stop1 = widget.stops[node.stopId1];
      final stop2 = widget.stops[node.stopId2];
      if (stop1 == null || stop2 == null) continue;
      if (stop1.stopLat == 0 || stop1.stopLon == 0 || stop2.stopLat == 0 || stop2.stopLon == 0) {
        continue;
      }

      final p1 = LatLng(stop1.stopLat, stop1.stopLon);
      final p2 = LatLng(stop2.stopLat, stop2.stopLon);

      if (node.stopId1 != node.stopId2) {
        nodePolylines.add(Polyline(
          points: [p1, p2],
          color: const Color(0xFFE67E22),
          strokeWidth: 2.5,
          pattern: StrokePattern.dashed(segments: [8, 6]),
        ));
      }

      nodeMarkers.add(Marker(
        point: p1,
        width: 20,
        height: 20,
        child: Tooltip(
          message:
              'Uzlový bod: ${node.lineNumber1} ↔ ${node.lineNumber2}\n${node.stopName1}${node.stopId1 != node.stopId2 ? ' / ${node.stopName2}' : ''}',
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE67E22), width: 2.5),
            ),
            child: const Center(
              child: Icon(Icons.hub, size: 10, color: Color(0xFFE67E22)),
            ),
          ),
        ),
      ));

      if (node.stopId1 != node.stopId2) {
        nodeMarkers.add(Marker(
          point: p2,
          width: 16,
          height: 16,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFE67E22),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
          ),
        ));
      }
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: plzenCenter,
            initialZoom: 13.0,
            minZoom: 10,
            maxZoom: 18,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'cz.blackout.dispatch',
            ),
            PolylineLayer(polylines: polylines),
            PolylineLayer(polylines: nodePolylines),
            MarkerLayer(markers: stopMarkers),
            MarkerLayer(markers: nodeMarkers),
            MarkerLayer(markers: vehicleMarkers),
          ],
        ),
        // Nodes panel (left)
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            width: 360,
            constraints: const BoxConstraints(maxHeight: 260),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Uzly a propojené zastávky (${enabledNodes.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: enabledNodes.isEmpty
                      ? const Text(
                          'Žádné uzly k zobrazení.',
                          style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        )
                      : ListView.builder(
                          itemCount: enabledNodes.length,
                          itemBuilder: (context, index) {
                            final n = enabledNodes[index];
                            final label = n.stopId1 == n.stopId2
                                ? n.stopName1
                                : '${n.stopName1} → ${n.stopName2}';
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                '${n.lineNumber1} ↔ ${n.lineNumber2}: $label',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        // Legend
        Positioned(
          bottom: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Legenda',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 4),
                ...allRoutes.asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 16,
                            height: 3,
                            color: _routeColors[e.key % _routeColors.length],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${e.value.route.routeShortName} – ${e.value.route.routeLongName}',
                            style: const TextStyle(
                                fontSize: 10, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 4),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.directions_bus, size: 12, color: Color(0xFF38A169)),
                    SizedBox(width: 4),
                    Text('Vozidlo v provozu',
                        style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Vehicle info card
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.vehicle.id,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary)),
                if (widget.vehicle.currentLineNumber != null)
                  Text('Linka ${widget.vehicle.currentLineNumber}',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                if (widget.vehicle.currentStopName != null)
                  Text(widget.vehicle.currentStopName!,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                if (widget.vehicle.delayMinutes > 0)
                  Text('Zpoždění: +${widget.vehicle.delayMinutes} min',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.danger,
                          fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<LatLng> _stopTimesToPoints(List<GtfsStopTime> stopTimes) {
    final points = <LatLng>[];
    for (final st in stopTimes) {
      final stop = widget.stops[st.stopId];
      if (stop != null && stop.stopLat != 0 && stop.stopLon != 0) {
        points.add(LatLng(stop.stopLat, stop.stopLon));
      }
    }
    return points;
  }

  List<LatLng> _downsample(List<LatLng> points, int maxPoints) {
    if (points.length <= maxPoints) return points;
    final result = <LatLng>[];
    final step = (points.length - 1) / (maxPoints - 1);
    for (int i = 0; i < maxPoints; i++) {
      final idx = (i * step).round().clamp(0, points.length - 1);
      result.add(points[idx]);
    }
    return result;
  }

  void _requestRoadPolylineIfNeeded(String key, List<LatLng> fallbackPoints) {
    if (_roadPolylineCache.containsKey(key)) return;
    if (_pendingRoadRequests.contains(key)) return;
    if (fallbackPoints.length < 2) return;

    _pendingRoadRequests.add(key);
    _fetchRoadPolyline(fallbackPoints).then((roadPoints) {
      if (!mounted) return;
      _pendingRoadRequests.remove(key);
      if (roadPoints == null || roadPoints.length < 2) return;
      setState(() {
        _roadPolylineCache[key] = roadPoints;
      });
    });
  }

  Future<List<LatLng>?> _fetchRoadPolyline(List<LatLng> originalPoints) async {
    try {
      final points = _downsample(originalPoints, 90);
      final coordinates = points
          .map((p) => '${p.longitude},${p.latitude}')
          .join(';');
      final uri = Uri.parse(
        'https://router.project-osrm.org/match/v1/driving/$coordinates'
        '?geometries=geojson&overview=full&tidy=true',
      );

      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final matchings = data['matchings'] as List<dynamic>?;
      if (matchings == null || matchings.isEmpty) return null;

      final roadPoints = <LatLng>[];
      for (final match in matchings) {
        final geometry = (match as Map<String, dynamic>)['geometry']
            as Map<String, dynamic>?;
        final coords = geometry?['coordinates'] as List<dynamic>?;
        if (coords == null) continue;
        for (final c in coords) {
          final pair = c as List<dynamic>;
          if (pair.length < 2) continue;
          final lon = (pair[0] as num).toDouble();
          final lat = (pair[1] as num).toDouble();
          roadPoints.add(LatLng(lat, lon));
        }
      }

      return roadPoints;
    } catch (_) {
      return null;
    }
  }
}

/// Marker widget for a vehicle on the map
class _VehicleMarkerWidget extends StatelessWidget {
  final String vehicleId;
  final String? lineNumber;
  final bool isSelected;
  final bool isInService;
  final int delay;

  const _VehicleMarkerWidget({
    required this.vehicleId,
    this.lineNumber,
    required this.isSelected,
    required this.isInService,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isSelected
        ? AppTheme.primary
        : isInService
            ? const Color(0xFF38A169)
            : const Color(0xFFA0AEC0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white,
          width: isSelected ? 2.5 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: bgColor.withValues(alpha: 0.4),
            blurRadius: isSelected ? 8 : 4,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.directions_bus, size: 12, color: Colors.white),
          const SizedBox(width: 2),
          Text(
            lineNumber ?? vehicleId,
            style: TextStyle(
              fontSize: isSelected ? 11 : 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          if (delay > 0) ...[
            const SizedBox(width: 2),
            Text(
              '+$delay',
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFFD700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : AppTheme.surfaceWhite,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;
  final String label;

  const _StatusDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}
