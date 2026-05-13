import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';

/// Reactive view of the AWS API reachability flag maintained by
/// [ApiService]. Bridges the service's broadcast stream into Riverpod so
/// any widget can react to going offline / coming back online without
/// polling.
///
/// Emits `true` while the last request succeeded or no requests have run
/// yet, `false` once a SocketException-class failure flips the service
/// into "network down" mode.
final networkStatusProvider = StreamProvider<bool>((ref) async* {
  // Seed with the current value so listeners get state immediately
  // instead of waiting for the next flip.
  yield ApiService.isOnline;
  yield* ApiService.networkStatusStream;
});

/// Convenience boolean — true when offline. Use in widgets:
///
///     final offline = ref.watch(isOfflineProvider);
///     if (offline) ...
final isOfflineProvider = Provider<bool>((ref) {
  final status = ref.watch(networkStatusProvider);
  return status.maybeWhen(
    data: (online) => !online,
    orElse: () => false,
  );
});

/// Lightweight retry queue. Callers register a "retry on reconnect"
/// callback when a request fails because of the network being down;
/// the callback fires once the network flips back online, then the
/// entry is dropped. Idempotent dedup keys keep us from re-running
/// the same fetch a dozen times if multiple screens registered.
class RetryQueueNotifier extends Notifier<Set<String>> {
  final Map<String, Future<void> Function()> _callbacks = {};

  @override
  Set<String> build() => const <String>{};

  void register(String key, Future<void> Function() retry) {
    _callbacks[key] = retry;
    state = {...state, key};
  }

  Future<void> flushAll() async {
    final pending = List<MapEntry<String, Future<void> Function()>>.from(
        _callbacks.entries);
    _callbacks.clear();
    state = const <String>{};
    for (final entry in pending) {
      try {
        await entry.value();
      } catch (_) {
        // Don't crash the queue on one failed retry — leave the rest
        // to run; the next reconnect cycle will pick up anything that
        // re-registers itself.
      }
    }
  }
}

final retryQueueProvider =
    NotifierProvider<RetryQueueNotifier, Set<String>>(RetryQueueNotifier.new);

/// Listen to network flips and drain the retry queue on the rising edge
/// (offline → online). Wire this once from MainShell (or any always-mounted
/// widget) so the queue actually runs.
void wireRetryQueueToConnectivity(WidgetRef ref) {
  ref.listen<AsyncValue<bool>>(networkStatusProvider, (prev, next) {
    final wasOffline = prev?.maybeWhen(data: (v) => !v, orElse: () => false) ??
        false;
    final isOnline =
        next.maybeWhen(data: (v) => v, orElse: () => false);
    if (wasOffline && isOnline) {
      ref.read(retryQueueProvider.notifier).flushAll();
    }
  });
}
