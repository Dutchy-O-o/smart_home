import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../providers/navigation_provider.dart';
import '../providers/network_status_provider.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/ai_hub/ai_tab_screen.dart';
import '../screens/automations/automations_list_screen.dart';
import '../screens/devices/device_control_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

/// Top-level shell with the bottom nav and PageView so users can swipe
/// horizontally between tabs (with smooth animation when tapping the nav).
/// Each page is wrapped with KeepAlive so scroll position survives.
///
/// Slimmed to 5 tabs (was 7): Emotion + AI Chat moved into a single AI tab
/// with a top segmented control, and Notifications moved to a header bell
/// inside the dashboard.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  static const _items = <_NavItem>[
    _NavItem(Icons.grid_view_rounded, Icons.grid_view, 'Home'),
    _NavItem(Icons.psychology_alt_rounded, Icons.psychology_alt_outlined, 'AI'),
    _NavItem(Icons.auto_awesome_rounded, Icons.auto_awesome_outlined, 'Auto'),
    _NavItem(Icons.devices_rounded, Icons.devices_other, 'Devices'),
    _NavItem(Icons.person_rounded, Icons.person_outline, 'Profile'),
  ];

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: ref.read(tabIndexProvider));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(tabIndexProvider);

    // Drain the retry queue automatically whenever the network flips
    // back to "online" — screens that registered a callback after a
    // failed fetch get re-run without the user having to pull-to-refresh.
    wireRetryQueueToConnectivity(ref);

    // External tab change (e.g. dashboard "Mood" button) — animate to it.
    ref.listen<int>(tabIndexProvider, (prev, next) {
      if (!_pageController.hasClients) return;
      final page = _pageController.page?.round();
      if (page != next) {
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 280),
          curve: AppMotion.standard,
        );
      }
    });

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            physics: const ClampingScrollPhysics(),
            onPageChanged: (i) {
              if (i != ref.read(tabIndexProvider)) {
                HapticFeedback.selectionClick();
                ref.read(tabIndexProvider.notifier).setTab(i);
              }
            },
            children: const [
              _KeepAlive(child: DashboardScreen()),       // 0
              _KeepAlive(child: AiTabScreen()),           // 1 (Emotion + Chat sub-tabs)
              _KeepAlive(child: AutomationsListScreen()), // 2
              _KeepAlive(child: DeviceControlScreen()),   // 3
              _KeepAlive(child: ProfileScreen()),         // 4
            ],
          ),
          // Top-of-screen offline banner. Overlays content so it doesn't
          // shrink the PageView height and trigger relayouts.
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(child: _ConnectivityBanner()),
          ),
        ],
      ),
      bottomNavigationBar: _ModernNavBar(
        items: MainShell._items,
        currentIndex: currentIndex,
        onTap: (i) {
          if (i != currentIndex) HapticFeedback.selectionClick();
          ref.read(tabIndexProvider.notifier).setTab(i);
        },
      ),
    );
  }
}

/// Keeps a page alive in the PageView so it doesn't rebuild when swiped
/// off-screen — critical for the dashboard's polling timers and AI chat
/// history to survive between tabs.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;
  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _NavItem {
  const _NavItem(this.activeIcon, this.icon, this.label);
  final IconData activeIcon;
  final IconData icon;
  final String label;
}

/// Slim banner that slides down from the top of MainShell when the
/// AWS API becomes unreachable, and slides back out the moment a
/// request succeeds again. Subscribes to [networkStatusProvider] so
/// it reflects the same flag the API service maintains internally —
/// no separate connectivity poll.
class _ConnectivityBanner extends ConsumerWidget {
  const _ConnectivityBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(isOfflineProvider);
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: !offline
          ? const SizedBox(width: double.infinity)
          : Material(
              color: AppColors.accentRed.withValues(alpha: 0.94),
              elevation: 6,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                child: Row(
                  children: const [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No connection — retrying…',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
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

/// Frosted, floating bottom navigation with a sliding gradient pill
/// underneath the active tab. The pill animates between slots and the
/// label fades in as it lands — same idiom used by Linear / Arc /
/// Vercel mobile dashboards.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navColor =
        AppColors.navBar(context).withValues(alpha: isDark ? 0.78 : 0.86);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: ClipRRect(
          borderRadius: AppRadius.brXl,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 70,
              decoration: BoxDecoration(
                color: navColor,
                borderRadius: AppRadius.brXl,
                border: Border.all(
                  color: AppColors.borderCol(context).withValues(alpha: 0.6),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: AppColors.primaryBlue
                        .withValues(alpha: isDark ? 0.18 : 0.10),
                    blurRadius: 28,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, c) {
                  final slotWidth = c.maxWidth / items.length;
                  return Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // Sliding gradient pill — the visual anchor.
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 360),
                        curve: Curves.easeOutCubic,
                        left: slotWidth * currentIndex + 8,
                        top: 8,
                        bottom: 8,
                        width: slotWidth - 16,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: AppColors.brandGradient,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryBlue
                                    .withValues(alpha: 0.45),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Tap targets / labels live above the pill.
                      Row(
                        children: List.generate(items.length, (i) {
                          final selected = currentIndex == i;
                          final item = items[i];
                          return Expanded(
                            child: _NavBtn(
                              icon: selected ? item.activeIcon : item.icon,
                              label: item.label,
                              selected: selected,
                              onTap: () => onTap(i),
                            ),
                          );
                        }),
                      ),
                    ],
                  );
                },
              ),
            ),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: Colors.white.withValues(alpha: 0.10),
        highlightColor: Colors.transparent,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: selected
              ? Column(
                  key: const ValueKey('on'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 22, color: Colors.white),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                )
              : Center(
                  key: const ValueKey('off'),
                  child: Icon(
                    icon,
                    size: 22,
                    color: AppColors.textSub(context),
                  ),
                ),
        ),
      ),
    );
  }
}
