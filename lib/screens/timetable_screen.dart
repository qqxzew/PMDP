import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/timetable_models.dart';
import '../services/export_service.dart';

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  String? _selectedLine;
  String? _selectedVehicle;
  String _viewMode = 'line'; // 'line' or 'vehicle'

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        if (!state.isTimetableGenerated) {
          return _buildEmptyState(context);
        }

        // Get unique lines and vehicles
        final lines = state.routes
            .where((r) => r.assignedBuses > 0)
            .map((r) => r.route.routeShortName)
            .toList();
        final vehicles = state.vehicles.map((v) => v.id).toList();

        _selectedLine ??= lines.isNotEmpty ? lines.first : null;
        _selectedVehicle ??= vehicles.isNotEmpty ? vehicles.first : null;

        List<TimetableJob> displayedJobs;
        if (_viewMode == 'line' && _selectedLine != null) {
          displayedJobs = state.getLineJobs(_selectedLine!);
        } else if (_viewMode == 'vehicle' && _selectedVehicle != null) {
          displayedJobs = state.getVehicleJobs(_selectedVehicle!);
        } else {
          displayedJobs = [];
        }

        return Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Jízdní řády',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Vygenerované nouzové jízdní řády',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Export buttons
                      OutlinedButton.icon(
                        onPressed: () => _exportJson(context, state),
                        icon:
                            const Icon(Icons.download_outlined, size: 18),
                        label: const Text('Export JSON'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _copyToClipboard(context, state),
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        label: const Text('Kopírovat'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // View mode toggle + filters
                  Row(
                    children: [
                      // View mode
                      _ToggleButton(
                        label: 'Podle linky',
                        isSelected: _viewMode == 'line',
                        onTap: () => setState(() => _viewMode = 'line'),
                      ),
                      const SizedBox(width: 4),
                      _ToggleButton(
                        label: 'Podle vozů',
                        isSelected: _viewMode == 'vehicle',
                        onTap: () => setState(() => _viewMode = 'vehicle'),
                      ),
                      const SizedBox(width: 16),
                      // Line / vehicle selector
                      if (_viewMode == 'line') ...[
                        const Text('Linka: ',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary)),
                        ...lines.map((l) => Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: _LineSelectorChip(
                                lineNumber: l,
                                isSelected: _selectedLine == l,
                                onTap: () =>
                                    setState(() => _selectedLine = l),
                              ),
                            )),
                      ] else ...[
                        const Text('Vuz: ',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary)),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 180,
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedVehicle,
                            isDense: true,
                            items: vehicles
                                .map((v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(v,
                                          style: const TextStyle(
                                              fontSize: 13)),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedVehicle = v),
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        '${displayedJobs.length} jízd',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Driver regulation check (vehicle mode)
            if (_viewMode == 'vehicle' && _selectedVehicle != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _DriverInfo(vehicleId: _selectedVehicle!),
              ),
            ],

            // Timetable list
            Expanded(
              child: displayedJobs.isEmpty
                  ? const Center(
                      child: Text('Žádné jízdy',
                          style: TextStyle(color: AppTheme.textMuted)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      itemCount: displayedJobs.length,
                      itemBuilder: (context, index) {
                        return _JobCard(job: displayedJobs[index]);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_outlined,
              size: 64, color: AppTheme.textMuted),
          const SizedBox(height: 16),
          const Text(
            'Jízdní řády nebyly vygenerovány',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Nejprve nastavte počty autobusů na linkách\na poté vygenerujte jízdní řády.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              // Navigate to lines screen - will be handled by parent
            },
            child: const Text('Přejít na linky'),
          ),
        ],
      ),
    );
  }

  void _exportJson(BuildContext context, AppState state) {
    final json = ExportService.exportAsJson(state.generatedJobs);
    Clipboard.setData(ClipboardData(text: json));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('JSON data zkopírována do schránky'),
        backgroundColor: AppTheme.success,
      ),
    );
  }

  void _copyToClipboard(BuildContext context, AppState state) {
    String text;
    if (_viewMode == 'line' && _selectedLine != null) {
      text = ExportService.exportAsText(
          state.generatedJobs, _selectedLine!);
    } else if (_viewMode == 'vehicle' && _selectedVehicle != null) {
      text = ExportService.exportVehicleJson(
          state.generatedJobs, _selectedVehicle!);
    } else {
      return;
    }
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Data zkopírována do schránky'),
        backgroundColor: AppTheme.success,
      ),
    );
  }
}

class _DriverInfo extends StatelessWidget {
  final String vehicleId;

  const _DriverInfo({required this.vehicleId});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final info = state.checkVehicleRegulations(vehicleId);

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: info.isValid ? AppTheme.successLight : AppTheme.dangerLight,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            info.isValid
                ? Icons.check_circle_outline
                : Icons.warning_outlined,
            size: 18,
            color: info.isValid ? AppTheme.success : AppTheme.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Řidič: ${info.totalDrivingMinutes ~/ 60}h ${info.totalDrivingMinutes % 60}min řízení, '
              'směna: ${info.totalShiftMinutes ~/ 60}h ${info.totalShiftMinutes % 60}min'
              '${info.warnings.isNotEmpty ? ' | ${info.warnings.join(", ")}' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: info.isValid ? AppTheme.success : AppTheme.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JobCard extends StatefulWidget {
  final TimetableJob job;

  const _JobCard({required this.job});

  @override
  State<_JobCard> createState() => _JobCardState();
}

class _JobCardState extends State<_JobCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final firstStop = job.stops.firstOrNull;
    final lastStop = job.stops.lastOrNull;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          // Header row
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  // Line badge
                  Container(
                    width: 36,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      job.lineNumber,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Time
                  Text(
                    _formatTime(firstStop?.departureTime),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward,
                      size: 14, color: AppTheme.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    _formatTime(lastStop?.arrivalTime),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Route
                  Expanded(
                    child: Text(
                      '${firstStop?.name ?? "?"} -> ${lastStop?.name ?? "?"}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Vehicle
                  if (job.vehicleId != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        job.vehicleId!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: AppTheme.textMuted,
                  ),
                ],
              ),
            ),
          ),
          // Expanded detail
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  ...job.stops.map((stop) => _StopRow(stop: stop)),
                ],
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

class _StopRow extends StatelessWidget {
  final TimetableStop stop;

  const _StopRow({required this.stop});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 60,
                child: Text(
                  _formatTime(stop.arrivalTime),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: stop.isTerminus
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: AppTheme.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Icon(
                stop.isTerminus
                    ? Icons.radio_button_checked
                    : Icons.circle,
                size: stop.isTerminus ? 10 : 6,
                color: stop.isTerminus ? AppTheme.primary : AppTheme.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stop.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: stop.isTerminus
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          // Transfers
          ...stop.transfers.map((t) => Padding(
                padding: const EdgeInsets.only(left: 74, top: 1, bottom: 1),
                child: Row(
                  children: [
                    const Icon(Icons.swap_horiz,
                        size: 14, color: AppTheme.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      'Linka ${t.lineNumber} směr ${t.direction} (max. čekání ${t.maxWaitMinutes} min)',
                      style: TextStyle(
                        fontSize: 11,
                        color: t.isGuaranteed
                            ? AppTheme.success
                            : AppTheme.textMuted,
                      ),
                    ),
                    if (t.isGuaranteed) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.successLight,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const Text(
                          'GARANTOVANÝ',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.success,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              )),
        ],
      ),
    );
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : AppTheme.surfaceWhite,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _LineSelectorChip extends StatelessWidget {
  final String lineNumber;
  final bool isSelected;
  final VoidCallback onTap;

  const _LineSelectorChip({
    required this.lineNumber,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 36,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : AppTheme.surfaceWhite,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Text(
          lineNumber,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
