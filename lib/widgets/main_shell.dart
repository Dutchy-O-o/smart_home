import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../providers/navigation_provider.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/ai_hub/ai_tab_screen.dart';
import '../screens/automations/automations_list_screen.dart';
import '../screens/devices/device_control_screen.dart';
import '../screens/profile/profile_screen.dart';

/// Top-level shell with the bottom nav and per-tab IndexedStack so each
/// tab keeps its scroll position when the user comes back to it.
///
/// Slimmed to 5 tabs (was 7): Emotion + AI Chat moved into a single AI tab
/// with a top segmented control, and Notifications moved to a header bell
/// inside the dashboard.
class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  static const _items = <_NavItem>[
    _NavItem(Icons.grid_view_rounded, Icons.grid_view, 'Home'),
    _NavItem(Icons.psychology_alt_rounded, Icons.psychology_alt_outlined, 'AI'),
    _NavItem(Icons.auto_awesome_rounded, Icons.auto_awesome_outlined, 'Auto'),
    _NavItem(Icons.devices_rounded, Icons.devices_other, 'Devices'),
    _NavItem(Icons.person_rounded, Icons.person_outline, 'Profile'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(tabIndexProvider);

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: currentIndex,
        children: const [
          DashboardScreen(),       // 0
          AiTabScreen(),           // 1 (Emotion + Chat sub-tabs)
          AutomationsListScreen(), // 2
          DeviceControlScreen(),   // 3
          ProfileScreen(),         // 4
        ],
      ),
      bottomNavigationBar: _ModernNavBar(
        items: _items,
        currentIndex: currentIndex,
        onTap: (i) => ref.read(tabIndexProvider.notifier).setTab(i),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.activeIcon, this.icon, this.label);
  final IconData activeIcon;
  final IconData icon;
  final String label;
}

class _ModernNavBar extends StatelessWidget {
  const _ModernNavBar({
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<_NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final navColor = AppColors.navBar(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            color: navColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.borderCol(context).withValues(alpha: 0.6),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final selected = currentIndex == i;
              final item = items[i];
              return _NavBtn(
                icon: selected ? item.activeIcon : item.icon,
                label: item.label,
                selected: selected,
                onTap: () => onTap(i),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: AppColors.primaryBlue.withValues(alpha: 0.15),
        highlightColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2196F3), Color(0xFF00BFA5)],
                  )
                : null,
            borderRadius: BorderRadius.circular(16),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.45),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? Colors.white : AppColors.textSub(context),
              ),
              if (selected) ...[
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
