/// Zoeken on a phone — mockup `05-zoeken.png`, iOS Unified 2026 fase 4.
///
/// Geometry is asserted against boxes, never against rendered text: the test
/// font gives every glyph an em box, so a width measured here says nothing
/// about a device. Where the mockup's number is about text — the chip row —
/// the assertion is that the row scrolls rather than that it fits.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/models/seerr/seerr_media.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/search/mobile_search_body.dart';
import 'package:pleya/screens/search/search_failure.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/unified_catalog/search_projection.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/mobile/mobile_catalog_header.dart';
import 'package:pleya/widgets/mobile/mobile_search_results.dart';
import 'package:provider/provider.dart';

MediaItem _item({
  required MediaKind kind,
  required String id,
  required String title,
  String serverId = 's1',
  String? serverName,
  int? year,
  int? childCount,
}) {
  return MediaItem(
    id: id,
    backend: MediaBackend.plex,
    kind: kind,
    title: title,
    serverId: serverId,
    serverName: serverName ?? serverId,
    year: year,
    childCount: childCount,
  );
}

UnifiedMediaGroup _group(List<MediaItem> items) {
  final sources = items.map(UnifiedMediaSource.fromItem).toList();
  return UnifiedMediaGroup(
    groupId: 'g-${items.first.id}',
    identity: CanonicalMediaIdentity.movie(title: items.first.title, year: items.first.year),
    sources: sources,
    representativeSourceKey: sources.first.sourceKey,
    watchState: UnifiedWatchState(representativeSourceKey: sources.first.sourceKey),
  );
}

void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  late TextEditingController controller;
  late FocusNode focusNode;
  late MultiServerProvider multiServer;

  setUp(() {
    controller = TextEditingController();
    focusNode = FocusNode();
    final manager = MultiServerManager();
    multiServer = MultiServerProvider(manager, DataAggregationService(manager));
  });

  tearDown(() {
    controller.dispose();
    focusNode.dispose();
    multiServer.dispose();
  });

  final dune2 = _group([
    _item(kind: MediaKind.movie, id: 'm1', title: 'Dune: Part Two', year: 2024, serverId: 'nas'),
    _item(kind: MediaKind.movie, id: 'm1b', title: 'Dune: Part Two', year: 2024, serverId: 'plex'),
  ]);
  final dune1 = _group([_item(kind: MediaKind.movie, id: 'm2', title: 'Dune', year: 2021)]);
  final silo = _group([_item(kind: MediaKind.show, id: 'sh1', title: 'Silo', year: 2023, childCount: 2)]);

  Future<void> pump(
    WidgetTester tester, {
    UnifiedSearchProjection? projection,
    MediaKind? kindFilter,
    bool isBusy = false,
    bool hasSearched = true,
    SearchFailure? failure,
    MobileSearchRequests requests = const MobileSearchRequests(
      isConfigured: false,
      isSearching: false,
      hasSearched: false,
      results: [],
    ),
    List<String> history = const [],
    void Function(MediaKind?)? onFilterChanged,
    VoidCallback? onBack,
    VoidCallback? onSearchRequests,
    void Function(UnifiedMediaGroup)? onGroupTap,
    String Function(MediaItem)? serverNameFor,
  }) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: multiServer,
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: MobileSearchBody(
            controller: controller,
            focusNode: focusNode,
            status: MobileSearchStatus(
              isBusy: isBusy,
              hasSearched: hasSearched,
              failure: failure,
              projection: projection,
            ),
            requests: requests,
            kindFilter: kindFilter,
            onFilterChanged: onFilterChanged ?? (_) {},
            onBack: onBack ?? () {},
            onClear: () {},
            onRetry: () {},
            onSubmit: (_) {},
            history: history,
            onRunHistoryQuery: (_) {},
            onClearHistory: () {},
            onGroupTap: onGroupTap ?? (_) {},
            onItemTap: (_) {},
            serverNameFor: serverNameFor,
            onSearchRequests: onSearchRequests ?? () {},
            onOpenRequest: (_) {},
            onRequest: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('groups results per section, films before series — mockup 05', (tester) async {
    await pump(
      tester,
      projection: UnifiedSearchProjection(movies: [dune2, dune1], shows: [silo]),
    );

    expect(find.text('MOVIES'), findsOneWidget);
    expect(find.text('SHOWS'), findsOneWidget);
    expect(find.text('Dune: Part Two'), findsOneWidget);
    expect(find.text('Silo'), findsOneWidget);

    final films = tester.getTopLeft(find.text('MOVIES')).dy;
    final series = tester.getTopLeft(find.text('SHOWS')).dy;
    expect(films, lessThan(series));
  });

  testWidgets('a title on two servers is one row, with its source count behind it', (tester) async {
    await pump(tester, projection: UnifiedSearchProjection(movies: [dune2, dune1]));

    // Hoofdstuk 16.2: never `Dune - NAS` next to `Dune - Plex`.
    expect(find.text('Dune: Part Two'), findsOneWidget);
    expect(find.text('2 sources'), findsOneWidget);
  });

  testWidgets('one source says nothing at all', (tester) async {
    await pump(tester, projection: UnifiedSearchProjection(movies: [dune1]));

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('1 source'), findsNothing);
    expect(find.textContaining('source'), findsNothing);
  });

  testWidgets('a row carries the mockup geometry: 86 tall, 44×66 thumbnail, 16 inset', (tester) async {
    await pump(tester, projection: UnifiedSearchProjection(movies: [dune1]));

    final row = tester.getRect(find.byType(MobileSearchGroupRow));
    expect(row.height, MobileSearchMetrics.rowHeight);
    expect(row.left, MobileSearchMetrics.pageInset);
    expect(row.right, 393 - MobileSearchMetrics.pageInset);

    final poster = tester.getRect(find.byType(ClipRRect).first);
    expect(poster.width, MobileSearchMetrics.posterWidth);
    expect(poster.height, MobileSearchMetrics.posterHeight);
    // Vertically centred in the row, which is what the 10 points above and
    // below it in the mockup come to.
    expect(poster.center.dy, closeTo(row.center.dy, 0.5));
  });

  testWidgets('all four chips are drawn, including one with nothing behind it', (tester) async {
    // Mockup 05 draws Afleveringen next to a result set that has no episodes,
    // so the row is a fixed set of narrowings, not a summary of what came back.
    await pump(tester, projection: UnifiedSearchProjection(movies: [dune1]));

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Shows'), findsOneWidget);
    expect(find.text('Episodes'), findsOneWidget);
  });

  testWidgets('the chip row scrolls rather than overflowing', (tester) async {
    await pump(tester, projection: UnifiedSearchProjection(movies: [dune1]));

    expect(find.descendant(of: find.byType(SingleChildScrollView), matching: find.text('Episodes')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a chip narrows to its own section', (tester) async {
    await pump(
      tester,
      projection: UnifiedSearchProjection(movies: [dune1], shows: [silo]),
      kindFilter: MediaKind.show,
    );

    expect(find.text('SHOWS'), findsOneWidget);
    expect(find.text('MOVIES'), findsNothing);
    expect(find.text('Dune'), findsNothing);
  });

  testWidgets('collections and playlists show under All, and not under a kind chip', (tester) async {
    final collection = _item(kind: MediaKind.collection, id: 'c1', title: 'Dune Collection');
    final playlist = _item(kind: MediaKind.playlist, id: 'p1', title: 'Desert nights');

    await pump(
      tester,
      projection: UnifiedSearchProjection(movies: [dune1], collections: [collection], playlists: [playlist]),
    );
    expect(find.text('Dune Collection'), findsOneWidget);
    expect(find.text('Desert nights'), findsOneWidget);

    await pump(
      tester,
      projection: UnifiedSearchProjection(movies: [dune1], collections: [collection], playlists: [playlist]),
      kindFilter: MediaKind.movie,
    );
    expect(find.text('Dune Collection'), findsNothing);
  });

  testWidgets('a source-concrete row names its server when there is more than one', (tester) async {
    final collection = _item(kind: MediaKind.collection, id: 'c1', title: 'Dune Collection', serverName: 'NAS');

    await pump(
      tester,
      projection: UnifiedSearchProjection(collections: [collection]),
      serverNameFor: (item) => item.serverName ?? '',
    );
    expect(find.text('NAS'), findsOneWidget);
  });

  testWidgets('without a requests server there is no "Not on your servers" section', (tester) async {
    await pump(tester, projection: UnifiedSearchProjection(movies: [dune1]));
    expect(find.text('NOT ON YOUR SERVERS'), findsNothing);
  });

  testWidgets('with one, the section is there and asks before it queries', (tester) async {
    var asked = 0;
    await pump(
      tester,
      projection: UnifiedSearchProjection(movies: [dune1]),
      requests: const MobileSearchRequests(isConfigured: true, isSearching: false, hasSearched: false, results: []),
      onSearchRequests: () => asked++,
    );

    expect(find.text('NOT ON YOUR SERVERS'), findsOneWidget);
    // Never per keystroke: Pleya does not hand a query to a third party until
    // the viewer says so.
    expect(asked, 0);
    await tester.tap(find.text('Not in your library? Search on Jellyseerr / Overseerr'));
    await tester.pump();
    expect(asked, 1);
  });

  testWidgets('a requestable title draws its row with the request chip', (tester) async {
    await pump(
      tester,
      projection: const UnifiedSearchProjection(),
      requests: const MobileSearchRequests(
        isConfigured: true,
        isSearching: false,
        hasSearched: true,
        results: [SeerrMedia(tmdbId: 1, mediaType: 'movie', title: 'Dune', year: '1984')],
      ),
    );

    expect(find.byType(MobileSearchRequestRow), findsOneWidget);
    expect(find.text('Request'), findsOneWidget);
    final chip = tester.getRect(find.byType(TextButton));
    expect(chip.height, MobileSearchMetrics.requestChipHeight);
  });

  testWidgets('nothing anywhere is an empty state, not a page of empty sections', (tester) async {
    await pump(tester, projection: const UnifiedSearchProjection());
    expect(find.text('No results found'), findsOneWidget);
  });

  testWidgets('a failure is shown as a failure, with its own words per cause', (tester) async {
    await pump(tester, failure: SearchFailure.noServers);
    expect(find.text('No servers available'), findsOneWidget);

    await pump(tester, failure: SearchFailure.network);
    expect(find.text('Search failed'), findsOneWidget);
  });

  testWidgets('the header is the compact one, and carries no search glyph', (tester) async {
    var back = 0;
    await pump(
      tester,
      projection: UnifiedSearchProjection(movies: [dune1]),
      onBack: () => back++,
    );

    expect(find.byType(MobileCatalogHeader), findsOneWidget);
    // Search is the destination the glyph opens, so on this page it has
    // nowhere to send anyone and is absent rather than disabled.
    expect(find.byTooltip('Search'), findsNothing);

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(back, 1);
  });

  testWidgets('before the first search it offers the recent queries', (tester) async {
    await pump(tester, hasSearched: false, history: const ['dune', 'silo']);
    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('dune'), findsOneWidget);
  });

  testWidgets('a search in flight draws skeletons, not an empty result page', (tester) async {
    await pump(tester, isBusy: true);
    expect(find.text('No results found'), findsNothing);
  });
}
