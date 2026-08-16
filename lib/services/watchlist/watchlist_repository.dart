import '../../media/media_item.dart';
import '../../media/watchlist_entry.dart';
import '../../media/watchlist_source.dart';
import '../../utils/app_logger.dart';
import '../../utils/external_ids.dart';

/// Outcome of a repository fetch.
///
/// [complete] says whether every source answered. A source that failed is not
/// the same as a source with nothing on it, and the difference matters: a
/// half-loaded list that looks whole invites the user to re-add a title that
/// is already there.
typedef WatchlistFetchResult = ({List<WatchlistEntry> entries, bool complete, List<WatchlistSource> failed});

/// Merges the watchlists of every source the active profile has into one list.
///
/// Deduplication runs in three tiers, most specific first: the canonical key,
/// then the guid, then an external id. The same film on the Plex watchlist and
/// as a Jellyfin favorite has two different canonical keys (`plex:...` and
/// `imdb:...`) and only meets itself on the third tier, which is exactly why
/// the tiers exist.
///
/// **Memberships are joined on every merge, never replaced.** Dropping one
/// would leave a forgotten copy behind that reappears on the next refresh, and
/// removing a title would look broken while the code did what it was told.
class WatchlistRepository {
  WatchlistRepository({required this.sources});

  /// Every source for the active profile, in priority order. The first source
  /// that holds a title decides its identity and its position in the list.
  ///
  /// Order matters beyond taste. Plex returns its watchlist newest-first and
  /// puts no timestamp on the items, so the sequence is the only "recently
  /// added" signal there is. Putting the account source first keeps that
  /// order intact and appends the Jellyfin-only titles behind it.
  final List<WatchlistSource> sources;

  /// Everything on the merged list.
  ///
  /// One failing source does not sink the fetch: the rest still renders, and
  /// [WatchlistFetchResult.complete] tells the caller not to treat the result
  /// as the whole truth.
  Future<WatchlistFetchResult> fetch() async {
    final results = await Future.wait(
      sources.map((source) async {
        try {
          return (source: source, entries: await source.fetch(), ok: true);
        } catch (e, st) {
          appLogger.w('Watchlist source ${source.scope.storageKey} failed', error: e, stackTrace: st);
          return (source: source, entries: const <WatchlistEntry>[], ok: false);
        }
      }),
    );

    final merged = mergeEntries(results.expand((r) => r.entries));
    final failed = results.where((r) => !r.ok).map((r) => r.source).toList();
    return (entries: merged, complete: failed.isEmpty, failed: failed);
  }

  /// The source that should hold [item] when the user adds it, or null when no
  /// source will take it.
  ///
  /// A Jellyfin item goes to the favorites of its own server; a Plex item with
  /// a `plex://` guid goes to the account watchlist. A Plex item without a
  /// guid, a local file and a shared item have no route, and saying so is
  /// better than picking a source that will fail on the wire.
  WatchlistSource? targetFor(MediaItem item) {
    for (final source in sources) {
      if (source.accepts(item)) return source;
    }
    return null;
  }

  /// Fold [entries] into one list, joining anything that turns out to be the
  /// same title. Preserves first-seen order.
  static List<WatchlistEntry> mergeEntries(Iterable<WatchlistEntry> entries) {
    final merged = <WatchlistEntry>[];
    // Every alias of an already-merged entry points at its slot, so a later
    // entry that matches on any tier lands on the same title.
    final slotByAlias = <String, int>{};

    for (final entry in entries) {
      final aliases = _aliasesOf(entry);
      int? slot;
      for (final alias in aliases) {
        final existing = slotByAlias[alias];
        if (existing != null) {
          slot = existing;
          break;
        }
      }

      if (slot == null) {
        merged.add(entry);
        slot = merged.length - 1;
      } else {
        merged[slot] = merged[slot].mergeWith(entry);
      }

      // Register the aliases of the merged result, not just of this entry, so
      // a third source matching on a different tier still finds the slot.
      for (final alias in _aliasesOf(merged[slot])) {
        slotByAlias.putIfAbsent(alias, () => slot!);
      }
    }

    return merged;
  }

  /// Identities under which an entry can be recognised, most specific first.
  ///
  /// Namespaced so an IMDb id can never be mistaken for a guid or a canonical
  /// key that happens to read the same.
  static List<String> _aliasesOf(WatchlistEntry entry) {
    final guid = entry.guid;
    final ids = entry.externalIds;
    return ['key:${entry.key}', if (guid != null && guid.isNotEmpty) 'guid:$guid', ..._externalAliases(ids)];
  }

  static List<String> _externalAliases(ExternalIds ids) {
    final imdb = ids.imdb;
    final tmdb = ids.tmdb;
    final tvdb = ids.tvdb;
    return [
      if (imdb != null && imdb.isNotEmpty) 'imdb:$imdb',
      if (tmdb != null) 'tmdb:$tmdb',
      if (tvdb != null) 'tvdb:$tvdb',
    ];
  }
}
