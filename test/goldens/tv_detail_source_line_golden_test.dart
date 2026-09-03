import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_coverage_state.dart';
import 'package:pleya/media/unified/unified_route_context.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:provider/provider.dart';

import '../test_helpers/golden.dart';
import '../test_helpers/notice_layer.dart';
import '../test_helpers/prefs.dart';
import '../test_helpers/profile_navigation.dart';

/// Visual acceptance for hoofdstuk 15's source line on the TV detail hero:
/// `Bron: … [ Wijzigen ]`, the row that says which concrete source the page is
/// reading and offers the switch.
///
/// This surface had no picture at all, and it is exactly the kind that fails
/// silently: the hero budgets its own height, so a source line that does not
/// fit does not wrap or scroll — it overflows the box it was never counted in.
/// That defect shipped once already (the action row reserved
/// `_tvDetailActionSize` and nothing else), and a test asserting "the chip is
/// on screen" stayed green right through it. A render is what shows the line
/// sitting under the buttons with room around it.
///
/// One harness caveat, so the picture is not misread: the summary renders as
/// placeholder boxes. `monoTheme` builds its `textTheme` from
/// `Typography.englishLike2021`, which resolves to a family this app does not
/// bundle, and the golden harness can only load what `pubspec.yaml` ships
/// (Inter, ArchivoBlack, the icon font). The *geometry* is still exact — the
/// summary's line boxes come from its explicit `fontSize` and `height: 1.35`,
/// not from glyph coverage — and geometry is what these two renders are for.
/// Everything styled in Inter (the metadata line, the source line, the chip)
/// renders as it ships.
///
/// Regenerate after an intentional visual change:
/// `flutter test --update-goldens test/goldens/tv_detail_source_line_golden_test.dart`
void main() {
  setUpAll(loadAppFontsForGoldens);

  setUp(() {
    resetNotices();
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  MediaItem movie() => MediaItem(
    id: 'movie_1',
    backend: MediaBackend.jellyfin,
    kind: MediaKind.movie,
    title: 'Sintel',
    year: 2010,
    summary:
        'A lonely young woman, Sintel, helps and befriends a dragon, whom she calls Scales. '
        'But when he is kidnapped by an adult dragon, Sintel decides to embark on a dangerous quest.',
    durationMs: 14 * 60 * 1000,
    serverId: 'server_1',
    serverName: 'NAS',
    libraryTitle: 'Films 4K',
  );

  UnifiedMediaRouteContext routeContext() => UnifiedMediaRouteContext(
    groupId: 'g1',
    identity: CanonicalMediaIdentity.movie(title: 'Sintel', year: 2010),
    sourceKey: 'server_1:movie_1',
    availableSourceKeys: const ['server_1:movie_1', 'server_2:movie_1'],
    coverage: SourceCoverageState.complete(const {'server_1', 'server_2'}),
    intent: UnifiedActivationIntent.details,
  );

  Future<void> pumpDetail(WidgetTester tester, {required bool withAlternatives}) async {
    setGoldenSurfaceSize(tester);
    await SettingsService.getInstance();

    final manager = MultiServerManager();
    final provider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<MultiServerProvider>.value(
          value: provider,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            builder: withNoticeLayer(),
            theme: monoTheme(dark: true),
            home: withProfileNavigationScope(
              child: MediaDetailScreen(
                metadata: movie(),
                unifiedRouteContext: withAlternatives ? routeContext() : null,
                onChangeSource: withAlternatives ? (_) async {} : null,
              ),
            ),
          ),
        ),
      ),
    );

    // The hero reveals on its own timer; settle would wait on the artwork
    // shimmer that never stops.
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('a multi-source title carries the source line under its actions', (tester) async {
    await pumpDetail(tester, withAlternatives: true);

    await expectLater(find.byType(MediaDetailScreen), matchesGoldenFile('tv_detail_source_line.png'));
  });

  testWidgets('a single-source title has no line at all, and the hero closes up', (tester) async {
    // The negative control, and the reason the height has to be conditional:
    // an unconditional reservation would leave a gap under the buttons of
    // every ordinary title in the app.
    await pumpDetail(tester, withAlternatives: false);

    await expectLater(find.byType(MediaDetailScreen), matchesGoldenFile('tv_detail_no_source_line.png'));
  });
}
