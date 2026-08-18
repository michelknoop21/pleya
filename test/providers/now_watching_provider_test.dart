import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/watch_session.dart';
import 'package:pleya/providers/now_watching_provider.dart';
import 'package:pleya/services/now_watching_service.dart';
import 'package:pleya/services/tautulli/tautulli_client.dart';
import 'package:pleya/services/tautulli/tautulli_constants.dart';
import 'package:pleya/services/tautulli/tautulli_session.dart';

/// Answers whatever the test queues, without a transport. Null stands for "the
/// instance could not be reached", which the provider treats differently from
/// an empty answer.
class _FakeService implements NowWatchingService {
  _FakeService(this.answer);

  NowWatching? Function() answer;
  int calls = 0;

  @override
  Future<NowWatching?> resolve(TautulliClient tautulli, {int? selfUserId, MediaServerClient? artworkClient}) async {
    calls++;
    return answer();
  }

  @override
  NowWatching map(activity, {int? selfUserId, MediaServerClient? artworkClient}) => NowWatching.empty;
}

WatchSession _session(String id, {int? remainingSeconds, int progressPercent = 0}) => WatchSession(
  id: id,
  userName: 'user67',
  title: 'Reacher',
  progressPercent: progressPercent,
  remainingSeconds: remainingSeconds,
);

NowWatching _watching(int count) => NowWatching(sessions: [for (var i = 0; i < count; i++) _session('$i')]);

TautulliClient _client() => TautulliClient(
  TautulliSession(baseUrl: 'https://tautulli.example.test', authMode: TautulliAuthMode.apiKey, token: 'T'),
  httpClient: MockClient((_) async => http.Response('{}', 200)),
);

NowWatchingProvider _provider(_FakeService service, {bool enabled = true, TautulliClient? client}) {
  final resolved = client ?? _client();
  return NowWatchingProvider(client: () => resolved, enabled: () => enabled, service: service);
}

void main() {
  // The provider listens for the app leaving the foreground, which needs a
  // binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('nobody looking is no polling at all', () {
    final provider = _provider(_FakeService(() => NowWatching.empty));
    addTearDown(provider.dispose);

    expect(provider.pollInterval, isNull);
  });

  test('the presence control alone polls on the slow tempo', () async {
    final provider = _provider(_FakeService(() => _watching(1)));
    addTearDown(provider.dispose);

    provider.watchAmbient();
    expect(provider.pollInterval, NowWatchingProvider.ambientInterval);
  });

  test('an open panel raises the tempo and releasing it lowers it again', () async {
    final provider = _provider(_FakeService(() => _watching(1)));
    addTearDown(provider.dispose);

    provider.watchAmbient();
    provider.watchDetail();
    expect(provider.pollInterval, NowWatchingProvider.detailInterval);

    provider.releaseDetail();
    expect(provider.pollInterval, NowWatchingProvider.ambientInterval);

    provider.releaseAmbient();
    expect(provider.pollInterval, isNull);
  });

  // A Tautulli key opens the whole admin API, so a non-owner must not even
  // cause a request, let alone a hidden widget over a live poller.
  test('a profile without server ownership never polls', () async {
    final service = _FakeService(() => _watching(2));
    final provider = _provider(service, enabled: false);
    addTearDown(provider.dispose);

    provider.watchAmbient();
    provider.watchDetail();
    await provider.refresh();

    expect(provider.pollInterval, isNull);
    expect(service.calls, 0);
    expect(provider.hasOthers, isFalse);
  });

  test('a poll fills the sessions and notifies', () async {
    final provider = _provider(_FakeService(() => _watching(2)));
    addTearDown(provider.dispose);

    var notifications = 0;
    provider.addListener(() => notifications++);

    await provider.refresh();

    expect(provider.sessions, hasLength(2));
    expect(provider.hasOthers, isTrue);
    expect(notifications, 1);
  });

  // Repainting the app bar because a progress bar moved is noise; the panel
  // reads the same object either way.
  test('an unchanged picture does not notify again', () async {
    final provider = _provider(_FakeService(() => _watching(2)));
    addTearDown(provider.dispose);

    await provider.refresh();
    var notifications = 0;
    provider.addListener(() => notifications++);
    await provider.refresh();

    expect(notifications, 0);
  });

  // A whole percent of a three-hour film is nearly two minutes, so a comparison
  // that only looked at progressPercent left the open panel with a countdown
  // standing still and then jumping.
  test('a ticking countdown notifies even while the percentage holds', () async {
    var remaining = 7200;
    final provider = _provider(
      _FakeService(() {
        remaining -= 5;
        return NowWatching(sessions: [_session('0', progressPercent: 12, remainingSeconds: remaining)]);
      }),
    );
    addTearDown(provider.dispose);

    await provider.refresh();
    var notifications = 0;
    provider.addListener(() => notifications++);
    await provider.refresh();

    expect(provider.sessions.single.remainingSeconds, 7190);
    expect(notifications, 1);
  });

  group('an instance that stops answering', () {
    test('keeps the last picture through a single miss', () async {
      final service = _FakeService(() => _watching(2));
      final provider = _provider(service);
      addTearDown(provider.dispose);

      await provider.refresh();
      service.answer = () => null;
      await provider.refresh();

      expect(provider.sessions, hasLength(2), reason: 'one dropped request is not evidence that everyone stopped');
    });

    test('clears after the second miss in a row', () async {
      final service = _FakeService(() => _watching(2));
      final provider = _provider(service);
      addTearDown(provider.dispose);

      await provider.refresh();
      service.answer = () => null;
      await provider.refresh();
      await provider.refresh();

      expect(provider.sessions, isEmpty);
      expect(provider.hasOthers, isFalse);
    });

    test('a recovered answer resets the tolerance', () async {
      final service = _FakeService(() => _watching(1));
      final provider = _provider(service);
      addTearDown(provider.dispose);

      await provider.refresh();
      service.answer = () => null;
      await provider.refresh();
      service.answer = () => _watching(1);
      await provider.refresh();
      service.answer = () => null;
      await provider.refresh();

      expect(provider.sessions, hasLength(1));
    });
  });

  // An empty answer is a real answer, unlike a failed one.
  test('nobody watching clears immediately', () async {
    final service = _FakeService(() => _watching(2));
    final provider = _provider(service);
    addTearDown(provider.dispose);

    await provider.refresh();
    service.answer = () => NowWatching.empty;
    await provider.refresh();

    expect(provider.hasOthers, isFalse);
  });

  // A server can go offline, a profile switch can land on one this user does
  // not administer, Tautulli can be disconnected. A timer that keeps firing on
  // nothing for the rest of the session is the bug that hides behind that.
  test('losing server ownership mid-session stops the timer', () async {
    var owns = true;
    final service = _FakeService(() => _watching(2));
    final client = _client();
    final provider = NowWatchingProvider(client: () => client, enabled: () => owns, service: service);
    addTearDown(provider.dispose);

    provider.watchAmbient();
    await provider.refresh();
    expect(provider.pollInterval, NowWatchingProvider.ambientInterval);

    owns = false;
    await provider.refresh();

    expect(provider.pollInterval, isNull, reason: 'nothing left to ask, so nothing left to schedule');
    expect(provider.hasOthers, isFalse);
  });

  test('a disabled poll also forgets the failure streak', () async {
    var owns = true;
    final service = _FakeService(() => _watching(1));
    final client = _client();
    final provider = NowWatchingProvider(client: () => client, enabled: () => owns, service: service);
    addTearDown(provider.dispose);

    await provider.refresh();
    service.answer = () => null;
    await provider.refresh(); // one miss on the record

    owns = false;
    await provider.refresh(); // cleared, and the record wiped with it
    owns = true;
    service.answer = () => _watching(1);
    await provider.refresh();
    service.answer = () => null;
    await provider.refresh();

    expect(provider.sessions, hasLength(1), reason: 'the first miss after coming back may not clear anything');
  });

  test('without a Tautulli session there is nothing to ask', () async {
    final service = _FakeService(() => _watching(1));
    final provider = NowWatchingProvider(client: () => null, enabled: () => true, service: service);
    addTearDown(provider.dispose);

    provider.watchAmbient();
    await provider.refresh();

    expect(service.calls, 0);
    expect(provider.hasOthers, isFalse);
  });
}
