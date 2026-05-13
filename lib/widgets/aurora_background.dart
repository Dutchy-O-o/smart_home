import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// A subtle, animated "aurora" of three blurred gradient blobs that drift
/// in opposing directions behind hero content. Modeled after the look
/// used by Linear / Vercel / OpenAI dashboards — gives the dashboard a
/// premium, dynamic backdrop without being distracting.
///
/// Stack this *behind* your content:
///
///     Stack(children: [
///       const Positioned.fill(child: AuroraBackground()),
///       MyContent(),
///     ])
///
/// The blobs are blurred in software (BackdropFilter) so they read as
/// soft glows even on dark backgrounds. Animation is a single 18-second
/// looping controller — cheap to render at 60fps on phones.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({
    super.key,
    this.intensity = 1.0,
    this.colors,
  });

  /// 0..1 multiplier on blob opacity. Use lower values (0.4–0.6) when
  /// stacking behind text-heavy content.
  final double intensity;

  /// Optional override for blob colors. Defaults to the brand gradient
  /// (indigo / violet / teal).
  final List<Color>? colors;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = widget.colors ??
        const [
          Color(0xFF5B6CFF), // indigo
          Color(0xFF8B5CF6), // violet
          Color(0xFF14B8A6), // teal
        ];
    final baseAlpha = (isDark ? 0.55 : 0.32) * widget.intensity;

    return ClipRect(
      // LayoutBuilder MUST be outside the Stack so that the Positioned
      // children below are direct descendants of Stack — wrapping a
      // Positioned inside a LayoutBuilder makes Flutter throw
      // "Incorrect use of ParentDataWidget" thousands of times per frame.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final t = _ctrl.value * 2 * math.pi;
              return Stack(
                fit: StackFit.expand,
                children: [
                  // Three-stop base wash — keeps the aurora from feeling like
                  // floating circles against a flat surface AND tints the
                  // bottom of the screen so the gradient reaches edge-to-edge
                  // instead of fading to a flat white rectangle on light
                  // theme. Top: indigo hint, middle: clean bg, bottom: teal
                  // hint. Alphas tuned for light theme — dark theme blobs
                  // already dominate so an extra wash isn't needed there.
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.alphaBlend(
                            palette[0].withValues(
                              alpha: isDark ? 0.10 : 0.14,
                            ),
                            AppColors.bg(context),
                          ),
                          AppColors.bg(context),
                          Color.alphaBlend(
                            (palette.length > 2 ? palette[2] : palette[1])
                                .withValues(alpha: isDark ? 0.12 : 0.18),
                            AppColors.bg(context),
                          ),
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                  _Blob(
                    color: palette[0],
                    alpha: baseAlpha,
                    size: 320,
                    parentW: w,
                    parentH: h,
                    dx: 0.18 + 0.10 * math.sin(t),
                    dy: 0.12 + 0.06 * math.cos(t * 0.8),
                  ),
                  _Blob(
                    color: palette[1],
                    alpha: baseAlpha * 0.85,
                    size: 280,
                    parentW: w,
                    parentH: h,
                    dx: 0.78 + 0.08 * math.cos(t * 1.1),
                    dy: 0.22 + 0.10 * math.sin(t * 0.7),
                  ),
                  _Blob(
                    color: palette.length > 2 ? palette[2] : palette[0],
                    alpha: baseAlpha * 0.9,
                    size: 300,
                    parentW: w,
                    parentH: h,
                    dx: 0.55 + 0.12 * math.sin(t * 0.9 + math.pi / 3),
                    dy: 0.78 + 0.08 * math.cos(t * 0.6),
                  ),
                  // Frosted glass over the blobs — softens the edges so
                  // the blobs read as light, not painted shapes.
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                    child: const SizedBox.expand(),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({
    required this.color,
    required this.alpha,
    required this.size,
    required this.parentW,
    required this.parentH,
    required this.dx,
    required this.dy,
  });

  final Color color;
  final double alpha;
  final double size;

  /// Parent dimensions (passed down from the outer LayoutBuilder) so this
  /// widget can return a Positioned directly without wrapping it in any
  /// other widget — Stack requires Positioned to be its direct child.
  final double parentW;
  final double parentH;

  /// 0..1 horizontal/vertical position relative to parent.
  final double dx;
  final double dy;

  @override
  Widget build(BuildContext context) {
    final left = (parentW * dx) - (size / 2);
    final top = (parentH * dy) - (size / 2);
    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
