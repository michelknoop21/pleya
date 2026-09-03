/// Fase 8 (hoofdstuk 17.5): the user's Home hide/reorder preferences, stored
/// against legacy `homeRowId`s, applied to *unified* rows.
///
/// The two asymmetries are the whole point, so they are asserted directly
/// rather than through a widget: a merged row survives until every contributor
/// is hidden, and it ranks by its earliest contributor.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/unified/unified_media_hub.dart';
import 'package:pleya/services/unified_catalog/home_row_layout.dart';

UnifiedMediaHub _row(String id, {List<String> contributors = const []}) => UnifiedMediaHub(
  hubId: id,
  title: id,
  kind: UnifiedHubKind.movie,
  groups: const [],
  contributingRowIds: contributors,
);

List<String> _ids(List<UnifiedMediaHub> rows) => [for (final r in rows) r.hubId];

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

  test('a synthesized row with no contributors is never hidden', () {
    // Continue Watching and Recently Released: they were never in the settings
    // screen's list, so no stored preference can name them, and a hidden-set
    // membership test against an empty contributor list must not drop them.
    final rows = [_row('pleya:home:continue-watching')];
    expect(_ids(applyHomeLayoutToUnifiedRows(rows, hiddenRowIds: {'s1:a', 's1:b'}, order: const [])), [
      'pleya:home:continue-watching',
    ]);
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
}
