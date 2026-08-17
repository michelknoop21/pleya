import '../media/item_watcher.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../utils/app_logger.dart';
import 'plex_client.dart';
import 'tautulli/tautulli_client.dart';

/// Resolves "who watched this" for one title, preferring Tautulli and falling
/// back to the Plex Media Server's own history.
///
/// Why the preference: Tautulli carries an avatar for every user, which the
/// PMS `/accounts` endpoint does not (it returned an empty thumb for all 23
/// accounts on the measured server), and it reports `watched_status`, so a play
/// that stopped at ten percent can be excluded instead of counted.
///
/// Both sources are admin-only by construction. Callers gate on server
/// ownership before getting here; nothing in this file relaxes that.
class ItemWatchersService {
  const ItemWatchersService();

  /// Everyone who watched [metadata], newest or busiest first.
  ///
  /// Returns an empty list on any failure, deliberately: this is secondary
  /// detail-page content and a monitoring service being down is not a reason to
  /// show an error next to a film.
  Future<ItemWatchers> resolve(
    MediaItem metadata, {
    TautulliClient? tautulli,
    PlexClient? plex,
    String? plexOwnerToken,

    /// plex.tv account id of the signed-in profile, for Tautulli's id space.
    int? selfPlexAccountId,

    /// Plex Media Server account id of the signed-in profile. The owner is 1 on
    /// an owned server; a managed user has their plex.tv id here instead.
    int? selfServerAccountId,
  }) async {
    if (tautulli != null) {
      final fromTautulli = await _fromTautulli(tautulli, metadata, selfPlexAccountId);
      // An empty Tautulli answer is a real answer (nobody watched it), so it is
      // not a reason to fall back and ask Plex the same question differently.
      if (fromTautulli != null) return fromTautulli;
    }
    if (plex != null) {
      return (
        watchers: await _fromPlex(plex, metadata, plexOwnerToken, selfServerAccountId),
        scope: ItemWatchersScope.watched,
      );
    }
    return (watchers: const <ItemWatcher>[], scope: ItemWatchersScope.watched);
  }

  /// Null when Tautulli could not answer, so the caller can still try Plex.
  Future<ItemWatchers?> _fromTautulli(TautulliClient client, MediaItem metadata, int? selfId) async {
    try {
      if (metadata.isShow) {
        // A series has no single completion, so aggregate per user across
        // episodes and label it as watching rather than watched.
        final stats = await client.itemUserStats(metadata.id);
        return (
          watchers: [
            for (final s in stats)
              ItemWatcher(
                id: '${s.userId}',
                displayName: s.displayName,
                thumbUrl: s.userThumb,
                plays: s.totalPlays,
                isSelf: selfId != null && s.userId == selfId,
              ),
          ]..sort(ItemWatcher.compare),
          scope: ItemWatchersScope.watchingSeries,
        );
      }

      final entries = await client.watchersOf(metadata.id);
      return (
        watchers: [
          for (final e in entries)
            ItemWatcher(
              id: '${e.userId}',
              displayName: e.displayName,
              thumbUrl: e.userThumb,
              viewedAt: e.date,
              isSelf: selfId != null && e.userId == selfId,
            ),
        ]..sort(ItemWatcher.compare),
        scope: ItemWatchersScope.watched,
      );
    } catch (e) {
      appLogger.d('Tautulli watchers unavailable, falling back to Plex history', error: e);
      return null;
    }
  }

  Future<List<ItemWatcher>> _fromPlex(
    PlexClient client,
    MediaItem metadata,
    String? ownerToken,
    int? selfAccountId,
  ) async {
    final rows = await client.fetchItemWatchers(metadata.id, authToken: ownerToken);
    return [
      for (final r in rows)
        ItemWatcher(
          id: '${r.accountId}',
          displayName: r.displayName,
          thumbUrl: r.thumbUrl,
          viewedAt: r.viewedAt,
          // On an owned server Plex files the owner under account 1, so that is
          // the fallback when the caller could not resolve a real id.
          isSelf: r.accountId == (selfAccountId ?? 1),
        ),
    ]..sort(ItemWatcher.compare);
  }
}
