import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:pleya/widgets/media_markers.dart';
import 'package:pleya/widgets/mobile/mobile_media_card.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

/// The 2:3/16:9 card the northstar's Home rails and Verder kijken use — see
/// `docs/ios-unified-2026-fase1-plan.md` stap 4's BEWIJS list.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  MediaItem item({
    String id = 'i1',
    String serverId = 'nas',
    int? year,
    List<String>? genres,
    int? viewOffsetMs,
    int? durationMs,
    int? addedAt,
    int? viewCount,
    int? leafCount,
    int? viewedLeafCount,
    MediaKind kind = MediaKind.movie,
  }) => MediaItem(
    id: id,
    backend: .plex,
    kind: kind,
    title: 'Dune',
    year: year,
    genres: genres,
    viewOffsetMs: viewOffsetMs,
    durationMs: durationMs,
    addedAt: addedAt,
    viewCount: viewCount,
    leafCount: leafCount,
    viewedLeafCount: viewedLeafCount,
    serverId: serverId,
    serverName: serverId,
  );

  UnifiedMediaGroup group(
    MediaItem representative, {
    List<MediaItem>? extraSources,
    bool isWatched = false,
    bool hasActiveProgress = false,
  }) {
    final sources = [representative, ...?extraSources].map(UnifiedMediaSource.fromItem).toList();
    return UnifiedMediaGroup(
      groupId: 'g1',
      identity: CanonicalMediaIdentity.movie(title: representative.title, year: representative.year),
      sources: sources,
      representativeSourceKey: sources.first.sourceKey,
      watchState: UnifiedWatchState(
        representativeSourceKey: sources.first.sourceKey,
        isWatched: isWatched,
        hasActiveProgress: hasActiveProgress,
      ),
    );
  }

  Future<void> pump(WidgetTester tester, Widget card, {double width = 393}) async {
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
          home: Scaffold(body: Center(child: card)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a portrait card measures its poster at 2:3', (tester) async {
    const width = 118.0;
    await pump(tester, MobileMediaCard(group: group(item()), shape: MobileCardShape.portrait, width: width));

    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    final sizedBox = clip.child! as SizedBox;
    expect(sizedBox.width, width);
    expect(sizedBox.height, closeTo(width * 3 / 2, 0.01));
  });

  testWidgets('a wide card measures its still at 16:9', (tester) async {
    const width = 220.0;
    await pump(tester, MobileMediaCard(group: group(item()), shape: MobileCardShape.wide, width: width));

    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    final sizedBox = clip.child! as SizedBox;
    expect(sizedBox.height, closeTo(width * 9 / 16, 0.01));
  });

  testWidgets('the source capsule is absent with a single source', (tester) async {
    await pump(tester, MobileMediaCard(group: group(item()), shape: MobileCardShape.portrait, width: 118));
    expect(find.byType(SourceCountCapsule), findsNothing);
  });

  testWidgets('the source capsule appears once a group has more than one source', (tester) async {
    await pump(
      tester,
      MobileMediaCard(
        group: group(
          item(),
          extraSources: [item(id: 'i2', serverId: 'attic')],
        ),
        shape: MobileCardShape.portrait,
        width: 118,
      ),
    );
    expect(find.byType(SourceCountCapsule), findsOneWidget);
    expect(find.text('2 sources'), findsOneWidget);
  });

  testWidgets('the watched tick and the new marker never render together', (tester) async {
    final watched = group(item(viewCount: 1), isWatched: true);
    await pump(tester, MobileMediaCard(group: watched, shape: MobileCardShape.portrait, width: 118));
    expect(find.byType(WatchedTick), findsOneWidget);
    expect(find.byType(NewEpisodeDot), findsNothing);

    // NewEpisodeDot maps only to `newBadgeLabel == 'NEW EPISODE'` (a show
    // with unwatched, recently-added episodes) — a plain movie's `NEW` has
    // no marker on this card, per the fase-1 plan's stap-4 spec.
    final newEpisode = group(
      item(
        kind: MediaKind.show,
        addedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        leafCount: 10,
        viewedLeafCount: 8,
      ),
    );
    await pump(tester, MobileMediaCard(group: newEpisode, shape: MobileCardShape.portrait, width: 118));
    expect(find.byType(WatchedTick), findsNothing);
    expect(find.byType(NewEpisodeDot), findsOneWidget);
  });

  testWidgets('the caption grows to fit a larger text scale without overflowing', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final manager = MultiServerManager();
    final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(multiServerProvider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: multiServerProvider,
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: Scaffold(
              body: Center(
                child: MobileMediaCard(
                  group: group(item(year: 2021, genres: const ['Science Fiction'])),
                  shape: MobileCardShape.portrait,
                  width: 118,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 430.0]) {
    testWidgets('no overflow at $width pt', (tester) async {
      await pump(
        tester,
        MobileMediaCard(
          group: group(item(year: 2021, genres: const ['Science Fiction'])),
          shape: MobileCardShape.portrait,
          width: 118,
        ),
        width: width,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
