/// Fase 8 (hoofdstuk 17.5): the user's Home hide/reorder preferences, stored
/// against legacy `homeRowId`s, applied to *unified* rows.
///
/// The two asymmetries are the whole point, so they are asserted directly
/// rather than through a widget: a merged row survives until every contributor
/// is hidden, and it ranks by its earliest contributor.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_hub.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/providers/home_layout_provider.dart';
import 'package:pleya/services/unified_catalog/home_row_layout.dart';

UnifiedMediaHub _row(String id, {List<String> contributors = const []}) => UnifiedMediaHub(
  hubId: id,
  title: id,
  kind: UnifiedHubKind.movie,
  groups: const [],
  contributingRowIds: contributors,
);

List<String> _ids(List<UnifiedMediaHub> rows) => [for (final r in rows) r.hubId];

MediaItem _item(String id, String serverId) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: id, serverId: serverId);

UnifiedMediaGroup _group(String id, String serverId) {
  final source = UnifiedMediaSource.fromItem(_item(id, serverId));
  return UnifiedMediaGroup(
    groupId: id,
    identity: CanonicalMediaIdentity.movie(title: id, year: 2021),
    sources: [source],
    representativeSourceKey: source.sourceKey,
    watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey, isWatched: false),
  );
}

void main() {
  test('no preferences leaves the projection order untouched', () {
    final rows = [
      _row('a', contributors: ['s1:a']),
      _row('b', contributors: ['s1:b']),
    ];
    expect(
      identical(applyHomeLayoutToUnifiedRows(rows, hiddenRowIds: const {}, order: const []), rows),
      isTrue,
      reason: 'the empty case must not even allocate a new list',
    );
  });

  test('a single-contributor row hides when its own legacy id is hidden', () {
    final rows = [
      _row('a', contributors: ['s1:a']),
      _row('b', contributors: ['s1:b']),
    ];
    expect(_ids(applyHomeLayoutToUnifiedRows(rows, hiddenRowIds: {'s1:a'}, order: const [])), ['b']);
  });

  test('a merged row survives while any contributor is still visible', () {
    // The asymmetry that matters: the viewer switched off the NAS copy of
    // "Recently Added". The merged row still carries the attic server's
    // titles, and dropping it would remove content from a server they never
    // touched.
    final rows = [
      _row('merged', contributors: ['nas:recently-added', 'attic:recently-added']),
    ];
    expect(_ids(applyHomeLayoutToUnifiedRows(rows, hiddenRowIds: {'nas:recently-added'}, order: const [])), ['merged']);
  });

  test('a merged row hides only when every contributor is hidden', () {
    final rows = [
      _row('merged', contributors: ['nas:recently-added', 'attic:recently-added']),
    ];
    expect(
      applyHomeLayoutToUnifiedRows(rows, hiddenRowIds: {'nas:recently-added', 'attic:recently-added'}, order: const []),
      isEmpty,
    );
  });

  test('a synthesized row survives a hidden set that does not name it', () {
    // The guard against a vacuous `every`: a row with no contributors answers
    // for itself, so an empty contributor list must never make "all of its ids
    // are hidden" trivially true.
    final rows = [_row('pleya:home:continue-watching')];
    expect(_ids(applyHomeLayoutToUnifiedRows(rows, hiddenRowIds: {'s1:a', 's1:b'}, order: const [])), [
      'pleya:home:continue-watching',
    ]);
  });

  test('a contributorless row answers to its own hub id', () {
    // The fallback half of [homeLayoutIdsOf]. Every row Home actually draws
    // states its layout ids — a projected hub carries its contributors, and a
    // row the viewer defined carries `#custom:<id>` — so this is the guard for
    // a synthesized row that states none, not the mechanism ROW1 relies on.
    final rows = [_row('hub:pleya:one'), _row('hub:pleya:two')];
    expect(_ids(applyHomeLayoutToUnifiedRows(rows, hiddenRowIds: {'hub:pleya:one'}, order: const [])), [
      'hub:pleya:two',
    ]);
    expect(_ids(applyHomeLayoutToUnifiedRows(rows, hiddenRowIds: const {}, order: const ['hub:pleya:two'])), [
      'hub:pleya:two',
      'hub:pleya:one',
    ]);
  });

  test('Recent uitgebracht and an own row take part like any other row', () {
    // ROW1/DEC-100 (4): only Uitgelicht and Verder kijken are fixed, and they
    // are fixed by never reaching this function.
    final rows = [
      _row('latest', contributors: [':pleya:home:latest-movies']),
      _row('a', contributors: ['s1:a']),
      _row('own', contributors: ['#custom:r1']),
    ];
    expect(
      _ids(
        applyHomeLayoutToUnifiedRows(
          rows,
          hiddenRowIds: const {'s1:a'},
          order: const ['#custom:r1', ':pleya:home:latest-movies'],
        ),
      ),
      ['own', 'latest'],
    );
  });

  test('rows sort by the stored order, unknown rows keeping their place at the end', () {
    final rows = [
      _row('a', contributors: ['s1:a']),
      _row('b', contributors: ['s1:b']),
      _row('new', contributors: ['s1:new']),
      _row('c', contributors: ['s1:c']),
    ];
    final out = applyHomeLayoutToUnifiedRows(rows, hiddenRowIds: const {}, order: ['s1:c', 's1:a', 's1:b']);
    expect(_ids(out), ['c', 'a', 'b', 'new']);
  });

  test('a merged row ranks by its earliest contributor, not its latest', () {
    // The viewer dragged "Recently Added" to the top and left "Top Picks"
    // third. The merge of the two belongs where the earliest of them was —
    // ranking by the later one would push it under rows they had deliberately
    // placed beneath it.
    final rows = [
      _row('other', contributors: ['s1:other']),
      _row('merged', contributors: ['s1:top-picks', 's1:recently-added']),
    ];
    final out = applyHomeLayoutToUnifiedRows(
      rows,
      hiddenRowIds: const {},
      order: ['s1:recently-added', 's1:other', 's1:top-picks'],
    );
    expect(_ids(out), ['merged', 'other']);
  });

  test('the sort is stable for rows the stored order has never seen', () {
    final rows = [_row('x'), _row('y'), _row('z')];
    expect(_ids(applyHomeLayoutToUnifiedRows(rows, hiddenRowIds: const {}, order: ['s1:unrelated'])), ['x', 'y', 'z']);
  });

  group('mediaHubFromCustomRow (ROW1b)', () {
    test('the legacy identifier is the row\'s own contributing id, not its hubId', () {
      final row = UnifiedMediaHub(
        hubId: 'hub:pleya:custom:abc',
        title: 'Sci-fi',
        kind: UnifiedHubKind.movie,
        groups: [_group('m1', 's1')],
        contributingRowIds: const ['#custom:abc'],
      );
      final hub = mediaHubFromCustomRow(row);

      expect(hub.identifier, '#custom:abc');
      // The point of the fix: without it, `homeRowId` would wrap this in
      // `serverId:identifier` and produce `:#custom:abc`, a different id than
      // the one `HomeLayoutProvider.saveCustomRow`/`removeCustomRow` already
      // store hide/order preferences against.
      expect(homeRowId(hub), '#custom:abc');
    });

    test('falls back to hubId when a row somehow carries no contributing id', () {
      final row = UnifiedMediaHub(
        hubId: 'hub:pleya:custom:abc',
        title: 'Sci-fi',
        kind: UnifiedHubKind.movie,
        groups: const [],
      );
      expect(mediaHubFromCustomRow(row).identifier, 'hub:pleya:custom:abc');
    });

    test('each group\'s representative item becomes one MediaHub item, in order', () {
      final row = UnifiedMediaHub(
        hubId: 'hub:pleya:custom:abc',
        title: 'Sci-fi',
        kind: UnifiedHubKind.movie,
        groups: [_group('m1', 's1'), _group('m2', 's1')],
        contributingRowIds: const ['#custom:abc'],
      );
      final hub = mediaHubFromCustomRow(row);

      expect(hub.title, 'Sci-fi');
      expect(hub.size, 2);
      expect(hub.items.map((i) => i.id), ['m1', 'm2']);
    });
  });
}
