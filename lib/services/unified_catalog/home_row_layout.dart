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
/// A synthesized row has no contributing hub ids, so it answers for itself:
/// its own [UnifiedMediaHub.hubId] is its name in the layout space. That is
/// what makes Recent uitgebracht orderable and hideable alongside the backend
/// rows (DEC-100 (4) locks exactly two rows, Uitgelicht and Verder kijken, and
/// Recent uitgebracht is not one of them), and what lets a row the viewer
/// defined take part in the same order list as everything else. A synthesized
/// row the stored layout has never seen still keeps its incoming position,
/// because an id absent from both lists ranks last and hides nothing.
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
            if (!_layoutIdsOf(row).every(hiddenRowIds.contains)) row,
        ];

  if (order.isEmpty) return visible;

  final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
  int rankOf(UnifiedMediaHub row) {
    var best = order.length;
    for (final id in _layoutIdsOf(row)) {
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

/// The names [row] answers to in `HomeLayoutProvider`'s id space.
///
/// The contributing hubs for a projected row, and the row's own id for a
/// synthesized one. Never empty, so "hidden when every name is hidden" cannot
/// be vacuously true — an empty list would make `every` return true and hide
/// every synthesized row the moment anything at all was hidden.
List<String> _layoutIdsOf(UnifiedMediaHub row) => row.contributingRowIds.isEmpty ? [row.hubId] : row.contributingRowIds;
