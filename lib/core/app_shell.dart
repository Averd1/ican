import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';

class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  static const _tabs = <_TabDefinition>[
    _TabDefinition(
      label: 'Home',
      activeIcon: Icons.home,
      inactiveIcon: Icons.home_outlined,
    ),
    _TabDefinition(
      label: 'Settings',
      activeIcon: Icons.settings,
      inactiveIcon: Icons.settings_outlined,
    ),
    _TabDefinition(
      label: 'Help',
      activeIcon: Icons.help,
      inactiveIcon: Icons.help_outline,
    ),
  ];

  void _onTabTapped(int index) {
    HapticFeedback.selectionClick();
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentIndex = navigationShell.currentIndex;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Semantics(
        container: true,
        label: 'Main navigation. ${_tabs.length} tabs.',
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 72,
              child: Row(
                children: List.generate(_tabs.length, (index) {
                  final tab = _tabs[index];
                  final isActive = index == currentIndex;
                  return Expanded(
                    child: _AccessibleTab(
                      label: tab.label,
                      icon: isActive ? tab.activeIcon : tab.inactiveIcon,
                      isActive: isActive,
                      position: index + 1,
                      totalTabs: _tabs.length,
                      isDark: isDark,
                      onTap: () => _onTabTapped(index),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabDefinition {
  final String label;
  final IconData activeIcon;
  final IconData inactiveIcon;

  const _TabDefinition({
    required this.label,
    required this.activeIcon,
    required this.inactiveIcon,
  });
}

class _AccessibleTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final int position;
  final int totalTabs;
  final bool isDark;
  final VoidCallback onTap;

  const _AccessibleTab({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.position,
    required this.totalTabs,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // SemanticLabel: "[Tab name] tab. [N] of [total]."
    // plus selected state so VoiceOver/TalkBack announces "selected" automatically.
    final semanticLabel = '$label tab. $position of $totalTabs.';

    final activeColor = isDark
        ? AppColors.interactiveOnDark
        : AppColors.interactive;
    final inactiveColor = isDark
        ? AppColors.textSecondaryOnDark
        : AppColors.textSecondaryOnLight;
    final color = isActive ? activeColor : inactiveColor;

    return Semantics(
      button: true,
      selected: isActive,
      label: semanticLabel,
      hint: isActive ? 'Currently selected' : 'Double tap to switch to $label',
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon: 32dp as specified
              ExcludeSemantics(child: Icon(icon, size: 32, color: color)),
              const SizedBox(height: 4),
              // Text label: always visible, weight change on active
              ExcludeSemantics(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // Active underline indicator — never color alone
              ExcludeSemantics(
                child: Container(
                  height: 3,
                  width: 32,
                  decoration: BoxDecoration(
                    color: isActive ? activeColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(1.5),
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
