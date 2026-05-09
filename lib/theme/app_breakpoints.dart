import 'package:flutter/widgets.dart';

/// Width breakpoints used to adapt layouts. Phone-first; the tablet/desktop
/// thresholds are where 2-column grids and side-by-side panels become
/// reasonable.
class AppBreakpoints {
  AppBreakpoints._();

  static const double phone = 0;
  static const double tablet = 600;
  static const double desktop = 1024;

  static FormFactor formFactorOf(BuildContext context) =>
      formFactorFromWidth(MediaQuery.of(context).size.width);

  static FormFactor formFactorFromWidth(double width) {
    if (width >= desktop) return FormFactor.desktop;
    if (width >= tablet) return FormFactor.tablet;
    return FormFactor.phone;
  }

  static bool isTabletOrLarger(BuildContext context) =>
      MediaQuery.of(context).size.width >= tablet;
}

enum FormFactor { phone, tablet, desktop }

/// Picks one of the three layouts based on the current width. Use this
/// inside a `LayoutBuilder` or a screen body where tablet UX should diverge
/// (e.g. a 2-column dashboard, a side panel for navigation).
class Responsive extends StatelessWidget {
  const Responsive({
    super.key,
    required this.phone,
    this.tablet,
    this.desktop,
  });

  final Widget phone;
  final Widget? tablet;
  final Widget? desktop;

  @override
  Widget build(BuildContext context) {
    final ff = AppBreakpoints.formFactorOf(context);
    switch (ff) {
      case FormFactor.desktop:
        return desktop ?? tablet ?? phone;
      case FormFactor.tablet:
        return tablet ?? phone;
      case FormFactor.phone:
        return phone;
    }
  }
}
