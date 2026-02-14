import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../services/timetable_generator.dart';

/// Obrazovka pro zobrazení směn řidičů s kontrolou 8hodinového limitu
class DriverShiftsScreen extends StatelessWidget {
  const DriverShiftsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        if (!state.isTimetableGenerated || state.vehicles.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.access_time, size: 64, color: AppTheme.textMuted),
                SizedBox(height: 16),
                Text(
                  'Žádné směny',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                ),
                SizedBox(height: 8),
                Text(
                  'Nejprve vygenerujte jízdní řády.',
                  style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                ),
              ],
            ),
          );
        }

        // Získat směny pro všechna vozidla
        final shifts = <_ShiftInfo>[];
        for (final vehicle in state.vehicles) {
          final jobs = state.getVehicleJobs(vehicle.id);
          if (jobs.isEmpty) continue;

          final scheduleInfo = state.checkVehicleRegulations(vehicle.id);
          
          // Určit začátek a konec směny
          DateTime? shiftStart;
          DateTime? shiftEnd;
          
          for (final job in jobs) {
            if (job.startTime != null) {
              if (shiftStart == null || job.startTime!.isBefore(shiftStart)) {
                shiftStart = job.startTime;
              }
            }
            if (job.endTime != null) {
              if (shiftEnd == null || job.endTime!.isAfter(shiftEnd)) {
                shiftEnd = job.endTime;
              }
            }
          }

          if (shiftStart != null && shiftEnd != null) {
            shifts.add(_ShiftInfo(
              vehicle: vehicle,
              vehicleId: vehicle.id,
              lineNumber: vehicle.currentLineNumber ?? '--',
              shiftStart: shiftStart,
              shiftEnd: shiftEnd,
              scheduleInfo: scheduleInfo,
            ));
          }
        }

        // Seřadit podle začátku směny
        shifts.sort((a, b) => a.shiftStart.compareTo(b.shiftStart));

        // Statistiky
        final totalShifts = shifts.length;
        final validShifts = shifts.where((s) => s.scheduleInfo.isValid).length;
        final invalidShifts = totalShifts - validShifts;
        final shiftsOver8h = shifts.where((s) => s.scheduleInfo.totalShiftMinutes > 480).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hlavička
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surfaceWhite,
                border: const Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Směny řidičů',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Přehled pracovních směn s kontrolou 8hodinového limitu',
                    style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  // Statistiky
                  Row(
                    children: [
                      _StatCard(
                        icon: Icons.people,
                        label: 'Celkem směn',
                        value: '$totalShifts',
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        icon: Icons.check_circle,
                        label: 'Platné (≤8h)',
                        value: '$validShifts',
                        color: AppTheme.success,
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        icon: Icons.warning,
                        label: 'Přesčasy (>8h)',
                        value: '$shiftsOver8h',
                        color: AppTheme.warning,
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        icon: Icons.error,
                        label: 'Neplatné',
                        value: '$invalidShifts',
                        color: AppTheme.danger,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Tabulka směn
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: shifts.length,
                itemBuilder: (context, index) {
                  final shift = shifts[index];
                  return _ShiftCard(shift: shift);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftCard extends StatelessWidget {
  final _ShiftInfo shift;

  const _ShiftCard({required this.shift});

  @override
  Widget build(BuildContext context) {
    final totalHours = (shift.scheduleInfo.totalShiftMinutes / 60).toStringAsFixed(1);
    final drivingHours = (shift.scheduleInfo.totalDrivingMinutes / 60).toStringAsFixed(1);
    final isOver8h = shift.scheduleInfo.totalShiftMinutes > 480;
    final isValid = shift.scheduleInfo.isValid;

    Color statusColor = AppTheme.success;
    IconData statusIcon = Icons.check_circle;
    String statusText = 'Platná směna';

    if (isOver8h) {
      statusColor = AppTheme.warning;
      statusIcon = Icons.warning;
      statusText = 'Přesčas (>8h)';
    }
    if (!isValid) {
      statusColor = AppTheme.danger;
      statusIcon = Icons.error;
      statusText = 'Neplatná směna';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Vozidlo
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  shift.vehicleId,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Linka
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Linka ${shift.lineNumber}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              // Status
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 14, color: statusColor),
                    const SizedBox(width: 6),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Časy
              Expanded(
                child: _InfoRow(
                  icon: Icons.access_time,
                  label: 'Začátek směny',
                  value: _formatTime(shift.shiftStart),
                ),
              ),
              Expanded(
                child: _InfoRow(
                  icon: Icons.access_time_filled,
                  label: 'Konec směny',
                  value: _formatTime(shift.shiftEnd),
                ),
              ),
              Expanded(
                child: _InfoRow(
                  icon: Icons.timer,
                  label: 'Celková doba',
                  value: '$totalHours h',
                  valueColor: isOver8h ? AppTheme.warning : AppTheme.textPrimary,
                ),
              ),
              Expanded(
                child: _InfoRow(
                  icon: Icons.directions_bus,
                  label: 'Jízda',
                  value: '$drivingHours h',
                ),
              ),
            ],
          ),
          // Реальний час роботи водія (з випадково згенерованої зміни)
          if (shift.vehicle.driverShift != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, size: 16, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    'Řidič ${shift.vehicle.driverShift!.driverId}:',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, size: 14, color: Colors.green),
                        const SizedBox(width: 4),
                        Text(
                          'Odpracováno: ${shift.vehicle.driverShift!.getFormattedWorked(DateTime.now())}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.schedule, size: 14, color: Colors.orange),
                        const SizedBox(width: 4),
                        Text(
                          'Zbývá: ${shift.vehicle.driverShift!.getFormattedRemaining(DateTime.now())}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Varování
          if (shift.scheduleInfo.warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: shift.scheduleInfo.warnings.map((w) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.warning, size: 14, color: AppTheme.warning),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            w,
                            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
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

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppTheme.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _ShiftInfo {
  final Vehicle vehicle;
  final String vehicleId;
  final String lineNumber;
  final DateTime shiftStart;
  final DateTime shiftEnd;
  final DriverScheduleInfo scheduleInfo;

  _ShiftInfo({
    required this.vehicle,
    required this.vehicleId,
    required this.lineNumber,
    required this.shiftStart,
    required this.shiftEnd,
    required this.scheduleInfo,
  });
}
