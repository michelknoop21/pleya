/// SYS-1b: detail, collection and person open over the nested route contract.
///
/// SYS-1a built the contract and moved the settings subpages onto it;
/// `test/screens/tv/tv_content_route_test.dart` owns that mechanism and
/// `test/navigation/tv/tv_nested_route_viewport_test.dart` owns INV-1. What is
/// left, and what this file asserts, is that the three *content* surfaces PB-1
/// names — film and series detail (09, 10), collection (24) and person (25) —
/// actually take that route rather than the full-window push they used to.
///
/// The screens themselves are never mounted. A nested route's builder does not
/// run until a shell renders it, and no shell is rendered here, so the
/// assertion is about the choice the call site makes and the identity it hands
/// over. Mounting `MediaDetailScreen` would drag its whole provider graph in
/// and prove nothing extra about the choice.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/navigation/tv/tv_content_route_registry.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/navigation/tv/tv_nested_surface.dart';
import 'package:pleya/screens/focusable_detail_screen_mixin.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/mixins/grid_focus_node_mixin.dart';
import 'package:pleya/focus/focusable_action_bar.dart';
import 'package:pleya/utils/media_navigation_helper.dart';
import 'package:pleya/utils/platform_detector.dart';

MediaItem _movie({String serverId = 'server-1'}) =>
    MediaItem(id: 'movie-1', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Movie', serverId: serverId);

MediaItem _episode() => MediaItem(
  id: 'episode-1',
  backend: MediaBackend.plex,
  kind: MediaKind.episode,
  title: 'Episode 1',
  parentId: 'season-2',
  parentIndex: 2,
  grandparentId: 'show-1',
  grandparentTitle: 'The Show',
  serverId: 'server-1',
);

MediaItem _collection() => MediaItem(
  id: 'collection-1',
  backend: MediaBackend.plex,
  kind: MediaKind.collection,
  title: 'Marvel',
  serverId: 'server-1',
);

/// A shell that takes every content route and hands back the route object,
/// without rendering it. That is the whole point: the call site's choice is
/// observable one step before any screen is built.
class _FakeShell {
  final List<TvNestedRoute> taken = [];

  /// A field and not a method, because [TvContentRouteRegistry.detach] guards
  /// on `identical` and a method tear-off is only guaranteed to be `==`.
  late final TvContentRoutePush push = (route) {
    taken.add(route);
    return route.result;
  };

  TvNestedRoute get only {
    expect(taken, hasLength(1), reason: 'exactly one content route should have been opened');
    return taken.single;
  }

  void attach() {
    tvContentRouteRegistry.attach(push);
    addTearDown(() => tvContentRouteRegistry.detach(push));
  }
}

/// Records what reached the navigator, so "it did not push" is an assertion
/// rather than an absence nobody looked for.
class _PushRecorder extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) pushed.add(route);
  }
}

/// Runs [body] with a `BuildContext` under a navigator whose pushes are
/// recorded.
Future<void> pumpCaller(WidgetTester tester, _PushRecorder recorder, Future<void> Function(BuildContext) body) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [recorder],
      home: Builder(
        builder: (context) {
          captured = context;
          return const Scaffold(body: SizedBox());
        },
      ),
    ),
  );
  await body(captured);
}

/// Drops a route the navigator has accepted, before any frame builds it.
///
/// The negative control is about which mechanism the call site chose, and it
/// has made that choice by the time `didPush` fires. Letting the route live
/// into a build would mount the real detail screen, which is a different test
/// with a different set of dependencies — and leaving its transition running
/// past the end of the test is an invariant failure of its own.
void discard(_PushRecorder recorder) => recorder.navigator!.removeRoute(recorder.pushed.single);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Process-wide registry: a leaked attach would silently decide the next
    // test's answer for it.
    expect(tvContentRouteRegistry.isAvailable, isFalse);
    // Pinned rather than assumed. `mediaDetailRoute` picks its transition off
    // this, and the fallback path's assertion is about the shape it produces.
    TvDetectionService.debugSetAppleTVOverride(false);
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  group('the route identity', () {
    test('is the title on its server, so two servers sharing a rating key stay two screens', () {
      final a = tvDetailRouteId(mediaDetailNavigationTargetFor(_movie(serverId: 'server-1')));
      final b = tvDetailRouteId(mediaDetailNavigationTargetFor(_movie(serverId: 'server-2')));

      expect(a, isNot(b));
    });

    test('is stable for the same target, so a second Select opens one screen and needs one Back', () {
      final first = tvDetailRouteId(mediaDetailNavigationTargetFor(_episode()));
      final second = tvDetailRouteId(mediaDetailNavigationTargetFor(_episode()));

      expect(first, second);
    });

    test('separates the same show entered at a different season or episode', () {
      final show = mediaDetailNavigationTargetFor(_episode());
      final bare = mediaDetailNavigationTargetFor(
        MediaItem(
          id: 'show-1',
          backend: MediaBackend.plex,
          kind: MediaKind.show,
          title: 'The Show',
          serverId: 'server-1',
        ),
      );

      expect(show.metadata.id, bare.metadata.id, reason: 'same title: only the entry point differs');
      expect(tvDetailRouteId(show), isNot(tvDetailRouteId(bare)));
    });
  });

  group('detail', () {
    testWidgets('opens inside the shell and pushes nothing on the navigator', (tester) async {
      final shell = _FakeShell()..attach();
      final recorder = _PushRecorder();

      await pumpCaller(tester, recorder, (context) async {
        unawaited(navigateToMediaItemDetails(context, _movie()));
      });

      expect(shell.only.id, tvDetailRouteId(mediaDetailNavigationTargetFor(_movie())));
      expect(recorder.pushed, isEmpty, reason: 'PB-1: this is exactly the full-window push that took the bar away');

      shell.only.completeResult(null);
    });

    testWidgets('NEGATIVE CONTROL: with no shell listening it pushes on the navigator as before', (tester) async {
      final recorder = _PushRecorder();

      await pumpCaller(tester, recorder, (context) async {
        unawaited(navigateToMediaItemDetails(context, _movie()));
      });

      expect(recorder.pushed, hasLength(1));
      expect(recorder.pushed.single, isA<PageRoute<bool>>());
      discard(recorder);
      await tester.pumpAndSettle();
    });

    testWidgets('the result the route is closed with reaches the caller', (tester) async {
      final shell = _FakeShell()..attach();
      final recorder = _PushRecorder();
      final refreshed = <String>[];

      await pumpCaller(tester, recorder, (context) async {
        unawaited(navigateToMediaItemDetails(context, _movie(), onRefresh: refreshed.add));
      });

      shell.only.completeResult(true);
      await tester.pumpAndSettle();

      expect(refreshed, ['movie-1'], reason: 'the watch state changed, so the row that opened this has to redraw');
    });

    testWidgets('and a route closed with nothing refreshes nothing', (tester) async {
      final shell = _FakeShell()..attach();
      final recorder = _PushRecorder();
      final refreshed = <String>[];

      await pumpCaller(tester, recorder, (context) async {
        unawaited(navigateToMediaItemDetails(context, _movie(), onRefresh: refreshed.add));
      });

      shell.only.completeResult(null);
      await tester.pumpAndSettle();

      expect(refreshed, isEmpty);
    });
  });

  group('collection', () {
    testWidgets('opens inside the shell and pushes nothing on the navigator', (tester) async {
      final shell = _FakeShell()..attach();
      final recorder = _PushRecorder();

      await pumpCaller(tester, recorder, (context) async {
        unawaited(navigateToMediaItem(context, _collection()));
      });

      expect(shell.only.id, 'tvCollection_${_collection().globalKey}');
      expect(recorder.pushed, isEmpty);

      shell.only.completeResult(null);
    });

    testWidgets('NEGATIVE CONTROL: with no shell listening it pushes on the navigator as before', (tester) async {
      final recorder = _PushRecorder();

      await pumpCaller(tester, recorder, (context) async {
        unawaited(navigateToMediaItem(context, _collection()));
      });

      expect(recorder.pushed, hasLength(1));
      discard(recorder);
      await tester.pumpAndSettle();
    });

    testWidgets('a deleted collection still tells its caller the list is stale', (tester) async {
      final shell = _FakeShell()..attach();
      final recorder = _PushRecorder();
      late Future<MediaNavigationResult> pending;

      await pumpCaller(tester, recorder, (context) async {
        pending = navigateToMediaItem(context, _collection());
      });

      // What `CollectionDetailScreen._deleteCollection` now hands to
      // `dismissDetailScreen`, which used to be `Navigator.pop(context, true)`.
      shell.only.completeResult(true);

      expect(await pending, MediaNavigationResult.listRefreshNeeded);
    });
  });

  group('the shared dismissal owner', () {
    testWidgets('nested, a detail screen closes its route instead of popping the navigator', (tester) async {
      final recorder = _PushRecorder();
      final route = TvNestedRoute(id: 'probe', builder: (_) => const SizedBox());
      Object? dismissedWith;
      var dismissals = 0;

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [recorder],
          home: TvNestedSurface(
            route: route,
            dismiss: ([result]) {
              dismissals++;
              dismissedWith = result;
            },
            child: const _DetailProbe(),
          ),
        ),
      );

      await tester.tap(find.text('close'));
      await tester.pumpAndSettle();

      expect(dismissals, 1);
      expect(dismissedWith, true);
      expect(recorder.pushed, isEmpty, reason: 'the navigator was never involved');
      expect(find.text('close'), findsOneWidget, reason: 'and nothing was popped out from under the screen');
    });

    testWidgets('nested, a system back cannot pop the route the shell itself is in', (tester) async {
      var dismissals = 0;
      final route = TvNestedRoute(id: 'probe', builder: (_) => const SizedBox());
      late NavigatorState navigator;

      // iOS, because that is the one platform where `buildDetailScaffold` used
      // to hand the pop straight to the route: `canPop` was
      // `PlatformDetector.isHandheldIOS`, and nested the route it would pop is
      // the one carrying the whole shell.
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true).copyWith(platform: TargetPlatform.iOS),
          home: Builder(
            builder: (context) {
              navigator = Navigator.of(context);
              return Scaffold(
                body: TextButton(
                  onPressed: () => navigator.push<Object?>(
                    MaterialPageRoute(
                      builder: (_) => TvNestedSurface(
                        route: route,
                        dismiss: ([result]) => dismissals++,
                        child: const _DetailProbe(),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('close'), findsOneWidget);

      await navigator.maybePop();
      await tester.pumpAndSettle();

      expect(dismissals, 1, reason: 'the nested route is what closes');
      expect(find.text('close'), findsOneWidget, reason: 'and the route under it is untouched');
    });

    testWidgets('NEGATIVE CONTROL: pushed on the navigator it pops the route it is in', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    Navigator.push<Object?>(context, MaterialPageRoute(builder: (_) => const _DetailProbe())),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('close'), findsOneWidget);

      await tester.tap(find.text('close'));
      await tester.pumpAndSettle();

      expect(find.text('close'), findsNothing, reason: 'no nested scope here, so `Navigator.pop` is still the answer');
      expect(find.text('open'), findsOneWidget);
    });
  });
}

/// The two screens PB-1 moves in here — collection and person — share
/// [FocusableDetailScreenMixin] and nothing else, so the dismissal is asserted
/// on the mixin rather than twice on two screens that would each need their own
/// media client to mount.
class _DetailProbe extends StatefulWidget {
  const _DetailProbe();

  @override
  State<_DetailProbe> createState() => _DetailProbeState();
}

class _DetailProbeState extends State<_DetailProbe>
    with GridFocusNodeMixin<_DetailProbe>, FocusableDetailScreenMixin<_DetailProbe> {
  @override
  bool get hasItems => false;

  @override
  List<FocusableAction> getAppBarActions() => const [];

  @override
  void dispose() {
    disposeFocusResources();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => buildDetailScaffold(
    slivers: [
      SliverToBoxAdapter(
        child: TextButton(onPressed: () => dismissDetailScreen(true), child: const Text('close')),
      ),
    ],
  );
}
