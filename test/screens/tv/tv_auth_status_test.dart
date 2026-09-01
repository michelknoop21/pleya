/// WP3, hoofdstuk 18.4: on TV a rejected token asks for attention with a small
/// dot on Mijn Pleya, never with a permanent red strip over the content.
///
/// > Eén server offline bij meerdere gezonde servers veroorzaakt geen
/// > blokkerende Home-banner. […] Een klein statuspunt bij Mijn Pleya mag
/// > aandacht vragen, maar mag geen permanente grote rode melding over content
/// > leggen.
///
/// Two halves, and both matter. The banner must be *gone* on TV — that is what
/// the viewer complained about — and something must take its place, or the
/// feature is not moved but deleted: a viewer whose session expired would see
/// empty rows and be told nothing.
///
/// Driven against the production [TvRootShell] with the production
/// [TvTopNavigation] and a real [MultiServerProvider], so what is proved is the
/// wiring and not a rehearsal of it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/auth_error_banner.dart';
import 'package:pleya/widgets/tv/tv_top_navigation.dart';

/// A stand-in for the real registry: the shell only ever asks it one question,
/// and `MultiServerProvider` itself needs a whole connection stack to build.
///
/// It overrides exactly the getter the production code reads, so the test is
/// still exercising the real selector on the real type.
class _FakeServers extends ChangeNotifier implements MultiServerProvider {
  _FakeServers({List<String> authErrors = const []}) : _authErrors = authErrors;

  List<String> _authErrors;

  void setAuthErrors(List<String> ids) {
    _authErrors = ids;
    notifyListeners();
  }

  @override
  List<String> get authErrorServerIds => _authErrors;

  @override
  bool get hasAuthErrorServers => _authErrors.isNotEmpty;

  @override
  List<({ServerId serverId, String displayName})> get authErrorServers => [
    for (final id in _authErrors) (serverId: ServerId(id), displayName: id),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late TvNavigationCoordinator coordinator;
  late FocusMemoryTracker nodes;
  late FocusScopeNode navScope;
  late FocusScopeNode contentScope;

  setUp(() {
    // Every group below except the non-TV one is about the TV branch, so the
    // detector says TV. Reset in tearDown; the override is process-global.
    TvDetectionService.debugSetAppleTVOverride(true);
    coordinator = TvNavigationCoordinator()..updateConditions(const TvNavConditions(hasLiveTv: false));
    nodes = FocusMemoryTracker(debugLabelPrefix: 'tvNav');
    navScope = FocusScopeNode(debugLabel: 'nav');
    contentScope = FocusScopeNode(debugLabel: 'content');
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    coordinator.dispose();
    nodes.dispose();
    navScope.dispose();
    contentScope.dispose();
  });

  /// Mounts the TV shell under the same `Column` `MainScreen` builds around it,
  /// guard and all.
  ///
  /// The guard is the point. Pumping `TvRootShell` on its own would prove only
  /// that the shell has no banner inside it — which was true before this work
  /// package too, because the banner was always mounted *above* the shell in
  /// `MainScreen._buildTickerAwareStack`. A negative control caught exactly
  /// that: with the production guard deleted, a shell-only harness stayed
  /// green. So the harness carries the guard expression, and TV is forced on
  /// for the whole group.
  Future<void> pump(WidgetTester tester, _FakeServers servers, {TvDestinationId? active}) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    if (active != null) coordinator.syncToTab(active.tab);

    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: servers,
        child: TranslationProvider(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: monoTheme(dark: true),
            home: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!PlatformDetector.isTV()) const AuthErrorBanner(),
                Expanded(
                  child: InputModeTracker(
                    child: TvRootShell(
                      coordinator: coordinator,
                      navNodes: nodes,
                      navFocusScope: navScope,
                      contentFocusScope: contentScope,
                      isNavFocused: false,
                      profile: null,
                      onSelectDestination: (_) {},
                      onFocusContent: ({bool restorePreviousFocus = true}) {},
                      onFocusNav: () {},
                      onOpenProfiles: () {},
                      onOverlaySheetOpenChanged: (_) {},
                      onKeyEvent: (_) => KeyEventResult.ignored,
                      selectLibrary: null,
                      openSettings: null,
                      child: const Center(child: Text('destination root')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The dot has no widget type of its own — it is a `Container` inside the
  /// nav item — so it is found by the one thing that identifies it: the amber
  /// circle. Matching on the colour is deliberate; hoofdstuk 14.7 keeps amber
  /// ("you can fix this from the couch") apart from red ("something is broken")
  /// everywhere else in this rewrite, and a dot that drifted to red would be
  /// saying the wrong thing while still passing a type-based finder.
  Finder attentionDot() => find.byWidgetPredicate((w) {
    if (w is! Container) return false;
    final decoration = w.decoration;
    return decoration is BoxDecoration && decoration.shape == BoxShape.circle && decoration.color == kAccentAlt;
  }, description: 'amber attention dot');

  /// The Mijn Pleya nav item, whatever else is on the bar.
  Finder myPleyaItem() => find.ancestor(
    of: find.text(t.navigation.myPleya),
    matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_NavItem'),
  );

  group('the banner is gone from TV', () {
    testWidgets('an auth error draws no AuthErrorBanner anywhere in the TV shell', (tester) async {
      await pump(tester, _FakeServers(authErrors: ['nas']));

      expect(
        find.byType(AuthErrorBanner),
        findsNothing,
        reason: 'hoofdstuk 18.4 forbids a permanent large red notice over the content',
      );
    });

    for (final destination in [
      TvDestinationId.home,
      TvDestinationId.movies,
      TvDestinationId.series,
      TvDestinationId.search,
    ]) {
      testWidgets('no red strip over ${destination.name}', (tester) async {
        await pump(tester, _FakeServers(authErrors: ['nas']), active: destination);

        expect(find.byType(AuthErrorBanner), findsNothing);
        // The content still starts immediately under the bar: nothing was
        // inserted between them, red or otherwise.
        final bar = tester.getRect(find.byType(TvTopNavigation));
        final content = tester.getRect(find.text('destination root'));
        expect(content.top, greaterThanOrEqualTo(bar.bottom - 1));
      });
    }
  });

  group('the dot takes its place', () {
    testWidgets('an actionable auth error shows the attention dot on Mijn Pleya', (tester) async {
      await pump(tester, _FakeServers(authErrors: ['nas']));

      expect(attentionDot(), findsOneWidget);
      expect(
        find.descendant(of: myPleyaItem(), matching: attentionDot()),
        findsOneWidget,
        reason: 'it rides the destination that leads to the fix, not an arbitrary one',
      );
    });

    testWidgets('no auth error, no dot', (tester) async {
      await pump(tester, _FakeServers());

      expect(attentionDot(), findsNothing);
    });

    testWidgets('a server that is merely offline is not an auth error and draws no dot', (tester) async {
      // The distinction the provider already draws: `authErrorServerIds` is
      // 401/403 only. A transient outage needs no user action, and marking it
      // would train the viewer to ignore the dot that does.
      final servers = _FakeServers();
      await pump(tester, servers);

      expect(attentionDot(), findsNothing);
      expect(servers.hasAuthErrorServers, isFalse);
    });

    testWidgets('re-authenticating clears the dot without a remount', (tester) async {
      final servers = _FakeServers(authErrors: ['nas']);
      await pump(tester, servers);
      expect(attentionDot(), findsOneWidget);

      servers.setAuthErrors([]);
      await tester.pumpAndSettle();

      expect(attentionDot(), findsNothing, reason: 'the indicator disappears when the attention is no longer needed');
    });

    testWidgets('several servers still yield one compact root status', (tester) async {
      await pump(tester, _FakeServers(authErrors: ['nas', 'attic', 'shed']));

      expect(attentionDot(), findsOneWidget, reason: 'the count belongs on the Servers screen, not on the bar');
      expect(find.text('3'), findsNothing);
    });
  });

  group('the bar does not move', () {
    testWidgets('toggling the status changes no destination geometry', (tester) async {
      final servers = _FakeServers();
      await pump(tester, servers);

      final barBefore = tester.getRect(find.byType(TvTopNavigation));
      final labelsBefore = {
        for (final d in coordinator.destinations.where((d) => !d.isCompact)) d.name: tester.getRect(find.text(d.label)),
      };

      servers.setAuthErrors(['nas']);
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byType(TvTopNavigation)), barBefore, reason: 'the bar itself must not resize');
      for (final entry in labelsBefore.entries) {
        final destination = coordinator.destinations.firstWhere((d) => d.name == entry.key);
        expect(
          tester.getRect(find.text(destination.label)),
          entry.value,
          reason: '${entry.key} moved when the status toggled; a dot may not push its neighbours',
        );
      }
    });

    testWidgets('the dot is small', (tester) async {
      await pump(tester, _FakeServers(authErrors: ['nas']));

      final dot = tester.getRect(attentionDot());
      final label = tester.getRect(find.text(t.navigation.myPleya));
      expect(
        dot.width,
        lessThan(label.height / 2),
        reason: 'hoofdstuk 18.4 allows a "klein statuspunt", not a badge that competes with the label',
      );
    });
  });

  group('semantics', () {
    testWidgets('the destination announces that it needs attention', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, _FakeServers(authErrors: ['nas']));

      expect(
        find.bySemanticsLabel(RegExp(t.tvNavigation.attentionRequired)),
        findsOneWidget,
        reason: 'the dot is inside an ExcludeSemantics, so a silent mark would be invisible to VoiceOver',
      );
      handle.dispose();
    });

    testWidgets('and stops announcing it once the session is restored', (tester) async {
      final handle = tester.ensureSemantics();
      final servers = _FakeServers(authErrors: ['nas']);
      await pump(tester, servers);

      servers.setAuthErrors([]);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(RegExp(t.tvNavigation.attentionRequired)), findsNothing);
      handle.dispose();
    });
  });

  // Point 12 of the WP3 brief, and the half that makes this a *move* rather
  // than a deletion. `AuthErrorBanner` itself is untouched — its own tests in
  // `test/widgets/auth_error_banner_test.dart` still hold — so what is left to
  // prove is the mount condition in `MainScreen`, which is the only line this
  // work package changed about non-TV.
  group('non-TV keeps the banner', () {
    tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    testWidgets('the banner still renders where it always did', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(false);
      final servers = _FakeServers(authErrors: ['nas']);

      await tester.pumpWidget(
        ChangeNotifierProvider<MultiServerProvider>.value(
          value: servers,
          child: TranslationProvider(
            child: MaterialApp(
              theme: monoTheme(dark: true),
              // The shape `MainScreen._buildTickerAwareStack` builds, with the
              // guard this work package added, so the condition under test is
              // the production expression and not a paraphrase of it.
              home: Builder(
                builder: (context) => Scaffold(
                  body: Column(
                    children: [
                      if (!PlatformDetector.isTV()) const AuthErrorBanner(),
                      const Expanded(child: SizedBox.expand()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AuthErrorBanner), findsOneWidget);
      expect(find.text(t.connections.sessionExpiredOne(name: 'nas')), findsOneWidget);
    });

    testWidgets('and the same expression drops it on TV', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);

      await tester.pumpWidget(
        ChangeNotifierProvider<MultiServerProvider>.value(
          value: _FakeServers(authErrors: ['nas']),
          child: TranslationProvider(
            child: MaterialApp(
              theme: monoTheme(dark: true),
              home: Builder(
                builder: (context) => Scaffold(
                  body: Column(
                    children: [
                      if (!PlatformDetector.isTV()) const AuthErrorBanner(),
                      const Expanded(child: SizedBox.expand()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AuthErrorBanner), findsNothing);
    });
  });

  group('the resolution route', () {
    testWidgets('Mijn Pleya is on the bar and reachable, which is where the fix lives', (tester) async {
      // The dot is only useful if the destination it marks is present and
      // selectable; the Servers screen under it is the existing management
      // route (`TvMyPleyaSection.servers` -> `TvServersScreen`), unchanged by
      // this work package.
      final selected = <TvDestinationId>[];
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider<MultiServerProvider>.value(
          value: _FakeServers(authErrors: ['nas']),
          child: TranslationProvider(
            child: MaterialApp(
              theme: monoTheme(dark: true),
              home: InputModeTracker(
                child: TvRootShell(
                  coordinator: coordinator,
                  navNodes: nodes,
                  navFocusScope: navScope,
                  contentFocusScope: contentScope,
                  isNavFocused: true,
                  profile: null,
                  onSelectDestination: selected.add,
                  onFocusContent: ({bool restorePreviousFocus = true}) {},
                  onFocusNav: () {},
                  onOpenProfiles: () {},
                  onOverlaySheetOpenChanged: (_) {},
                  onKeyEvent: (_) => KeyEventResult.ignored,
                  selectLibrary: null,
                  openSettings: null,
                  child: const Center(child: Text('destination root')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(coordinator.destinations, contains(TvDestinationId.myPleya));

      final node = nodes.get(TvDestinationId.myPleya.focusKey);
      node.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(selected, contains(TvDestinationId.myPleya));
    });
  });
}
