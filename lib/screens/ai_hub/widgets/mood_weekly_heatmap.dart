import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';
import '../../../constants/mood_palette.dart';
import '../../../services/mood_history_service.dart';

/// 7×24 grid showing the dominant mood per hour over the last week. Each
/// cell is colored by mood (using [MoodPalette.colorFor]); empty cells
/// fall back to a faint border so the grid is still legible.
///
/// The chart is rebuilt every time the parent passes a new [grid] (e.g.
/// after a fresh scan), so callers should hold the grid in state.
class MoodWeeklyHeatmap extends StatelessWidget {
  const MoodWeeklyHeatmap({super.key, required this.grid});

  /// Same shape as [MoodHistoryService.weeklyGrid] — outer key is days
  /// ago (0 = today, 6 = 7 days ago), inner key is hour (0–23) → mood.
  final Map<int, Map<int, String>> grid;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderCol(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_view_week,
                  color: AppColors.textSub(context), size: 16),
              const SizedBox(width: 8),
              Text(
                'Mood — last 7 days',
                style: TextStyle(
                  color: AppColors.text(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              Text(
                _samplesLabel(grid),
                style: TextStyle(
                  color: AppColors.textSub(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isEmpty(grid))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.auto_graph,
                        color: AppColors.primaryBlue, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No data yet',
                          style: TextStyle(
                            color: AppColors.text(context),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tap "Scan" up top to log your first mood — once you have a few entries, this grid fills with one cell per hour.',
                          style: TextStyle(
                            color: AppColors.textSub(context),
                            fontSize: 11.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else ...[
            _grid(context),
            const SizedBox(height: 10),
            _hourAxis(context),
            const SizedBox(height: 12),
            _legend(context),
          ],
        ],
      ),
    );
  }

  Widget _grid(BuildContext context) {
    return Column(
      children: List.generate(7, (rowIdx) {
        // rowIdx 0 = 6 days ago, 6 = today (top→bottom = oldest→newest).
        final dayOffset = 6 - rowIdx;
        final dayLabel = _dayLabel(dayOffset);
        final hours = grid[dayOffset] ?? const <int, String>{};

        final weekday = _weekdayShort(dayOffset);
        return Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            children: [
              SizedBox(
                width: 42,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dayLabel,
                      style: TextStyle(
                        color: dayOffset == 0
                            ? AppColors.primaryBlue
                            : AppColors.textSub(context),
                        fontSize: 10,
                        fontWeight:
                            dayOffset == 0 ? FontWeight.w800 : FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    if (dayOffset <= 1)
                      Text(
                        weekday,
                        style: TextStyle(
                          color: AppColors.textSub(context)
                              .withValues(alpha: 0.7),
                          fontSize: 8,
                          fontWeight: FontWeight.w500,
                          height: 1.0,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    const gap = 2.0;
                    final cellW = (constraints.maxWidth - 23 * gap) / 24;
                    return Row(
                      children: List.generate(24, (hour) {
                        final mood = hours[hour];
                        return Padding(
                          padding: EdgeInsets.only(
                              right: hour == 23 ? 0 : gap),
                          child: _Cell(
                            width: cellW,
                            mood: mood,
                            isCurrentHour:
                                dayOffset == 0 && hour == DateTime.now().hour,
                          ),
                        );
                      }),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _hourAxis(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 46),
      child: Row(
        children: [
          for (final h in const [0, 6, 12, 18])
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${h.toString().padLeft(2, '0')}:00',
                  style: TextStyle(
                    color: AppColors.textSub(context),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context) {
    final moods = ['happy', 'neutral', 'sad', 'angry', 'surprise', 'fear'];
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: moods.map((m) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: MoodPalette.colorFor(m),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              m,
              style: TextStyle(
                color: AppColors.textSub(context),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  bool _isEmpty(Map<int, Map<int, String>> g) {
    if (g.isEmpty) return true;
    return g.values.every((m) => m.isEmpty);
  }

  String _samplesLabel(Map<int, Map<int, String>> g) {
    final n = g.values.fold<int>(0, (sum, m) => sum + m.length);
    if (n == 0) return 'no data yet';
    return '$n hour${n == 1 ? '' : 's'} logged';
  }

  String _dayLabel(int offset) {
    if (offset == 0) return 'Today';
    if (offset == 1) return 'Yest';
    return _weekdayShort(offset);
  }

  String _weekdayShort(int offset) {
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final d = DateTime.now().subtract(Duration(days: offset));
    return wd[d.weekday - 1];
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.width,
    required this.mood,
    required this.isCurrentHour,
  });

  final double width;
  final String? mood;
  final bool isCurrentHour;

  @override
  Widget build(BuildContext context) {
    final color = mood == null
        ? AppColors.borderCol(context).withValues(alpha: 0.4)
        : MoodPalette.colorFor(mood!);
    return Container(
      width: width,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
        border: isCurrentHour
            ? Border.all(color: AppColors.text(context), width: 1.2)
            : null,
      ),
    );
  }
}
