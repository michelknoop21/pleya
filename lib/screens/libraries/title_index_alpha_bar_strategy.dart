import '../../media/library_first_character.dart';
import '../../media/library_query.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../media/title_letter_count_client.dart';
import 'alpha_jump_helper.dart';
import 'library_alpha_bar_strategy.dart';
import 'title_letter_index.dart';

/// Loads a letter index for the grid listing [query] describes, or `null` when
/// it cannot be trusted.
typedef TitleIndexLoader =
    Future<List<LibraryFirstCharacter>?> Function(LibraryQuery query, {required bool descending});

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

  /// Jellyfin: one `NameLessThan` count per letter, so the offsets come from
  /// the same `SortName` comparison the grid is sorted by.
  factory TitleIndexAlphaBarStrategy.counted({
    required MediaServerClient Function() clientProvider,
    required String libraryKey,
    required MediaKind? libraryKind,
  }) {
    return TitleIndexAlphaBarStrategy((query, {required descending}) async {
      // Typed as Object so the check promotes: the interface is not a
      // subtype of MediaServerClient.
      final Object client = clientProvider();
      if (client is! TitleLetterCountClient) return null;
      final counts = await client.fetchTitleCountsBefore(
        libraryKey,
        query: query,
        libraryKind: libraryKind,
        bounds: titleIndexBounds,
      );
      return letterIndexFromCountsBefore(total: counts.total, before: counts.before);
    });
  }

  /// Local folders and Pleya Server: read the complete listing in grid order
  /// and bucket it by first letter. [sortTitleOf] must return the title the
  /// backend sorts on.
  factory TitleIndexAlphaBarStrategy.fromListing({
    required MediaServerClient Function() clientProvider,
    required String libraryKey,
    required MediaKind? libraryKind,
    required String Function(MediaItem item) sortTitleOf,
  }) {
    return TitleIndexAlphaBarStrategy((query, {required descending}) async {
      final page = await clientProvider().fetchLibraryPagedContent(
        libraryKey,
        query: query.copyWith(offset: 0, limit: maxListingItems),
        libraryKind: libraryKind,
      );
      // A short or capped read would put every later letter at the wrong offset.
      if (page.items.length != page.totalCount || page.items.length >= maxListingItems) return null;
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
  }) async {
    // No requests for a sort the rail would not be shown for anyway.
    if (!_isTitleSortKey(query.sort?.field)) {
      return (chars: const <LibraryFirstCharacter>[], helper: AlphaJumpHelper(const []));
    }
    final chars = await loadIndex(query, descending: descending) ?? const <LibraryFirstCharacter>[];
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
