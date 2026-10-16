/// HOME-R1: a row merged from two servers is one line that answers to every
/// contributing id (DEC-145). It says what it is made of, hides on all of its
/// ids and moves with all of them (iPhone list). Fake projection, real layout.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_hub.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/home_layout_provider.dart';
import 'package:pleya/providers/tv_home_projection_provider.dart';
import 'package:pleya/screens/home/customize/home_customize_row_tile.dart';
import 'package:pleya/screens/home/customize/home_customize_screen.dart';
import 'package:pleya/services/unified_catalog/home_layout_entries.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:provider/provider.dart';

import '../../../test_helpers/home_rows_harness.dart';
import '../../../test_helpers/prefs.dart';
import 'home_customize_screen_test.dart' show settle;

MediaItem _item(String id, String server, String serverName) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.show,
  title: id,
  serverId: server,
  serverName: serverName,
);

/// One show present on both servers: a merged group with two sources.
UnifiedMediaGroup _mergedGroup() {
  final a = UnifiedMediaSource.fromItem(_item('s1', 'plex', 'Plex Familie'));
  final b = UnifiedMediaSource.fromItem(_item('s1', 'jf', 'Jellyfin NAS'));
  return UnifiedMediaGroup(
    groupId: 'g1',
    identity: CanonicalMediaIdentity.movie(title: 's1', year: 2020),
    sources: [a, b],
    representativeSourceKey: a.sourceKey,
    watchState: UnifiedWatchState(representativeSourceKey: a.sourceKey, isWatched: false),
  );
}

class _Projection extends ChangeNotifier implements TvHomeProjectionProvider {
  @override
  UnifiedMediaHub? get latestMovies => null;

  @override
  List<UnifiedMediaGroup> get heroGroups => const [];

  @override
  UnifiedMediaHub? get continueWatching => null;

  @override
  List<UnifiedMediaHub> get hubs => [
    UnifiedMediaHub(
      hubId: 'merged',
      title: 'Recent toegevoegde series',
      kind: UnifiedHubKind.show,
      groups: [_mergedGroup()],
      contributingRowIds: const ['plex:recent', 'jf:recent'],
    ),
    UnifiedMediaHub(
      hubId: 'top',
      title: 'Top Picks',
      kind: UnifiedHubKind.movie,
      groups: const [],
      contributingRowIds: const ['plex:top'],
      serverName: 'Plex Familie',
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Discover extends ChangeNotifier implements DiscoverProvider {
  @override
  List<MediaItem> get latestMovies => const [];

  @override
  List<MediaItem> get onDeck => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late HomeLayoutProvider layout;
  late _Projection projection;

  Future<void> pump(WidgetTester tester) async {
    resetSharedPreferencesForTest();
    LocaleSettings.setLocaleSync(AppLocale.en);
    layout = (await tester.runAsync(() async {
      final provider = HomeLayoutProvider();
      await provider.ensureInitialized();
      return provider;
    }))!;
    addTearDown(layout.dispose);
    projection = _Projection();
    addTearDown(projection.dispose);
    final discover = _Discover();
    addTearDown(discover.dispose);
    installHomeRowEditingStub();
    addTearDown(uninstallHomeRowEditingStub);
    tester.view.physicalSize = HomeTestDevice.phone.size;
    tester.view.devicePixelRatio = HomeTestDevice.phone.pixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<HomeLayoutProvider>.value(value: layout),
          ChangeNotifierProvider<TvHomeProjectionProvider>.value(value: projection),
          ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(dark: true).copyWith(platform: TargetPlatform.iOS),
            home: const HomeCustomizeScreen(),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Finder rowOf(String title) => find.ancestor(of: find.text(title), matching: find.byType(HomeCustomizeRowTile)).first;

  testWidgets('a merged row names its sources and counts them', (tester) async {
    await pump(tester);
    final home = t.unifiedCatalog.homeRows;
    expect(find.text('Recent toegevoegde series'), findsOneWidget, reason: 'one line, not one per server');
    expect(find.text('${home.sourcesCount(count: 2)} · Plex Familie · Jellyfin NAS'), findsOneWidget);
  });

  testWidgets('hiding a merged row hides every contributing id', (tester) async {
    await pump(tester);
    await tester.tap(
      find.descendant(of: rowOf('Recent toegevoegde series'), matching: find.byIcon(Symbols.visibility_rounded)),
    );
    await settle(tester);
    expect(layout.isRowHidden('plex:recent'), isTrue);
    expect(layout.isRowHidden('jf:recent'), isTrue);
    expect(layout.isRowHidden('plex:top'), isFalse);
  });

  test('NEGATIVE CONTROL: hiding only the first id would leave the merged row on Home', () async {
    resetSharedPreferencesForTest();
    final provider = HomeLayoutProvider();
    await provider.ensureInitialized();
    addTearDown(provider.dispose);
    await provider.setRowHidden('plex:recent', true);
    final hidden = provider.hiddenRowIds;
    // Home drops a merged row only when every contributor is hidden.
    expect(['plex:recent', 'jf:recent'].every(hidden.contains), isFalse);
  });

  testWidgets('moving a merged row writes both ids next to each other', (tester) async {
    await pump(tester);
    final entries = homeLayoutEntries(layout: layout, projection: projection);
    final next = homeLayoutEntriesAfterMove(entries, 0, 1, previous: layout.order)!;
    expect(next, ['plex:top', 'plex:recent', 'jf:recent']);
  });

  testWidgets('the kind of each line: merged and server row', (tester) async {
    await pump(tester);
    final entries = homeLayoutEntries(layout: layout, projection: projection);
    expect(entries[0].kind, HomeLayoutEntryKind.mergedRow);
    expect(entries[0].sourceNames, ['Plex Familie', 'Jellyfin NAS']);
    expect(entries[1].kind, HomeLayoutEntryKind.serverRow);
  });
}
