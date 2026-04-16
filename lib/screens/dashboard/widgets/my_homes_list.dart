import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';

/// Horizontal scrolling list of the user's homes shown on the dashboard.
/// Each card displays the home name and the user's role (admin/guest)
/// with role-appropriate accent color and icon.
class MyHomesList extends StatelessWidget {
  const MyHomesList({
    super.key,
    required this.homes,
    required this.isLoading,
    required this.errorMessage,
  });

  final List<dynamic> homes;
  final bool isLoading;
  final String errorMessage;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      );
    }
    if (errorMessage.isNotEmpty) {
      return Text(errorMessage,
          style: const TextStyle(color: AppColors.accentRed));
    }
    if (homes.isEmpty) {
      return Text('No homes found.',
          style: TextStyle(color: AppColors.textSub(context)));
    }

    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: homes.length,
        itemBuilder: (context, index) =>
            _HomeCard(home: homes[index], index: index),
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({required this.home, required this.index});

  final dynamic home;
  final int index;

  @override
  Widget build(BuildContext context) {
    final role = home['role'] ?? 'Unknown Role';
    final isGuest = role.toString().toLowerCase() == 'guest';
    final accent =
        isGuest ? AppColors.accentOrange : AppColors.primaryBlue;

    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(
                isGuest
                    ? Icons.vpn_key_outlined
                    : Icons.admin_panel_settings,
                color: accent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  home['home_name'] ?? 'Home $index',
                  style: TextStyle(
                    color: AppColors.text(context),
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              role.toString().toUpperCase(),
              style: TextStyle(
                color: accent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
