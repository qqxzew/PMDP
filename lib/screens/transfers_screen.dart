import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/transfer_node.dart';
import '../models/gtfs_models.dart';
import '../services/osrm_service.dart';

class TransfersScreen extends StatefulWidget {
  const TransfersScreen({super.key});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  String? _selectedLineA;
  String? _selectedStopA;
  String? _selectedLineB;
  String? _selectedStopB;
  String? _highlightedLine;

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

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        return Row(
          children: [
            SizedBox(width: 440, child: _buildLeftPanel(state)),
            Container(width: 1, color: AppTheme.border),
            Expanded(child: _buildMapPanel(state)),
          ],
        );
      },
    );
  }

  Widget _buildLeftPanel(AppState state) {
    final autoTransfers = state.transferNodes.where((t) => t.isAutomatic).toList();
    final manualTransfers = state.transferNodes.where((t) => !t.isAutomatic).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Přestupní uzly',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              const SizedBox(height: 4),
              Text(
                '${state.transferNodes.length} vazeb celkem, ${state.transferNodes.where((t) => t.isEnabled).length} aktivních',
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        _buildSyncPanel(state),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              if (manualTransfers.isNotEmpty) ...[
                _sectionLabel('Vlastní (${manualTransfers.length})'),
                ...manualTransfers.map((t) => _TransferRow(transfer: t)),
                const SizedBox(height: 12),
              ],
              _sectionLabel('Automatické (${autoTransfers.length})'),
              ...autoTransfers.map((t) => _TransferRow(transfer: t)),
              if (autoTransfers.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Žádné automatické přestupy.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(text,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.5)),
    );
  }

  Widget _buildSyncPanel(AppState state) {
    final lineOptions = state.routes.map((r) => r.route.routeShortName).toList();

    List<MapEntry<String, String>> stopsForLine(String? lineNumber) {
      if (lineNumber == null) return [];
      final route = state.routes.where((r) => r.route.routeShortName == lineNumber).firstOrNull;
      if (route == null) return [];
      return route.allStopIds.map((id) => MapEntry(id, state.stops[id]?.stopName ?? id)).toList()
        ..sort((a, b) => a.value.compareTo(b.value));
    }

    final stopsA = stopsForLine(_selectedLineA);
    final stopsB = stopsForLine(_selectedLineB);
    final canSync = _selectedLineA != null && _selectedLineB != null && _selectedStopA != null && _selectedStopB != null;

    return Container(
      padding: const EdgeInsets.all(12),
      color: AppTheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Nová synchronizace',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Row(children: [
            const SizedBox(width: 56, child: Text('Linka A', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))),
            Expanded(
              child: _MiniDropdown<String>(
                value: _selectedLineA,
                hint: 'Vyberte',
                items: lineOptions.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                onChanged: (v) => setState(() { _selectedLineA = v; _selectedStopA = null; _highlightedLine = v; }),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: _MiniDropdown<String>(
                value: _selectedStopA,
                hint: 'Zastávka',
                items: stopsA.map((s) => DropdownMenuItem(value: s.key, child: Text(s.value))).toList(),
                onChanged: (v) => setState(() => _selectedStopA = v),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const SizedBox(width: 56, child: Text('Linka B', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))),
            Expanded(
              child: _MiniDropdown<String>(
                value: _selectedLineB,
                hint: 'Vyberte',
                items: lineOptions.where((l) => l != _selectedLineA).map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                onChanged: (v) => setState(() { _selectedLineB = v; _selectedStopB = null; _highlightedLine = v; }),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: _MiniDropdown<String>(
                value: _selectedStopB,
                hint: 'Zastávka',
                items: stopsB.map((s) => DropdownMenuItem(value: s.key, child: Text(s.value))).toList(),
                onChanged: (v) => setState(() => _selectedStopB = v),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: canSync ? () => _showSyncDialog(context, state) : null,
              icon: const Icon(Icons.sync, size: 16),
              label: const Text('Synchronizovat'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), textStyle: const TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  void _showSyncDialog(BuildContext context, AppState state) {
    int waitMinutes = 2;
    TransferPriority priority = TransferPriority.equal;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDS) {
          return AlertDialog(
            title: const Text('Nastavení synchronizace'),
            content: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  'Linka $_selectedLineA (${state.stops[_selectedStopA]?.stopName ?? _selectedStopA})'
                  '  ↔  Linka $_selectedLineB (${state.stops[_selectedStopB]?.stopName ?? _selectedStopB})',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  const Text('Čas čekání (min):'),
                  const SizedBox(width: 12),
                  SizedBox(width: 60, child: TextFormField(initialValue: waitMinutes.toString(), keyboardType: TextInputType.number, textAlign: TextAlign.center, onChanged: (v) => waitMinutes = int.tryParse(v) ?? 2)),
                ]),
                const SizedBox(height: 16),
                const Text('Priorita (kdo koho čeká):', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                _PriorityRadio(label: 'Oba čekají symetricky', value: TransferPriority.equal, groupValue: priority, onChanged: (v) => setDS(() => priority = v!)),
                _PriorityRadio(label: 'Linka $_selectedLineB čeká na $_selectedLineA', value: TransferPriority.line1First, groupValue: priority, onChanged: (v) => setDS(() => priority = v!)),
                _PriorityRadio(label: 'Linka $_selectedLineA čeká na $_selectedLineB', value: TransferPriority.line2First, groupValue: priority, onChanged: (v) => setDS(() => priority = v!)),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Zrušit')),
              ElevatedButton(
                onPressed: () {
                  state.addManualTransfer(
                    stopId1: _selectedStopA!, stopName1: state.stops[_selectedStopA]?.stopName ?? _selectedStopA!,
                    lineNumber1: _selectedLineA!, stopId2: _selectedStopB!, stopName2: state.stops[_selectedStopB]?.stopName ?? _selectedStopB!,
                    lineNumber2: _selectedLineB!, maxWaitMinutes: waitMinutes,
                  );
                  final last = state.transferNodes.last;
                  state.updateTransfer(last.id, priority: priority);
                  Navigator.pop(ctx);
                  setState(() { _selectedLineA = null; _selectedLineB = null; _selectedStopA = null; _selectedStopB = null; });
                },
                child: const Text('Synchronizovat'),
              ),
            ],
          );
        });
      },
    );
  }

  Widget _buildMapPanel(AppState state) {
    const plzenCenter = LatLng(49.7475, 13.3776);
    final polylines = <Polyline>[];
    final allRoutes = state.routes;

    for (int i = 0; i < allRoutes.length; i++) {
      final route = allRoutes[i];
      final lineName = route.route.routeShortName;
      final isHL = _highlightedLine == null || _highlightedLine == lineName;
      final color = _routeColors[i % _routeColors.length];

      final fwd = route.forwardStopTimes;
      if (fwd.length >= 2) {
        final pts = _stopsToPoints(fwd, state.stops);
        final roadKey = '${route.route.routeId}-0';
        final road = OsrmService.instance.getPolyline(roadKey, pts, onReady: () { if (mounted) setState(() {}); });
        final points = road ?? pts;
        if (points.length >= 2) polylines.add(Polyline(points: points, color: isHL ? color : color.withValues(alpha: 0.15), strokeWidth: isHL ? 4.5 : 2.0));
      }

      final bwd = route.backwardStopTimes;
      if (bwd.length >= 2) {
        final pts = _stopsToPoints(bwd, state.stops);
        final roadKey = '${route.route.routeId}-1';
        final road = OsrmService.instance.getPolyline(roadKey, pts, onReady: () { if (mounted) setState(() {}); });
        final points = road ?? pts;
        if (points.length >= 2) polylines.add(Polyline(points: points, color: isHL ? color.withValues(alpha: 0.45) : color.withValues(alpha: 0.08), strokeWidth: isHL ? 3.0 : 1.5, pattern: const StrokePattern.dotted()));
      }
    }

    final stopMarkers = <Marker>[];
    final activeStopIds = <String>{};
    for (final route in allRoutes) activeStopIds.addAll(route.allStopIds);
    for (final stopId in activeStopIds) {
      final stop = state.stops[stopId];
      if (stop == null || stop.stopLat == 0) continue;
      final belongsToSelected = (_selectedLineA != null && allRoutes.where((r) => r.route.routeShortName == _selectedLineA).any((r) => r.allStopIds.contains(stopId)))
          || (_selectedLineB != null && allRoutes.where((r) => r.route.routeShortName == _selectedLineB).any((r) => r.allStopIds.contains(stopId)));
      final isSelStop = stopId == _selectedStopA || stopId == _selectedStopB;
      stopMarkers.add(Marker(
        point: LatLng(stop.stopLat, stop.stopLon), width: isSelStop ? 22 : 14, height: isSelStop ? 22 : 14,
        child: GestureDetector(
          onTap: () => _onStopTapped(stopId, state),
          child: Tooltip(message: stop.stopName, child: Container(
            decoration: BoxDecoration(color: isSelStop ? const Color(0xFFE53E3E) : Colors.white, shape: BoxShape.circle, border: Border.all(color: isSelStop ? const Color(0xFFE53E3E) : belongsToSelected ? const Color(0xFFE67E22) : const Color(0xFF4299E1), width: isSelStop ? 3 : 2)),
            child: Center(child: Icon(Icons.circle, size: isSelStop ? 8 : 5, color: isSelStop ? Colors.white : const Color(0xFF4299E1))),
          )),
        ),
      ));
    }

    final nodePolylines = <Polyline>[];
    final nodeMarkers = <Marker>[];
    final enabledNodes = state.transferNodes.where((t) => t.isEnabled).toList();
    for (final node in enabledNodes) {
      final s1 = state.stops[node.stopId1]; final s2 = state.stops[node.stopId2];
      if (s1 == null || s2 == null || s1.stopLat == 0 || s2.stopLat == 0) continue;
      final p1 = LatLng(s1.stopLat, s1.stopLon); final p2 = LatLng(s2.stopLat, s2.stopLon);
      if (node.stopId1 != node.stopId2) nodePolylines.add(Polyline(points: [p1, p2], color: const Color(0xFFE67E22), strokeWidth: 2.5, pattern: StrokePattern.dashed(segments: [8, 6])));
      nodeMarkers.add(Marker(point: p1, width: 20, height: 20, child: Tooltip(
        message: '${node.lineNumber1} ↔ ${node.lineNumber2}\n${node.stopName1}${node.isSameStop ? '' : ' / ${node.stopName2}'}',
        child: Container(decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFE67E22), width: 2.5)), child: const Center(child: Icon(Icons.hub, size: 10, color: Color(0xFFE67E22)))),
      )));
    }

    return Stack(children: [
      FlutterMap(
        options: MapOptions(initialCenter: plzenCenter, initialZoom: 13.0, minZoom: 10, maxZoom: 18),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'cz.blackout.dispatch'),
          PolylineLayer(polylines: polylines), PolylineLayer(polylines: nodePolylines),
          MarkerLayer(markers: stopMarkers), MarkerLayer(markers: nodeMarkers),
        ],
      ),
      Positioned(bottom: 12, left: 12, child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const Text('Linky', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          const SizedBox(height: 4),
          ...allRoutes.asMap().entries.map((e) {
            final ln = e.value.route.routeShortName;
            return GestureDetector(
              onTap: () => setState(() { _highlightedLine = _highlightedLine == ln ? null : ln; }),
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 1), child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 16, height: 4, decoration: BoxDecoration(color: _routeColors[e.key % _routeColors.length], borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 6),
                Text('$ln – ${e.value.route.routeLongName}', style: TextStyle(fontSize: 10, color: _highlightedLine == ln ? AppTheme.textPrimary : AppTheme.textSecondary, fontWeight: _highlightedLine == ln ? FontWeight.w700 : FontWeight.w400)),
              ])),
            );
          }),
        ]),
      )),
      Positioned(top: 10, right: 10, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(6), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)]),
        child: const Text('Klikni na linku v legendě → zvýraznění\nKlikni na zastávku → výběr pro synchronizaci', style: TextStyle(fontSize: 11, color: AppTheme.textMuted), textAlign: TextAlign.right),
      )),
    ]);
  }

  void _onStopTapped(String stopId, AppState state) {
    String? belongsLine;
    for (final route in state.routes) {
      if (route.allStopIds.contains(stopId)) { belongsLine = route.route.routeShortName; break; }
    }
    setState(() {
      if (_selectedLineA == null || _selectedStopA == null) {
        if (belongsLine != null) _selectedLineA = belongsLine;
        _selectedStopA = stopId;
      } else if (_selectedLineB == null || _selectedStopB == null) {
        if (belongsLine != null && belongsLine != _selectedLineA) _selectedLineB = belongsLine;
        _selectedStopB = stopId;
      } else {
        if (belongsLine != null) _selectedLineA = belongsLine;
        _selectedStopA = stopId; _selectedLineB = null; _selectedStopB = null;
      }
    });
  }

  List<LatLng> _stopsToPoints(List<GtfsStopTime> stopTimes, Map<String, GtfsStop> stops) {
    final points = <LatLng>[];
    for (final st in stopTimes) { final s = stops[st.stopId]; if (s != null && s.stopLat != 0 && s.stopLon != 0) points.add(LatLng(s.stopLat, s.stopLon)); }
    return points;
  }
}

class _MiniDropdown<T> extends StatelessWidget {
  final T? value; final String hint; final List<DropdownMenuItem<T>> items; final ValueChanged<T?>? onChanged;
  const _MiniDropdown({required this.value, required this.hint, required this.items, this.onChanged});
  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 34, child: DropdownButtonFormField<T>(
      value: value,
      decoration: InputDecoration(hintText: hint, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppTheme.border))),
      style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary), items: items, onChanged: onChanged,
    ));
  }
}

class _PriorityRadio extends StatelessWidget {
  final String label; final TransferPriority value; final TransferPriority groupValue; final ValueChanged<TransferPriority?> onChanged;
  const _PriorityRadio({required this.label, required this.value, required this.groupValue, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
      Radio<TransferPriority>(value: value, groupValue: groupValue, onChanged: onChanged, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
      const SizedBox(width: 4),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary))),
    ]));
  }
}

class _TransferRow extends StatelessWidget {
  final TransferNode transfer;
  const _TransferRow({required this.transfer});
  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: transfer.isEnabled ? AppTheme.surfaceWhite : AppTheme.surface, borderRadius: BorderRadius.circular(6), border: Border.all(color: transfer.isEnabled ? AppTheme.border : AppTheme.borderLight)),
      child: Row(children: [
        SizedBox(width: 36, height: 24, child: Transform.scale(scale: 0.7, child: Switch(value: transfer.isEnabled, onChanged: (v) => state.updateTransfer(transfer.id, isEnabled: v), activeTrackColor: AppTheme.accent))),
        _LineBadge(lineNumber: transfer.lineNumber1),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.swap_horiz, size: 14, color: AppTheme.textMuted)),
        _LineBadge(lineNumber: transfer.lineNumber2),
        const SizedBox(width: 6),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(transfer.isSameStop ? transfer.stopName1 : '${transfer.stopName1} / ${transfer.stopName2}', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary), overflow: TextOverflow.ellipsis),
          Text('${transfer.maxWaitMinutes} min · ${transfer.priorityLabel}', style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
        ])),
        if (transfer.isAutomatic)
          Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), decoration: BoxDecoration(color: AppTheme.infoLight, borderRadius: BorderRadius.circular(3)), child: const Text('AUTO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.info)))
        else
          IconButton(onPressed: () => state.removeTransfer(transfer.id), icon: const Icon(Icons.close, size: 14), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), color: AppTheme.textMuted, tooltip: 'Odebrat'),
      ]),
    );
  }
}

class _LineBadge extends StatelessWidget {
  final String lineNumber;
  const _LineBadge({required this.lineNumber});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(3)),
      child: Text(lineNumber, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }
}
