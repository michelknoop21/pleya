/// P4: a focus transition must resolve **one** artwork URL per variant, not a
/// bucket of them.
///
/// ## Why the assertion is on distinct URLs and not on a call count
///
/// A tile rebuilds many times over a 200 ms tween and that is not a defect;
/// resolving the same stable URL on each of those rebuilds is not a defect
/// either. What was a defect is that the *value* changed: the tile animates its
/// width, `OptimizedMediaImage` fell into its `LayoutBuilder` branch because no
/// explicit size was given, and `MediaImageHelper` buckets transcode dimensions
/// in steps of 40 device pixels — at TV's minimum DPR of 2.0, one new URL,
/// cache key, provider and disk lookup every ~20 logical pixels of the
/// expansion.
///
/// ## Why this cannot go through `debugImageBuilder`
///
/// `OptimizedMediaImage.build` consults `debugImageBuilder` on its first line
/// and returns. Every discovery widget test installs it (through
/// `TvDiscoveryArtwork`), so none of them reaches the sizing pipeline at all —
/// which is why this regression was invisible at the widget level. This file
/// installs [OptimizedMediaImage.debugResolvedUrlObserver] instead, which fires
/// after `getOptimizedImageUrl` and before any provider work, and installs no
/// image builder at all.
///
/// The artwork paths are self-contained Jellyfin-style URLs (`api_key=...`), so
/// `getOptimizedImageUrl` sizes them through `calculateOptimalDimensions`
/// without needing a `MediaServerClient`. A relative path with no client
/// returns `''` and would make this test pass by resolving nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/optimized_media_image.dart';
import 'package:pleya/widgets/tv/tv_discovery_rail.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

const Size _canvas = Size(1038, 584);

const String _posterUrl = 'https://fixture.test/Items/1/Images/Primary?api_key=k';
const String _wideUrl = 'https://fixture.test/Items/1/Images/Backdrop?api_key=k';

UnifiedMediaGroup _group() {
  final item = MediaItem(
    id: 'p4-item',
    backend: MediaBackend.jellyfin,
    kind: MediaKind.movie,
    title: 'Bucket Churn',
    year: 2024,
    serverId: 'nas',
    serverName: 'NAS',
    thumbPath: _posterUrl,
    artPath: _wideUrl,
  );
  final source = UnifiedMediaSource.fromItem(item);
  return UnifiedMediaGroup(
    groupId: 'p4-group',
    identity: CanonicalMediaIdentity.movie(title: item.title, year: item.year),
    sources: [source],
    representativeSourceKey: source.sourceKey,
    watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey),
  );
}

void main() {
  final resolved = <String>[];

  setUpAll(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  setUp(() {
    resolved.clear();
    OptimizedMediaImage.debugResolvedUrlObserver = resolved.add;
  });

  // Unconditional, and in `tearDown` rather than `tearDownAll`: this is
  // process-global state, and a seam left installed leaks into every other test
  // file that shares the process.
  tearDown(() => OptimizedMediaImage.debugResolvedUrlObserver = null);

  Future<void> pumpTile(WidgetTester tester, UnifiedMediaGroup group) async {
    tester.view.physicalSize = _canvas;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: monoTheme(dark: true),
        home: InputModeTracker(
          child: Scaffold(
            body: Builder(
              builder: (context) => SizedBox(
                height: TvDiscoveryLayout.railSectionHeight(TvLayoutConstants.scaleOf(context)),
                child: TvDiscoveryRail(title: 'Films', groups: [group], onActivate: (_) {}),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the observer sees the sizing pipeline at all', (tester) async {
    await pumpTile(tester, _group());
    expect(
      resolved,
      isNotEmpty,
      reason: 'if this is empty the test is measuring nothing — check that no debugImageBuilder is installed',
    );
    expect(resolved.every((url) => url.contains('maxWidth=')), isTrue, reason: 'the URL has to carry a size bucket');
  });

  testWidgets('a whole focus transition resolves one URL per variant', (tester) async {
    final group = _group();
    await pumpTile(tester, group);
    resolved.clear();

    final rail = tester.state<TvDiscoveryRailState>(find.byType(TvDiscoveryRail));
    expect(rail.focusGroup(group.groupId), isTrue);

    // Pumped in small steps *through* the 200 ms easeOutCubic rather than
    // settled: the whole point is what happens while the width is moving, and
    // `pumpAndSettle` would jump straight past it.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 12));
    }
    await tester.pumpAndSettle();

    final distinct = resolved.toSet();
    expect(
      distinct.length,
      lessThanOrEqualTo(2),
      reason:
          'one poster bucket and one wide bucket. More than two means the request size is following the tween '
          'again — every extra entry is a cache key, a provider and, on a miss, a download.\n'
          'resolved: $distinct',
    );
    // And both are real, so "two" is not two spellings of the same request.
    expect(distinct.where((url) => url.startsWith(_wideUrl)), hasLength(1), reason: 'exactly one wide bucket');
  });

  testWidgets('the resting tile resolves one poster bucket however often it rebuilds', (tester) async {
    final group = _group();
    await pumpTile(tester, group);
    resolved.clear();

    for (var i = 0; i < 8; i++) {
      tester.element(find.byType(TvDiscoveryRail)).markNeedsBuild();
      await tester.pump();
    }

    expect(resolved.toSet(), hasLength(lessThanOrEqualTo(1)));
  });
}
