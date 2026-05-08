import 'package:flutter_riverpod/flutter_riverpod.dart';

class TabIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void setTab(int index) => state = index;
}

final tabIndexProvider = NotifierProvider<TabIndexNotifier, int>(TabIndexNotifier.new);

/// Sub-tab inside the AI tab (0 = Emotion Hub, 1 = AI Assistant chat).
/// Lets other screens deep-link to a specific sub-section.
class AiSubTabNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void setTab(int index) => state = index;
}

final aiSubTabProvider =
    NotifierProvider<AiSubTabNotifier, int>(AiSubTabNotifier.new);
