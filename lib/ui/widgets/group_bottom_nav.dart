//ui/widgets/group_bottom_nav.dart

import 'package:flutter/material.dart';

enum GroupNavItem { grid, timeline, calendar }

class GroupBottomNavigation extends StatelessWidget {
  final GroupNavItem active;
  final VoidCallback? onGrid;
  final VoidCallback? onTimeline;
  final VoidCallback? onCalendar;

  const GroupBottomNavigation({
    super.key,
    required this.active,
    this.onGrid,
    this.onTimeline,
    this.onCalendar,
  });

  void _handleTap(GroupNavItem item) {
    if (item == GroupNavItem.grid) {
      onGrid?.call();
    } else if (item == GroupNavItem.timeline) {
      onTimeline?.call();
    } else if (item == GroupNavItem.calendar) {
      onCalendar?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: BottomAppBar(
        color: colorScheme.surface,
        elevation: 4,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              _NavIconButton(
                label: 'グリッド',
                icon: active == GroupNavItem.grid
                    ? Icons.grid_view
                    : Icons.grid_view_outlined,
                active: active == GroupNavItem.grid,
                onPressed: active == GroupNavItem.grid
                    ? null
                    : () => _handleTap(GroupNavItem.grid),
              ),
              _NavIconButton(
                label: 'タイムライン',
                icon: active == GroupNavItem.timeline
                    ? Icons.view_timeline
                    : Icons.view_timeline_outlined,
                active: active == GroupNavItem.timeline,
                onPressed: active == GroupNavItem.timeline
                    ? null
                    : () => _handleTap(GroupNavItem.timeline),
              ),
              _NavIconButton(
                label: 'カレンダー',
                icon: active == GroupNavItem.calendar
                    ? Icons.calendar_month
                    : Icons.calendar_month_outlined,
                active: active == GroupNavItem.calendar,
                onPressed: active == GroupNavItem.calendar
                    ? null
                    : () => _handleTap(GroupNavItem.calendar),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavIconButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback? onPressed;

  const _NavIconButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = colorScheme.primary;
    final inactiveColor = colorScheme.onSurfaceVariant;

    return Expanded(
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: active ? activeColor : inactiveColor,
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? activeColor : inactiveColor),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: active ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}