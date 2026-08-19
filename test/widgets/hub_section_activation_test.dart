import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/diagnostics/select_trace_recorder.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/hub_section.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

/// What a row opens when the user presses Select on it.
///
/// A row reloads in place, and the reported failure is what happens in the gap:
/// press on one title, get the one that slid into its slot while you were
/// looking at the old frame. These tests drive the widget the way a remote does
/// and count what reaches the navigator, because "did it open the wrong thing"
/// is a behavioural question, not a rendering one.
///
/// Which item a resolution picks is pinned separately and directly in
/// `hub_activation_test.dart`; here the point is that a dropped activation
/// opens nothing at all, and that the row stays usable afterwards.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  MediaItem item(String id) => MediaItem.plex(id: id, kind: MediaKind.movie, serverId: 's1', title: 'Title $id');

  MediaHub hub(List<String> ids, {bool more = false}) => MediaHub(
    id: 'recently_added',
    title: 'Recently added',
    type: 'movie',
    identifier: '_recently_added_',
    size: ids.length + (more ? 1 : 0),
    more: more,
    items: [for (final id in ids) item(id)],
  );

  /// Pumps one row and hands back the spy plus a way to swap the hub contents,
  /// which is what a background refresh does to a live row.
  Future<(_RouteSpy, Future<void> Function(MediaHub))> pumpHub(
    WidgetTester tester,
    MediaHub initial, {
    GlobalKey<HubSectionState>? hubKey,
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await SettingsService.getInstance();

    final spy = _RouteSpy();
    final key = hubKey ?? GlobalKey<HubSectionState>();

    final librariesProvider = LibrariesProvider();
    addTearDown(librariesProvider.dispose);
    final hiddenLibrariesProvider = HiddenLibrariesProvider();
    await hiddenLibrariesProvider.ensureInitialized();
    addTearDown(hiddenLibrariesProvider.dispose);
    final manager = MultiServerManager();
    final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(multiServerProvider.dispose);

    Future<void> pumpWith(MediaHub next) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LibrariesProvider>.value(value: librariesProvider),
            ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibrariesProvider),
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true),
            navigatorObservers: [spy],
            home: Scaffold(
              body: SingleChildScrollView(
                child: HubSection(key: key, hub: next, icon: Symbols.play_circle_rounded),
              ),
            ),
          ),
        ),
      );
      // Timed, not a bare pump: the row schedules post-frame scroll work and a
      // zero-length pump lets it reschedule itself forever.
      await tester.pump(const Duration(milliseconds: 50));
    }

    await pumpWith(initial);
    return (spy, pumpWith);
  }

  Future<void> pressSelect(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('a refreshed-away item opens nothing instead of its replacement', (tester) async {
    // The reported failure. The row keeps its length, so nothing that counts
    // items notices; only the identity does.
    final hubKey = GlobalKey<HubSectionState>();
    final (spy, pumpWith) = await pumpHub(tester, hub(['a', 'b', 'c', 'd']), hubKey: hubKey);

    hubKey.currentState!.requestFocusAt(3);
    await tester.pump(const Duration(milliseconds: 300));
    spy.pushed.clear();

    // 'd' is gone and 'zz' now sits at index 3, exactly where the cursor is.
    await pumpWith(hub(['a', 'b', 'c', 'zz']));
    await pressSelect(tester);

    expect(spy.pushed, isEmpty, reason: 'the item the user was looking at is gone, so this press has no target');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the row stays usable: the next press opens the card that is there now', (tester) async {
    // The guard against over-fixing. Refusing once is right; refusing forever
    // would leave the row dead.
    final hubKey = GlobalKey<HubSectionState>();
    final (spy, pumpWith) = await pumpHub(tester, hub(['a', 'b', 'c', 'd']), hubKey: hubKey);

    hubKey.currentState!.requestFocusAt(3);
    await tester.pump(const Duration(milliseconds: 300));
    await pumpWith(hub(['a', 'b', 'c', 'zz']));
    await pressSelect(tester);
    spy.pushed.clear();

    await pressSelect(tester);

    expect(spy.pushed, hasLength(1), reason: 'the second press acts on the visible card');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an item that only moved is still opened', (tester) async {
    // The case the older length-and-position bookkeeping already handled, kept
    // as the regression line so the identity rule does not lose it.
    final hubKey = GlobalKey<HubSectionState>();
    final (spy, pumpWith) = await pumpHub(tester, hub(['a', 'b', 'c', 'd']), hubKey: hubKey);

    hubKey.currentState!.requestFocusAt(3);
    await tester.pump(const Duration(milliseconds: 300));
    spy.pushed.clear();

    // Finishing an episode moves it to the front: same item, new index.
    await pumpWith(hub(['d', 'a', 'b', 'c']));
    await pressSelect(tester);

    expect(spy.pushed, hasLength(1), reason: 'the item still exists, so the press still opens it');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a first press with no stored identity still works', (tester) async {
    // Nothing has been chosen yet, so the cursor position is the only
    // information there is and it must still be used.
    final (spy, _) = await pumpHub(tester, hub(['a', 'b', 'c']));
    spy.pushed.clear();

    await tester.tap(find.text('Title a'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));

    expect(spy.pushed, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('losing the View All card does not leave the row unable to open anything', (tester) async {
    // hub.more comes off the server on every refresh, so the trailing card can
    // disappear while the cursor is on it. The index gets clamped onto the last
    // real card, which is what the user then sees highlighted, and the target
    // was left saying "View All": activation resolved that to nothing and
    // returned without re-pointing, so Select stayed dead until the user pressed
    // left or right.
    final hubKey = GlobalKey<HubSectionState>();
    final (spy, pumpWith) = await pumpHub(tester, hub(['a', 'b', 'c'], more: true), hubKey: hubKey);

    hubKey.currentState!.requestFocusAt(3); // the "View All" slot
    await tester.pump(const Duration(milliseconds: 300));

    await pumpWith(hub(['a', 'b', 'c']));
    spy.pushed.clear();

    await pressSelect(tester);

    expect(spy.pushed, hasLength(1), reason: 'the press acts on the card the cursor was clamped onto');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a reorder the row absorbs stays one line naming what the user aimed at', (tester) async {
    // The counterweight to the warnings: this row follows the identity across a
    // refresh, so a reorder is not a defect and must not produce noise. What
    // the line has to prove is that selected and activated are the same title.
    final lines = <String>[];
    SelectTraceRecorder.debugSetInstance(
      SelectTraceRecorder(enabled: true, emitInfo: lines.add, emitWarning: lines.add),
    );
    addTearDown(() => SelectTraceRecorder.debugSetInstance(null));

    final hubKey = GlobalKey<HubSectionState>();
    final (_, pumpWith) = await pumpHub(tester, hub(['a', 'b', 'c', 'd']), hubKey: hubKey);

    hubKey.currentState!.requestFocusAt(3);
    await tester.pump(const Duration(milliseconds: 300));

    await pumpWith(hub(['d', 'a', 'b', 'c']));
    await pressSelect(tester);

    final trace = lines.singleWhere((line) => line.contains('Select trace'));
    expect(trace, contains('selected=s1:d'));
    expect(trace, contains('activated=s1:d'), reason: 'the cursor followed the item to its new slot');
    expect(trace, isNot(contains('ABNORMAL')), reason: 'a reorder the row absorbs is not a defect');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a dropped activation is reported as such', (tester) async {
    final lines = <String>[];
    SelectTraceRecorder.debugSetInstance(
      SelectTraceRecorder(enabled: true, emitInfo: lines.add, emitWarning: lines.add),
    );
    addTearDown(() => SelectTraceRecorder.debugSetInstance(null));

    final hubKey = GlobalKey<HubSectionState>();
    final (_, pumpWith) = await pumpHub(tester, hub(['a', 'b', 'c', 'd']), hubKey: hubKey);

    hubKey.currentState!.requestFocusAt(3);
    await tester.pump(const Duration(milliseconds: 300));

    await pumpWith(hub(['a', 'b', 'c', 'zz']));
    await pressSelect(tester);

    final trace = lines.singleWhere((line) => line.contains('Select trace'));
    expect(trace, contains('ABNORMAL'));
    expect(trace, contains('activation_dropped'));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the trailing card opens the hub, not a title', (tester) async {
    final hubKey = GlobalKey<HubSectionState>();
    final (spy, _) = await pumpHub(tester, hub(['a', 'b', 'c'], more: true), hubKey: hubKey);

    hubKey.currentState!.requestFocusAt(3); // the "View All" slot
    await tester.pump(const Duration(milliseconds: 300));
    spy.pushed.clear();

    await pressSelect(tester);

    expect(spy.pushed, hasLength(1), reason: 'View All navigates');
    expect(
      spy.pushed.single,
      isNot(isA<MaterialPageRoute<bool>>()),
      reason: 'the media detail route is the bool-returning one; this is the hub page',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// Records what the row pushed, then drops the route again.
///
/// Same reasoning as the hero activation tests: the assertion is about which
/// route the production code chose, not about the destination rendering. A real
/// detail screen wants its own provider tree and would say nothing about the
/// key press under test.
class _RouteSpy extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) return; // the home route itself
    pushed.add(route);
    scheduleMicrotask(() => route.navigator?.removeRoute(route));
  }
}
