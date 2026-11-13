import 'dart:async';

import '../providers/watchlist_provider.dart';
import 'assistant_tools.dart';

/// Brings [provider] up to date for a read by Big P and says how it ended.
///
/// `ensureLoaded` is not enough here. It returns at once while another screen
/// is loading, and after a failed load it never tries again: Big P would then
/// read an empty list and tell the user their kijklijst is empty.
Future<AssistantWatchlistRead> assistantReadWatchlist(
  WatchlistProvider provider, {
  required bool offline,
  Duration patience = const Duration(seconds: 20),
}) async {
  if (provider.isLoading) await _loaded(provider, patience);
  if (!provider.isLoading && (!provider.hasLoaded || provider.error != null)) {
    await provider.load(offline: offline);
  }
  return (
    // Still loading after the wait counts as failed: nothing was read.
    failed: provider.isLoading || provider.error != null,
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
