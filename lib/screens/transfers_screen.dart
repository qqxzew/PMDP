import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/gtfs_models.dart';
import '../models/transfer_node.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

enum RouteDirection {
  forward,
  backward,
  both,
}

class TransfersScreen extends StatefulWidget {
  const TransfersScreen({super.key});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  
  static const _routeColors = [
    Color(0xFFE53E3E),
    Color(0xFF3182CE),
    Color(0xFF38A169),
    Color(0xFFD69E2E),
    Color(0xFF805AD5),
    Color(0xFFDD6B20),
    Color(0xFF319795),
    Color(0xFFD53F8C),
    Color(0xFF2B6CB0),
    Color(0xFF276749),
    Color(0xFFB83280),
    Color(0xFF9C4221),
  ];

  final Map<String, List<LatLng>> _routeGeometry = {};
  final Map<String, List<LatLng>> _transferRouteGeometry = {}; // Cache for transfer node routes
  final Set<String> _activeLineNumbers = {};

  // Selection state for creating transfers
  String? _selectedLine1;
  String? _selectedLine2;
  String? _selectedStopId;
  int _syncGapMinutes = 5;

  _MapPick? _pickA;
  _MapPick? _pickB;

  bool _showLayers = false;
  bool _showTransferNodes = true;
  RouteDirection _routeDirection = RouteDirection.forward;
  
  // Loading progress tracking
  bool _isLoadingRoutes = false;
  double _loadingProgress = 0.0;
  int _totalRoutesToLoad = 0;
  int _loadedRoutes = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.read<AppState>();
    if (_activeLineNumbers.isEmpty) {
      _activeLineNumbers.addAll(state.routes.map((r) => r.route.routeShortName));
      // Загрузка маршрутов при первом открытии экрана
      Future.microtask(() => _warmupRouteGeometry(state));
    }
  }

  Future<void> _warmupRouteGeometry(
    AppState state, {
    Set<String>? onlyLines,
  }) async {
    final routing = state.osrmRoutingService;
    
    // Calculate total routes to load
    final routesToLoad = state.routes.where((r) => 
      onlyLines == null || onlyLines.contains(r.route.routeShortName)
    ).toList();
    
    _totalRoutesToLoad = routesToLoad.length * 2; // forward + backward
    _loadedRoutes = 0;
    
    if (mounted) {
      setState(() {
        _isLoadingRoutes = true;
        _loadingProgress = 0.0;
      });
    }
    
    for (final route in routesToLoad) {
      final line = route.route.routeShortName;
      final fwd = _stopTimesToPoints(route.forwardStopTimes, state.stops);
      final bwd = _stopTimesToPoints(route.backwardStopTimes, state.stops);
      
      if (fwd.length >= 2) {
        final key = 'line:$line:0';
        try {
          final poly = await routing.getRoutePolyline(
            cacheKey: key,
            waypoints: fwd,
          );
          if (mounted) {
            setState(() {
              _routeGeometry[key] = poly;
              _loadedRoutes++;
              _loadingProgress = _loadedRoutes / _totalRoutesToLoad;
            });
          }
          // Задержка 500мс между запросами
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          if (mounted) {
            setState(() {
              _loadedRoutes++;
              _loadingProgress = _loadedRoutes / _totalRoutesToLoad;
            });
          }
        }
      }
      
      if (bwd.length >= 2) {
        final key = 'line:$line:1';
        try {
          final poly = await routing.getRoutePolyline(
            cacheKey: key,
            waypoints: bwd,
          );
          if (mounted) {
            setState(() {
              _routeGeometry[key] = poly;
              _loadedRoutes++;
              _loadingProgress = _loadedRoutes / _totalRoutesToLoad;
            });
          }
          // Задержка 500мс между запросами
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          if (mounted) {
            setState(() {
              _loadedRoutes++;
              _loadingProgress = _loadedRoutes / _totalRoutesToLoad;
            });
          }
        }
      }
    }
    
    if (mounted) {
      setState(() {
        _isLoadingRoutes = false;
        _loadingProgress = 1.0;
      });
    }
  }

  Future<void> _loadTransferRoute(AppState state, String nodeId, LatLng p1, LatLng p2) async {
    final routing = state.osrmRoutingService;
    final key = 'transfer:$nodeId';
    
    try {
      final poly = await routing.getRoutePolyline(
        cacheKey: key,
        waypoints: [p1, p2],
      );
      if (mounted && poly.length >= 2) {
        setState(() => _transferRouteGeometry[key] = poly);
      }
      // Задержка 500мс между запросами
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      // Fallback to direct line on error
      if (mounted) {
        setState(() => _transferRouteGeometry[key] = [p1, p2]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Keep alive
    return Consumer<AppState>(
      builder: (context, state, _) {
        return Row(
          children: [
            Flexible(
              flex: 35,
              child: _buildLeftPanel(state),
            ),
            Container(width: 1, color: AppTheme.border),
            Flexible(
              flex: 65,
              child: _buildMapPanel(state),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLeftPanel(AppState state) {
    final transfers = state.transferNodes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AppTheme.surfaceWhite,
            border: Border(bottom: BorderSide(color: AppTheme.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Přestupní uzly',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Synchronizace spojů mezi linkami',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
        
        // Line selection section
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AppTheme.surfaceWhite,
            border: Border(bottom: BorderSide(color: AppTheme.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '1. Vyberte dvě linky',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildLineDropdown('Linka A', _selectedLine1, (value) {
                      setState(() {
                        _selectedLine1 = value;
                        _selectedStopId = null; // Reset stop selection
                      });
                    }, state),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildLineDropdown('Linka B', _selectedLine2, (value) {
                      setState(() {
                        _selectedLine2 = value;
                        _selectedStopId = null; // Reset stop selection
                      });
                    }, state),
                  ),
                ],
              ),
              
              // Stop selection
              if (_selectedLine1 != null && _selectedLine2 != null) ...[
                const SizedBox(height: 16),
                const Text(
                  '2. Vyberte zastávku',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                _buildStopDropdown(state),
                
                const SizedBox(height: 16),
                const Text(
                  '3. Nastavte čas',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Gap (minuty):', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 60,
                      child: TextFormField(
                        initialValue: _syncGapMinutes.toString(),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          final parsed = int.tryParse(v);
                          if (parsed != null) {
                            setState(() => _syncGapMinutes = parsed.clamp(1, 30));
                          }
                        },
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _selectedStopId != null
                        ? () => _synchronizeTransfer(state)
                        : null,
                    icon: const Icon(Icons.sync),
                    label: const Text('Synchronizovat'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        
        // Existing transfers list
        Container(
          padding: const EdgeInsets.all(16),
          child: const Text(
            'Aktivní synchronizace',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: transfers.isEmpty
              ? const Center(
                  child: Text(
                    'Žádné synchronizace',
                    style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(10),
                  itemCount: transfers.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final transfer = transfers[index];
                    return _TransferTableRow(transfer: transfer);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLineDropdown(String label, String? value, Function(String?) onChanged, AppState state) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: const OutlineInputBorder(),
      ),
      initialValue: value,
      items: state.routes.map((route) {
        return DropdownMenuItem(
          value: route.route.routeShortName,
          child: Text(route.route.routeShortName),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildStopDropdown(AppState state) {
    final route1 = state.routes.firstWhere((r) => r.route.routeShortName == _selectedLine1);
    final route2 = state.routes.firstWhere((r) => r.route.routeShortName == _selectedLine2);
    
    // Получаем конечные остановки для определения направления
    final route1FwdDest = route1.forwardStopTimes.isNotEmpty 
        ? state.stops[route1.forwardStopTimes.last.stopId]?.stopName ?? '?'
        : '?';
    final route1BwdDest = route1.backwardStopTimes.isNotEmpty
        ? state.stops[route1.backwardStopTimes.last.stopId]?.stopName ?? '?'
        : '?';
    final route2FwdDest = route2.forwardStopTimes.isNotEmpty
        ? state.stops[route2.forwardStopTimes.last.stopId]?.stopName ?? '?'
        : '?';
    final route2BwdDest = route2.backwardStopTimes.isNotEmpty
        ? state.stops[route2.backwardStopTimes.last.stopId]?.stopName ?? '?'
        : '?';
    
    final stops1Fwd = route1.forwardStopTimes.map((st) => st.stopId).toSet();
    final stops1Bwd = route1.backwardStopTimes.map((st) => st.stopId).toSet();
    final stops2Fwd = route2.forwardStopTimes.map((st) => st.stopId).toSet();
    final stops2Bwd = route2.backwardStopTimes.map((st) => st.stopId).toSet();
    
    // Находим близкие остановки между двумя маршрутами (без дубликатов)
    final nearbyStops = <String, Map<String, dynamic>>{};
    final processedStops = <String>{};
    
    // Проверяем все комбинации направлений
    for (final stopId1 in [...stops1Fwd, ...stops1Bwd]) {
      final stop1 = state.stops[stopId1];
      if (stop1 == null || processedStops.contains(stop1.stopName)) continue;
      
      for (final stopId2 in [...stops2Fwd, ...stops2Bwd]) {
        final stop2 = state.stops[stopId2];
        if (stop2 == null) continue;
        
        final distance = _calculateDistance(
          stop1.stopLat, stop1.stopLon,
          stop2.stopLat, stop2.stopLon,
        );
        
        if (distance < 200) {
          if (processedStops.contains(stop1.stopName)) continue;
          
          // Определяем направления для обеих линий
          final line1Dir = stops1Fwd.contains(stopId1) ? '→ $route1FwdDest' : '→ $route1BwdDest';
          final line2Dir = stops2Fwd.contains(stopId2) ? '→ $route2FwdDest' : '→ $route2BwdDest';
          
          final key = stopId1 == stopId2 ? stopId1 : '$stopId1-$stopId2';
          nearbyStops[key] = {
            'stopId1': stopId1,
            'stopId2': stopId2,
            'name': stop1.stopName,
            'distance': distance,
            'line1Direction': line1Dir,
            'line2Direction': line2Dir,
          };
          processedStops.add(stop1.stopName);
          break;
        }
      }
    }
    
    if (nearbyStops.isEmpty) {
      return const Text(
        'Žádné blízké zastávky mezi těmito linkami',
        style: TextStyle(fontSize: 12, color: AppTheme.warning),
      );
    }
    
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        labelText: 'Zastávka',
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(),
      ),
      isExpanded: true,
      initialValue: _selectedStopId,
      items: nearbyStops.entries.map((entry) {
        final data = entry.value;
        final distance = (data['distance'] as double).round();
        return DropdownMenuItem(
          value: entry.key,
          child: Text(
            '${data['name']} (${distance}m)',
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: (value) {
        setState(() => _selectedStopId = value);
      },
    );
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0; // meters
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) * math.cos(_degToRad(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _degToRad(double deg) => deg * math.pi / 180.0;

  void _synchronizeTransfer(AppState state) {
    if (_selectedLine1 == null || _selectedLine2 == null || _selectedStopId == null) return;
    
    final stopParts = _selectedStopId!.split('-');
    final stopId1 = stopParts[0];
    final stopId2 = stopParts.length > 1 ? stopParts[1] : stopParts[0];
    
    final stop1 = state.stops[stopId1];
    final stop2 = state.stops[stopId2];
    
    if (stop1 == null || stop2 == null) return;
    
    // Добавляем transfer node
    state.addManualTransfer(
      stopId1: stopId1,
      stopName1: stop1.stopName,
      lineNumber1: _selectedLine1!,
      stopId2: stopId2,
      stopName2: stop2.stopName,
      lineNumber2: _selectedLine2!,
      maxWaitMinutes: _syncGapMinutes,
    );
    
    // Инвалидируем кэш геометрии маршрутов только для затронутых линий
    final line1 = _selectedLine1;
    final line2 = _selectedLine2;
    
    if (line1 != null && line2 != null) {
      _routeGeometry.remove('line:$line1:0');
      _routeGeometry.remove('line:$line1:1');
      _routeGeometry.remove('line:$line2:0');
      _routeGeometry.remove('line:$line2:1');
    }
    
    // Reset selection
    setState(() {
      _selectedLine1 = null;
      _selectedLine2 = null;
      _selectedStopId = null;
    });
    
    // Перезагружаем геометрию только для измененных линий
    if (line1 != null && line2 != null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _warmupRouteGeometry(
            state,
            onlyLines: {line1, line2},
          );
        }
      });
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Synchronizace vytvořena - maršruty se aktualizují'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Widget _buildMapPanel(AppState state) {
    const center = LatLng(49.7475, 13.3776);
    final visibleRoutes = state.routes
        .where((r) => _activeLineNumbers.contains(r.route.routeShortName))
        .toList();
    
    // Check if we have selected lines for transfer creation
    final hasSelectedLines = _selectedLine1 != null || _selectedLine2 != null;
    final selectedLines = {
      if (_selectedLine1 != null) _selectedLine1!,
      if (_selectedLine2 != null) _selectedLine2!,
    };

    final polylines = <Polyline>[];
    for (int i = 0; i < state.routes.length; i++) {
      final route = state.routes[i];
      final line = route.route.routeShortName;
      if (!_activeLineNumbers.contains(line)) continue;
      
      // Check if this line is selected
      final isSelected = !hasSelectedLines || selectedLines.contains(line);
      final color = _routeColors[i % _routeColors.length];
      final displayColor = isSelected ? color : color.withValues(alpha: 0.2);
      final strokeWidth = isSelected ? 5.0 : 2.0;

      final fwdKey = 'line:$line:0';
      final bwdKey = 'line:$line:1';

      final fwd = _routeGeometry[fwdKey] ?? _stopTimesToPoints(route.forwardStopTimes, state.stops);
      final bwd = _routeGeometry[bwdKey] ?? _stopTimesToPoints(route.backwardStopTimes, state.stops);

      // Show routes based on selected direction
      if ((_routeDirection == RouteDirection.forward || _routeDirection == RouteDirection.both) && fwd.length >= 2) {
        polylines.add(Polyline(
          points: fwd,
          color: displayColor,
          strokeWidth: _routeDirection == RouteDirection.both ? (isSelected ? strokeWidth * 0.7 : strokeWidth * 0.5) : strokeWidth,
        ));
      }
      if ((_routeDirection == RouteDirection.backward || _routeDirection == RouteDirection.both) && bwd.length >= 2) {
        polylines.add(Polyline(
          points: bwd,
          color: _routeDirection == RouteDirection.both ? displayColor.withValues(alpha: 0.65) : displayColor,
          strokeWidth: _routeDirection == RouteDirection.both ? (isSelected ? strokeWidth * 0.6 : strokeWidth * 0.4) : strokeWidth,
          pattern: _routeDirection == RouteDirection.both ? const StrokePattern.dotted() : const StrokePattern.solid(),
        ));
      }
    }

    final stopMarkers = <Marker>[];
    for (final route in visibleRoutes) {
      final line = route.route.routeShortName;
      final isLineSelected = !hasSelectedLines || selectedLines.contains(line);
      
      for (final stopId in route.allStopIds) {
        final stop = state.stops[stopId];
        if (stop == null || stop.stopLat == 0 || stop.stopLon == 0) continue;
        
        // Не показуємо остановки невыбраних линій
        if (!isLineSelected && hasSelectedLines) continue;
        
        final pickType = _pickTypeForStop(stopId);
        stopMarkers.add(
          Marker(
            point: LatLng(stop.stopLat, stop.stopLon),
            width: pickType == _PickType.none ? 12 : 24,
            height: pickType == _PickType.none ? 12 : 24,
            child: GestureDetector(
              onTap: () => _handleStopTap(route.route.routeShortName, stopId, stop.stopName, state),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: pickType == _PickType.none ? Colors.white : AppTheme.primary,
                  border: Border.all(
                    color: pickType == _PickType.none ? const Color(0xFF3182CE) : AppTheme.primary,
                    width: pickType == _PickType.none ? 2 : 3,
                  ),
                  boxShadow: pickType != _PickType.none ? [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.4),
                      blurRadius: 6,
                      spreadRadius: 2,
                    ),
                  ] : null,
                ),
                child: pickType == _PickType.none
                    ? null
                    : Center(
                        child: Text(
                          pickType == _PickType.a ? 'A' : 'B',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        );
      }
    }

    final nodePolylines = <Polyline>[];
    final nodeMarkers = <Marker>[];
    if (_showTransferNodes) {
      for (final node in state.transferNodes.where((t) => t.isEnabled)) {
        final s1 = state.stops[node.stopId1];
        final s2 = state.stops[node.stopId2];
        if (s1 == null || s2 == null) continue;
        if (s1.stopLat == 0 || s1.stopLon == 0 || s2.stopLat == 0 || s2.stopLon == 0) continue;
        final p1 = LatLng(s1.stopLat, s1.stopLon);
        final p2 = LatLng(s2.stopLat, s2.stopLon);

        if (node.stopId1 != node.stopId2) {
          // Load route via OSRM for transfer connections
          final transferKey = 'transfer:${node.id}';
          if (!_transferRouteGeometry.containsKey(transferKey)) {
            // Schedule async load
            _loadTransferRoute(state, node.id, p1, p2);
          }
          
          final routePoints = _transferRouteGeometry[transferKey] ?? [p1, p2];
          nodePolylines.add(
            Polyline(
              points: routePoints,
              color: const Color(0xFF16A34A),
              strokeWidth: 3,
              pattern: StrokePattern.dashed(segments: [10, 6]),
            ),
          );
        }
        nodeMarkers.add(
          Marker(
            point: p1,
            width: 20,
            height: 20,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF16A34A),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 3,
                  ),
                ],
              ),
              child: const Icon(Icons.sync_alt, size: 10, color: Colors.white),
            ),
          ),
        );
      }
    }

    return Stack(
      children: [
        FlutterMap(
          options: const MapOptions(
            initialCenter: center,
            initialZoom: 13,
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
          ],
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Column(
            children: [
              Tooltip(
                message: _routeDirection == RouteDirection.forward
                    ? 'Směr tam'
                    : _routeDirection == RouteDirection.backward
                        ? 'Směr zpět'
                        : 'Oba směry',
                child: FloatingActionButton.small(
                  heroTag: 'directionToggle',
                  backgroundColor: Colors.white,
                  onPressed: () {
                    setState(() {
                      _routeDirection = switch (_routeDirection) {
                        RouteDirection.forward => RouteDirection.backward,
                        RouteDirection.backward => RouteDirection.both,
                        RouteDirection.both => RouteDirection.forward,
                      };
                    });
                  },
                  child: Icon(
                    _routeDirection == RouteDirection.forward
                        ? Icons.arrow_forward
                        : _routeDirection == RouteDirection.backward
                            ? Icons.arrow_back
                            : Icons.sync_alt,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'layersPanel',
                backgroundColor: Colors.white,
                onPressed: () => setState(() => _showLayers = !_showLayers),
                child: const Icon(Icons.layers_outlined, color: AppTheme.textPrimary),
              ),
            ],
          ),
        ),
        if (_showLayers)
          Positioned(
            top: 108,
            right: 12,
            width: 230,
            bottom: 24,
            child: _buildLayersPanel(state),
          ),
        // Loading progress indicator
        if (_isLoadingRoutes)
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
      ],
    );
  }

  Widget _buildLayersPanel(AppState state) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Слои',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          SwitchListTile(
            dense: true,
            title: const Text('Пересадочные узлы', style: TextStyle(fontSize: 12)),
            value: _showTransferNodes,
            onChanged: (v) => setState(() => _showTransferNodes = v),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: state.routes.length,
              itemBuilder: (context, index) {
                final route = state.routes[index];
                final line = route.route.routeShortName;
                final active = _activeLineNumbers.contains(line);
                final color = _routeColors[index % _routeColors.length];
                return CheckboxListTile(
                  dense: true,
                  value: active,
                  activeColor: color,
                  title: Text('Линия $line', style: const TextStyle(fontSize: 12)),
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _activeLineNumbers.add(line);
                      } else {
                        _activeLineNumbers.remove(line);
                      }
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleStopTap(
    String line,
    String stopId,
    String stopName,
    AppState state,
  ) async {
    if (_pickA == null) {
      setState(() {
        _pickA = _MapPick(lineNumber: line, stopId: stopId, stopName: stopName);
      });
      return;
    }

    if (_pickB == null) {
      setState(() {
        _pickB = _MapPick(lineNumber: line, stopId: stopId, stopName: stopName);
      });
      await _tryCreateTransferFromPicks(state);
      return;
    }

    setState(() {
      _pickA = _MapPick(lineNumber: line, stopId: stopId, stopName: stopName);
      _pickB = null;
    });
  }

  Future<void> _tryCreateTransferFromPicks(AppState state) async {
    if (_pickA == null || _pickB == null) return;
    final a = _pickA!;
    final b = _pickB!;

    if (a.lineNumber == b.lineNumber) {
      _resetPicks();
      return;
    }

    final s1 = state.stops[a.stopId];
    final s2 = state.stops[b.stopId];
    if (s1 == null || s2 == null) {
      _resetPicks();
      return;
    }

    final distance = const Distance().as(
      LengthUnit.Meter,
      LatLng(s1.stopLat, s1.stopLon),
      LatLng(s2.stopLat, s2.stopLon),
    );

    if (distance > 300) {
      _resetPicks();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Остановки дальше 300м, узел не создан.'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _CreateTransferDialog(a: a, b: b),
    );

    if (result != null) {
      state.addManualTransfer(
        stopId1: a.stopId,
        stopName1: a.stopName,
        lineNumber1: a.lineNumber,
        stopId2: b.stopId,
        stopName2: b.stopName,
        lineNumber2: b.lineNumber,
        maxWaitMinutes: result['maxWait'] as int,
        priority: result['priority'] as TransferPriority,
      );
      
      // Инвалидируем кэш и перегенерируем маршруты для затронутых линий
      final affectedLines = {a.lineNumber, b.lineNumber};
      for (final line in affectedLines) {
        _routeGeometry.remove('line:$line:0');
        _routeGeometry.remove('line:$line:1');
      }
      
      // Перезагружаем геометрию для измененных линий
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _warmupRouteGeometry(
            state,
            onlyLines: affectedLines,
          );
        }
      });
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Přestupní uzel vytvořen - trasy se aktualizují'),
          duration: Duration(seconds: 3),
        ),
      );
    }

    _resetPicks();
  }

  void _resetPicks() {
    setState(() {
      _pickA = null;
      _pickB = null;
    });
  }

  _PickType _pickTypeForStop(String stopId) {
    if (_pickA?.stopId == stopId) return _PickType.a;
    if (_pickB?.stopId == stopId) return _PickType.b;
    return _PickType.none;
  }

  List<LatLng> _stopTimesToPoints(
    List<GtfsStopTime> stopTimes,
    Map<String, GtfsStop> stops,
  ) {
    final points = <LatLng>[];
    for (final st in stopTimes) {
      final s = stops[st.stopId];
      if (s == null || s.stopLat == 0 || s.stopLon == 0) continue;
      points.add(LatLng(s.stopLat, s.stopLon));
    }
    return points;
  }
}

class _TransferTableRow extends StatelessWidget {
  final TransferNode transfer;
  const _TransferTableRow({required this.transfer});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with lines and switch
          Row(
            children: [
              _LineChip(line: transfer.lineNumber1),
              const SizedBox(width: 6),
              const Icon(Icons.swap_horiz, size: 16, color: AppTheme.textMuted),
              const SizedBox(width: 6),
              _LineChip(line: transfer.lineNumber2),
              const Spacer(),
              Switch(
                value: transfer.isEnabled,
                onChanged: (v) => state.updateTransfer(transfer.id, isEnabled: v),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Stops display - each on separate line
          _StopDisplayRow(
            icon: Icons.radio_button_checked,
            label: 'Zastávka A:',
            stopName: transfer.stopName1,
            lineNumber: transfer.lineNumber1,
          ),
          const SizedBox(height: 6),
          _StopDisplayRow(
            icon: Icons.radio_button_checked,
            label: 'Zastávka B:',
            stopName: transfer.stopName2,
            lineNumber: transfer.lineNumber2,
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          // Settings section
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Max čekání:', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 36,
                      child: TextFormField(
                        initialValue: transfer.maxWaitMinutes.toString(),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          isDense: true,
                          suffixText: 'min',
                          suffixStyle: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          border: const OutlineInputBorder(),
                        ),
                        onFieldSubmitted: (v) {
                          final parsed = int.tryParse(v);
                          if (parsed != null) {
                            state.updateTransfer(transfer.id, maxWaitMinutes: parsed.clamp(1, 20));
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: transfer.isEnabled ? AppTheme.success.withValues(alpha: 0.14) : AppTheme.warning.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  children: [
                    Icon(
                      transfer.isEnabled ? Icons.sync : Icons.pause,
                      size: 20,
                      color: transfer.isEnabled ? AppTheme.success : AppTheme.warning,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      transfer.isEnabled ? 'Sync' : 'Wait',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: transfer.isEnabled ? AppTheme.success : AppTheme.warning,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text('Приоритет:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          const SizedBox(height: 6),
          DropdownButtonFormField<TransferPriority>(
            value: transfer.priority,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                value: TransferPriority.equal,
                child: Row(
                  children: [
                    const Icon(Icons.sync_alt, size: 16, color: AppTheme.textMuted),
                    const SizedBox(width: 8),
                    Text('Oba čekají (равный)', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              DropdownMenuItem(
                value: TransferPriority.line1First,
                child: Row(
                  children: [
                    const Icon(Icons.arrow_forward, size: 16, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Text('${transfer.lineNumber2} čeká na ${transfer.lineNumber1}', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              DropdownMenuItem(
                value: TransferPriority.line2First,
                child: Row(
                  children: [
                    const Icon(Icons.arrow_back, size: 16, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Text('${transfer.lineNumber1} čeká na ${transfer.lineNumber2}', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                state.updateTransfer(transfer.id, priority: value);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _LineChip extends StatelessWidget {
  final String line;
  const _LineChip({required this.line});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        line,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CreateTransferDialog extends StatefulWidget {
  final _MapPick a;
  final _MapPick b;

  const _CreateTransferDialog({required this.a, required this.b});

  @override
  State<_CreateTransferDialog> createState() => _CreateTransferDialogState();
}

class _CreateTransferDialogState extends State<_CreateTransferDialog> {
  int _maxWait = 5;
  TransferPriority _priority = TransferPriority.equal;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Создать узел пересадки'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Линия ${widget.a.lineNumber}: ${widget.a.stopName}'),
            const SizedBox(height: 4),
            Text('Линия ${widget.b.lineNumber}: ${widget.b.stopName}'),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('maxWaitMinutes'),
                const SizedBox(width: 12),
                SizedBox(
                  width: 70,
                  child: TextFormField(
                    initialValue: _maxWait.toString(),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      final parsed = int.tryParse(v);
                      if (parsed != null) {
                        _maxWait = parsed.clamp(1, 20);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Приоритет:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            DropdownButtonFormField<TransferPriority>(
              value: _priority,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(
                  value: TransferPriority.equal,
                  child: Text('Oba čekají (равный)'),
                ),
                DropdownMenuItem(
                  value: TransferPriority.line1First,
                  child: Text('${widget.b.lineNumber} čeká na ${widget.a.lineNumber}'),
                ),
                DropdownMenuItem(
                  value: TransferPriority.line2First,
                  child: Text('${widget.a.lineNumber} čeká na ${widget.b.lineNumber}'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _priority = value);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, {'maxWait': _maxWait, 'priority': _priority}),
          child: const Text('Создать'),
        ),
      ],
    );
  }
}

enum _PickType { none, a, b }

class _MapPick {
  final String lineNumber;
  final String stopId;
  final String stopName;

  _MapPick({
    required this.lineNumber,
    required this.stopId,
    required this.stopName,
  });
}

// Helper widget for stop display
class _StopDisplayRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String stopName;
  final String lineNumber;

  const _StopDisplayRow({
    required this.icon,
    required this.label,
    required this.stopName,
    required this.lineNumber,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppTheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                stopName,
                style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            'L$lineNumber',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
