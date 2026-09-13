import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:pleya/media/watch_session.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/navigation/tv/tv_nested_surface.dart';
import 'package:pleya/providers/now_watching_provider.dart';
import 'package:pleya/screens/now_watching_screen.dart';
import 'package:pleya/screens/tv/sections/tv_now_watching_screen.dart';
import 'package:pleya/services/now_watching_service.dart';
import 'package:pleya/services/tautulli/tautulli_client.dart';
import 'package:pleya/services/tautulli/tautulli_constants.dart';
import 'package:pleya/services/tautulli/tautulli_session.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/now_watching/now_watching_panel.dart';
import 'package:provider/provider.dart';

/// MOC-16b / ACT2: a route mounted inside a [TvNestedRoute] must close through
/// [TvNestedRouteScope.dismiss], never through a bare `Navigator.pop`, which
/// reaches the profile navigator that owns the whole shell instead of just
/// this route.

class _FakeService implements NowWatchingService {
  _FakeService(this.answer);

  NowWatching Function() answer;

  @override
  Future<NowWatching?> resolve(TautulliClient tautulli, {int? selfUserId, MediaServerClient? artworkClient}) async =>
      answer();

  @override
  NowWatching map(activity, {int? selfUserId, MediaServerClient? artworkClient}) => NowWatching.empty;
}

WatchSession _session({String id = '1', String user = 'user67', String title = 'Reacher'}) =>
    WatchSession(id: id, userName: user, title: title, bandwidthKbps: 8000);

/// A provider plus the setter that drives what it will resolve to next. The
/// setter, not a reassigned local, is what the fake service closure reads, so
/// a later `next.value = NowWatching.empty` actually reaches it.
class _Fixture {
  _Fixture(this.provider, this.next);

  final NowWatchingProvider provider;
  final _Box next;
}

class _Box {
  _Box(this.value);
  NowWatching value;
}

Future<_Fixture> _providerWith(NowWatching now) async {
  final client = TautulliClient(
    TautulliSession(baseUrl: 'https://tautulli.example.test', authMode: TautulliAuthMode.apiKey, token: 'T'),
    httpClient: MockClient((_) async => http.Response('{}', 200)),
  );
  final box = _Box(now);
  final provider = NowWatchingProvider(
    client: () => client,
    enabled: () => true,
    service: _FakeService(() => box.value),
  );
  await provider.refresh();
  return _Fixture(provider, box);
}

/// Wraps [child] the way [TvNestedRoute] wraps a section screen: a scope whose
/// `dismiss` a well-behaved screen calls, sitting inside a real [Navigator] so
/// a screen that instead calls the bare `Navigator.pop` has somewhere to
/// wrongly pop.
Widget _asNestedRoute(Widget child, {required void Function([Object?]) dismiss}) => MaterialApp(
  theme: monoTheme(dark: true),
  home: Navigator(
    onGenerateRoute: (_) => MaterialPageRoute<void>(
      builder: (context) => TvNestedRouteScope(dismiss: dismiss, markResult: (_) {}, child: child),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ACT2 negative control', () {
    // Proves the failure mode this screen exists to avoid: the shared
    // NowWatchingScreen (still correct for its mobile/desktop Navigator.push
    // callers) auto-pops with a bare Navigator.pop, which inside a
    // TvNestedRoute never reaches the scope's dismiss.
    testWidgets('the shared NowWatchingScreen does not call the nested-route dismiss', (tester) async {
      final fixture = await _providerWith(NowWatching(sessions: [_session()]));
      addTearDown(fixture.provider.dispose);
      var dismissed = false;

      await tester.pumpWidget(
        ChangeNotifierProvider<NowWatchingProvider>.value(
          value: fixture.provider,
          child: _asNestedRoute(const NowWatchingScreen(), dismiss: ([_]) => dismissed = true),
        ),
      );
      await tester.pump();

      fixture.next.value = NowWatching.empty;
      await fixture.provider.refresh();
      await tester.pump();
      await tester.pump();

      expect(dismissed, isFalse);
    });
  });

  group('TvNowWatchingScreen', () {
    testWidgets('shows the panel while someone is watching', (tester) async {
      final fixture = await _providerWith(NowWatching(sessions: [_session()]));
      addTearDown(fixture.provider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<NowWatchingProvider>.value(
          value: fixture.provider,
          child: _asNestedRoute(const TvNowWatchingScreen(), dismiss: ([_]) {}),
        ),
      );
      await tester.pump();

      expect(find.byType(NowWatchingPanel), findsOneWidget);
      expect(find.textContaining('user67'), findsOneWidget);
    });

    testWidgets('dismisses through the nested-route scope, not a bare Navigator.pop, when the last stream ends', (
      tester,
    ) async {
      final fixture = await _providerWith(NowWatching(sessions: [_session()]));
      addTearDown(fixture.provider.dispose);
      var dismissed = false;

      await tester.pumpWidget(
        ChangeNotifierProvider<NowWatchingProvider>.value(
          value: fixture.provider,
          child: _asNestedRoute(const TvNowWatchingScreen(), dismiss: ([_]) => dismissed = true),
        ),
      );
      await tester.pump();
      expect(find.byType(NowWatchingPanel), findsOneWidget);

      fixture.next.value = NowWatching.empty;
      await fixture.provider.refresh();
      await tester.pump();
      await tester.pump();

      expect(dismissed, isTrue);
      // The screen itself is still there: dismiss is a coordinator callback,
      // not a real pop, so nothing should have unmounted it out from under us.
      expect(find.byType(TvNowWatchingScreen), findsOneWidget);
    });

    testWidgets('falls back to Navigator.pop when there is no nested-route scope', (tester) async {
      final fixture = await _providerWith(NowWatching(sessions: [_session()]));
      addTearDown(fixture.provider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<NowWatchingProvider>.value(
          value: fixture.provider,
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: Navigator(
              onGenerateRoute: (_) =>
                  MaterialPageRoute<void>(builder: (context) => const Scaffold(body: TvNowWatchingScreen())),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(TvNowWatchingScreen), findsOneWidget);

      fixture.next.value = NowWatching.empty;
      await fixture.provider.refresh();
      await tester.pumpAndSettle();

      expect(find.byType(TvNowWatchingScreen), findsNothing);
    });
  });
}
