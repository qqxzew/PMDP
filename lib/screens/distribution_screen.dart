import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

/// Screen for distributing timetables to drivers via WiFi
class DistributionScreen extends StatefulWidget {
  const DistributionScreen({super.key});

  @override
  State<DistributionScreen> createState() => _DistributionScreenState();
}

class _DistributionScreenState extends State<DistributionScreen> {
  String? _selectedDriverId;
  String? _selectedVehicleId;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        return Scaffold(
          backgroundColor: AppTheme.sidebarBg,
          body: Column(
            children: [
              // Platform warning banner
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'HTTP server funguje pouze na desktop platformách (Windows, Linux, macOS). Pro použití na webu nebo mobilu použijte jinou metodu distribuce.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Server status card
              _buildServerStatusCard(state),
              const SizedBox(height: 16),
              
              // Assignment section
              if (state.isTimetableGenerated) ...[
                _buildAssignmentSection(state),
                const SizedBox(height: 16),
              ],

              // Driver list
              Expanded(
                child: _buildDriverList(state),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildServerStatusCard(AppState state) {
    final isRunning = state.isServerRunning;
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2D3748),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRunning ? Colors.green : Colors.orange,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isRunning ? Icons.wifi : Icons.wifi_off,
                color: isRunning ? Colors.green : Colors.grey,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isRunning ? 'Server běží' : 'Server vypnut',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (isRunning && state.serverIpAddress != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'http://${state.serverIpAddress}:${state.serverPort}',
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 14,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _toggleServer(state),
                icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
                label: Text(isRunning ? 'Zastavit' : 'Spustit'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isRunning ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          if (isRunning && state.serverIpAddress != null) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white24),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Klienti se připojují na:',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        state.serverIpAddress!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _copyToClipboard(state.serverIpAddress!),
                  icon: const Icon(Icons.copy, color: Colors.white70),
                  tooltip: 'Kopírovat IP adresu',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAssignmentSection(AppState state) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2D3748),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Přiřadit jízdní řád',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedDriverId,
                  decoration: const InputDecoration(
                    labelText: 'Řidič',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue),
                    ),
                  ),
                  dropdownColor: AppTheme.sidebarBg,
                  style: const TextStyle(color: Colors.white),
                  items: state.drivers.map((driver) {
                    return DropdownMenuItem(
                      value: driver.id,
                      child: Text('${driver.id} - ${driver.name}'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedDriverId = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedVehicleId,
                  decoration: const InputDecoration(
                    labelText: 'Vůz / Směna',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue),
                    ),
                  ),
                  dropdownColor: AppTheme.sidebarBg,
                  style: const TextStyle(color: Colors.white),
                  items: state.vehicles.map((vehicle) {
                    return DropdownMenuItem(
                      value: vehicle.id,
                      child: Text(vehicle.name),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedVehicleId = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: (_selectedDriverId != null && _selectedVehicleId != null)
                    ? () => _assignTimetable(state)
                    : null,
                icon: const Icon(Icons.send),
                label: const Text('Přiřadit'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDriverList(AppState state) {
    if (state.drivers.isEmpty) {
      return const Center(
        child: Text(
          'Žádní řidiči',
          style: TextStyle(color: Colors.white54, fontSize: 16),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF2D3748),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: state.driverStatuses.length,
        separatorBuilder: (context, index) => const Divider(
          color: Colors.white12,
          height: 24,
        ),
        itemBuilder: (context, index) {
          final driverStatus = state.driverStatuses[index];
          final driver = driverStatus['driver'];
          final hasAssignment = driverStatus['has_assignment'] ?? false;
          final retrieved = driverStatus['retrieved'] ?? false;
          final assignedAt = driverStatus['assigned_at'];

          return Row(
            children: [
              // Status indicator
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: !hasAssignment
                      ? Colors.grey
                      : retrieved
                          ? Colors.green
                          : Colors.orange,
                ),
              ),
              const SizedBox(width: 16),
              
              // Driver info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driver['id'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      driver['name'],
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    if (hasAssignment && assignedAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Přiřazeno: ${_formatDateTime(assignedAt)}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: !hasAssignment
                      ? Colors.grey.withOpacity(0.2)
                      : retrieved
                          ? Colors.green.withOpacity(0.2)
                          : Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  !hasAssignment
                      ? 'Bez přiřazení'
                      : retrieved
                          ? 'Staženo'
                          : 'Čeká',
                  style: TextStyle(
                    color: !hasAssignment
                        ? Colors.grey
                        : retrieved
                            ? Colors.green
                            : Colors.orange,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _toggleServer(AppState state) async {
    if (state.isServerRunning) {
      await state.stopServer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server zastaven')),
        );
      }
    } else {
      final started = await state.startServer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              started 
                ? 'Server spuštěn' 
                : 'Chyba spuštění serveru - HTTP server funguje pouze na desktop platformách (Windows, Linux, macOS)',
            ),
            backgroundColor: started ? Colors.green : Colors.red,
            duration: started ? const Duration(seconds: 2) : const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _assignTimetable(AppState state) async {
    if (_selectedDriverId == null || _selectedVehicleId == null) return;

    final success = await state.assignTimetableToDriver(
      _selectedDriverId!,
      _selectedVehicleId!,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Jízdní řád přiřazen řidiči $_selectedDriverId'
                : 'Chyba přiřazení jízdního řádu',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );

      if (success) {
        setState(() {
          _selectedDriverId = null;
          _selectedVehicleId = null;
        });
      }
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('IP adresa zkopírována'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.day}.${dt.month}. ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }
}
