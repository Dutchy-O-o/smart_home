import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';

/// LED color picker shared by Device Control and Automation Create.
///
/// Design intent: a hard rainbow gradient at full saturation reads as
/// neon/eye-strain, but a fixed swatch grid feels constrained. This widget
/// combines both:
///
///   1. A row of 10 curated pastel swatches — instant, calm, "good enough"
///      for ~80% of cases.
///   2. A continuous hue strip below at 65% saturation / 95% value, so
///      scrubbing still gives you any color you want, just softened. No
///      glaring neon.
///   3. A white pill on the right for daylight mode.
///
/// All three controls write through the same `onChanged` callback as a
/// `#RRGGBB` hex so the rest of the app (which already stores colors as
/// hex strings in device state + automation actions) stays unchanged.
class LedColorPicker extends StatelessWidget {
  const LedColorPicker({
    super.key,
    required this.currentHex,
    required this.onChanged,
  });

  /// Current color as a "#RRGGBB" hex string. White if RGB are equal.
  final String currentHex;

  /// Fired with a new "#RRGGBB" hex whenever the user picks a color via
  /// swatch tap, strip drag, or the white pill.
  final ValueChanged<String> onChanged;

  /// Pastel quick-pick palette. Saturation matches the strip (S≈0.65)
  /// so a tap on a swatch lands at roughly the same look as picking that
  /// hue on the strip — no jarring brightness shift between the two
  /// inputs.
  static const List<Color> _quickPalette = [
    Color(0xFFF87171), // soft red
    Color(0xFFFB923C), // warm orange
    Color(0xFFFBBF24), // golden
    Color(0xFFA3E635), // lime
    Color(0xFF4ADE80), // mint
    Color(0xFF2DD4BF), // teal
    Color(0xFF60A5FA), // sky blue
    Color(0xFF818CF8), // indigo
    Color(0xFFA78BFA), // lavender
    Color(0xFFE879F9), // pink-violet
  ];

  @override
  Widget build(BuildContext context) {
    final selected = _parseHex(currentHex);
    final isWhite = _isGrayscale(selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quick-pick swatch row — single horizontal scroll so it works on
        // narrow screens without wrapping into a multi-row mess.
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _quickPalette.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = _quickPalette[i];
              final isSelected = !isWhite && _isClose(c, selected);
              return _QuickSwatch(
                color: c,
                selected: isSelected,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(_hexFromColor(c));
                },
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        // Soft hue strip + W pill.
        _SoftHueStrip(
          currentHex: currentHex,
          onChanged: (hex) {
            HapticFeedback.selectionClick();
            onChanged(hex);
          },
        ),
      ],
    );
  }

  // ── helpers ─────────────────────────────────────────────────────────

  static Color _parseHex(String hex) {
    final h = hex.replaceAll('#', '');
    if (h.length != 6) return Colors.white;
    final v = int.tryParse(h, radix: 16);
    if (v == null) return Colors.white;
    return Color(0xFF000000 | v);
  }

  static String _hexFromColor(Color c) {
    final argb = c.toARGB32();
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    String two(int n) => n.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '#${two(r)}${two(g)}${two(b)}';
  }

  static bool _isGrayscale(Color c) {
    final argb = c.toARGB32();
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    return r == g && g == b;
  }

  /// Manhattan distance — close enough to call "the same swatch" for the
  /// purposes of highlighting which swatch you just picked. Generous
  /// threshold (24) so a strip-scrubbed approximation still lights up
  /// the nearest swatch.
  static bool _isClose(Color a, Color b) {
    final aa = a.toARGB32();
    final bb = b.toARGB32();
    int dr = ((aa >> 16) & 0xFF) - ((bb >> 16) & 0xFF);
    int dg = ((aa >> 8) & 0xFF) - ((bb >> 8) & 0xFF);
    int db = (aa & 0xFF) - (bb & 0xFF);
    return (dr.abs() + dg.abs() + db.abs()) < 24;
  }
}

/// One swatch in the quick-pick row. Soft pastel fill, gradient inner
/// highlight, animated selection ring + glow. Same idiom as Apple Home
/// / Philips Hue but with a smaller footprint so we can fit 10 in a row.
class _QuickSwatch extends StatelessWidget {
  const _QuickSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color,
                Color.alphaBlend(
                  Colors.white.withValues(alpha: 0.20),
                  color,
                ),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.08),
              width: selected ? 2.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: selected ? 0.55 : 0.30),
                blurRadius: selected ? 14 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: selected
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
              : null,
        ),
      ),
    );
  }
}

/// The continuous soft hue strip + W pill. Saturation is held at 0.65
/// (vs 1.0 for the old neon gradient), value at 0.95. Drag anywhere to
/// scrub; tap to set; tap the white pill on the right for daylight.
class _SoftHueStrip extends StatelessWidget {
  const _SoftHueStrip({
    required this.currentHex,
    required this.onChanged,
  });

  final String currentHex;
  final ValueChanged<String> onChanged;

  /// Build the strip gradient at runtime so the saturation is consistent
  /// across the rainbow — a hard-coded gradient between full-sat colors
  /// is what produces the painful neon look. We sample 12 stops at
  /// HSV(hue, 0.65, 0.95).
  List<Color> _softStops() {
    return [
      for (int i = 0; i <= 12; i++)
        HSVColor.fromAHSV(1.0, (i / 12) * 360.0, 0.65, 0.95).toColor(),
    ];
  }

  void _onScrubbed(double dx, double width) {
    final t = (dx / width).clamp(0.0, 1.0);
    final hue = t * 360.0;
    // Same saturation/value as the strip so picking and the visible color
    // match. The output is still a full hex string so device firmware
    // doesn't have to know about HSV.
    final color = HSVColor.fromAHSV(1.0, hue, 0.65, 0.95).toColor();
    onChanged(LedColorPicker._hexFromColor(color));
  }

  @override
  Widget build(BuildContext context) {
    final selected = LedColorPicker._parseHex(currentHex);
    final isWhite = LedColorPicker._isGrayscale(selected);
    final hue = isWhite
        ? -1.0
        : HSVColor.fromColor(selected).hue;

    return LayoutBuilder(
      builder: (context, constraints) {
        const whitePillWidth = 44.0;
        const gap = 10.0;
        final barWidth = constraints.maxWidth - whitePillWidth - gap;
        final indicatorX = hue < 0 ? -1.0 : (hue / 360.0) * barWidth;
        final softStops = _softStops();

        return Row(
          children: [
            SizedBox(
              width: barWidth,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _onScrubbed(d.localPosition.dx, barWidth),
                // onHorizontalDrag* claims the gesture from the parent
                // SingleChildScrollView's vertical arena, so the strip
                // actually responds to swipes inside scrollable screens.
                onHorizontalDragStart: (d) =>
                    _onScrubbed(d.localPosition.dx, barWidth),
                onHorizontalDragUpdate: (d) =>
                    _onScrubbed(d.localPosition.dx, barWidth),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 28,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(colors: softStops),
                        border: Border.all(
                          color: AppColors.borderCol(context),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    if (indicatorX >= 0)
                      Positioned(
                        left: (indicatorX - 9).clamp(0.0, barWidth - 18),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 100),
                          width: 18,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: AppColors.borderCol(context),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: selected,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: gap),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged('#FFFFFF');
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: whitePillWidth,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isWhite
                        ? AppColors.primaryBlue
                        : AppColors.borderCol(context),
                    width: isWhite ? 2.4 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  'W',
                  style: TextStyle(
                    color: isWhite
                        ? AppColors.primaryBlue
                        : Colors.grey.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
