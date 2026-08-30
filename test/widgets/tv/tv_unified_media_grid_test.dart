/// The grid's own contracts: how a focus move drives the artwork warm-up
/// (hoofdstuk 10.2 and DEC-039's viewport-plus-margin rule).
///
/// The prefetcher's *policy* — margins, ordering, de-duplication, bounding — is
/// proven in `test/services/unified_catalog/unified_artwork_prefetcher_test.dart`
/// without a widget tree at all. What can only be proven here is the wiring:
/// that the grid actually calls it, that it calls it with the row the user is
/// standing in, and that it never asks for the whole catalog.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_unified_media_grid.dart';

/// A self-contained artwork URL, so `getOptimizedImageUrl` needs no client to
/// size it and the fixtures stay honest about where the URLs come from.
UnifiedMediaGroup _group(int index) {
  final item = MediaItem(
    id: 'i$index',
    backend: MediaBackend.jellyfin,
    kind: MediaKind.movie,
    title: 'Title $index',
    thumbPath: 'https://jf.test/Items/$index/Images/Primary?api_key=secret',
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

void main() {
  setUpAll(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  /// Records what the grid asked to warm, instead of hitting the network.
  final warmed = <String>[];

  Future<void> pumpGrid(WidgetTester tester, {required int count}) async {
    warmed.clear();
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: Scaffold(
              body: TvUnifiedMediaGrid(
                groups: [for (var i = 0; i < count; i++) _group(i)],
                onActivate: (_) {},
                hasMore: false,
                isLoadingMore: false,
                onLoadMore: () {},
                precache: (request, context) async => warmed.add(request.groupId),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('nothing is warmed until the user is somewhere', (tester) async {
    await pumpGrid(tester, count: 40);
    expect(warmed, isEmpty, reason: 'a grid nobody has entered has no viewport to warm around');
  });

  testWidgets('focusing a card warms that card and its neighbourhood', (tester) async {
    await pumpGrid(tester, count: 40);
    Focus.of(tester.element(find.text('Title 0'))).requestFocus();
    await tester.pumpAndSettle();

    expect(warmed, isNotEmpty);
    expect(warmed, contains('g0'), reason: 'the focused card first of all');
    // The prefetcher's own margin, not the whole catalog: hoofdstuk 39's
    // "viewport + kleine marge", and the reason a grid of forty titles must not
    // turn into forty image requests the moment focus lands.
    expect(warmed.length, lessThan(40));
  });

  testWidgets('moving deeper into the grid warms around the new row, not the old one', (tester) async {
    await pumpGrid(tester, count: 40);
    Focus.of(tester.element(find.text('Title 0'))).requestFocus();
    await tester.pumpAndSettle();
    final afterFirst = {...warmed};

    Focus.of(tester.element(find.text('Title 30'))).requestFocus();
    await tester.pumpAndSettle();

    expect(warmed, contains('g30'));
    expect(
      warmed.toSet().difference(afterFirst),
      isNotEmpty,
      reason: 'a move to the far end of the catalog must warm something new',
    );
  });

  testWidgets('walking back over warmed cards asks for nothing twice', (tester) async {
    await pumpGrid(tester, count: 40);
    Focus.of(tester.element(find.text('Title 0'))).requestFocus();
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.text('Title 1'))).requestFocus();
    await tester.pumpAndSettle();

    expect(warmed.length, warmed.toSet().length, reason: 'no poster is fetched twice');
  });

  testWidgets('a grid leaving the tree mid-warm neither throws nor keeps working', (tester) async {
    await pumpGrid(tester, count: 40);
    Focus.of(tester.element(find.text('Title 0'))).requestFocus();
    await tester.pumpAndSettle();
    final before = warmed.length;

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect(warmed.length, before);
    expect(tester.takeException(), isNull);
  });

  // Pleya ships sixteen locales and not one of them is right-to-left (see
  // `AppLocale` in `strings.g.dart`: en, bg, da, de, es, fr, it, ja, ko, nb,
  // nl, pl, pt, ru, sv, zh). So there is no RTL *acceptance render* to make —
  // it would picture a state no user can reach — and claiming one would be
  // claiming coverage that does not exist.
  //
  // What is worth having is this: the grid resolves its own columns, gutters
  // and insets from the viewport and wires LEFT and RIGHT by hand, so it is
  // exactly the kind of widget that throws or mirrors badly the first time a
  // right-to-left locale is added. One assertion now is much cheaper than
  // finding out during that translation.
  testWidgets('builds under a right-to-left directionality without breaking', (tester) async {
    warmed.clear();
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          locale: const Locale('ar'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('ar'), Locale('en')],
          home: InputModeTracker(
            child: Scaffold(
              body: TvUnifiedMediaGrid(
                groups: [for (var i = 0; i < 12; i++) _group(i)],
                onActivate: (_) {},
                hasMore: false,
                isLoadingMore: false,
                onLoadMore: () {},
                precache: (request, context) async => warmed.add(request.groupId),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(Directionality.of(tester.element(find.text('Title 0'))), TextDirection.rtl);
    // The same twelve cards, laid out on the same grid: the column count comes
    // from the viewport width, which has no handedness.
    expect(find.text('Title 11'), findsOneWidget);

    Focus.of(tester.element(find.text('Title 0'))).requestFocus();
    await tester.pumpAndSettle();
    expect(warmed, contains('g0'));
  });

  // The seam itself: production passes nothing, and the grid must then still
  // build and warm through the real `precacheImage` path without complaint.
  testWidgets('the default prefetcher is used when no seam is injected', (tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: Scaffold(
              body: TvUnifiedMediaGrid(
                groups: [for (var i = 0; i < 8; i++) _group(i)],
                onActivate: (_) {},
                hasMore: false,
                isLoadingMore: false,
                onLoadMore: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.text('Title 0'))).requestFocus();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
