import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/providers/home_layout_provider.dart';

import '../test_helpers/prefs.dart';

MediaHub _hub(String identifier) =>
    MediaHub(id: identifier, identifier: identifier, title: identifier, type: 'mixed', items: const []);

List<String> _ids(List<MediaHub> hubs) => hubs.map(homeRowId).toList();

void main() {
  setUp(resetSharedPreferencesForTest);

  group('HomeLayoutProvider.apply', () {
    final hubs = [_hub('a'), _hub('b'), _hub('c')];

    test('no layout stored leaves the list untouched', () async {
      final p = HomeLayoutProvider();
      await p.ensureInitialized();
      expect(_ids(p.apply(hubs, homeRowId)), [':a', ':b', ':c']);
      p.dispose();
    });

    test('hidden rows are dropped, and kept when dropHidden is false', () async {
      final p = HomeLayoutProvider();
      await p.ensureInitialized();
      await p.setRowHidden(':b', true);
      expect(_ids(p.apply(hubs, homeRowId)), [':a', ':c']);
      expect(_ids(p.apply(hubs, homeRowId, dropHidden: false)), [':a', ':b', ':c']);
      p.dispose();
    });

    test('stored order wins; unknown rows keep relative order at the end', () async {
      final p = HomeLayoutProvider();
      await p.ensureInitialized();
      await p.setOrder([':c', ':a']);
      final withNew = [...hubs, _hub('d')];
      expect(_ids(p.apply(withNew, homeRowId)), [':c', ':a', ':b', ':d']);
      p.dispose();
    });

    test('layout survives a reload from storage', () async {
      final p = HomeLayoutProvider();
      await p.ensureInitialized();
      await p.setOrder([':c', ':b', ':a']);
      await p.setRowHidden(':b', true);
      p.dispose();

      final reloaded = HomeLayoutProvider();
      await reloaded.ensureInitialized();
      expect(_ids(reloaded.apply(hubs, homeRowId)), [':c', ':a']);
      reloaded.dispose();
    });

    test('one hidden because-you-watched id hides every seed row of that server', () async {
      final p = HomeLayoutProvider();
      await p.ensureInitialized();
      final seedA = MediaHub(
        id: 'a',
        identifier: 'home.becauseyouwatched',
        title: 'Because you watched A',
        type: 'mixed',
        items: const [],
        serverId: 's1',
      );
      final seedB = MediaHub(
        id: 'b',
        identifier: 'home.becauseyouwatched',
        title: "Because you're watching B",
        type: 'mixed',
        items: const [],
        serverId: 's1',
      );
      final other = MediaHub(
        id: 'c',
        identifier: 'home.toppicks',
        title: 'Top Picks',
        type: 'mixed',
        items: const [],
        serverId: 's1',
      );
      await p.setRowHidden(homeRowId(seedA), true);

      final shown = p.apply([seedA, seedB, other], homeRowId);

      expect(shown.map((h) => h.id), ['c']);
      p.dispose();
    });
  });
}
