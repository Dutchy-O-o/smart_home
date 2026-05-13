import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_colors.dart';
import '../../providers/navigation_provider.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import '../ai_agent/ai_chat_screen.dart';
import 'emotion_hub_screen.dart';

/// Combines the two AI surfaces (Emotion Hub + Chat Assistant) under one
/// bottom-nav tab with a segmented top control. Driven by [aiSubTabProvider]
/// so other screens (e.g. dashboard "Mood" scene) can deep-link to a specific
/// sub-tab.
class AiTabScreen extends ConsumerStatefulWidget {
  const AiTabScreen({super.key});

  @override
  ConsumerState<AiTabScreen> createState() => _AiTabScreenState();
}

class _AiTabScreenState extends ConsumerState<AiTabScreen> {
  @override
  Widget build(BuildContext context) {
    final sub = ref.watch(aiSubTabProvider);
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _AiSegmented(
              selected: sub,
              onChanged: (i) {
                if (i != sub) HapticFeedback.selectionClick();
                ref.read(aiSubTabProvider.notifier).setTab(i);
              },
            ),
            Expanded(
              child: IndexedStack(
                index: sub,
                children: const [
                  EmotionHubScreen(),
                  AiChatScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiSegmented extends StatelessWidget {
  const _AiSegmented({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 14, AppSpacing.xl, 6),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: AppRadius.brSm,
          border: Border.all(color: AppColors.borderCol(context)),
        ),
        child: Row(
          children: [
            _SegBtn(
              label: 'Emotion',
              icon: Icons.sentiment_satisfied_alt,
              active: selected == 0,
              onTap: () => onChanged(0),
            ),
            _SegBtn(
              label: 'Assistant',
              icon: Icons.smart_toy,
              active: selected == 1,
              onTap: () => onChanged(1),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegBtn extends StatelessWidget {
  const _SegBtn({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: AppMotion.standard,
          height: 42,
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: AppColors.brandGradient,
                  )
                : null,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.40),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: active ? Colors.white : AppColors.textSub(context),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : AppColors.textSub(context),
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
