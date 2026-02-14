import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/vehicle.dart';
import '../models/timetable_models.dart';
import '../models/gtfs_models.dart';
import '../models/transfer_node.dart';
import '../services/simulation_service.dart';
import '../services/osrm_routing_service.dart';

class VehicleMapScreen extends StatefulWidget {
  const VehicleMapScreen({super.key});

  @override
  State<VehicleMapScreen> createState() => _VehicleMapScreenState();
}

class _VehicleMapScreenState extends State<VehicleMapScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  
  final Set<String> _selectedLineNumbers = {}; // Изначально пусто - карта пустая

  @override
  Widget build(BuildContext context) {
    super.build(context); // Keep alive
    return Consumer<AppState>(
      builder: (context, state, _) {
        if (!state.isTimetableGenerated || state.vehicles.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.map_outlined, size: 64, color: AppTheme.textMuted),
                SizedBox(height: 16),
                Text('Žádná vozidla',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                SizedBox(height: 8),
                Text('Nejprve vygenerujte jízdní řády.',
                    style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
              ],
            ),
          );
        }

        // Получаем уникальные номера линий
        final lineNumbers = state.routes
            .map((r) => r.route.routeShortName)
            .where((n) => n.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

        return Row(
          children: [
            // Left panel – line selection with checkboxes
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
                        const Text('Mapa vozů',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                        const SizedBox(height: 4),
                        Text(
                          'Vyberte linky pro zobrazení',
                          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                if (_selectedLineNumbers.length == lineNumbers.length) {
                                  _selectedLineNumbers.clear();
                                } else {
                                  _selectedLineNumbers.addAll(lineNumbers);
                                }
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              side: const BorderSide(color: AppTheme.border),
                            ),
                            child: Text(
                              _selectedLineNumbers.length == lineNumbers.length ? 'Zrušit vše' : 'Vybrat vše',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: lineNumbers.length,
                      itemBuilder: (context, index) {
                        final lineNumber = lineNumbers[index];
                        final isSelected = _selectedLineNumbers.contains(lineNumber);
                        
                        // Подсчитываем автобусы на этой линии
                        final busCount = state.vehicles
                            .where((v) => v.currentLineNumber == lineNumber)
                            .length;

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedLineNumbers.remove(lineNumber);
                                } else {
                                  _selectedLineNumbers.add(lineNumber);
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected ? AppTheme.primary.withValues(alpha: 0.05) : Colors.transparent,
                                border: const Border(bottom: BorderSide(color: AppTheme.borderLight)),
                              ),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: isSelected,
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) {
                                          _selectedLineNumbers.add(lineNumber);
                                        } else {
                                          _selectedLineNumbers.remove(lineNumber);
                                        }
                                      });
                                    },
                                    activeColor: AppTheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      lineNumber,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '$busCount vozidel',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Container(width: 1, color: AppTheme.border),
            Expanded(
              child: _VehicleMapView(
                selectedLineNumbers: _selectedLineNumbers,
                stops: state.stops,
                shapes: state.shapes,
                allVehicles: state.vehicles,
                getVehicleJobs: state.getVehicleJobs,
                routes: state.routes,
                transferNodes: state.transferNodes,
                simulationService: state.simulationService,
                osrmRoutingService: state.osrmRoutingService,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Vehicle list item ───────────────────────────────────────────────────────

class _VehicleListItem extends StatelessWidget {
  final Vehicle vehicle;
  final bool isSelected;
  final VoidCallback onTap;

  const _VehicleListItem({required this.vehicle, required this.isSelected, required this.onTap});

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
            left: BorderSide(color: isSelected ? AppTheme.accent : Colors.transparent, width: 3),
            bottom: const BorderSide(color: AppTheme.borderLight),
          ),
        ),
        child: Row(
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(vehicle.id, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  if (vehicle.currentLineNumber != null)
                    Text('Linka ${vehicle.currentLineNumber} | ${vehicle.statusLabel}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            if (vehicle.delayMinutes > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppTheme.dangerLight, borderRadius: BorderRadius.circular(3)),
                child: Text('+${vehicle.delayMinutes}\'',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.danger)),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Vehicle detail with job list ────────────────────────────────────────────

class _VehicleDetail extends StatefulWidget {
  final Vehicle vehicle;
  final List<TimetableJob> jobs;
  final ValueChanged<String> onSendMessage;

  const _VehicleDetail({required this.vehicle, required this.jobs, required this.onSendMessage});

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
          Row(
            children: [
              Container(
                width: 48, height: 48, alignment: Alignment.center,
                decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.directions_bus, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vehicle.id, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                    Text(vehicle.statusLabel, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              if (vehicle.delayMinutes > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: AppTheme.dangerLight, borderRadius: BorderRadius.circular(6)),
                  child: Text('Zpoždění: +${vehicle.delayMinutes} min',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.danger)),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _InfoTile(label: 'Linka', value: vehicle.currentLineNumber ?? '--'),
              const SizedBox(width: 12),
              _InfoTile(label: 'Směr', value: vehicle.currentDirection ?? '--'),
              const SizedBox(width: 12),
              _InfoTile(label: 'Aktuální zastávka', value: vehicle.currentStopName ?? '--'),
              const SizedBox(width: 12),
              _InfoTile(label: 'Celkem jízd', value: '${jobs.length}'),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Odeslat hlášení / zprávu',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(controller: _messageController, decoration: const InputDecoration(hintText: 'Napište zprávu pro řidiče...')),
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
          Text('Jízdní řád vozu (${jobs.length} jízd)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          ...jobs.map((job) => _ExpandableJobRow(job: job)),
        ],
      ),
    );
  }
}

// ── Map view with simulation ────────────────────────────────────────────────

class _VehicleMapView extends StatefulWidget {
  final Set<String> selectedLineNumbers;
  final Map<String, GtfsStop> stops;
  final Map<String, List<GtfsShape>> shapes;
  final List<Vehicle> allVehicles;
  final List<TimetableJob> Function(String) getVehicleJobs;
  final List<RouteData> routes;
  final List<TransferNode> transferNodes;
  final SimulationService simulationService;
  final OsrmRoutingService osrmRoutingService;

  const _VehicleMapView({
    required this.selectedLineNumbers,
    required this.stops,
    required this.shapes,
    required this.allVehicles,
    required this.getVehicleJobs,
    required this.routes,
    required this.transferNodes,
    required this.simulationService,
    required this.osrmRoutingService,
  });

  @override
  State<_VehicleMapView> createState() => _VehicleMapViewState();
}

class _VehicleMapViewState extends State<_VehicleMapView> {
  late final MapController _mapController;
  final Set<String> _visibleRouteIds = {};
  bool _isLegendVisible = false;
  bool _areTransferNodesVisible = true;
  String? _selectedVehicleId; // Вибраний автобус для показу інфо
  
  // OSRM polylines cache: "routeId_direction" -> List<LatLng>
  final Map<String, List<LatLng>> _osrmPolylines = {};
  bool _isLoadingOsrmRoutes = false;
  double _loadingProgress = 0.0;
  int _totalRoutesToLoad = 0;
  int _loadedRoutes = 0;

  static const _routeColors = [
    Color(0xFFE53E3E), Color(0xFF3182CE), Color(0xFF38A169), Color(0xFFD69E2E),
    Color(0xFF805AD5), Color(0xFFDD6B20), Color(0xFF319795), Color(0xFFD53F8C),
    Color(0xFF2B6CB0), Color(0xFF276749), Color(0xFFB83280), Color(0xFF9C4221),
  ];

  @override
  void initState() {
    super.initState();
    _visibleRouteIds.clear();
    _visibleRouteIds.addAll(widget.routes.map((r) => r.route.routeId));
    _mapController = MapController();
    widget.simulationService.addListener(_onSimTick);
    // Не загружаем маршруты сразу - только когда выберут линию
  }

  @override
  void didUpdateWidget(covariant _VehicleMapView old) {
    super.didUpdateWidget(old);
    if (widget.routes.length != old.routes.length) {
       final newIds = widget.routes.map((r) => r.route.routeId).toSet();
       final oldIds = old.routes.map((r) => r.route.routeId).toSet();
       final added = newIds.difference(oldIds);
       _visibleRouteIds.addAll(added);
    }
    if (old.simulationService != widget.simulationService) {
      old.simulationService.removeListener(_onSimTick);
      widget.simulationService.addListener(_onSimTick);
    }
    // Загружаем маршруты для новых выбранных линий
    if (widget.selectedLineNumbers != old.selectedLineNumbers) {
      _loadOsrmRoutesForSelected();
    }
  }

  @override
  void dispose() {
    widget.simulationService.removeListener(_onSimTick);
    _mapController.dispose();
    super.dispose();
  }

  void _onSimTick() {
    if (mounted) setState(() {});
  }

  // Загружаем маршруты для выбранных линий из Mapbox
  Future<void> _loadOsrmRoutesForSelected() async {
    if (_isLoadingOsrmRoutes) return;
    
    final selectedRoutes = widget.routes.where((route) {
      return widget.selectedLineNumbers.contains(route.route.routeShortName);
    }).toList();

    if (selectedRoutes.isEmpty) return;
    
    _totalRoutesToLoad = selectedRoutes.length * 2; // forward + backward
    _loadedRoutes = 0;
    
    if (mounted) {
      setState(() {
        _isLoadingOsrmRoutes = true;
        _loadingProgress = 0.0;
      });
    }

    try {
      debugPrint('🌐 Загрузка маршрутов Mapbox для ${selectedRoutes.length} линий...');
      
      for (final route in selectedRoutes) {
        for (final dir in [0, 1]) {
          final key = '${route.route.routeId}_$dir';
          
          // Пропускаем если уже загружен
          if (_osrmPolylines.containsKey(key)) continue;

          final stList = dir == 0 ? route.forwardStopTimes : route.backwardStopTimes;
          if (stList.isEmpty) continue;

          // Собираем точки остановок
          final waypoints = <LatLng>[];
          for (final st in stList) {
            final stop = widget.stops[st.stopId];
            if (stop != null && stop.stopLat != 0 && stop.stopLon != 0) {
              waypoints.add(LatLng(stop.stopLat, stop.stopLon));
            }
          }

          if (waypoints.length < 2) continue;

          final cacheKey = widget.osrmRoutingService.makeRouteKeyFromStops(
            stList.map((st) => st.stopId).toList(),
            lineNumber: route.route.routeShortName,
            direction: dir,
          );
          
          try {
            final polyline = await widget.osrmRoutingService.getRoutePolyline(
              cacheKey: cacheKey,
              waypoints: waypoints,
            ).timeout(const Duration(seconds: 25));

            if (polyline.length >= 2 && mounted) {
              setState(() {
                _osrmPolylines[key] = polyline;
                _loadedRoutes++;
                _loadingProgress = _loadedRoutes / _totalRoutesToLoad;
              });
              debugPrint('✅ Mapbox: ${route.route.routeShortName} направление $dir (${polyline.length} точек)');
            }
            // Задержка 500мс между запросами
            await Future.delayed(const Duration(milliseconds: 500));
          } catch (e) {
            debugPrint('⚠️ Mapbox ошибка для ${route.route.routeShortName}: $e');
            if (mounted) {
              setState(() {
                _osrmPolylines[key] = waypoints;
                _loadedRoutes++;
                _loadingProgress = _loadedRoutes / _totalRoutesToLoad;
              });
            }
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingOsrmRoutes = false;
          _loadingProgress = 1.0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const plzenCenter = LatLng(49.7475, 13.3776);
    final sim = widget.simulationService;

    if (!_isLoadingOsrmRoutes && widget.selectedLineNumbers.isNotEmpty) {
      var needsLoad = false;
      for (final route in widget.routes) {
        if (!widget.selectedLineNumbers.contains(route.route.routeShortName)) continue;
        final key0 = '${route.route.routeId}_0';
        final key1 = '${route.route.routeId}_1';
        if (!_osrmPolylines.containsKey(key0) || !_osrmPolylines.containsKey(key1)) {
          needsLoad = true;
          break;
        }
      }
      if (needsLoad) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadOsrmRoutesForSelected();
          }
        });
      }
    }

    // ── Route polylines (OSRM with fallback) ──
    final polylines = <Polyline>[];
    final allRoutes = widget.routes;
    
    // Определяем есть ли выбранные линии
    final hasSelectedLines = _visibleRouteIds.isNotEmpty;
    
    for (int i = 0; i < allRoutes.length; i++) {
      final route = allRoutes[i];
      final lineNumber = route.route.routeShortName;
      final routeId = route.route.routeId;
      
      // Проверяем выбрана ли эта линия
      final isSelected = _visibleRouteIds.contains(routeId);
      
      // Если есть выбранные линии и эта не выбрана - делаем серой
      final baseColor = _routeColors[i % _routeColors.length];
      final displayColor = (hasSelectedLines && !isSelected) ? Colors.grey : baseColor;
      final opacity = (hasSelectedLines && !isSelected) ? 0.2 : 1.0;
      final strokeWidth = (hasSelectedLines && isSelected) ? 5.0 : 2.0;

      for (final dir in [0, 1]) {
        final key = '${route.route.routeId}_$dir';
        List<LatLng> pts = [];

        // Проверяем загруженный маршрут
        if (_osrmPolylines.containsKey(key)) {
          pts = _osrmPolylines[key]!;
        } else {
          // Еще не загружен - используем прямые линии
          final stList = dir == 0 ? route.forwardStopTimes : route.backwardStopTimes;
          pts = _stopTimesToPoints(stList);
        }

        if (pts.length >= 2) {
          polylines.add(Polyline(
            points: pts,
            color: dir == 0 ? displayColor.withValues(alpha: opacity) : displayColor.withValues(alpha: opacity * 0.65),
            strokeWidth: dir == 0 ? strokeWidth : strokeWidth * 0.7,
            pattern: dir == 0 ? const StrokePattern.solid() : const StrokePattern.dotted(),
          ));
        }
      }
    }

    // ── Stop markers (only for selected lines) ──
    final activeStopIds = <String>{};
    for (final route in allRoutes) {
      final routeId = route.route.routeId;
      // Показываем только остановки выбранных линий
      if (hasSelectedLines && !_visibleRouteIds.contains(routeId)) continue;
      activeStopIds.addAll(route.allStopIds);
    }
    final stopMarkers = <Marker>[];
    for (final stopId in activeStopIds) {
      final stop = widget.stops[stopId];
      if (stop == null || stop.stopLat == 0 || stop.stopLon == 0) continue;
      stopMarkers.add(Marker(
        point: LatLng(stop.stopLat, stop.stopLon),
        width: 14, height: 14,
        child: Tooltip(
          message: stop.stopName,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white, shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF4299E1), width: 2),
            ),
            child: const Center(child: Icon(Icons.circle, size: 5, color: Color(0xFF4299E1))),
          ),
        ),
      ));
    }

    // ── Vehicle markers (simulation-aware) ──
    final vehicleMarkers = <Marker>[];
    final simPositions = sim.positions;

    if (sim.isRunning && simPositions.isNotEmpty) {
      // Use live simulation positions
      for (final vp in simPositions.values) {
        // Фильтр по выбранным линиям
        if (hasSelectedLines) {
          final vehicleRoute = allRoutes.firstWhere(
            (r) => r.route.routeShortName == vp.lineNumber,
            orElse: () => allRoutes.first,
          );
          if (!_visibleRouteIds.contains(vehicleRoute.route.routeId)) continue;
        }
        
        vehicleMarkers.add(Marker(
          point: vp.position,
          width: _selectedVehicleId == vp.vehicleId ? 16 : 12,
          height: _selectedVehicleId == vp.vehicleId ? 16 : 12,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedVehicleId = _selectedVehicleId == vp.vehicleId ? null : vp.vehicleId;
              });
            },
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFDC143C), // Красный цвет
                shape: BoxShape.circle,
                border: Border.all(
                  color: _selectedVehicleId == vp.vehicleId ? Colors.yellow : Colors.white,
                  width: _selectedVehicleId == vp.vehicleId ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
        ));
      }
    } else {
      // Static fallback
      for (final v in widget.allVehicles) {
        // Фильтр по выбранным линиям
        if (hasSelectedLines) {
          final vehicleRoute = allRoutes.firstWhere(
            (r) => r.route.routeShortName == v.currentLineNumber,
            orElse: () => allRoutes.first,
          );
          if (!_visibleRouteIds.contains(vehicleRoute.route.routeId)) continue;
        }
        
        if (v.currentStopName == null) continue;
        final stopMatch = widget.stops.values.where((s) => s.stopName == v.currentStopName).firstOrNull;
        if (stopMatch == null || stopMatch.stopLat == 0) continue;
        vehicleMarkers.add(Marker(
          point: LatLng(stopMatch.stopLat, stopMatch.stopLon),
          width: _selectedVehicleId == v.id ? 16 : 12,
          height: _selectedVehicleId == v.id ? 16 : 12,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedVehicleId = _selectedVehicleId == v.id ? null : v.id;
              });
            },
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFDC143C), // Красный цвет
                shape: BoxShape.circle,
                border: Border.all(
                  color: _selectedVehicleId == v.id ? Colors.yellow : Colors.white,
                  width: _selectedVehicleId == v.id ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
        ));
      }
    }

    // ── Transfer node markers & polylines ──
    final nodePolylines = <Polyline>[];
    final nodeMarkers = <Marker>[];
    final enabledNodes = _areTransferNodesVisible ? widget.transferNodes.where((t) => t.isEnabled).toList() : <TransferNode>[];

    for (final node in enabledNodes) {
      final stop1 = widget.stops[node.stopId1];
      final stop2 = widget.stops[node.stopId2];
      if (stop1 == null || stop2 == null) continue;
      if (stop1.stopLat == 0 || stop2.stopLat == 0) continue;
      final p1 = LatLng(stop1.stopLat, stop1.stopLon);
      final p2 = LatLng(stop2.stopLat, stop2.stopLon);

      if (node.stopId1 != node.stopId2) {
        nodePolylines.add(Polyline(
          points: [p1, p2], color: const Color(0xFFE67E22), strokeWidth: 2.5,
          pattern: StrokePattern.dashed(segments: [8, 6]),
        ));
      }

      nodeMarkers.add(Marker(
        point: p1, width: 20, height: 20,
        child: Tooltip(
          message: 'Uzlový bod: ${node.lineNumber1} ↔ ${node.lineNumber2}\n${node.stopName1}${node.stopId1 != node.stopId2 ? " / ${node.stopName2}" : ""}',
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white, shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE67E22), width: 2.5),
            ),
            child: const Center(child: Icon(Icons.hub, size: 10, color: Color(0xFFE67E22))),
          ),
        ),
      ));
      if (node.stopId1 != node.stopId2) {
        nodeMarkers.add(Marker(
          point: p2, width: 16, height: 16,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFE67E22), shape: BoxShape.circle,
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
          options: MapOptions(initialCenter: plzenCenter, initialZoom: 13.0, minZoom: 10, maxZoom: 18),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'cz.blackout.dispatch'),
            PolylineLayer(polylines: polylines),
            PolylineLayer(polylines: nodePolylines),
            MarkerLayer(markers: stopMarkers),
            MarkerLayer(markers: nodeMarkers),
            MarkerLayer(markers: vehicleMarkers),
          ],
        ),

        // ── Simulation control bar ──
        Positioned(
          top: 12, left: 12, right: 12,
          child: _SimulationControlBar(sim: sim),
        ),

        // ── Vehicle info card (when selected) ──
        if (_selectedVehicleId != null)
          Positioned(
            top: 70, right: 12,
            child: _VehicleInfoCard(
              vehicleId: _selectedVehicleId!,
              allVehicles: widget.allVehicles,
              simPosition: simPositions[_selectedVehicleId],
              getVehicleJobs: widget.getVehicleJobs,
              onClose: () => setState(() => _selectedVehicleId = null),
            ),
          ),

        // ── Loading progress indicator ──
        if (_isLoadingOsrmRoutes)
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Načítání tras...',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${(_loadingProgress * 100).toInt()}% • $_loadedRoutes/$_totalRoutesToLoad',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _loadingProgress,
                      minHeight: 6,
                      backgroundColor: AppTheme.border,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Legend Toggle ──
        Positioned(
          bottom: 20,
          right: 20,
          child: FloatingActionButton.small(
            heroTag: 'legendToggle',
            backgroundColor: Colors.white,
            child: Icon(_isLegendVisible ? Icons.visibility_off : Icons.visibility, color: AppTheme.textPrimary),
            onPressed: () => setState(() => _isLegendVisible = !_isLegendVisible),
          ),
        ),

        // ── Legend Panel ──
        if (_isLegendVisible)
          Positioned(
            bottom: 70, // Above button
            right: 20,
            width: 200,
            height: 300,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)],
              ),
              child: Column(
                children: [
                   Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.borderLight))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Zobrazit linky', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        InkWell(
                          onTap: () {
                            setState(() {
                              if (_visibleRouteIds.length == widget.routes.length) {
                                _visibleRouteIds.clear();
                              } else {
                                _visibleRouteIds.addAll(widget.routes.map((r) => r.route.routeId));
                              }
                            });
                          },
                          child: Text(
                            _visibleRouteIds.length == widget.routes.length ? 'Skrýt vše' : 'Vše',
                            style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Transfer Nodes Toggle
                  Material(
                    color: Colors.transparent,
                    child: CheckboxListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      title: const Text('Přestupní uzly', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      activeColor: const Color(0xFFE67E22),
                      value: _areTransferNodesVisible,
                      onChanged: (val) => setState(() => _areTransferNodesVisible = val ?? false),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: widget.routes.length,
                      itemBuilder: (context, index) {
                        final route = widget.routes[index];
                        final isVisible = _visibleRouteIds.contains(route.route.routeId);
                        final color = _routeColors[index % _routeColors.length];
                        
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                if (isVisible) {
                                  _visibleRouteIds.remove(route.route.routeId);
                                } else {
                                  _visibleRouteIds.add(route.route.routeId);
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Row(
                                children: [
                                  Container(
                                    width: 16, height: 16,
                                    decoration: BoxDecoration(
                                      color: isVisible ? color : Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: isVisible ? color : Colors.grey.shade400, width: 2),
                                    ),
                                    child: isVisible ? const Icon(Icons.check, size: 10, color: Colors.white) : null,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Linka ${route.route.routeShortName}',
                                      style: TextStyle(
                                        color: isVisible ? AppTheme.textPrimary : AppTheme.textMuted,
                                        fontWeight: isVisible ? FontWeight.w600 : FontWeight.normal,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
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
}

// ── Simulation control bar ──────────────────────────────────────────────────

class _SimulationControlBar extends StatelessWidget {
  final SimulationService sim;
  const _SimulationControlBar({required this.sim});

  @override
  Widget build(BuildContext context) {
    final st = sim.simTime;
    final timeStr = '${st.hour.toString().padLeft(2, "0")}:${st.minute.toString().padLeft(2, "0")}:${st.second.toString().padLeft(2, "0")}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8)],
      ),
      child: Row(
        children: [
          // Play / Pause
          IconButton(
            icon: Icon(sim.isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 28),
            color: AppTheme.primary,
            tooltip: sim.isRunning ? 'Pozastavit' : 'Spustit simulaci',
            onPressed: () {
              if (sim.isRunning) {
                sim.pause();
              } else {
                sim.start();
              }
            },
          ),
          // Stop
          IconButton(
            icon: const Icon(Icons.stop_rounded, size: 24),
            color: AppTheme.danger,
            tooltip: 'Zastavit simulaci',
            onPressed: () => sim.stop(),
          ),
          const SizedBox(width: 8),

          // Time display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.surface, borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.access_time, size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Text(timeStr,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'monospace', color: AppTheme.textPrimary)),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Speed label
          const Text('Rychlost:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(width: 6),

          // Speed buttons
          ...[1.0, 5.0, 15.0, 30.0].map((s) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _SpeedChip(
                  label: '${s.toInt()}×',
                  isActive: (sim.speedMultiplier - s).abs() < 0.1,
                  onTap: () => sim.setSpeed(s),
                ),
              )),

          const Spacer(),

          // Status indicator
          if (sim.isRunning)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF38A169), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('${sim.positions.length} vozidel aktivních',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            ])
          else
            const Text('Simulace zastavena', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        ],
      ),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  const _SpeedChip({required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primary : AppTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isActive ? AppTheme.primary : AppTheme.border),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: isActive ? Colors.white : AppTheme.textSecondary,
            )),
      ),
    );
  }
}

// ── Vehicle info card ───────────────────────────────────────────────────────

class _VehicleInfoCard extends StatelessWidget {
  final String vehicleId;
  final List<Vehicle> allVehicles;
  final VehiclePosition? simPosition;
  final List<TimetableJob> Function(String) getVehicleJobs;
  final VoidCallback onClose;
  
  const _VehicleInfoCard({
    required this.vehicleId,
    required this.allVehicles,
    required this.getVehicleJobs,
    required this.onClose,
    this.simPosition,
  });

  @override
  Widget build(BuildContext context) {
    final vehicle = allVehicles.where((v) => v.id == vehicleId).firstOrNull;
    if (vehicle == null) return const SizedBox.shrink();
    
    final jobs = getVehicleJobs(vehicleId);
    final currentJob = jobs.where((j) => 
      j.startTime != null && 
      j.endTime != null && 
      DateTime.now().isAfter(j.startTime!) && 
      DateTime.now().isBefore(j.endTime!)
    ).firstOrNull;

    return Container(
      width: 280,
      constraints: const BoxConstraints(maxHeight: 400),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3), width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  vehicle.id,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Line info
          if (simPosition != null) ...[
            _InfoRow(
              icon: Icons.route,
              label: 'Linka',
              value: simPosition!.lineNumber,
            ),
            const SizedBox(height: 8),
            if (simPosition!.currentStopName != null)
              _InfoRow(
                icon: Icons.place,
                label: 'Aktuální',
                value: simPosition!.currentStopName!,
              ),
            const SizedBox(height: 8),
            if (simPosition!.nextStopName != null)
              _InfoRow(
                icon: Icons.arrow_forward,
                label: 'Další',
                value: simPosition!.nextStopName!,
              ),
            const SizedBox(height: 8),
            if (simPosition!.isWaiting)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hourglass_top, size: 14, color: Color(0xFFE67E22)),
                    SizedBox(width: 6),
                    Text(
                      'Čeká na přestup',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFE67E22),
                      ),
                    ),
                  ],
                ),
              ),
          ] else ...[
            if (vehicle.currentLineNumber != null)
              _InfoRow(
                icon: Icons.route,
                label: 'Linka',
                value: vehicle.currentLineNumber!,
              ),
            const SizedBox(height: 8),
            if (vehicle.currentStopName != null)
              _InfoRow(
                icon: Icons.place,
                label: 'Zastávka',
                value: vehicle.currentStopName!,
              ),
          ],
          
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          
          // Job list
          Text(
            'Jízdy (${jobs.length})',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          
          if (jobs.isEmpty)
            const Text(
              'Žádné jízdy',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: jobs.length > 5 ? 5 : jobs.length,
                itemBuilder: (context, index) {
                  final job = jobs[index];
                  final isCurrent = job == currentJob;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isCurrent 
                        ? AppTheme.success.withValues(alpha: 0.1)
                        : AppTheme.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isCurrent 
                          ? AppTheme.success 
                          : AppTheme.borderLight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isCurrent)
                              const Icon(
                                Icons.play_circle,
                                size: 14,
                                color: AppTheme.success,
                              ),
                            if (isCurrent) const SizedBox(width: 4),
                            Text(
                              job.lineNumber,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isCurrent ? AppTheme.success : AppTheme.primary,
                              ),
                            ),
                            const Spacer(),
                            Expanded(
                              child: Text(
                                '${job.stops.first.name} → ${job.stops.last.name}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                        if (job.startTime != null && job.endTime != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${_formatTime(job.startTime!)} - ${_formatTime(job.endTime!)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          
          if (jobs.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '+ ${jobs.length - 5} dalších jízd',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.textMuted),
        const SizedBox(width: 6),
        Text(
          '$label:',
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Live vehicle marker (simulation mode) ───────────────────────────────────

class _LiveVehicleMarker extends StatelessWidget {
  final String vehicleId;
  final String lineNumber;
  final bool isSelected;
  final bool isWaiting;
  final double heading;
  final String? currentStop;
  final String? nextStop;

  const _LiveVehicleMarker({
    required this.vehicleId,
    required this.lineNumber,
    required this.isSelected,
    required this.isWaiting,
    required this.heading,
    this.currentStop,
    this.nextStop,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isWaiting
        ? const Color(0xFFE67E22)
        : isSelected
            ? AppTheme.primary
            : const Color(0xFF38A169);

    return Tooltip(
      message: '$vehicleId – Linka $lineNumber\n${currentStop ?? ""}${nextStop != null ? " → $nextStop" : ""}${isWaiting ? "\n⏳ Čeká na přestup" : ""}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: isSelected ? 2.5 : 1.5),
          boxShadow: [BoxShadow(color: bgColor.withValues(alpha: 0.4), blurRadius: isSelected ? 8 : 4)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isWaiting ? Icons.hourglass_top : Icons.directions_bus, size: 12, color: Colors.white),
            const SizedBox(width: 2),
            Text(lineNumber,
                style: TextStyle(fontSize: isSelected ? 11 : 10, fontWeight: FontWeight.w700, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

// ── Static vehicle marker (no simulation) ───────────────────────────────────

class _StaticVehicleMarker extends StatelessWidget {
  final String vehicleId;
  final String? lineNumber;
  final bool isSelected;
  final bool isInService;
  final int delay;

  const _StaticVehicleMarker({
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
        : isInService ? const Color(0xFF38A169) : const Color(0xFFA0AEC0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: isSelected ? 2.5 : 1.5),
        boxShadow: [BoxShadow(color: bgColor.withValues(alpha: 0.4), blurRadius: isSelected ? 8 : 4)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.directions_bus, size: 12, color: Colors.white),
          const SizedBox(width: 2),
          Text(lineNumber ?? vehicleId,
              style: TextStyle(fontSize: isSelected ? 11 : 10, fontWeight: FontWeight.w700, color: Colors.white)),
          if (delay > 0) ...[
            const SizedBox(width: 2),
            Text('+$delay', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFFFFD700))),
          ],
        ],
      ),
    );
  }
}

// ── Shared small widgets ────────────────────────────────────────────────────

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
          color: AppTheme.surfaceWhite, borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary), overflow: TextOverflow.ellipsis),
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
        color: AppTheme.surface, borderRadius: BorderRadius.circular(4),
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
                    width: 32, height: 22, alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(3)),
                    child: Text(job.lineNumber, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11)),
                  ),
                  const SizedBox(width: 10),
                  Text(_fmtTime(first?.departureTime), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  const Text(' – ', style: TextStyle(color: AppTheme.textMuted)),
                  Text(_fmtTime(last?.arrivalTime), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('${first?.name ?? "?"} → ${last?.name ?? "?"}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary), overflow: TextOverflow.ellipsis),
                  ),
                  Text('${job.stops.length} zast.', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  const SizedBox(width: 4),
                  Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: AppTheme.textMuted),
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
                          child: Text(_fmtTime(stop.departureTime ?? stop.arrivalTime),
                              style: TextStyle(fontSize: 12, fontWeight: stop.isTerminus ? FontWeight.w600 : FontWeight.w400, color: AppTheme.textPrimary)),
                        ),
                        Icon(stop.isTerminus ? Icons.radio_button_checked : Icons.circle,
                            size: stop.isTerminus ? 10 : 6, color: stop.isTerminus ? AppTheme.primary : AppTheme.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(stop.name,
                              style: TextStyle(fontSize: 12, fontWeight: stop.isTerminus ? FontWeight.w600 : FontWeight.w400, color: AppTheme.textPrimary)),
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

  String _fmtTime(DateTime? dt) {
    if (dt == null) return '--:--';
    return '${dt.hour.toString().padLeft(2, "0")}:${dt.minute.toString().padLeft(2, "0")}';
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  const _TabButton({required this.label, required this.icon, required this.isSelected, required this.onTap});

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
          border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isSelected ? Colors.white : AppTheme.textSecondary)),
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
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      ],
    );
  }
}
