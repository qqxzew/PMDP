import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/stat_card.dart';
import '../services/timetable_generator.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

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
                          'Přehled',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Nouzový provoz – dispečerský panel',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: (state.assignedBuses > 0 && !state.isGeneratingTimetable)
                        ? () async => await state.generateTimetable()
                        : null,
                    icon: state.isGeneratingTimetable
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.play_arrow, size: 18),
                    label: Text(
                      state.isGeneratingTimetable
                          ? 'Generuji...'
                          : state.isTimetableGenerated
                              ? 'Přegenerovat jízdní řády'
                              : 'Generovat jízdní řády',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Warning banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.warningLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFFECC94B).withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppTheme.warning, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Nouzový režim aktivován',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.warning,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Blackout – omezený počet vozidel a řidičů. '
                            'Dostupné autobusy: ${state.totalAvailableBuses}, '
                            'Přiřazené: ${state.assignedBuses}',
                            style: const TextStyle(
                              color: AppTheme.warning,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Stats grid
              LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth > 900
                      ? 4
                      : constraints.maxWidth > 600
                          ? 2
                          : 1;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      SizedBox(
                        width: (constraints.maxWidth -
                                (crossAxisCount - 1) * 16) /
                            crossAxisCount,
                        child: StatCard(
                          title: 'DOSTUPNÉ AUTOBUSY',
                          value: '${state.totalAvailableBuses}',
                          subtitle: '${state.unassignedBuses} nepřiřazeno',
                          icon: Icons.directions_bus_outlined,
                          color: AppTheme.primary,
                        ),
                      ),
                      SizedBox(
                        width: (constraints.maxWidth -
                                (crossAxisCount - 1) * 16) /
                            crossAxisCount,
                        child: StatCard(
                          title: 'AKTIVNÍ LINKY',
                          value: '${state.activeLines}',
                          subtitle: 'z ${state.routes.length} celkem',
                          icon: Icons.route_outlined,
                          color: AppTheme.accent,
                        ),
                      ),
                      SizedBox(
                        width: (constraints.maxWidth -
                                (crossAxisCount - 1) * 16) /
                            crossAxisCount,
                        child: StatCard(
                          title: 'PŘESTUPNÍ UZLY',
                          value: '${state.totalTransfers}',
                          subtitle: 'aktivních vazeb',
                          icon: Icons.swap_horiz,
                          color: AppTheme.success,
                        ),
                      ),
                      SizedBox(
                        width: (constraints.maxWidth -
                                (crossAxisCount - 1) * 16) /
                            crossAxisCount,
                        child: StatCard(
                          title: 'GENEROVANÉ JÍZDY',
                          value: '${state.totalTrips}',
                          subtitle: state.isTimetableGenerated
                              ? 'jízdní řád vygenerován'
                              : 'čeká na generování',
                          icon: Icons.schedule_outlined,
                          color: state.isTimetableGenerated
                              ? AppTheme.success
                              : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),

              // Line overview and demands
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Lines summary
                  Expanded(
                    flex: 3,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceWhite,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Přehled linek',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          ...state.routes.map((route) => _RouteRow(route: route)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Demand chart placeholder
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceWhite,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Denní vytíženost',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: _DemandChart(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Vehicle status (if timetable generated)
              if (state.isTimetableGenerated && state.vehicles.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceWhite,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Stav vozidel',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: state.vehicles
                              .take(20)
                              .map((v) => _VehicleChip(vehicle: v))
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RouteRow extends StatelessWidget {
  final dynamic route;

  const _RouteRow({required this.route});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.borderLight)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: route.assignedBuses > 0
                  ? AppTheme.primary
                  : AppTheme.textMuted.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              route.route.routeShortName,
              style: TextStyle(
                color: route.assignedBuses > 0
                    ? Colors.white
                    : AppTheme.textMuted,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              route.route.routeLongName,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Text(
            '${route.assignedBuses} vozů',
            style: TextStyle(
              fontSize: 13,
              color: route.assignedBuses > 0
                  ? AppTheme.textPrimary
                  : AppTheme.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            route.assignedBuses > 0
                ? 'interval: ${route.intervalMinutes} min'
                : '--',
            style: TextStyle(
              fontSize: 12,
              color: route.assignedBuses > 0
                  ? AppTheme.textSecondary
                  : AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _DemandChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(24, (hour) {
          final demand = TimetableGenerator.demandMultipliers[hour] ?? 0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Tooltip(
                message: '${hour.toString().padLeft(2, '0')}:00 - ${(demand * 100).round()}%',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: 180 * demand,
                      decoration: BoxDecoration(
                        color: _getBarColor(demand),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (hour % 3 == 0)
                      Text(
                        hour.toString().padLeft(2, '0'),
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppTheme.textMuted,
                        ),
                      )
                    else
                      const SizedBox(height: 11),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Color _getBarColor(double demand) {
    if (demand >= 0.8) return AppTheme.danger.withValues(alpha: 0.7);
    if (demand >= 0.5) return AppTheme.warning.withValues(alpha: 0.6);
    return AppTheme.accent.withValues(alpha: 0.4);
  }
}

class _VehicleChip extends StatelessWidget {
  final dynamic vehicle;

  const _VehicleChip({required this.vehicle});

  @override
  Widget build(BuildContext context) {
    Color dotColor;
    switch (vehicle.status.toString()) {
      case 'VehicleStatus.inService':
        dotColor = const Color(0xFF68D391);
        break;
      case 'VehicleStatus.onBreak':
        dotColor = const Color(0xFFF6AD55);
        break;
      case 'VehicleStatus.outOfService':
        dotColor = const Color(0xFFFC8181);
        break;
      default:
        dotColor = const Color(0xFFA0AEC0);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            vehicle.id,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
            ),
          ),
          if (vehicle.delayMinutes > 0) ...[
            const SizedBox(width: 6),
            Text(
              '+${vehicle.delayMinutes}\'',
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
