import 'package:flutter/material.dart';

/// Standard durations & curves so micro-interactions feel cohesive
/// instead of every screen picking its own timing.
class AppMotion {
  AppMotion._();

  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 380);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuint;
  static const Curve decelerate = Curves.easeOut;

  /// Drop-in replacement for [MaterialPageRoute] that fades + slides
  /// the new screen up a few pixels. Use for navigation transitions
  /// when you want a softer feel than the platform default.
  static Route<T> fadeSlideRoute<T>(
    Widget page, {
    Duration duration = base,
    RouteSettings? settings,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: duration,
      reverseTransitionDuration: fast,
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(parent: animation, curve: standard);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /// Use for modal/dialog opens — scales up subtly while fading in.
  static Route<T> scaleFadeRoute<T>(
    Widget page, {
    Duration duration = base,
    RouteSettings? settings,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      opaque: false,
      barrierColor: Colors.black54,
      transitionDuration: duration,
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(parent: animation, curve: emphasized);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}
