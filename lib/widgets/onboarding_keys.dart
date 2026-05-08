import 'package:flutter/widgets.dart';

/// Shared GlobalKeys used by the first-run onboarding tour. Each key
/// pins a Showcase target to a UI element so the wrapper widget in
/// dashboard_screen can start the tour with the correct sequence.
class OnboardingKeys {
  OnboardingKeys._();

  static final hero = GlobalKey();
  static final notifications = GlobalKey();
  static final scenes = GlobalKey();
  static final navAi = GlobalKey();
}
