/// The rows "Home aanpassen" lists, as plain data (HOME-R1, plan BP-12a).
///
/// One function answers "which rows can the viewer move, hide, edit or delete,
/// in what order, and under which ids", for every surface that needs it: the
/// phone/tablet/desktop customise screen, the Instellingen tile that opens the
/// same screen, the TV panel and, later, Big P. A surface that derived the list
/// itself would put a merged row in one place and let the next one split it.
///
/// ## Two lists, because Home itself draws two
///
/// * **Unified** (iPhone and TV, DEC-145): one entry per unified row, so a row
///   merged from two servers is one line that answers to every contributing id.
///   Selected by passing [projection].
/// * **Per backend hub** (iPad and Mac, DEC-103): one entry per server hub, plus
///   the viewer's own rows and Kijklijst, and no Recent uitgebracht or Nu op tv
///   because that Home draws neither. Rows that share an identity (several
///   "Because you watched") are one entry, which moves and hides as one block.
///
/// The edit list must be the list Home draws, or a row moves to a place Home
/// then puts somewhere else.
///
/// ## Identity
///
/// An own row's id is `#custom:<id>` here and nowhere else. `hub:pleya:custom:<id>`
/// is the same row in the projection's own space; writing it into the layout
/// is the bug `removeCustomRow` cannot clean up (ROW1), so [HomeLayoutEntry.ids]
/// never carries it.
library;

import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import '../../media/unified/unified_media_hub.dart';
import '../../providers/home_custom_rows_provider.dart';
import '../../providers/home_extra_rows_provider.dart';
import '../../providers/home_layout_provider.dart';
import '../../providers/tv_home_projection_provider.dart';
import '../../utils/home_custom_row_labels.dart';
import '../../widgets/tv/tv_home_row_assembly.dart';
import 'home_custom_row.dart';
import 'home_row_layout.dart';

/// What a row is, which decides what the viewer may do with it.
enum HomeLayoutEntryKind {
  /// A row the viewer defined: can be edited and deleted.
  ownRow,

  /// A row Pleya adds itself (Recent uitgebracht, Kijklijst, Nu op tv).
  pleyaRow,

  /// One row merged from several servers.
  mergedRow,

  /// A hub of one server.
  serverRow,
}

class HomeLayoutEntry {
  const HomeLayoutEntry({
    required this.title,
    required this.ids,
    required this.kind,
    this.serverName,
    this.customRowId,
    this.optIn = false,
    this.mediaType,
    this.posters = const [],
    this.sourceNames = const [],
  });

  final String title;

  /// Every id the row answers to in `HomeLayoutProvider`'s space. Never empty.
  /// Hiding writes all of them, moving writes all of them next to each other.
  final List<String> ids;

  final HomeLayoutEntryKind kind;

  /// Only when the row genuinely belongs to one server.
  final String? serverName;

  /// The [HomeCustomRow.id] of an own row.
  final String? customRowId;

  /// Off until the viewer turns it on (Nu op tv).
  final bool optIn;

  /// `movie`, `show` or null when the row is neither.
  final String? mediaType;

  /// Up to three items, for the thumbnails.
  final List<MediaItem> posters;

  /// The servers a merged row draws on.
  final List<String> sourceNames;

  bool get isOwn => customRowId != null;
}

const int _kPosterCount = 3;

/// The rows the viewer can arrange, in display order, hidden and empty ones
/// included (a row you cannot see is a row you cannot bring back).
///
/// [projection] non-null means the unified list; otherwise the per-hub list is
/// built from [backendHubs] (`DiscoverProvider.hubs`).
List<HomeLayoutEntry> homeLayoutEntries({
  required HomeLayoutProvider layout,
  HomeCustomRowsProvider? customRows,
  HomeExtraRowsProvider? extraRows,
  TvHomeProjectionProvider? projection,
  List<MediaHub> backendHubs = const [],
}) => projection != null
    ? _unifiedEntries(layout, customRows, extraRows, projection)
    : _hubEntries(layout, customRows, extraRows, backendHubs);

List<HomeLayoutEntry> _unifiedEntries(
  HomeLayoutProvider layout,
  HomeCustomRowsProvider? customRows,
  HomeExtraRowsProvider? extraRows,
  TvHomeProjectionProvider projection,
) {
  final rows = tvHomeOrderableRows(
    projection: projection,
    layout: layout,
    customRows: customRows,
    extraRows: extraRows,
    includeHidden: true,
    includeEmpty: true,
  );
  final entries = <HomeLayoutEntry>[];
  final listed = <String>{};
  for (final row in rows) {
    final custom = _customRowOf(layout, row);
    if (custom != null) listed.add(custom.id);
    entries.add(_unifiedEntry(row, custom));
  }
  // A saved row whose content has not been asked yet has no projected row, but
  // it exists and must be reachable: it goes in front, where a new row lands.
  final pending = [
    for (final custom in layout.customRows)
      if (!listed.contains(custom.id))
        HomeLayoutEntry(
          title: homeCustomRowLabel(custom),
          ids: [custom.layoutRowId],
          kind: HomeLayoutEntryKind.ownRow,
          customRowId: custom.id,
          mediaType: custom.kind.id == 'movie' ? 'movie' : 'show',
        ),
  ];
  return [...pending, ...entries];
}

HomeCustomRow? _customRowOf(HomeLayoutProvider layout, UnifiedMediaHub row) {
  for (final custom in layout.customRows) {
    if (UnifiedMediaHub.synthesizedHubId(custom.hubSlug) == row.hubId) return custom;
  }
  return null;
}

HomeLayoutEntry _unifiedEntry(UnifiedMediaHub row, HomeCustomRow? custom) {
  final posters = [for (final group in row.groups.take(_kPosterCount)) group.representativeSource.item];
  final mediaType = switch (row.kind) {
    UnifiedHubKind.movie => 'movie',
    UnifiedHubKind.show || UnifiedHubKind.episode => 'show',
    _ => null,
  };
  if (custom != null) {
    return HomeLayoutEntry(
      title: row.title,
      // The layout's own name for the row, never the projection's.
      ids: [custom.layoutRowId],
      kind: HomeLayoutEntryKind.ownRow,
      customRowId: custom.id,
      mediaType: mediaType,
      posters: posters,
    );
  }
  final ids = homeLayoutIdsOf(row);
  final optIn = ids.contains(homeLiveTvRowId);
  final isPleya = row.contributingRowIds.isEmpty || ids.every(_isPleyaId);
  if (isPleya) {
    return HomeLayoutEntry(
      title: row.title,
      ids: ids,
      kind: HomeLayoutEntryKind.pleyaRow,
      optIn: optIn,
      mediaType: mediaType,
      posters: posters,
    );
  }
  if (row.isServerSpecific) {
    return HomeLayoutEntry(
      title: row.title,
      ids: ids,
      kind: HomeLayoutEntryKind.serverRow,
      serverName: row.serverName,
      mediaType: mediaType,
      posters: posters,
    );
  }
  final names = <String>[];
  for (final group in row.groups) {
    for (final source in group.sources) {
      if (!names.contains(source.serverName)) names.add(source.serverName);
    }
  }
  return HomeLayoutEntry(
    title: row.title,
    ids: ids,
    // One source is just a server row whose name the global titles leave off
    // (hoofdstuk 17.5); only two or more are a merge.
    kind: names.length > 1 ? HomeLayoutEntryKind.mergedRow : HomeLayoutEntryKind.serverRow,
    mediaType: mediaType,
    posters: posters,
    sourceNames: names,
  );
}

bool _isPleyaId(String id) => id.startsWith('#pleya:') || id.startsWith(':pleya:');

List<HomeLayoutEntry> _hubEntries(
  HomeLayoutProvider layout,
  HomeCustomRowsProvider? customRows,
  HomeExtraRowsProvider? extraRows,
  List<MediaHub> backendHubs,
) {
  // ROW1b: rows the viewer defined take part in the same list, in front like
  // DiscoverScreen. `allRows`, not `visibleRows`: a row that has gone empty is
  // still something the viewer must be able to find here and turn back on.
  final own = [
    ...?customRows?.allRows(titleFor: homeCustomRowLabel),
    for (final row in extraRows?.allRows() ?? const <UnifiedMediaHub>[])
      if (!row.contributingRowIds.contains(homeLiveTvRowId)) row,
  ].map(mediaHubFromCustomRow).toList();
  final listedCustom = {
    for (final hub in own)
      if (hub.identifier != null && HomeCustomRow.isCustomLayoutRowId(hub.identifier!)) hub.identifier!,
  };
  final pending = [
    for (final custom in layout.customRows)
      if (!listedCustom.contains(custom.layoutRowId))
        MediaHub(
          id: custom.hubSlug,
          identifier: custom.layoutRowId,
          title: homeCustomRowLabel(custom),
          type: custom.kind.id,
          items: const [],
          size: 0,
        ),
  ];
  // One entry per row identity: duplicate identities (several "Because you
  // watched" rows) move and hide as one block.
  final byId = <String, MediaHub>{};
  for (final hub in layout.apply([...pending, ...own, ...backendHubs], homeRowId, dropHidden: false)) {
    byId.putIfAbsent(homeRowId(hub), () => hub);
  }
  return [for (final entry in byId.entries) _hubEntry(entry.key, entry.value)];
}

HomeLayoutEntry _hubEntry(String id, MediaHub hub) {
  final posters = hub.items.take(_kPosterCount).toList();
  if (HomeCustomRow.isCustomLayoutRowId(id)) {
    return HomeLayoutEntry(
      title: hub.title,
      ids: [id],
      kind: HomeLayoutEntryKind.ownRow,
      customRowId: id.substring('#custom:'.length),
      mediaType: hub.type == 'movie' ? 'movie' : 'show',
      posters: posters,
    );
  }
  if (_isPleyaId(id)) {
    return HomeLayoutEntry(
      title: hub.title,
      ids: [id],
      kind: HomeLayoutEntryKind.pleyaRow,
      optIn: id == homeLiveTvRowId,
      mediaType: hub.type == 'movie' ? 'movie' : null,
      posters: posters,
    );
  }
  return HomeLayoutEntry(
    title: hub.title,
    ids: [id],
    kind: HomeLayoutEntryKind.serverRow,
    serverName: hub.serverName,
    mediaType: hub.type,
    posters: posters,
  );
}

/// The unified rows [homeLayoutOrderAfterMove] works on, without content: the
/// move rule only reads a row's layout ids, so the customise screen reuses it
/// for both lists instead of keeping a second copy (HOME-R1).
List<UnifiedMediaHub> _stubRows(List<HomeLayoutEntry> entries) => [
  for (var i = 0; i < entries.length; i++)
    UnifiedMediaHub(
      hubId: 'entry:$i',
      title: entries[i].title,
      kind: UnifiedHubKind.other,
      groups: const [],
      contributingRowIds: entries[i].ids,
    ),
];

/// The order to store after dragging [entries]`[from]` to row index [to] (the
/// index `onReorderItem` reports, i.e. after the dragged row was taken out).
/// Built from single moves of [homeLayoutOrderAfterMove], so twin rows that
/// share an id keep moving as one block there too. Null when nothing moves.
List<String>? homeLayoutEntriesAfterReorder(
  List<HomeLayoutEntry> entries,
  int from,
  int to, {
  required List<String> previous,
}) {
  if (from == to || from < 0 || to < 0 || from >= entries.length || to >= entries.length) return null;
  final rows = _stubRows(entries);
  final moving = rows[from].hubId;
  final direction = to > from ? 1 : -1;
  var order = previous;
  var index = from;
  var moved = false;
  // Each step moves a block by one block, so the loop ends when the row has
  // reached or passed [to], or cannot move on.
  for (var guard = 0; guard < rows.length && (direction > 0 ? index < to : index > to); guard++) {
    final next = homeLayoutOrderAfterMove(rows, index, direction, previous: order);
    if (next == null) break;
    order = next;
    moved = true;
    final ranked = applyHomeLayoutToUnifiedRows(rows, hiddenRowIds: const {}, order: order);
    rows
      ..clear()
      ..addAll(ranked);
    index = rows.indexWhere((row) => row.hubId == moving);
  }
  return moved ? order : null;
}
