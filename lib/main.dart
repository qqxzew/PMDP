import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'theme/app_theme.dart';
import 'widgets/sidebar.dart';
import 'screens/dashboard_screen.dart';
import 'screens/lines_screen.dart';
import 'screens/transfers_screen.dart';
import 'screens/timetable_screen.dart';
import 'screens/vehicle_map_screen.dart';
import 'screens/messages_screen.dart';

void main() {
  runApp(const BlackoutDispatchApp());
}

class BlackoutDispatchApp extends StatelessWidget {
  const BlackoutDispatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..initialize(),
      child: MaterialApp(
        title: 'Dispečink - Nouzový režim',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        home: const AppShell(),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        if (state.isLoading) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Načítání dat...',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          body: Row(
            children: [
              AppSidebar(
                selectedIndex: _selectedIndex,
                onItemSelected: (index) =>
                    setState(() => _selectedIndex = index),
                unreadMessages: state.unreadCount,
              ),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: const BoxDecoration(
                        color: AppTheme.surfaceWhite,
                        border: Border(
                          bottom:
                              BorderSide(color: AppTheme.border, width: 1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _getPageTitle(),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          if (state.isTimetableGenerated)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.successLight,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: AppTheme.success,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'JR aktivní | ${state.totalTrips} jízd',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.success,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.warningLight,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.warning_amber_rounded,
                                      size: 14, color: AppTheme.warning),
                                  SizedBox(width: 4),
                                  Text(
                                    'JR nevygenerovaný',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.warning,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(width: 12),
                          Text(
                            _getCurrentTime(),
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _getScreen(),
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

  String _getPageTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Přehled';
      case 1:
        return 'Linky a vozy';
      case 2:
        return 'Přestupní uzly';
      case 3:
        return 'Jízdní řády';
      case 4:
        return 'Mapa vozů';
      case 5:
        return 'Zprávy';
      default:
        return '';
    }
  }

  Widget _getScreen() {
    switch (_selectedIndex) {
      case 0:
        return const DashboardScreen();
      case 1:
        return const LinesScreen();
      case 2:
        return const TransfersScreen();
      case 3:
        return const TimetableScreen();
      case 4:
        return const VehicleMapScreen();
      case 5:
        return const MessagesScreen();
      default:
        return const DashboardScreen();
    }
  }

  String _getCurrentTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}
