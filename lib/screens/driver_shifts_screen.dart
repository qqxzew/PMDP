// Driver Shifts Screen - Gantt Chart visualization with 8-hour shift splitting

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/driver_shift_models.dart';

/// Driver Shifts Screen with Gantt Chart timeline
class DriverShiftsScreen extends StatefulWidget {
  const DriverShiftsScreen({super.key});

  @override
  State<DriverShiftsScreen> createState() => _DriverShiftsScreenState();
}

class _DriverShiftsScreenState extends State<DriverShiftsScreen> {
  String? selectedShiftId;
  
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        if (!state.isTimetableGenerated || state.vehicleShiftSchedules.isEmpty) {
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

        final schedules = state.vehicleShiftSchedules;
        final drivers = state.driverWorkloads;
        
        // Find selected shift if any
        DriverShift? selectedShift;
        VehicleShiftSchedule? selectedVehicleSchedule;
        if (selectedShiftId != null) {
          for (final schedule in schedules) {
            final shift = schedule.shifts.firstWhere(
              (s) => s.shiftId == selectedShiftId,
              orElse: () => schedule.shifts.first,
            );
            if (shift.shiftId == selectedShiftId) {
              selectedShift = shift;
              selectedVehicleSchedule = schedule;
              break;
            }
          }
        }
        
        return Row(
          children: [
            // Main Gantt Chart Area
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(schedules, drivers),
                  const SizedBox(height: 16),
                  _buildTimeAxis(),
                  Expanded(
                    child: _buildGanttChart(schedules),
                  ),
                ],
              ),
            ),
            
            // Right Sidebar - Driver list or Shift details
            Container(
              width: 300,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border(left: BorderSide(color: AppTheme.border)),
              ),
              child: selectedShift != null
                  ? _buildShiftDetails(selectedShift, selectedVehicleSchedule!, state)
                  : _buildDriverSidebar(drivers),
            ),
          ],
        );
      },
    );
  }
  
  /// Header with statistics
  Widget _buildHeader(List<VehicleShiftSchedule> schedules, List<DriverWorkload> drivers) {
    final totalShifts = schedules.fold<int>(0, (sum, s) => sum + s.shifts.length);
    final overtimeShifts = schedules.fold<int>(0, (sum, s) => sum + s.shifts.where((sh) => sh.isOvertime).length);
    final totalDrivers = schedules.fold<Set<String>>({}, (set, s) {
      for (var shift in s.shifts) {
        set.add(shift.driverId);
      }
      return set;
    }).length;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          _StatBox(
            label: 'Vozidla',
            value: schedules.length.toString(),
            icon: Icons.directions_bus,
            color: Colors.blue,
          ),
          const SizedBox(width: 16),
          _StatBox(
            label: 'Směny',
            value: totalShifts.toString(),
            icon: Icons.schedule,
            color: Colors.green,
          ),
          const SizedBox(width: 16),
          _StatBox(
            label: 'Řidiči',
            value: totalDrivers.toString(),
            icon: Icons.person,
            color: Colors.purple,
          ),
          const SizedBox(width: 16),
          _StatBox(
            label: 'Přesčasy',
            value: overtimeShifts.toString(),
            icon: Icons.warning,
            color: overtimeShifts > 0 ? Colors.red : Colors.green,
          ),
        ],
      ),
    );
  }
  
  /// Time axis (0-24 hours)
  Widget _buildTimeAxis() {
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 120),
      child: Row(
        children: List.generate(25, (hour) {
          return Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: hour % 6 == 0 ? AppTheme.border : AppTheme.border.withValues(alpha: 0.3),
                    width: hour % 6 == 0 ? 2 : 1,
                  ),
                ),
              ),
              child: hour % 3 == 0
                  ? Padding(
                      padding: const EdgeInsets.only(left: 4, top: 8),
                      child: Text(
                        '${hour.toString().padLeft(2, '0')}:00',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                          fontWeight: hour % 6 == 0 ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    )
                  : const SizedBox(),
            ),
          );
        }),
      ),
    );
  }
  
  /// Gantt Chart with vehicle rows and shift blocks
  Widget _buildGanttChart(List<VehicleShiftSchedule> schedules) {
    return ListView.builder(
      itemCount: schedules.length,
      itemBuilder: (context, index) {
        final schedule = schedules[index];
        return _VehicleRow(
          schedule: schedule,
          selectedShiftId: selectedShiftId,
          onShiftTap: (shiftId) {
            setState(() {
              selectedShiftId = selectedShiftId == shiftId ? null : shiftId;
            });
          },
        );
      },
    );
  }
  
  /// Driver sidebar with workload list
  Widget _buildDriverSidebar(List<DriverWorkload> drivers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.border)),
          ),
          child: const Row(
            children: [
              Icon(Icons.people, size: 20, color: AppTheme.textPrimary),
              SizedBox(width: 8),
              Text(
                'Řidiči',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: drivers.length,
            itemBuilder: (context, index) {
              final driver = drivers[index];
              return _DriverListItem(driver: driver);
            },
          ),
        ),
      ],
    );
  }
  
  /// Shift details panel (shown when shift is selected)
  Widget _buildShiftDetails(DriverShift shift, VehicleShiftSchedule schedule, AppState state) {
    final isOvertime = shift.isOvertime;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isOvertime ? Colors.red.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1),
            border: Border(bottom: BorderSide(color: AppTheme.border)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  setState(() {
                    selectedShiftId = null;
                  });
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Směna ${shift.driverId}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isOvertime ? Colors.red : Colors.blue,
                      ),
                    ),
                    Text(
                      'Vůz ${shift.vehicleId}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // Shift info
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ShiftInfoRow(
                icon: Icons.access_time,
                label: 'Začátek',
                value: _formatTime(shift.startTime),
              ),
              const SizedBox(height: 12),
              _ShiftInfoRow(
                icon: Icons.access_time_filled,
                label: 'Konec',
                value: _formatTime(shift.endTime),
              ),
              const SizedBox(height: 12),
              _ShiftInfoRow(
                icon: Icons.timer,
                label: 'Doba trvání',
                value: shift.formattedDuration,
                valueColor: isOvertime ? Colors.red : AppTheme.textPrimary,
              ),
              const SizedBox(height: 12),
              _ShiftInfoRow(
                icon: Icons.work,
                label: 'Pracovní doba',
                value: shift.formattedWorkingTime,
                valueColor: isOvertime ? Colors.red : Colors.green,
              ),
              if (shift.breaks.isNotEmpty) ...[
                const SizedBox(height: 12),
                _ShiftInfoRow(
                  icon: Icons.coffee,
                  label: 'Pauzy',
                  value: '${shift.breaks.length}x (${shift.breakMinutes} min)',
                  valueColor: Colors.green,
                ),
              ],
              const SizedBox(height: 12),
              _ShiftInfoRow(
                icon: Icons.route,
                label: 'Počet jízd',
                value: shift.jobs.length.toString(),
              ),
              
              if (isOvertime) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Směna překračuje limit 8 hodin',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      // Fix the overtime shift
                      await _fixOvertimeShift(state, schedule.vehicleId);
                    },
                    icon: const Icon(Icons.build, size: 18),
                    label: const Text('Opravit směnu'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Přegeneruje rozvrh s malými prodlevami mezi jízdami, aby směna nepřekračovala 8 hodin.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),
              const Text(
                'Jízdy v této směně',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              
              // List of jobs
              ...shift.jobs.asMap().entries.map((entry) {
                final idx = entry.key;
                final job = entry.value;
                final startStop = job.stops.isNotEmpty ? job.stops.first.name : 'Unknown';
                final endStop = job.stops.isNotEmpty ? job.stops.last.name : 'Unknown';
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              job.lineNumber,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$startStop → $endStop',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_formatTime(job.startTime!)} → ${_formatTime(job.endTime!)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
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
  
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
  
  Future<void> _fixOvertimeShift(AppState state, String vehicleId) async {
    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Opravování směny...'),
              ],
            ),
          ),
        ),
      ),
    );
    
    try {
      await state.fixVehicleOvertimeShift(vehicleId);
      
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      
      setState(() {
        selectedShiftId = null; // Deselect shift
      });
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Směna byla úspěšně opravena'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Chyba při opravě: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

/// Shift info row widget
class _ShiftInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  
  const _ShiftInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });
  
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Stat box widget
class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  
  const _StatBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Vehicle row in Gantt chart
class _VehicleRow extends StatelessWidget {
  final VehicleShiftSchedule schedule;
  final String? selectedShiftId;
  final Function(String) onShiftTap;
  
  const _VehicleRow({
    required this.schedule,
    required this.selectedShiftId,
    required this.onShiftTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          // Vehicle ID label
          Container(
            width: 120,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.directions_bus, size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Vůz ${schedule.vehicleId}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          
          // Timeline with shift blocks
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    // Background grid
                    Row(
                      children: List.generate(24, (hour) {
                        return Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: AppTheme.border.withValues(alpha: hour % 6 == 0 ? 0.5 : 0.15),
                                  width: hour % 6 == 0 ? 2 : 1,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    
                    // Shift blocks
                    ...schedule.shifts.map((shift) => _ShiftBlock(
                      shift: shift,
                      isSelected: selectedShiftId == shift.shiftId,
                      onTap: () => onShiftTap(shift.shiftId),
                      availableWidth: constraints.maxWidth,
                    )),
                    
                    // Break blocks (driver rest periods)
                    ...schedule.shifts.expand((shift) => 
                      shift.breaks.map((breakInfo) => _BreakBlock(
                        breakInfo: breakInfo,
                        availableWidth: constraints.maxWidth,
                      ))
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Shift block widget (colored rectangle)
class _ShiftBlock extends StatelessWidget {
  final DriverShift shift;
  final bool isSelected;
  final VoidCallback onTap;
  final double availableWidth;
  
  const _ShiftBlock({
    required this.shift,
    required this.isSelected,
    required this.onTap,
    required this.availableWidth,
  });
  
  @override
  Widget build(BuildContext context) {
    // Calculate position and width based on time
    final baseTime = DateTime(shift.startTime.year, shift.startTime.month, shift.startTime.day);
    final startOffset = shift.startTime.difference(baseTime).inMinutes / (24 * 60);
    final duration = shift.durationMinutes / (24 * 60);
    
    final color = shift.isOvertime ? Colors.red : Colors.blue;
    
    return Positioned(
      left: startOffset * availableWidth,
      width: duration * availableWidth,
      top: 8,
      bottom: 8,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isSelected ? 0.9 : 0.7),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? color : Colors.transparent,
                width: 2,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 4, spreadRadius: 1)]
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  shift.driverId,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  shift.formattedDuration,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Driver list item in sidebar
class _DriverListItem extends StatelessWidget {
  final DriverWorkload driver;
  
  const _DriverListItem({required this.driver});
  
  @override
  Widget build(BuildContext context) {
    final isOverloaded = driver.isOverloaded;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border.withValues(alpha: 0.3))),
        color: isOverloaded ? Colors.red.withValues(alpha: 0.05) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.person,
                size: 16,
                color: isOverloaded ? Colors.red : AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  driver.driverId,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isOverloaded ? Colors.red : AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.access_time,
                size: 12,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                '${driver.formattedWorkload} / 8h',
                style: TextStyle(
                  fontSize: 11,
                  color: isOverloaded ? Colors.red : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (driver.totalMinutes / 480).clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: isOverloaded ? Colors.red : Colors.blue,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Break block widget (driver rest period - green rectangle)
class _BreakBlock extends StatelessWidget {
  final DriverBreak breakInfo;
  final double availableWidth;
  
  const _BreakBlock({
    required this.breakInfo,
    required this.availableWidth,
  });
  
  @override
  Widget build(BuildContext context) {
    // Calculate position and width based on time
    final baseTime = DateTime(
      breakInfo.startTime.year,
      breakInfo.startTime.month,
      breakInfo.startTime.day,
    );
    final startOffset = breakInfo.startTime.difference(baseTime).inMinutes / (24 * 60);
    final duration = breakInfo.durationMinutes / (24 * 60);
    
    return Positioned(
      left: startOffset * availableWidth,
      width: duration * availableWidth,
      top: 12,
      bottom: 12,
      child: Tooltip(
        message: '${breakInfo.isContinuous ? "30-minutová" : "10-minutová"} pauza\n${breakInfo.stopName ?? ""}',
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: Colors.green,
              width: 1,
            ),
          ),
          child: Center(
            child: Icon(
              Icons.coffee,
              size: 12,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
