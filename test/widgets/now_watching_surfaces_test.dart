import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:pleya/media/watch_session.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/providers/now_watching_provider.dart';
import 'package:pleya/screens/media_detail/now_watching_line.dart';
import 'package:pleya/services/now_watching_service.dart';
import 'package:pleya/services/tautulli/tautulli_client.dart';
import 'package:pleya/services/tautulli/tautulli_constants.dart';
import 'package:pleya/services/tautulli/tautulli_session.dart';
import 'package:pleya/widgets/now_watching/now_watching_button.dart';
import 'package:pleya/widgets/now_watching/now_watching_panel.dart';
import 'package:provider/provider.dart';

/// The surfaces that show who is streaming. The rule they all obey: nothing
/// playing means nothing drawn, so no toolbar and no page ever shifts because a
/// stream started or stopped.

class _FakeService implements NowWatchingService {
  _FakeService(this.answer);

  NowWatching Function() answer;

  @override
  Future<NowWatching?> resolve(TautulliClient tautulli, {int? selfUserId, MediaServerClient? artworkClient}) async =>
      answer();

  @override
  NowWatching map(activity, {int? selfUserId, MediaServerClient? artworkClient}) => NowWatching.empty;
}

WatchSession _session({
  String id = '1',
  String user = 'user67',
  String title = 'Reacher',
  String? ratingKey,
  StreamDelivery delivery = StreamDelivery.directPlay,
  bool paused = false,
  int progress = 42,
}) => WatchSession(
  id: id,
  userName: user,
  title: title,
  ratingKey: ratingKey,
  delivery: delivery,
  isPaused: paused,
  progressPercent: progress,
  bandwidthKbps: 8000,
);

Future<NowWatchingProvider> _providerWith(NowWatching now) async {
  final client = TautulliClient(
    TautulliSession(baseUrl: 'https://tautulli.example.test', authMode: TautulliAuthMode.apiKey, token: 'T'),
    httpClient: MockClient((_) async => http.Response('{}', 200)),
  );
  final provider = NowWatchingProvider(client: () => client, enabled: () => true, service: _FakeService(() => now));
  await provider.refresh();
  return provider;
}

Future<void> _pump(WidgetTester tester, NowWatchingProvider provider, Widget child, {TargetPlatform? platform}) =>
    tester.pumpWidget(
      ChangeNotifierProvider<NowWatchingProvider>.value(
        value: provider,
        child: MaterialApp(
          // The button opens a sheet on a phone and an overlay everywhere else,
          // and the two are torn down along different paths.
          theme: platform == null ? null : ThemeData(platform: platform),
          home: Scaffold(body: child),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the presence control', () {
    testWidgets('draws nothing when nobody else is watching', (tester) async {
      final provider = await _providerWith(NowWatching.empty);
      addTearDown(provider.dispose);

      await _pump(tester, provider, const NowWatchingButton());

      expect(find.byType(SizedBox), findsWidgets);
      expect(find.textContaining('1'), findsNothing);
    });

    testWidgets('shows the number of streams once someone is', (tester) async {
      final provider = await _providerWith(
        NowWatching(
          sessions: [
            _session(),
            _session(id: '2', user: 'user12'),
          ],
        ),
      );
      addTearDown(provider.dispose);

      await _pump(tester, provider, const NowWatchingButton());

      expect(find.text('2'), findsOneWidget);
    });

    // The overlay lives in the Overlay, not under the button, so it does not go
    // away with the button that stopped drawing: an empty panel would sit over
    // the page until the user clicked next to it.
    testWidgets('closes an open overlay when the last stream ends', (tester) async {
      var now = NowWatching(sessions: [_session()]);
      final client = TautulliClient(
        TautulliSession(baseUrl: 'https://tautulli.example.test', authMode: TautulliAuthMode.apiKey, token: 'T'),
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      final provider = NowWatchingProvider(client: () => client, enabled: () => true, service: _FakeService(() => now));
      addTearDown(provider.dispose);
      await provider.refresh();

      await _pump(tester, provider, const NowWatchingButton(), platform: TargetPlatform.macOS);
      tester.state<NowWatchingButtonState>(find.byType(NowWatchingButton)).togglePanel();
      await tester.pump();
      expect(find.byType(NowWatchingPanel), findsOneWidget);

      now = NowWatching.empty;
      await provider.refresh();
      await tester.pumpAndSettle();

      expect(find.byType(NowWatchingPanel), findsNothing);
      // And the faster tempo went back with it, rather than polling on for a
      // panel nobody can see.
      expect(provider.pollInterval, isNull);
    });
  });

  group('the panel', () {
    testWidgets('summarises the streams and names the delivery', (tester) async {
      final now = NowWatching(
        sessions: [
          _session(delivery: StreamDelivery.transcode),
          _session(id: '2', user: 'user12', delivery: StreamDelivery.directPlay),
        ],
        totalBandwidthKbps: 16000,
      );
      await _pump(tester, await _providerWith(now), NowWatchingPanel(now: now));

      expect(find.textContaining('2'), findsWidgets);
      expect(find.text('Transcode'), findsOneWidget);
      expect(find.text('Direct play'), findsOneWidget);
    });

    testWidgets('a paused stream says so instead of counting down', (tester) async {
      final now = NowWatching(sessions: [_session(paused: true)]);
      await _pump(tester, await _providerWith(now), NowWatchingPanel(now: now));

      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
    });
  });

  group('the line on a detail page', () {
    testWidgets('names the viewer of this title', (tester) async {
      final provider = await _providerWith(NowWatching(sessions: [_session(ratingKey: '57752')]));
      addTearDown(provider.dispose);

      await _pump(tester, provider, const NowWatchingLine(ratingKey: '57752'));

      expect(find.textContaining('user67'), findsOneWidget);
      expect(find.textContaining('42%'), findsOneWidget);
    });

    // A session on one episode is that episode's news, not the show's.
    testWidgets('stays silent for a different title', (tester) async {
      final provider = await _providerWith(NowWatching(sessions: [_session(ratingKey: '57781')]));
      addTearDown(provider.dispose);

      await _pump(tester, provider, const NowWatchingLine(ratingKey: '42716'));

      expect(find.textContaining('user67'), findsNothing);
    });

    testWidgets('stays silent without a provider at all', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NowWatchingLine(ratingKey: '57752')),
        ),
      );

      expect(find.textContaining('user67'), findsNothing);
    });
  });
}
