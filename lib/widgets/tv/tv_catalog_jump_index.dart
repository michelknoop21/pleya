/// Spring naar (A-06c): from a letter to a card, client-side over the groups
/// that are loaded, the same reading of a title the merge sorts on.
///
/// The merge's order is `normalizeTitleForMatching` over `titleSort`, so "The
/// Accountant" with a sort title stands under A, where the wall shows it. A
/// letter nothing starts with lands on the first title past it, in the
/// direction the page runs: a viewer who asks for X in a library with no X
/// wants to end up around there.
library;

import 'dart:async';

import '../../media/media_item.dart';
import '../../providers/unified_catalog_provider.dart';
import '../../utils/title_normalizer.dart';
import 'tv_catalog_card_grid.dart';

/// The rows of the Spring naar page. `#` holds everything that does not start
/// with a letter from A to Z, in the place the sort puts digits.
const List<String> tvCatalogJumpLetters = [
  '#',
  'A',
  'B',
  'C',
  'D',
  'E',
  'F',
  'G',
  'H',
  'I',
  'J',
  'K',
  'L',
  'M',
  'N',
  'O',
  'P',
  'Q',
  'R',
  'S',
  'T',
  'U',
  'V',
  'W',
  'X',
  'Y',
  'Z',
];

/// Which row of [tvCatalogJumpLetters] a title belongs to.
String tvCatalogJumpLetterOf(MediaItem item) {
  final title = normalizeTitleForMatching(item.titleSort ?? item.title);
  if (title.isEmpty) return '#';
  final first = title[0].toUpperCase();
  return tvCatalogJumpLetters.contains(first) ? first : '#';
}

/// The index in [letters] to land on for [target], or null while the answer can
/// still be further on.
///
/// [complete] says nothing more will load. Then a letter past everything lands
/// on the last card rather than nowhere.
int? tvCatalogJumpIndex(List<String> letters, String target, {required bool descending, required bool complete}) {
  final exact = letters.indexOf(target);
  if (exact >= 0) return exact;
  final rank = tvCatalogJumpLetters.indexOf(target);
  final past = letters.indexWhere((letter) {
    final other = tvCatalogJumpLetters.indexOf(letter);
    return descending ? other < rank : other > rank;
  });
  if (past >= 0) return past;
  return complete && letters.isNotEmpty ? letters.length - 1 : null;
}

/// The group to land on for [letter], loading further pages until it is known.
///
/// Bounded by [limit], the grid's own eager limit by default: a card past it is
/// not in the tree yet. A round that adds nothing ends the search on what there
/// is, so a source that stopped answering cannot keep this waiting.
Future<String?> tvCatalogJumpTarget(
  UnifiedCatalogProvider catalog,
  String letter, {
  required bool descending,
  int limit = TvCatalogCardGrid.eagerLoadLimit,
}) async {
  var seen = -1;
  while (true) {
    final snapshot = catalog.snapshot;
    final groups = snapshot.groups;
    final index = tvCatalogJumpIndex(
      [for (final group in groups) tvCatalogJumpLetterOf(group.representativeSource.item)],
      letter,
      descending: descending,
      complete: !snapshot.hasMore || groups.length >= limit,
    );
    if (index != null) return groups[index].groupId;
    if (catalog.isLoadingMore) {
      await _nextChange(catalog);
      continue;
    }
    if (groups.length == seen) return groups.lastOrNull?.groupId;
    seen = groups.length;
    await catalog.loadMore();
  }
}

/// The grid's eager loading may hold the round this search needs.
Future<void> _nextChange(UnifiedCatalogProvider catalog) {
  final done = Completer<void>();
  void listener() {
    if (done.isCompleted) return;
    catalog.removeListener(listener);
    done.complete();
  }

  catalog.addListener(listener);
  return done.future;
}
