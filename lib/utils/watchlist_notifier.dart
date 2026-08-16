import 'package:flutter/foundation.dart';

import 'app_logger.dart';
import 'base_notifier.dart';

enum WatchlistChangeType { added, removed }

/// One title went on or off the kijklijst.
///
/// Keyed by the canonical watchlist key rather than a `serverId:ratingKey`,
/// because the same event has to reach the detail screen of a server item and
/// the card of a discover item that has no server at all.
class WatchlistEvent {
  /// Canonical key from `watchlistKeyForItem`.
  final String key;

  final WatchlistChangeType changeType;

  /// Whether the change is still only local. A patch that has not been
  /// confirmed by every source yet is shown immediately but must be undone if
  /// the write turns out to have failed.
  final bool optimistic;

  const WatchlistEvent({required this.key, required this.changeType, this.optimistic = false});

  bool get isOnList => changeType == WatchlistChangeType.added;

  @override
  String toString() => 'WatchlistEvent(${changeType.name}, $key${optimistic ? ', optimistic' : ''})';
}

/// App-wide watchlist changes, same shape and lifetime as [WatchStateNotifier].
class WatchlistNotifier extends BaseNotifier<WatchlistEvent> {
  static final WatchlistNotifier _instance = WatchlistNotifier._internal();

  factory WatchlistNotifier() => _instance;

  WatchlistNotifier._internal();

  /// A private instance, so a test does not have to share the app-wide one and
  /// then clean up after itself.
  @visibleForTesting
  WatchlistNotifier.forTesting();

  Stream<WatchlistEvent> forKey(String key) => stream.where((e) => e.key == key);

  @override
  void notify(WatchlistEvent event) {
    appLogger.d('WatchlistNotifier: $event');
    super.notify(event);
  }
}
