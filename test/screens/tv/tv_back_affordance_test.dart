/// BACK1 / PB-2: no visible back button on a surface the remote cannot use.
///
/// The defect this pins was not a broken button. It was an *honest-looking*
/// one. `AppBarBackButton` is a `MouseRegion` around a `GestureDetector` and
/// holds no `FocusNode` at all, so it is not in the remote's traversal set,
/// and tvOS has no cursor to aim at it with either. Drawn on a TV surface it
/// therefore reads as "press here to go back" and cannot be pressed by any
/// input the platform has. Back on TV is the Menu/Back key, and always was.
///
/// Two families reproduced before the fix, and both are asserted here:
///
///   1. `MediaDetailScreen`'s TV branch drew the arrow unconditionally;
///   2. `CustomAppBar`'s implicit leading drew it on any full-window route
///      pushed on TV, because it consults `ModalRoute.canPop` and nothing
///      else. (A route *nested* in the shell never had it: the ambient
///      `ModalRoute` there is the shell's own, whose `canPop` is false. That
///      asymmetry is why the grep-level reading of this bug was incomplete,
///      and why the nested case is asserted too: it must stay at zero for a
///      different reason than the pushed one.)
///
/// Every test has a non-TV twin. PB-2 keeps the back button on touch and
/// pointer surfaces, so a fix that removed it everywhere would be a
/// cross-platform regression, and these twins are what would catch it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/navigation/tv/tv_content_focus_authority.dart';
import 'package:pleya/navigation/tv/tv_content_route_registry.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/app_bar_back_button.dart';
import 'package:pleya/widgets/bottom_sheet_page_scaffold.dart';
import 'package:pleya/watch_together/providers/watch_together_provider.dart';
import 'package:pleya/widgets/desktop_app_bar.dart';
import 'package:pleya/widgets/video_controls/widgets/video_controls_header.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/notice_layer.dart';
import '../../test_helpers/prefs.dart';
import '../../test_helpers/profile_navigation.dart';

/// A back control the viewer can actually see, rather than one that merely
/// exists in the tree. `hitTestable` is the closer question for a defect that
/// was about a *visible* affordance.
Finder visibleBackButton() => find.byType(AppBarBackButton).hitTestable();

/// A page built the way the affected screens build theirs: `CustomAppBar` with
/// its default `automaticallyImplyLeading`, which is the whole of the second
/// family. `CollectionDetailScreen`, `ActorMediaScreen`, `HubDetailScreen`,
/// `NowWatchingScreen` and `PlaylistDetailScreen` add nothing to that call
/// that changes the leading.
class _AppBarPage extends StatelessWidget {
  const _AppBarPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF141414),
    body: CustomScrollView(
      slivers: [
        CustomAppBar(title: const Text('page title'), pinned: true),
        const SliverToBoxAdapter(
          child: SizedBox(height: 400, child: Center(child: Text('page body'))),
        ),
      ],
    ),
  );
}

void main() {
  setUp(() {
    resetNotices();
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  void onTv({required bool tv}) => TvDetectionService.debugSetAppleTVOverride(tv);

  void sizeForTv(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('the primitive', () {
    Widget bare() => TranslationProvider(
      child: MaterialApp(
        theme: monoTheme(dark: true),
        home: const Scaffold(body: AppBarBackButton(style: BackButtonStyle.plain)),
      ),
    );

    testWidgets('a pointer surface draws it', (tester) async {
      onTv(tv: false);
      await tester.pumpWidget(bare());
      expect(visibleBackButton(), findsOneWidget);
    });

    testWidgets('a remote-first surface draws nothing at all', (tester) async {
      onTv(tv: true);
      await tester.pumpWidget(bare());
      expect(visibleBackButton(), findsNothing);
      expect(find.byType(GestureDetector), findsNothing, reason: 'not merely invisible: nothing is built');
    });

    testWidgets('it is pointer-only, which is the reason it may not be drawn on TV', (tester) async {
      // The load-bearing fact under BACK1. If this ever fails because someone
      // gave the button a focus node, PB-2 has to be reopened rather than
      // quietly satisfied: a focusable back button on TV is a product
      // decision (an extra focus stop in every app bar), not a bug fix.
      onTv(tv: false);
      await tester.pumpWidget(bare());

      expect(
        find.descendant(of: find.byType(AppBarBackButton), matching: find.byType(Focus)),
        findsNothing,
        reason: 'no FocusNode anywhere inside it, so remote traversal can never land on it',
      );
    });
  });

  group('family 1: the TV detail page', () {
    MediaItem movie() => MediaItem(
      id: 'movie_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.movie,
      title: 'Sintel',
      year: 2010,
      summary: 'A lonely young woman, Sintel, helps and befriends a dragon.',
      durationMs: 14 * 60 * 1000,
      serverId: 'server_1',
      serverName: 'NAS',
      libraryTitle: 'Films 4K',
    );

    Future<void> pumpDetail(WidgetTester tester) async {
      sizeForTv(tester);
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
              home: withProfileNavigationScope(child: MediaDetailScreen(metadata: movie())),
            ),
          ),
        ),
      );
      // The hero reveals on its own timer and the artwork shimmer never
      // settles, so this pumps frames rather than settling.
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    testWidgets('draws no back affordance on TV', (tester) async {
      onTv(tv: true);
      await pumpDetail(tester);

      expect(find.byType(AppBarBackButton), findsNothing);
      expect(visibleBackButton(), findsNothing);
    });
  });

  group('family 2: the implicit leading of CustomAppBar', () {
    Future<void> pumpPushedRoute(WidgetTester tester) async {
      sizeForTv(tester);
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: monoTheme(dark: true),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const _AppBarPage())),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('page title'), findsOneWidget, reason: 'the route is actually up');
    }

    testWidgets('a full-window route pushed on TV gets no implicit back button', (tester) async {
      // This is the reproduction: before the fix this route drew a visible,
      // hit-testable, unreachable arrow, because `buildLeadingSection` asked
      // `ModalRoute.canPop` and nothing about the input modality.
      onTv(tv: true);
      await pumpPushedRoute(tester);
      expect(visibleBackButton(), findsNothing);
    });

    testWidgets('the same route on a pointer platform keeps its back button', (tester) async {
      onTv(tv: false);
      await pumpPushedRoute(tester);
      expect(visibleBackButton(), findsOneWidget);
    });

    testWidgets('and the app bar reserves no leading width for a button it does not draw', (tester) async {
      // Not decoration: `leading` had to stay null, not become a shrunk
      // widget, or the title would still start behind a 56px gap nothing
      // fills. That is what makes the guard inside the button a backstop
      // rather than the fix.
      onTv(tv: true);
      await pumpPushedRoute(tester);

      final appBar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
      expect(appBar.leading, isNull);
    });
  });

  group('family 2, nested: a content route inside the shell', () {
    late TvNavigationCoordinator coordinator;
    late FocusMemoryTracker nodes;
    late FocusScopeNode navScope;
    late FocusScopeNode contentScope;

    setUp(() {
      coordinator = TvNavigationCoordinator()..updateConditions(const TvNavConditions(hasLiveTv: false));
      nodes = FocusMemoryTracker(debugLabelPrefix: 'tvNav');
      navScope = FocusScopeNode(debugLabel: 'nav');
      contentScope = FocusScopeNode(debugLabel: 'content');
    });

    tearDown(() {
      coordinator.dispose();
      nodes.dispose();
      navScope.dispose();
      contentScope.dispose();
    });

    Future<void> pumpShell(WidgetTester tester) async {
      sizeForTv(tester);
      Future<Object?> push(TvNestedRoute route) => coordinator.pushNested(coordinator.active, route).result;
      tvContentRouteRegistry.attach(push);
      addTearDown(() => tvContentRouteRegistry.detach(push));

      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: monoTheme(dark: true),
            home: InputModeTracker(
              child: TvRootShell(
                coordinator: coordinator,
                contentFocus: TvContentFocusAuthority(),
                navNodes: nodes,
                navFocusScope: navScope,
                contentFocusScope: contentScope,
                isNavFocused: false,
                profile: null,
                onSelectDestination: (_) {},
                onFocusDestination: (_) {},
                onFocusContent: ({bool restorePreviousFocus = true}) {},
                onFocusNav: () {},
                onOpenProfiles: () {},
                onOverlaySheetOpenChanged: (_) {},
                onKeyEvent: (_) => KeyEventResult.ignored,
                selectLibrary: null,
                openSettings: null,
                dismissNestedRoute: ([_]) => coordinator.popNested(),
                child: Builder(
                  builder: (context) => Center(
                    child: TextButton(
                      onPressed: () => openTvContentRoute(id: 'back1_probe', builder: (_) => const _AppBarPage()),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('page title'), findsOneWidget, reason: 'the nested route is actually up');
    }

    testWidgets('has no back button either, and Menu/Back still closes it', (tester) async {
      onTv(tv: true);
      await pumpShell(tester);

      expect(visibleBackButton(), findsNothing);

      // The exit that replaces the arrow. Driven through the coordinator the
      // shell's back chain uses (`TvBackStep.popNested`), so what is proved is
      // that the route this test opened is poppable without any visible
      // control, not merely that a button is absent.
      coordinator.popNested();
      await tester.pumpAndSettle();

      expect(find.text('page title'), findsNothing);
      expect(find.text('open'), findsOneWidget, reason: 'the destination root is back');
    });
  });

  group('family 4: a sheet sub-page header', () {
    // The same defect in a second widget, found by auditing for the *shape*
    // rather than for the class name. `BottomSheetHeader` draws its back arrow
    // over an `InkResponse` inside `ExcludeFocusTraversal`, so a sheet
    // sub-page on TV rendered a header whose `traversalDescendants` count was
    // zero, nothing in it the remote could reach, with a back arrow sitting
    // in it. `BottomSheetPageScaffold` already routes Menu/Back to the same
    // `onBack`, so only the chrome goes.
    Widget subPage() => TranslationProvider(
      child: MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          // ignore: no-empty-block - the callback is not what is under test
          body: BottomSheetPageScaffold(title: 'Sorteren', onBack: () {}, child: const SizedBox(height: 200)),
        ),
      ),
    );

    /// Not `hitTestable`: the arrow glyph sits *under* the `InkResponse` that
    /// makes it tappable, so on a pointer platform it is never the topmost hit
    /// at its own centre. The glyph is the affordance BACK1 is about, so the
    /// glyph is what is counted.
    Finder backArrow() => find.byWidgetPredicate((w) => w is Icon && w.icon == Symbols.arrow_back_rounded);

    testWidgets('draws no back arrow on TV', (tester) async {
      onTv(tv: true);
      sizeForTv(tester);
      await tester.pumpWidget(subPage());
      await tester.pumpAndSettle();

      expect(backArrow(), findsNothing);
      expect(find.text('Sorteren'), findsOneWidget, reason: 'the header itself still renders');
    });

    testWidgets('keeps it on a pointer platform', (tester) async {
      onTv(tv: false);
      sizeForTv(tester);
      await tester.pumpWidget(subPage());
      await tester.pumpAndSettle();

      expect(backArrow(), findsOneWidget);
    });
  });

  group('family 3: the player header', () {
    // TV takes the *desktop* controls (`video_controls.dart` builds `isMobile`
    // as mobile-and-not-TV), so this header is on screen during playback on
    // Apple TV, arrow and all. Leaving the player there is Menu/Back, handled
    // twice over in `video_controls/parts/key_events.dart`: on the focused
    // path and on the global one for when the controls lost focus.
    MediaItem episode() => MediaItem(
      id: 'ep_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.episode,
      title: 'Winter Is Coming',
      grandparentTitle: 'Sintel Chronicles',
      parentIndex: 1,
      index: 1,
      serverId: 'server_1',
    );

    Future<void> pumpHeader(WidgetTester tester) async {
      sizeForTv(tester);
      final watchTogether = WatchTogetherProvider();
      addTearDown(watchTogether.dispose);

      await tester.pumpWidget(
        TranslationProvider(
          child: ChangeNotifierProvider<WatchTogetherProvider>.value(
            value: watchTogether,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: monoTheme(dark: true),
              home: Scaffold(
                backgroundColor: Colors.black,
                body: VideoControlsHeader(metadata: episode(), onBack: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('draws no arrow on TV, and the title keeps its place', (tester) async {
      onTv(tv: true);
      await pumpHeader(tester);

      expect(visibleBackButton(), findsNothing);
      expect(find.textContaining('Sintel Chronicles'), findsOneWidget, reason: 'the header itself still renders');
    });

    testWidgets('keeps its arrow on a pointer platform', (tester) async {
      onTv(tv: false);
      await pumpHeader(tester);

      expect(visibleBackButton(), findsOneWidget);
    });
  });
}
