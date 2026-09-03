/// Hoofdstuk 17.5 of docs/tvos-unified-experience.md: "De bestaande
/// hide/reorder-logica blijft werken op stabiele unified row IDs."
///
/// `HomeLayoutProvider` stores its preferences against the *legacy* row ids —
/// `'serverId:identifier'`, one per concrete `MediaHub` — because that is what
/// existed when a user hid a row. A fase-8 Home row is a [UnifiedMediaHub],
/// which can be one such hub or the merge of several, so the mapping is not
/// one-to-one and `HomeLayoutProvider.apply`'s single `idOf` cannot express it.
///
/// Two rules, and both are asymmetric on purpose:
///
/// * **Hidden only when every contributor is hidden.** A merged row that draws
///   on the NAS and the attic server, of which the user hid only the NAS copy,
///   still carries the attic's titles. Dropping it would remove content from a
///   server the user never switched off — the same "false certainty" hoofdstuk
///   21 forbids elsewhere, applied to a preference instead of to a failure.
/// * **Ranked by its best contributor.** A merged row appears as early as the
///   earliest row the user dragged it from. Ranking by the *last* would push a
///   merge below rows the user had deliberately placed under one of its halves.
///
/// A row with no contributing ids at all — the synthesized Continue Watching
/// and recent-films rows — is never hidden and never ranked; it keeps its
/// incoming position, which is the position the projection provider gave it.
///
/// Pure, and top-level rather than a method on the provider, because it is the
/// product rule and not the storage: `test/services/home_row_layout_test.dart`
/// asserts it against sets and lists, with no provider and no widget.
library;

import '../../media/unified/unified_media_hub.dart';

/// Applies [hiddenRowIds] and [order] — both in `HomeLayoutProvider`'s legacy
/// `homeRowId` space — to already-projected unified [rows].
List<UnifiedMediaHub> applyHomeLayoutToUnifiedRows(
  List<UnifiedMediaHub> rows, {
  required Set<String> hiddenRowIds,
  required List<String> order,
}) {
  if (hiddenRowIds.isEmpty && order.isEmpty) return rows;

  final visible = hiddenRowIds.isEmpty
      ? List.of(rows)
      : [
          for (final row in rows)
            if (row.contributingRowIds.isEmpty || !row.contributingRowIds.every(hiddenRowIds.contains)) row,
        ];

  if (order.isEmpty) return visible;

  final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
  int rankOf(UnifiedMediaHub row) {
    var best = order.length;
    for (final id in row.contributingRowIds) {
      final r = rank[id];
      if (r != null && r < best) best = r;
    }
    return best;
  }

  // Stable: rows that share a rank — and every row the stored order has never
  // seen, which all rank `order.length` — keep the projection's own order
  // rather than being reshuffled by the sort.
  final indexed = [for (var i = 0; i < visible.length; i++) (visible[i], rankOf(visible[i]), i)];
  indexed.sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$3.compareTo(b.$3));
  return [for (final e in indexed) e.$1];
}
