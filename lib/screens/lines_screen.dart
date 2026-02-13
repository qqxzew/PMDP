import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

class LinesScreen extends StatelessWidget {
  const LinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Linky a přiřazení vozů',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Nastavte počet autobusů na jednotlivých linkách',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Total buses setter
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceWhite,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Dostupné autobusy:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 64,
                          height: 36,
                          child: _TotalBusesField(
                            value: state.totalAvailableBuses,
                            onChanged: (v) => state.setTotalBuses(v),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: state.routes.isEmpty
                        ? null
                        : () {
                            final used = state.autoAssignBusesByPriority();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Auto rozdělení hotovo: $used z ${state.totalAvailableBuses} autobusů'),
                                backgroundColor: AppTheme.success,
                              ),
                            );
                          },
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Auto rozdělit'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Available buses info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: state.unassignedBuses > 0
                      ? AppTheme.infoLight
                      : state.unassignedBuses == 0
                          ? AppTheme.successLight
                          : AppTheme.dangerLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      state.unassignedBuses > 0
                          ? Icons.info_outline
                          : Icons.check_circle_outline,
                      size: 18,
                      color: state.unassignedBuses > 0
                          ? AppTheme.info
                          : AppTheme.success,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Přiřazeno ${state.assignedBuses} z ${state.totalAvailableBuses} autobusů. '
                      '${state.unassignedBuses > 0 ? 'Zbývá ${state.unassignedBuses} k přiřazení.' : 'Všechny autobusy přiřazeny.'}',
                      style: TextStyle(
                        fontSize: 13,
                        color: state.unassignedBuses > 0
                            ? AppTheme.info
                            : AppTheme.success,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Error display
              if (state.loadError != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.danger),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppTheme.danger, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.loadError!,
                          style: const TextStyle(fontSize: 13, color: AppTheme.danger),
                        ),
                      ),
                    ],
                  ),
                ),

              // Empty state
              if (state.routes.isEmpty && state.loadError == null)
                Container(
                  padding: const EdgeInsets.all(32),
                  alignment: Alignment.center,
                  child: const Text(
                    'Žádné linky k zobrazení. Data GTFS se nepodařilo načíst.',
                    style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
                  ),
                ),

              // Lines list
              ...state.routes.map((route) => _LineCard(route: route)),

              const SizedBox(height: 24),

              // Generate button
              Center(
                child: ElevatedButton.icon(
                  onPressed: state.isGeneratingTimetable
                      ? null
                      : () async {
                          if (state.assignedBuses <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Nejprve přiřaďte alespoň 1 autobus na některou linku.'),
                                backgroundColor: AppTheme.warning,
                              ),
                            );
                            return;
                          }
                          try {
                            final jobCount = await state.generateTimetable();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    jobCount > 0
                                        ? 'Jízdní řády vygenerovány: $jobCount jízd pro ${state.vehicles.length} vozidel'
                                        : 'Generování proběhlo, ale nevznikly žádné jízdy. Zkontrolujte přiřazené linky.'),
                                backgroundColor: jobCount > 0 ? AppTheme.success : AppTheme.warning,
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Chyba generování: $e'),
                                backgroundColor: AppTheme.danger,
                              ),
                            );
                          }
                        },
                  icon: state.isGeneratingTimetable
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.play_arrow, size: 18),
                  label: Text(state.isGeneratingTimetable
                      ? 'Generuji...'
                      : state.isTimetableGenerated
                          ? 'Přegenerovat jízdní řády'
                          : 'Generovat jízdní řády'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LineCard extends StatefulWidget {
  final dynamic route;

  const _LineCard({required this.route});

  @override
  State<_LineCard> createState() => _LineCardState();
}

class _LineCardState extends State<_LineCard> {
  late TextEditingController _controller;
  late TextEditingController _intervalController;
  late FocusNode _busesFocusNode;
  bool _showStops = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.route.assignedBuses}');
    _intervalController = TextEditingController(
        text: widget.route.targetIntervalMinutes > 0
            ? '${widget.route.targetIntervalMinutes}'
            : '');
    _busesFocusNode = FocusNode();
    _busesFocusNode.addListener(() {
      if (!_busesFocusNode.hasFocus) {
        _applyBusCount();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _LineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newVal = '${widget.route.assignedBuses}';
    if (!_busesFocusNode.hasFocus && _controller.text != newVal) {
      _controller.text = newVal;
    }
    final newInterval = widget.route.targetIntervalMinutes > 0
        ? '${widget.route.targetIntervalMinutes}'
        : '';
    if (_intervalController.text != newInterval) {
      _intervalController.text = newInterval;
    }
    if (widget.route.assignedBuses <= 0 && _showStops) {
      _showStops = false;
    }
  }

  @override
  void dispose() {
    _busesFocusNode.dispose();
    _controller.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  void _applyBusCount() {
    final state = context.read<AppState>();
    final route = widget.route;
    final parsed = int.tryParse(_controller.text.trim());
    state.setRouteBuses(route.route.routeId, parsed ?? 0);
    _controller.text = '${route.assignedBuses}';
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final state = context.read<AppState>();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: route.assignedBuses > 0 ? AppTheme.accent : AppTheme.border,
          width: route.assignedBuses > 0 ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                // Line badge
                Container(
                  width: 56,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: route.assignedBuses > 0
                        ? AppTheme.primary
                        : AppTheme.surface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    route.route.routeShortName,
                    style: TextStyle(
                      color: route.assignedBuses > 0
                          ? Colors.white
                          : AppTheme.textMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Route info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        route.route.routeLongName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _InfoChip(
                            label: 'Čas jedním směrem: ${route.oneWayMinutes} min',
                          ),
                          const SizedBox(width: 8),
                          _InfoChip(
                            label: 'Oběh: ${route.roundTripMinutes} min',
                          ),
                          if (route.assignedBuses > 0) ...[
                            const SizedBox(width: 8),
                            _InfoChip(
                              label: 'Interval: ${route.intervalMinutes} min',
                              isHighlighted: true,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (route.assignedBuses > 0)
                  IconButton(
                    onPressed: () => setState(() => _showStops = !_showStops),
                    icon: Icon(
                      _showStops ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: AppTheme.textSecondary,
                    ),
                    tooltip: _showStops ? 'Skrýt zastávky' : 'Zobrazit zastávky',
                  ),
                // Bus count control
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Počet vozů',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _CounterButton(
                          icon: Icons.remove,
                          onPressed: route.assignedBuses > 0
                              ? () {
                                  state.setRouteBuses(
                                      route.route.routeId,
                                      route.assignedBuses - 1);
                                  _controller.text = '${route.assignedBuses}';
                                }
                              : null,
                        ),
                        SizedBox(
                          width: 56,
                          height: 36,
                          child: TextField(
                            controller: _controller,
                            focusNode: _busesFocusNode,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(3),
                            ],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 8),
                              filled: true,
                              fillColor: AppTheme.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.zero,
                                borderSide: BorderSide(color: AppTheme.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.zero,
                                borderSide: BorderSide(color: AppTheme.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.zero,
                                borderSide: BorderSide(
                                    color: AppTheme.primary, width: 2),
                              ),
                            ),
                            onSubmitted: (_) => _applyBusCount(),
                          ),
                        ),
                        _CounterButton(
                          icon: Icons.add,
                          onPressed: state.unassignedBuses > 0
                              ? () {
                                  state.setRouteBuses(
                                      route.route.routeId,
                                      route.assignedBuses + 1);
                                  _controller.text = '${route.assignedBuses}';
                                }
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 130,
                      child: TextField(
                        controller: _intervalController,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Interval (min)',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          filled: true,
                          fillColor: AppTheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: AppTheme.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: AppTheme.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(
                                color: AppTheme.primary, width: 1.5),
                          ),
                        ),
                        onSubmitted: (val) {
                          final minutes = int.tryParse(val) ?? 0;
                          state.setRouteTargetInterval(
                              route.route.routeId, minutes);
                          _controller.text = '${route.assignedBuses}';
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // Stop list (collapsible could be added)
            if (route.assignedBuses > 0 && _showStops) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              _StopsList(route: route, stops: state.stops),
            ],
          ],
        ),
      ),
    );
  }
}

class _StopsList extends StatelessWidget {
  final dynamic route;
  final Map stops;

  const _StopsList({required this.route, required this.stops});

  @override
  Widget build(BuildContext context) {
    final forwardStops = route.forwardStopTimes;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Směr: ${route.forwardHeadsign}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              ...List.generate(forwardStops.length, (i) {
                final st = forwardStops[i];
                final stop = stops[st.stopId];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: [
                      Icon(
                        i == 0 || i == forwardStops.length - 1
                            ? Icons.radio_button_checked
                            : Icons.circle,
                        size: i == 0 || i == forwardStops.length - 1
                            ? 10
                            : 6,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        stop?.stopName ?? st.stopId,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textPrimary,
                          fontWeight:
                              i == 0 || i == forwardStops.length - 1
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Směr: ${route.backwardHeadsign}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              ...List.generate(route.backwardStopTimes.length, (i) {
                final st = route.backwardStopTimes[i];
                final stop = stops[st.stopId];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: [
                      Icon(
                        i == 0 ||
                                i ==
                                    route.backwardStopTimes.length -
                                        1
                            ? Icons.radio_button_checked
                            : Icons.circle,
                        size: i == 0 ||
                                i ==
                                    route.backwardStopTimes.length -
                                        1
                            ? 10
                            : 6,
                        color: AppTheme.accent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        stop?.stopName ?? st.stopId,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textPrimary,
                          fontWeight: i == 0 ||
                                  i ==
                                      route.backwardStopTimes
                                              .length -
                                          1
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final bool isHighlighted;

  const _InfoChip({required this.label, this.isHighlighted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isHighlighted ? AppTheme.accent.withValues(alpha: 0.1) : AppTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isHighlighted ? AppTheme.accent : AppTheme.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: isHighlighted ? AppTheme.accent : AppTheme.textSecondary,
          fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

class _CounterButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _CounterButton({required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        width: 32,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onPressed != null ? AppTheme.surface : AppTheme.borderLight,
          border: Border.all(color: AppTheme.border),
        ),
        child: Icon(
          icon,
          size: 16,
          color: onPressed != null ? AppTheme.textPrimary : AppTheme.textMuted,
        ),
      ),
    );
  }
}

class _TotalBusesField extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _TotalBusesField({required this.value, required this.onChanged});

  @override
  State<_TotalBusesField> createState() => _TotalBusesFieldState();
}

class _TotalBusesFieldState extends State<_TotalBusesField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        _commitValue();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _TotalBusesField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && oldWidget.value != widget.value) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _commitValue() {
    final num = int.tryParse(_controller.text.trim()) ?? 1;
    final clamped = num.clamp(1, 999);
    widget.onChanged(clamped);
    _controller.text = '$clamped';
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(3),
      ],
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppTheme.primary,
      ),
      decoration: InputDecoration(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        filled: true,
        fillColor: AppTheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: AppTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: AppTheme.primary, width: 2),
        ),
      ),
      onSubmitted: (_) => _commitValue(),
    );
  }
}
