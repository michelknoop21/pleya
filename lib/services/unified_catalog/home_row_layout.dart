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

import '../../media/media_hub.dart';
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
            if (!homeLayoutIdsOf(row).every(hiddenRowIds.contains)) row,
        ];

  if (order.isEmpty) return visible;

  final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
  int rankOf(UnifiedMediaHub row) {
    var best = order.length;
    for (final id in homeLayoutIdsOf(row)) {
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
///
/// Public because the customise panel writes the order back through it: a row's
/// position in the list has to become *every* id it answers to, or a merged
/// row's rank stops matching where the viewer put it.
List<String> homeLayoutIdsOf(UnifiedMediaHub row) =>
    row.contributingRowIds.isEmpty ? [row.hubId] : row.contributingRowIds;

/// Moves the row at [index] in [rows] (already in display order) by [delta]
/// and returns the order to store (HOME-R1).
///
/// Two things the plain "write every row's ids" got wrong:
///
/// * **Rows that share a layout id move as one block.** One server can hand
///   out two hubs with one identifier (Plex gives every movie library its own
///   `movie.recentlyadded`), so two panel rows answer to the same id and
///   [applyHomeLayoutToUnifiedRows] can only rank them together. A row placed
///   between them was written as `[X, own, X]`, the rank map kept the last
///   `X`, and the own row snapped straight back: "move down" did nothing, on
///   every press. Treating adjacent rows that share an id as one block, and
///   writing each id once, makes every press land where the panel shows it.
/// * **Ids the panel cannot see keep their place.** A row of a server that is
///   offline, or an own row still loading, is not in [rows]. Writing only what
///   is on screen dropped it from the order, and it came back at the bottom.
///   Every id of [previous] that is not on screen is kept, right after the id
///   that preceded it there.
///
/// Returns null when the move falls outside the list.
List<String>? homeLayoutOrderAfterMove(
  List<UnifiedMediaHub> rows,
  int index,
  int delta, {
  required List<String> previous,
}) {
  if (index < 0 || index >= rows.length) return null;
  final blocks = <List<UnifiedMediaHub>>[];
  var blockIds = <String>{};
  var from = -1;
  for (var i = 0; i < rows.length; i++) {
    final ids = homeLayoutIdsOf(rows[i]);
    if (blocks.isNotEmpty && ids.any(blockIds.contains)) {
      blocks.last.add(rows[i]);
      blockIds.addAll(ids);
    } else {
      blocks.add([rows[i]]);
      blockIds = {...ids};
    }
    if (i == index) from = blocks.length - 1;
  }
  final to = from + delta;
  if (delta == 0 || to < 0 || to >= blocks.length) return null;
  blocks.insert(to, blocks.removeAt(from));

  final seen = <String>{};
  final next = [
    for (final block in blocks)
      for (final row in block)
        for (final id in homeLayoutIdsOf(row))
          if (seen.add(id)) id,
  ];
  String? anchor;
  for (final id in previous) {
    if (!seen.add(id)) {
      if (next.contains(id)) anchor = id;
      continue;
    }
    next.insert(anchor == null ? 0 : next.indexOf(anchor) + 1, id);
    anchor = id;
  }
  return next;
}

/// A viewer-defined Home row's projected content (ROW1b), in the [MediaHub]
/// shape the phone/desktop feed and the settings screen already draw.
///
/// [row]'s own contributing id (its `HomeCustomRow.layoutRowId`, e.g.
/// `#custom:<id>`) becomes the hub's [MediaHub.identifier], not a synthesized
/// title or [UnifiedMediaHub.hubId]. That is what lets `homeRowId` resolve it
/// back to the same id `HomeLayoutProvider` already stores hide/order
/// preferences against, rather than wrapping it in the `serverId:identifier`
/// shape a real backend hub uses.
MediaHub mediaHubFromCustomRow(UnifiedMediaHub row) => MediaHub(
  id: row.hubId,
  identifier: row.contributingRowIds.isNotEmpty ? row.contributingRowIds.first : row.hubId,
  title: row.title,
  type: row.kind.name,
  items: [for (final group in row.groups) group.representativeSource.item],
  size: row.groups.length,
);
