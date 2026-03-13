import 'package:flutter_riverpod/flutter_riverpod.dart';

class SelectedHomeNotifier extends Notifier<Map<String, dynamic>?> {
  @override
  Map<String, dynamic>? build() {
    return null;
  }

  void setHome(Map<String, dynamic> home) {
    state = home;
  }
}

final selectedHomeProvider = NotifierProvider<SelectedHomeNotifier, Map<String, dynamic>?>(SelectedHomeNotifier.new);
