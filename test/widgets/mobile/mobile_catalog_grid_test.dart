import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/media_card_grid_layout.dart';
import 'package:pleya/widgets/mobile/mobile_catalog_grid.dart';
import 'package:pleya/widgets/mobile/mobile_media_card.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

/// The three-column grid and its footer, from mockup `03-alle-films.png`. iOS
/// Unified 2026 fase 3.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  UnifiedMediaGroup mediaGroup(String id) {
    final item = MediaItem(
      id: id,
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      title: id,
      year: 2024,
      serverId: 'nas',
      serverName: 'NAS',
    );
    final source = UnifiedMediaSource.fromItem(item);
    return UnifiedMediaGroup(
      groupId: id,
      identity: CanonicalMediaIdentity.movie(title: id, year: 2024),
      sources: [source],
      representativeSourceKey: source.sourceKey,
      watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey),
    );
  }

  Future<void> pumpGrid(WidgetTester tester, List<Widget> slivers, {double width = 393}) async {
    tester.view.physicalSize = Size(width, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final manager = MultiServerManager();
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(multiServer.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: multiServer,
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(body: CustomScrollView(slivers: slivers)),
        ),
      ),
    );
    await tester.pump();
  }

  group('metrics', () {
    test('three columns on every phone width the northstar covers', () {
      // Fixed at three rather than derived: every frozen image is an iPhone 15
      // Pro, and a 430pt phone quietly rendering four would stop matching the
      // authority it is measured against.
      for (final width in [320.0, 375.0, 393.0, 430.0]) {
        final card = mobileCatalogCardWidth(width);
        final used = card * 3 + mobileCatalogGridGutter * 2 + mobileCatalogGridInset * 2;
        expect(used, closeTo(width, 0.01), reason: 'three columns must fill $width exactly');
        expect(card, greaterThan(80), reason: 'a poster narrower than this stops being readable');
      }
    });

    test('the card width on a 393pt phone matches the mockup', () {
      // (393 - 32 inset - 24 gutters) / 3
      expect(mobileCatalogCardWidth(393), closeTo(112.33, 0.01));
    });
  });

  testWidgets('draws one card per group, three to a row', (tester) async {
    await pumpGrid(tester, [
      MobileCatalogGrid(groups: [for (var i = 0; i < 6; i++) mediaGroup('g$i')], onCardTap: (_) {}),
    ]);

    expect(find.byType(MobileMediaCard), findsNWidgets(6));
    final first = tester.getTopLeft(find.byType(MobileMediaCard).at(0));
    final second = tester.getTopLeft(find.byType(MobileMediaCard).at(1));
    final fourth = tester.getTopLeft(find.byType(MobileMediaCard).at(3));

    expect(first.dy, second.dy, reason: 'the first three share a row');
    expect(fourth.dy, greaterThan(first.dy), reason: 'the fourth starts the second row');
    expect(first.dx, mobileCatalogGridInset);
  });

  testWidgets('a cell reserves exactly the poster plus its caption', (tester) async {
    await pumpGrid(tester, [
      MobileCatalogGrid(groups: [mediaGroup('g0')], onCardTap: (_) {}),
    ]);

    final cardWidth = mobileCatalogCardWidth(393);
    final size = tester.getSize(find.byType(MobileMediaCard).first);
    expect(size.width, closeTo(cardWidth, 0.01));
    // The card draws its poster at full width, so the cell is the poster plus
    // the caption — not `MediaCardGridLayout.cellHeightFor`, which insets the
    // poster for `MediaCard` and would leave a gap under every row.
    final context = tester.element(find.byType(MobileCatalogGrid));
    expect(size.height, closeTo(cardWidth * 3 / 2 + MediaCardGridLayout.textExtentFor(context), 0.5));
  });

  testWidgets('tapping a card reports its group', (tester) async {
    UnifiedMediaGroup? tapped;
    await pumpGrid(tester, [
      MobileCatalogGrid(groups: [mediaGroup('g0'), mediaGroup('g1')], onCardTap: (found) => tapped = found),
    ]);

    await tester.tap(find.byType(MobileMediaCard).at(1));
    await tester.pump();
    expect(tapped?.groupId, 'g1');
  });

  group('the footer', () {
    testWidgets('offers Load more while the merge has more to give', (tester) async {
      var loads = 0;
      await pumpGrid(tester, [
        SliverToBoxAdapter(
          child: MobileCatalogFooter(
            isLoadingMore: false,
            hasMore: true,
            onLoadMore: () => loads++,
            failedLibraryCount: 0,
          ),
        ),
      ]);

      await tester.tap(find.text('Load more'));
      expect(loads, 1);
    });

    testWidgets('shows a spinner instead of the button while a page is in flight', (tester) async {
      await pumpGrid(tester, [
        SliverToBoxAdapter(
          child: MobileCatalogFooter(isLoadingMore: true, hasMore: true, onLoadMore: () {}, failedLibraryCount: 0),
        ),
      ]);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('is silent once the catalogue is complete', (tester) async {
      await pumpGrid(tester, [
        SliverToBoxAdapter(
          child: MobileCatalogFooter(isLoadingMore: false, hasMore: false, onLoadMore: () {}, failedLibraryCount: 0),
        ),
      ]);

      expect(find.text('Load more'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('says when a library did not answer, so a short list is not read as the whole truth', (tester) async {
      await pumpGrid(tester, [
        SliverToBoxAdapter(
          child: MobileCatalogFooter(isLoadingMore: false, hasMore: false, onLoadMore: () {}, failedLibraryCount: 1),
        ),
      ]);
      expect(find.text('1 library did not answer'), findsOneWidget);

      await pumpGrid(tester, [
        SliverToBoxAdapter(
          child: MobileCatalogFooter(isLoadingMore: false, hasMore: false, onLoadMore: () {}, failedLibraryCount: 3),
        ),
      ]);
      expect(find.text('3 libraries did not answer'), findsOneWidget);
    });
  });
}
