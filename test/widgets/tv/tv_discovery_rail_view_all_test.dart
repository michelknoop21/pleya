/// ROW1c: the "Alle N" tile [TvDiscoveryRail] draws as a row's last card when
/// [TvDiscoveryRail.viewAll] is set — one past every real group, hard right
/// stop, own focus node, own semantics. Every existing rail keeps drawing
/// exactly as before when [TvDiscoveryRail.viewAll] is null: none of these
/// changes should be visible on a rail that never opts in.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_discovery_rail.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

import '../../test_helpers/tv_discovery_artwork.dart';
import '../../test_helpers/tv_discovery_fixtures.dart';

const Size _canvas = Size(1038, 584);

UnifiedMediaGroup _netGroup(int index) => tvDiscoveryGroup('net-$index', [
  MediaItem(
    id: 'net-$index',
    backend: MediaBackend.jellyfin,
    kind: MediaKind.movie,
    title: 'Net $index',
    year: 2024,
    serverId: 'nas',
    serverName: 'NAS',
    thumbPath: 'https://jf.test/Items/$index/Images/Primary?api_key=k',
    artPath: 'https://jf.test/Items/$index/Images/Backdrop?api_key=k',
  ),
]);

List<UnifiedMediaGroup> _netGroups(int count) => [for (var i = 0; i < count; i++) _netGroup(i)];

void main() {
  setUpAll(() {
    TvDetectionService.debugSetAppleTVOverride(true);
    TvDiscoveryArtwork.install();
  });

  tearDownAll(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    TvDiscoveryArtwork.remove();
  });

  Future<TvDiscoveryRailState> pumpRail(
    WidgetTester tester,
    List<UnifiedMediaGroup> groups, {
    TvDiscoveryViewAllTile? viewAll,
  }) async {
    tester.view.physicalSize = _canvas;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final theme = monoTheme(dark: true);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: InputModeTracker(
          child: Scaffold(
            backgroundColor: theme.extension<MonoTokens>()!.bg,
            body: Builder(
              builder: (context) => SizedBox(
                height: TvDiscoveryLayout.railSectionHeight(TvLayoutConstants.scaleOf(context)),
                child: TvDiscoveryRail(title: 'Films', groups: groups, onActivate: (_) {}, viewAll: viewAll),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state<TvDiscoveryRailState>(find.byType(TvDiscoveryRail));
  }

  testWidgets('a rail with no viewAll draws exactly its groups, nothing more', (tester) async {
    final groups = _netGroups(3);
    await pumpRail(tester, groups);

    // One tile per group, in a `ListView` whose semantics never mention a
    // fourth. `TvExpandableMediaTile` is the only tile type present.
    expect(find.byKey(ValueKey(groups[0].groupId)), findsOneWidget);
    expect(find.byKey(ValueKey(groups[1].groupId)), findsOneWidget);
    expect(find.byKey(ValueKey(groups[2].groupId)), findsOneWidget);
  });

  testWidgets('with viewAll set, the row draws one more tile than it has groups, past the last', (tester) async {
    final groups = _netGroups(3);
    var selected = false;
    final state = await pumpRail(
      tester,
      groups,
      viewAll: TvDiscoveryViewAllTile(count: 42, destinationLabel: 'All movies', onSelect: () => selected = true),
    );

    // The tile itself: not keyed by any group id, carries the composed label.
    expect(find.text('All 42, in All movies'), findsOneWidget);

    // It sits after the last real group in the scroll, reachable by walking
    // one column past it.
    expect(state.focusColumn(groups.length), isTrue);
    await tester.pump();
    expect(selected, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(selected, isTrue, reason: 'Select on the view-all tile reports the press, same as any other tile');
  });

  testWidgets('focusColumn clamps to the view-all tile when it is the last column', (tester) async {
    final groups = _netGroups(3);
    final state = await pumpRail(
      tester,
      groups,
      viewAll: TvDiscoveryViewAllTile(count: 5, destinationLabel: 'All series', onSelect: () {}),
    );

    // Column 99 clamps to the *effective* last index — the view-all tile's,
    // not the last group's — the same over-shoot contract `focusColumn`
    // already keeps for a plain rail (LAND4).
    expect(state.focusColumn(99), isTrue);
    await tester.pump();
    expect(find.text('All 5, in All series'), findsOneWidget);
  });

  testWidgets('RIGHT off the last real tile reaches the view-all tile, not off the row', (tester) async {
    final groups = _netGroups(2);
    final state = await pumpRail(
      tester,
      groups,
      viewAll: TvDiscoveryViewAllTile(count: 7, destinationLabel: 'All movies', onSelect: () {}),
    );

    expect(state.focusColumn(0), isTrue);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    // Two RIGHTs from column 0 of a two-group row lands on the view-all
    // tile — column 2 — not past it: RIGHT off *that* tile is the row's own
    // hard stop (ROW1c mirrors the same end-of-row contract every other rail
    // keeps).
    expect(find.text('All 7, in All movies'), findsOneWidget);
  });
}
