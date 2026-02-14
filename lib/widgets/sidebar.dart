import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Navigation sidebar widget
class AppSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final int unreadMessages;

  const AppSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    this.unreadMessages = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: AppTheme.sidebarBg,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFF6AD55),
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'NOUZOVÝ REŽIM',
                      style: TextStyle(
                        color: Color(0xFFF6AD55),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Text(
                  'Dispečink',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Dopravní podnik',
                  style: TextStyle(
                    color: AppTheme.sidebarText,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF2D3748), height: 1),
          const SizedBox(height: 8),
          // Navigation items
          _NavItem(
            icon: Icons.dashboard_outlined,
            label: 'Přehled',
            isSelected: selectedIndex == 0,
            onTap: () => onItemSelected(0),
          ),
          _NavItem(
            icon: Icons.route_outlined,
            label: 'Linky a vozy',
            isSelected: selectedIndex == 1,
            onTap: () => onItemSelected(1),
          ),
          _NavItem(
            icon: Icons.swap_horiz,
            label: 'Přestupní uzly',
            isSelected: selectedIndex == 2,
            onTap: () => onItemSelected(2),
          ),
          _NavItem(
            icon: Icons.schedule_outlined,
            label: 'Jízdní řády',
            isSelected: selectedIndex == 3,
            onTap: () => onItemSelected(3),
          ),
          _NavItem(
            icon: Icons.share_outlined,
            label: 'Distribuce řidičům',
            isSelected: selectedIndex == 4,
            onTap: () => onItemSelected(4),
          ),
          _NavItem(
            icon: Icons.access_time,
            label: 'Směny řidičů',
            isSelected: selectedIndex == 5,
            onTap: () => onItemSelected(5),
          ),
          _NavItem(
            icon: Icons.map_outlined,
            label: 'Mapa vozů',
            isSelected: selectedIndex == 6,
            onTap: () => onItemSelected(6),
          ),
          _NavItem(
            icon: Icons.message_outlined,
            label: 'Zprávy',
            isSelected: selectedIndex == 7,
            onTap: () => onItemSelected(7),
            badge: unreadMessages > 0 ? unreadMessages : null,
          ),
          const Spacer(),
          const Divider(color: Color(0xFF2D3748), height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF68D391),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Systém aktivní',
                  style: TextStyle(
                    color: AppTheme.sidebarText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final int? badge;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.sidebarActive.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? Colors.white : const Color(0xFFA0AEC0),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFFA0AEC0),
                    fontSize: 14,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.danger,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
