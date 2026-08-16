import 'dart:async';

import 'package:flutter/foundation.dart';

import '../media/media_item.dart';
import '../media/watchlist_key.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../utils/external_ids.dart';
import '../utils/watchlist_notifier.dart';

/// Session-local layer that makes a watchlist toggle feel instant.
///
/// The server list stays the source of truth; this only holds what the user
/// just did, so a heart icon flips on tap instead of after a round trip. Every
/// patch is keyed by the canonical watchlist key and **never** by
/// [MediaItem.globalKey]: a discover item has no server, so its global key is
/// a bare rating key sitting in the same namespace as real server keys, and
/// patching on that would let one title's state leak onto another server's
/// item with the same number.
class WatchlistStore extends ChangeNotifier with DisposableChangeNotifierMixin {
  WatchlistStore() {
    _subscription = WatchlistNotifier().stream.listen(_onEvent);
  }

  StreamSubscription<WatchlistEvent>? _subscription;

  /// key → is the title on the list. Absent means "no opinion, ask the list".
  final Map<String, bool> _patches = {};

  String? _activeProfileId;

  /// Rebind to [profileId]. A profile switch drops every patch: the patches
  /// describe one user's list, and carrying them across would flip a heart on
  /// a title the new user never added.
  void bindProfile(String? profileId) {
    if (_activeProfileId == profileId) return;
    _activeProfileId = profileId;
    if (_patches.isEmpty) return;
    _patches.clear();
    safeNotifyListeners();
  }

  /// What the store knows about [item], or null when it has no opinion.
  bool? isOnWatchlist(MediaItem item, {ExternalIds? externalIds}) {
    final key = watchlistKeyForItem(item, externalIds: externalIds);
    return key == null ? null : _patches[key];
  }

  bool? isOnWatchlistByKey(String key) => _patches[key];

  /// Record what the user just did, before the network agrees.
  void patch(String key, {required bool onList}) {
    if (_patches[key] == onList) return;
    _patches[key] = onList;
    safeNotifyListeners();
  }

  /// Undo a patch after a failed write, so the UI stops claiming something
  /// that never happened.
  void revert(String key) {
    if (_patches.remove(key) == null) return;
    safeNotifyListeners();
  }

  /// Forget every patch, for instance after a refetch made them redundant.
  void clear() {
    if (_patches.isEmpty) return;
    _patches.clear();
    safeNotifyListeners();
  }

  @visibleForTesting
  Map<String, bool> get debugPatches => Map.unmodifiable(_patches);

  void _onEvent(WatchlistEvent event) {
    patch(event.key, onList: event.isOnList);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }
}
