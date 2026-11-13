import 'dart:async';

import '../providers/watchlist_provider.dart';
import 'assistant_tools.dart';

/// Brings [provider] up to date for a read by Big P and says how it ended.
///
/// `ensureLoaded` is not enough here. It returns at once while another screen
/// is loading and never loads twice: Big P would then read an empty list and
/// tell the user their kijklijst is empty.
///
/// A source that is down does not show as an error: the repository keeps the
/// other sources and marks the result incomplete. So a list that is
/// incomplete, or that came from the snapshot while the device is online
/// again, is read anew on every call, not only after an error.
Future<AssistantWatchlistRead> assistantReadWatchlist(
  WatchlistProvider provider, {
  required bool offline,
  Duration patience = const Duration(seconds: 20),
}) async {
  if (provider.isLoading) await _loaded(provider, patience);
  final stale =
      !provider.hasLoaded || provider.error != null || !provider.isComplete || (provider.isFromSnapshot && !offline);
  if (!provider.isLoading && stale) await provider.load(offline: offline);
  return (
    // Still loading after the wait, or a load that a rebind cut short, read
    // nothing.
    failed: provider.isLoading || provider.error != null || !provider.hasLoaded,
    incomplete: !provider.isComplete,
    fromSnapshot: provider.isFromSnapshot,
  );
}

/// Completes when [provider] stops loading, or after [patience].
Future<void> _loaded(WatchlistProvider provider, Duration patience) {
  final done = Completer<void>();
  void check() {
    if (!provider.isLoading && !done.isCompleted) done.complete();
  }

  provider.addListener(check);
  return done.future.timeout(patience, onTimeout: () {}).whenComplete(() => provider.removeListener(check));
}
