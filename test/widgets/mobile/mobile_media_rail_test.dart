import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_hub.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/mobile/mobile_media_card.dart';
import 'package:pleya/widgets/mobile/mobile_media_rail.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  UnifiedMediaGroup group(String id) {
    final source = UnifiedMediaSource.fromItem(
      MediaItem(id: id, backend: .plex, kind: MediaKind.movie, title: 'Title $id', serverId: 'nas', serverName: 'NAS'),
    );
    return UnifiedMediaGroup(
      groupId: id,
      identity: CanonicalMediaIdentity.movie(title: 'Title $id', year: null),
      sources: [source],
      representativeSourceKey: source.sourceKey,
      watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey),
    );
  }

  UnifiedMediaHub hub({int count = 3, String title = 'Continue watching', UnifiedHubViewAll? viewAll}) =>
      UnifiedMediaHub.synthesized(
        slug: 'test',
        title: title,
        kind: UnifiedHubKind.movie,
        groups: [for (var i = 0; i < count; i++) group('i$i')],
        viewAll: viewAll,
      );

  Future<void> pump(WidgetTester tester, Widget rail, {double textScale = 1.0, double width = 393}) async {
    tester.view.physicalSize = Size(width, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final manager = MultiServerManager();
    final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(multiServerProvider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: multiServerProvider,
        child: MaterialApp(
          theme: monoTheme(dark: true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          // A `SliverToBoxAdapter`, matching production (`MobileHomeScreen`):
          // it gives the rail's `Column` an unbounded main-axis extent, so it
          // shrink-wraps to its content the way `mobileRailHeight` predicts.
          // A bare `Scaffold(body: rail)` instead hands the Column a *tight*
          // full-screen height, which its default `mainAxisSize.max` happily
          // fills — measuring 852pt regardless of the rail's real content.
          home: Scaffold(
            body: CustomScrollView(slivers: [SliverToBoxAdapter(child: rail)]),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders the hub title and one card per group', (tester) async {
    // Two cards, well within the 393pt viewport: ListView.builder only
    // materializes what is on (or near) screen, so a wider count here would
    // pin the lazy-build window rather than the rail's own composition.
    await pump(tester, MobileMediaRail(hub: hub(count: 2), railIndex: 0));

    expect(find.text('Continue watching'), findsOneWidget);
    expect(find.byType(MobileMediaCard), findsNWidgets(2));
  });

  // DEC-132: a seed row's reason ("Because you watched X") is its rail title;
  // a long seed title is cut on one line instead of overflowing the header.
  // The test font draws every glyph a full em wide, so on a 393pt phone even
  // the short label would be cut; 834pt keeps the short case meaningful.
  {
    const longTitle =
        'The Extraordinarily Long and Winding Chronicle of a Title That Never Seems to End Across Several Seasons';
    for (final locale in [AppLocale.en, AppLocale.nl]) {
      for (final seedTitle in ['Severance', longTitle]) {
        testWidgets('seed row title ${locale.languageCode}, ${seedTitle.length} chars', (tester) async {
          await tester.runAsync(() => LocaleSettings.setLocale(locale));
          addTearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));
          final label = t.discover.becauseYouWatched(title: seedTitle);
          await pump(tester, MobileMediaRail(hub: hub(count: 1, title: label), railIndex: 0), width: 834);

          expect(find.text(label), findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(tester.renderObject<RenderParagraph>(find.text(label)).didExceedMaxLines, seedTitle == longTitle);
        });
      }
    }
  }

  testWidgets('shows "View All" only when a callback is given', (tester) async {
    await pump(tester, MobileMediaRail(hub: hub(), railIndex: 0));
    expect(find.text('View All'), findsNothing);

    await pump(tester, MobileMediaRail(hub: hub(), railIndex: 0, onViewAll: () {}));
    expect(find.text('View All'), findsOneWidget);
  });

  testWidgets('a card tap reports its own group', (tester) async {
    UnifiedMediaGroup? tapped;
    await pump(tester, MobileMediaRail(hub: hub(count: 2), railIndex: 0, onCardTap: (g) => tapped = g));

    await tester.tap(find.byType(MobileMediaCard).last);
    expect(tapped?.groupId, 'i1');
  });

  testWidgets('long-press opens the unified group menu, not the legacy single-source one', (tester) async {
    await pump(tester, MobileMediaRail(hub: hub(count: 1), railIndex: 0));

    await tester.longPress(find.byType(MobileMediaCard).first);
    await tester.pumpAndSettle();

    expect(find.text('Mark as Watched'), findsOneWidget);
  });

  // `MobileHomeScreen._firstRailHeight` budgets the hero against
  // `mobileRailHeight`, so a drift between what it predicts and what this
  // widget actually renders silently re-opens density-review F5 (a font
  // mismatch between a bare TextPainter and the real Text widget once made
  // that prediction ~9pt short). Pinning the two against each other here, at
  // both a portrait and a wide shape and at an increased text scale, is what
  // stands in for re-deriving the title row's font metrics by hand.
  Future<void> expectRailHeightMatches(WidgetTester tester, MobileCardShape shape, {double textScale = 1.0}) async {
    final rail = MobileMediaRail(hub: hub(count: 1), railIndex: 0, shape: shape);
    await pump(tester, rail, textScale: textScale);

    final context = tester.element(find.byType(MobileMediaRail));
    final predicted = mobileRailHeight(context, shape);
    final actual = tester.getSize(find.byType(MobileMediaRail)).height;

    expect(predicted, closeTo(actual, 0.01), reason: 'shape=$shape textScale=$textScale');
  }

  testWidgets('mobileRailHeight matches the rendered rail: portrait shape, default text scale', (tester) async {
    await expectRailHeightMatches(tester, MobileCardShape.portrait);
  });

  testWidgets('mobileRailHeight matches the rendered rail: wide shape, default text scale', (tester) async {
    await expectRailHeightMatches(tester, MobileCardShape.wide);
  });

  testWidgets('mobileRailHeight matches the rendered rail: wide shape, increased text scale', (tester) async {
    await expectRailHeightMatches(tester, MobileCardShape.wide, textScale: 1.6);
  });
}
