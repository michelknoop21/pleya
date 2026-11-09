/// What a frame of the TV catalog grid costs, as a function of how many cards
/// it holds.
///
/// Alle films on the Apple TV spent about three times the build time of Alle
/// series per frame, with raster at 1-3 ms. These tests pin the three costs
/// that grow with the number of cards: a scroll frame that repaints the cards
/// (H1), an artwork recenter that rebuilds every card (H2), and a
/// `LocalLibraryProvider` notification that looks up a poster for every card
/// (H3).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/local_library_provider.dart';
import 'package:pleya/services/local_library/scan_diagnostics.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/optimized_media_image.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';
import 'package:pleya/widgets/tv/tv_unified_media_grid.dart';
import 'package:provider/provider.dart';

/// Copied from `tv_unified_media_grid_test.dart`, with a path the paint probe
/// can name its card by.
UnifiedMediaGroup _group(int index) {
  final item = MediaItem(
    id: 'i$index',
    backend: MediaBackend.jellyfin,
    kind: MediaKind.movie,
    title: 'Title $index',
    thumbPath: 'probe/g$index',
    serverId: 'nas',
    serverName: 'NAS',
  );
  final source = UnifiedMediaSource.fromItem(item);
  return UnifiedMediaGroup(
    groupId: 'g$index',
    identity: CanonicalMediaIdentity.movie(title: 'Title $index', year: 2010),
    sources: [source],
    representativeSourceKey: source.sourceKey,
    watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey, isWatched: false),
  );
}

/// Counts every time a drawn poster is painted.
class _PaintProbe extends CustomPainter {
  int count = 0;

  @override
  void paint(Canvas canvas, Size size) => count++;

  @override
  bool shouldRepaint(_PaintProbe oldDelegate) => false;
}

final paintProbe = _PaintProbe();

/// Pattern: `_LocalLibrary` in `test/providers/unified_catalog_provider_restart_test.dart`.
class _LocalLibrary extends LocalLibraryProvider {
  _LocalLibrary()
    : super(
        profileId: null,
        librariesForSync: () => [],
        clientFor: (_) => null,
        mayReadServer: (_) => true,
        mayReadLibrary: (_) => true,
        networkConnected: () => false,
        wifiConnected: () => false,
        changes: LibrariesProvider(),
      );

  void publish() => notifyListeners();
}

final localLibrary = _LocalLibrary();

late ScrollController controller;
late GlobalKey<TvUnifiedMediaGridState> gridKey;
TvUnifiedMediaGridState get gridState => gridKey.currentState!;

Future<void> pumpGrid(WidgetTester tester, {required int groups}) async {
  controller = ScrollController();
  addTearDown(controller.dispose);
  gridKey = GlobalKey<TvUnifiedMediaGridState>();
  await tester.pumpWidget(
    ChangeNotifierProvider<LocalLibraryProvider>.value(
      value: localLibrary,
      child: TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: Scaffold(
              body: TvUnifiedMediaGrid(
                key: gridKey,
                groups: [for (var i = 0; i < groups; i++) _group(i)],
                controller: controller,
                onActivate: (_) {},
                hasMore: false,
                isLoadingMore: false,
                onLoadMore: () {},
                precache: (request, context) async {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The column count the grid resolved for the test surface.
int columnsOf(WidgetTester tester) =>
    TvCatalogGrid.forWidth(tester.view.physicalSize.width / tester.view.devicePixelRatio, scale: 1.0).columns;

/// The distance from one row of cards to the next, as laid out.
double rowPitchOf(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(ValueKey('g${columnsOf(tester)}'))).dy -
    tester.getTopLeft(find.byKey(const ValueKey('g0'))).dy;

/// Card builds for one artwork recenter: focus on row 0, then on row 4.
Future<int> recenterBuilds(WidgetTester tester, {required int groups}) async {
  await pumpGrid(tester, groups: groups);
  final columns = columnsOf(tester);
  expect(gridState.focusItem('g0'), isTrue);
  await tester.pumpAndSettle();
  final before = ScanDiagnostics.cardBuilds;
  expect(gridState.focusItem('g${4 * columns}'), isTrue);
  await tester.pumpAndSettle();
  return ScanDiagnostics.cardBuilds - before;
}

void main() {
  setUpAll(() {
    TvDetectionService.debugSetAppleTVOverride(true);
    OptimizedMediaImage.debugImageBuilder = (context, imagePath) =>
        CustomPaint(key: ValueKey('probe-${imagePath?.split('/').last}'), painter: paintProbe, size: Size.infinite);
  });
  tearDownAll(() {
    OptimizedMediaImage.debugImageBuilder = null;
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  testWidgets('H1: a scroll-only frame repaints every drawn card', (tester) async {
    await pumpGrid(tester, groups: 500);
    final rowPitch = rowPitchOf(tester);
    paintProbe.count = 0;
    controller.jumpTo(controller.offset + rowPitch);
    await tester.pump();
    expect(paintProbe.count, greaterThan(0));
  });

  testWidgets('H2: an artwork recenter rebuilds cards in proportion to the list', (tester) async {
    final small = await recenterBuilds(tester, groups: 130);
    final large = await recenterBuilds(tester, groups: 500);
    expect(large, greaterThan(small * 3));
  });

  testWidgets('H3: one LocalLibraryProvider notification looks up a poster for every card', (tester) async {
    await pumpGrid(tester, groups: 500);
    ScanDiagnostics.posterPathCalls = 0;
    localLibrary.publish();
    await tester.pump();
    expect(ScanDiagnostics.posterPathCalls, greaterThanOrEqualTo(500));
  });
}
