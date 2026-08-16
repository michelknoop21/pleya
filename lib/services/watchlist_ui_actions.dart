import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/watchlist_entry.dart';
import '../media/watchlist_key.dart';
import '../providers/offline_mode_provider.dart';
import '../providers/watchlist_provider.dart';
import '../providers/watchlist_store.dart';
import '../utils/external_ids.dart';
import '../utils/haptics.dart';
import '../utils/snackbar_helper.dart';
import 'watchlist_actions.dart';

/// The context-aware half of the watchlist actions.
///
/// [WatchlistActions] stays pure so it can be tested without a widget tree;
/// everything that needs a [BuildContext] (which providers to read, which
/// feedback to give) lives here. The detail screen, the context menu and the
/// kijklijst itself all come through this one door, so a toggle behaves the
/// same wherever it is pressed.
class WatchlistUiActions {
  WatchlistUiActions._();

  /// Whether [item] is on the kijklijst as far as the app knows right now.
  ///
  /// The optimistic store wins over the fetched list. That is the whole point
  /// of the store: the user just tapped, and the list has not caught up yet.
  static bool isOnList({
    required WatchlistStore? store,
    required WatchlistProvider? provider,
    required MediaItem item,
    ExternalIds? externalIds,
  }) {
    final key = watchlistKeyForItem(item, externalIds: externalIds);
    if (key == null) return false;
    final patched = store?.isOnWatchlistByKey(key);
    if (patched != null) return patched;
    return provider?.entryForKey(key) != null;
  }

  /// Whether a toggle can be offered for [item] at all.
  ///
  /// Adding needs a source that will take the title; removing needs the entry
  /// the memberships hang off. Offering an action the layer underneath cannot
  /// carry out would be a button that fails on press, which is worse than a
  /// button that is not there.
  static bool canOffer({
    required WatchlistProvider? provider,
    required MediaItem item,
    required bool onList,
    ExternalIds? externalIds,
  }) {
    if (provider == null) return false;
    if (item.kind != MediaKind.movie && item.kind != MediaKind.show) return false;
    if (onList) {
      final key = watchlistKeyForItem(item, externalIds: externalIds);
      return key != null && provider.entryForKey(key) != null;
    }
    return provider.repository?.targetFor(item) != null;
  }

  /// Flip [item] on or off the list and tell the user what happened.
  ///
  /// [announce] is on where the list is not on screen, so the detail screen and
  /// the context menu confirm with a snackbar. The kijklijst itself passes
  /// `false`: the card leaving the grid is the confirmation, and a snackbar on
  /// top of it would say the same thing twice.
  static Future<WatchlistOutcome> toggle(BuildContext context, MediaItem item, {bool announce = true}) async {
    final provider = context.read<WatchlistProvider?>();
    final store = context.read<WatchlistStore?>();
    if (provider == null) return WatchlistOutcome.unsupported;

    final isOffline = context.read<OfflineModeProvider?>()?.isOffline ?? false;
    final onList = isOnList(store: store, provider: provider, item: item);

    final WatchlistOutcome outcome;
    if (onList) {
      final key = watchlistKeyForItem(item);
      final entry = key == null ? null : provider.entryForKey(key);
      if (entry == null) return WatchlistOutcome.unsupported;
      outcome = await provider.removeFromWatchlist(entry, isOffline: isOffline);
    } else {
      outcome = await provider.addToWatchlist(item, isOffline: isOffline);
    }

    if (!context.mounted) return outcome;
    report(context, outcome, announce: announce);
    return outcome;
  }

  /// Take [entry] off every list it was merged from.
  ///
  /// Separate from [toggle] because the kijklijst holds the entry already and
  /// its catalogue item has no server, so routing it back through
  /// [watchlistKeyForItem] would be a lookup of something already in hand.
  static Future<WatchlistOutcome> remove(BuildContext context, WatchlistEntry entry, {bool announce = false}) async {
    final provider = context.read<WatchlistProvider?>();
    if (provider == null) return WatchlistOutcome.unsupported;

    final isOffline = context.read<OfflineModeProvider?>()?.isOffline ?? false;
    final outcome = await provider.removeFromWatchlist(entry, isOffline: isOffline);
    if (!context.mounted) return outcome;
    report(context, outcome, announce: announce);
    return outcome;
  }

  /// Haptics on success, words on everything that needs them.
  ///
  /// A failure always speaks, even where a success stays quiet: silence after
  /// a tap reads as "nothing happened", which is exactly the wrong thing to
  /// believe about a half-finished removal.
  @visibleForTesting
  static void report(BuildContext context, WatchlistOutcome outcome, {required bool announce}) {
    switch (outcome) {
      case WatchlistOutcome.added:
        Haptics.light();
        if (announce) showAppSnackBar(context, t.watchlist.added);
      case WatchlistOutcome.removed:
        Haptics.light();
        if (announce) showAppSnackBar(context, t.watchlist.removed);
      case WatchlistOutcome.offlineRejected:
        showErrorSnackBar(context, t.watchlist.offlineRejected);
      case WatchlistOutcome.partiallyFailed:
        showErrorSnackBar(context, t.watchlist.partiallyFailed);
      case WatchlistOutcome.failed:
      case WatchlistOutcome.unsupported:
        showErrorSnackBar(context, t.watchlist.addFailed);
    }
  }
}
