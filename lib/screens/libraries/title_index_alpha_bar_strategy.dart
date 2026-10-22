import '../../media/library_first_character.dart';
import '../../media/library_query.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../media/title_letter_count_client.dart';
import '../../utils/media_server_http_client.dart' show AbortController;
import 'alpha_jump_helper.dart';
import 'library_alpha_bar_strategy.dart';
import 'title_letter_index.dart';

/// Loads a letter index for the grid listing [query] describes, or `null` when
/// it cannot be trusted or [abort] fired.
typedef TitleIndexLoader =
    Future<List<LibraryFirstCharacter>?> Function(
      LibraryQuery query, {
      required bool descending,
      AbortController? abort,
    });

/// Phone scrubber for backends without Plex's `/firstCharacter` endpoint.
///
/// Behaves like [PlexAlphaBarStrategy] once the index is loaded: the rail
/// scrolls the grid to a letter's offset. Same thresholds as Plex (at least 80
/// titles and 6 letters), title sort only, phone only. The rail stays hidden
/// when the loader returns `null` or when the index does not add up to the
/// grid's own total.
class TitleIndexAlphaBarStrategy implements LibraryAlphaBarStrategy {
  /// Largest listing [TitleIndexAlphaBarStrategy.fromListing] reads in full.
  static const int maxListingItems = 20000;

  final TitleIndexLoader loadIndex;

  const TitleIndexAlphaBarStrategy(this.loadIndex);

  /// Wait before [TitleIndexAlphaBarStrategy.counted] fires its requests, so a
  /// burst of filter or sort changes costs one batch instead of one per change.
  static const Duration countDebounce = Duration(milliseconds: 300);

  /// Jellyfin: one `NameLessThan` count per letter, so the offsets come from
  /// the same `SortName` comparison the grid is sorted by. The batch starts
  /// after [debounce] and is dropped when the caller aborts before then.
  factory TitleIndexAlphaBarStrategy.counted({
    required MediaServerClient Function() clientProvider,
    required String libraryKey,
    required MediaKind? libraryKind,
    Duration debounce = countDebounce,
  }) {
    return TitleIndexAlphaBarStrategy((query, {required descending, abort}) async {
      // Typed as Object so the check promotes: the interface is not a
      // subtype of MediaServerClient.
      final Object client = clientProvider();
      if (client is! TitleLetterCountClient) return null;
      if (debounce > Duration.zero) await Future<void>.delayed(debounce);
      if (abort?.isAborted ?? false) return null;
      final counts = await client.fetchTitleCountsBefore(
        libraryKey,
        query: query,
        libraryKind: libraryKind,
        bounds: const [...titleIndexBounds, titleIndexEndBound],
        abort: abort,
      );
      return letterIndexFromCountsBefore(total: counts.total, before: counts.before);
    });
  }

  /// Local folders and Pleya Server: read the complete listing in grid order
  /// and bucket it by first letter. [sortTitleOf] must return the title the
  /// backend sorts on. A one-item probe reads the total first, so a listing
  /// above [maxListingItems] is never fetched.
  factory TitleIndexAlphaBarStrategy.fromListing({
    required MediaServerClient Function() clientProvider,
    required String libraryKey,
    required MediaKind? libraryKind,
    required String Function(MediaItem item) sortTitleOf,
  }) {
    return TitleIndexAlphaBarStrategy((query, {required descending, abort}) async {
      final client = clientProvider();
      final probe = await client.fetchLibraryPagedContent(
        libraryKey,
        query: query.copyWith(offset: 0, limit: 1),
        libraryKind: libraryKind,
        abort: abort,
      );
      final total = probe.totalCount;
      if (total <= 0 || total > maxListingItems || (abort?.isAborted ?? false)) return null;
      final page = await client.fetchLibraryPagedContent(
        libraryKey,
        query: query.copyWith(offset: 0, limit: total),
        libraryKind: libraryKind,
        abort: abort,
      );
      // A short read would put every later letter at the wrong offset.
      if (abort?.isAborted ?? false) return null;
      if (page.items.length != page.totalCount || page.items.length > maxListingItems) return null;
      return letterIndexFromOrderedTitles(page.items.map(sortTitleOf), descending: descending);
    });
  }

  static bool _isTitleSortKey(String? key) {
    final k = (key ?? '').toLowerCase();
    return k.isEmpty || k == 'title' || k == 'name' || k == 'sortname' || k.startsWith('titlesort');
  }

  @override
  bool shouldShow({
    required int totalItemCount,
    required int loadedCharacterCount,
    required String? sortKey,
    required bool isFolderGrouping,
    required String? jellyfinAlphaPrefix,
    required bool isPhone,
    required int indexItemCount,
  }) {
    if (!isPhone || isFolderGrouping) return false;
    if (loadedCharacterCount < 6 || totalItemCount < 80) return false;
    if (indexItemCount != totalItemCount) return false;
    return _isTitleSortKey(sortKey);
  }

  @override
  Future<({List<LibraryFirstCharacter> chars, AlphaJumpHelper helper})> loadCharacters({
    required Map<String, String> filters,
    required int? typeId,
    required bool descending,
    required LibraryQuery query,
    AbortController? abort,
  }) async {
    // No requests for a sort the rail would not be shown for anyway.
    if (!_isTitleSortKey(query.sort?.field)) {
      return (chars: const <LibraryFirstCharacter>[], helper: AlphaJumpHelper(const []));
    }
    final chars = await loadIndex(query, descending: descending, abort: abort) ?? const <LibraryFirstCharacter>[];
    return (chars: chars, helper: AlphaJumpHelper(chars, descending: descending));
  }

  @override
  String currentLetter(int index, AlphaJumpHelper helper, {String? jellyfinAlphaPrefix}) => helper.currentLetter(index);

  @override
  void onLetterPressed(
    int targetIndex,
    AlphaJumpHelper helper, {
    required String? currentJellyfinPrefix,
    required void Function(int index) onPlexJump,
    required void Function(String? nextPrefix) onJellyfinPrefixChange,
  }) {
    onPlexJump(targetIndex);
  }
}
