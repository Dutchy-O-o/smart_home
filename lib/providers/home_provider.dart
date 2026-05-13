import 'package:flutter_riverpod/flutter_riverpod.dart';

class SelectedHomeNotifier extends Notifier<Map<String, dynamic>?> {
  @override
  Map<String, dynamic>? build() {
    return null;
  }

  void setHome(Map<String, dynamic> home) {
    state = home;
  }

  /// Drop the currently-selected home (e.g. after the user leaves it so
  /// they don't get navigated back into a home they no longer have access to).
  void clear() {
    state = null;
  }
}

final selectedHomeProvider = NotifierProvider<SelectedHomeNotifier, Map<String, dynamic>?>(SelectedHomeNotifier.new);
