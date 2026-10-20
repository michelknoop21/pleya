import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/companion_remote/playback_handoff.dart';
import 'package:pleya/services/companion_remote/playback_handoff_sender.dart';

import '../../test_helpers/fake_handoff_transport.dart';

// A-23d: Pleya Fly from the Apple TV to an iPhone or iPad. The roles invert for
// one fly, so the Apple TV stops its own host, joins the phone, and must host
// again afterwards whatever happened; otherwise a phone cannot reach it until
// Pleya restarts.
void main() {
  late FakeHandoffTransport transport;
  late List<String> events;
  void Function()? currentStop;

  PlaybackHandoffSender sender() {
    final s = PlaybackHandoffSender(
      transport: transport,
      currentStop: () => currentStop,
      onPlaying: (host) => events.add('playing:${host.name}'),
      onFailed: (host, refusal) => events.add('failed:${host.name}${refusal == null ? '' : ':${refusal.name}'}'),
    );
    addTearDown(s.dispose);
    return s;
  }

  Future<void> fly(PlaybackHandoffSender s, {String name = 'iPhone van Michel'}) =>
      s.handOff(fakeHost(name), serverId: 'srv', itemId: '42', positionMs: 61000, title: 'Big Buck Bunny');

  setUp(() {
    transport = FakeHandoffTransport();
    events = [];
    currentStop = null;
  });

  group('the Apple TV host', () {
    for (final outcome in [
      PlaybackHandoffOutcome.playing,
      PlaybackHandoffOutcome.failed,
      PlaybackHandoffOutcome.timedOut,
      PlaybackHandoffOutcome.wrongProfile,
      PlaybackHandoffOutcome.pinCancelled,
    ]) {
      test('stops before joining the phone and hosts again after ${outcome.name}', () async {
        transport.answer = (_) async => outcome;
        await fly(sender());

        expect(transport.log.first, 'stopHost', reason: 'the host and the client share one peer service');
        expect(transport.log.indexOf('stopHost'), lessThan(transport.log.indexOf('connect:iPhone van Michel')));
        expect(transport.log.where((l) => l.endsWith('Host')).last, 'restartHost');
        expect(transport.log.indexOf('restartHost'), greaterThan(transport.log.indexOf('leave')));
        expect(transport.hostRunning, isTrue, reason: 'a phone must find this Apple TV again');
      });
    }

    test('hosts again when joining the phone throws', () async {
      final s = PlaybackHandoffSender(
        transport: _ThrowingConnect(),
        currentStop: () => null,
        onFailed: (host, _) => events.add('failed'),
      );
      addTearDown(s.dispose);
      await fly(s);
      final log = (s.transport as _ThrowingConnect).log;
      expect(log, ['stopHost', 'leave', 'restartHost', 'stopDiscovery']);
      expect(events, ['failed']);
    });

    test('a device that hosted nothing does not start a host', () async {
      transport.hostRunning = false;
      await fly(sender());
      expect(transport.log, isNot(contains('stopHost')));
      expect(transport.log, isNot(contains('restartHost')));
    });
  });

  test('only iPhones and iPads are listed', () async {
    final s = sender();
    await s.search();
    transport.beacons.add([
      fakeHost('iPhone van Michel'),
      fakeHost('Apple TV slaapkamer', platform: 'tvOS'),
      fakeHost('MacBook', platform: 'macOS'),
      fakeHost('Shield', platform: 'Android'),
      fakeHost('iPad', clientId: 'ipad'),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(s.hosts.map((h) => h.name), ['iPhone van Michel', 'iPad']);
    expect(s.searching, isFalse);
  });

  test('without a remote identity the search ends at once and empty', () async {
    transport.discoverable = false;
    final s = sender();
    await s.search();
    expect(s.searching, isFalse);
    expect(s.hosts, isEmpty);
  });

  test('a timeout tells the phone to stand down before the session closes', () async {
    transport.answer = (_) async => PlaybackHandoffOutcome.timedOut;
    await fly(sender());
    final id = transport.requests.single.id;
    expect(transport.log, [
      'stopHost',
      'connect:iPhone van Michel',
      'handOff',
      'cancel:$id',
      'leave',
      'restartHost',
      'stopDiscovery',
    ]);
    expect(events, ['failed:iPhone van Michel']);
  });

  test('the request carries no Plex token and names this Apple TV', () async {
    await fly(sender());
    final request = transport.requests.single;
    expect(request.plexUserToken, isNull);
    expect(request.from, 'Woonkamer');
    expect(request.positionMs, 61000);
  });

  group('playing', () {
    test('stops the player the fly started from', () async {
      var stopped = 0;
      currentStop = () => stopped++;
      await fly(sender());
      expect(stopped, 1);
      expect(events, ['playing:iPhone van Michel']);
      expect(transport.log, containsAllInOrder(['leave', 'restartHost']));
    });

    test('leaves a later player alone', () async {
      var first = 0;
      var later = 0;
      currentStop = () => first++;
      final answer = Completer<PlaybackHandoffOutcome>();
      transport.answer = (_) => answer.future;
      final running = fly(sender());
      await Future<void>.delayed(Duration.zero);
      currentStop = () => later++;
      answer.complete(PlaybackHandoffOutcome.playing);
      await running;
      expect(first, 0);
      expect(later, 0);
    });
  });

  group('a refusal', () {
    for (final (outcome, refusal) in [
      (PlaybackHandoffOutcome.wrongProfile, PlaybackHandoffRefusal.wrongProfile),
      (PlaybackHandoffOutcome.pinCancelled, PlaybackHandoffRefusal.pinNotEntered),
    ]) {
      test('${outcome.name} keeps the list and marks the row', () async {
        final s = sender()..attachView();
        await s.search();
        final phone = fakeHost('iPhone van Michel');
        transport.beacons.add([phone, fakeHost('iPad')]);
        await Future<void>.delayed(Duration.zero);
        transport.answer = (_) async => outcome;

        await s.handOff(phone, serverId: 'srv', itemId: '42', positionMs: 0, title: 'x');

        expect(s.hosts, hasLength(2));
        expect(s.refusalFor(phone), refusal);
        expect(s.refusalFor(fakeHost('iPad')), isNull);
        expect(s.busy, isFalse);
        expect(events, isEmpty, reason: 'the user can fix it on the phone, the view stays');
      });
    }
  });

  test('a second press while one fly runs is ignored', () async {
    final answer = Completer<PlaybackHandoffOutcome>();
    transport.answer = (_) => answer.future;
    final s = sender();
    final running = fly(s);
    await Future<void>.delayed(Duration.zero);
    expect(s.busy, isTrue);
    await fly(s, name: 'iPad');
    answer.complete(PlaybackHandoffOutcome.failed);
    await running;
    expect(transport.log.where((l) => l.startsWith('connect')), ['connect:iPhone van Michel']);
  });

  group('a closed view', () {
    for (final (outcome, refusal) in [
      (PlaybackHandoffOutcome.wrongProfile, PlaybackHandoffRefusal.wrongProfile),
      (PlaybackHandoffOutcome.pinCancelled, PlaybackHandoffRefusal.pinNotEntered),
    ]) {
      test('still hears the ${outcome.name} refusal, with its reason', () async {
        final s = sender()..attachView();
        await s.search();
        s.stopSearch();
        transport.answer = (_) async => outcome;
        await fly(s);
        expect(events, ['failed:iPhone van Michel:${refusal.name}']);
        expect(transport.log, contains('stopDiscovery'), reason: 'no view, so no search either');
      });
    }
  });

  group('the search', () {
    test('brings the host back when deriving the identity stopped it', () async {
      final s = sender();
      transport.onDiscover = () => transport.hostRunning = false;
      await s.search();
      expect(transport.hostRunning, isTrue);
      expect(transport.log, ['discover', 'restartHost']);
    });

    test('does not start a host this device did not run', () async {
      transport.hostRunning = false;
      await sender().search();
      expect(transport.log, ['discover']);
    });

    test('does nothing while a fly runs', () async {
      final answer = Completer<PlaybackHandoffOutcome>();
      transport.answer = (_) => answer.future;
      final s = sender();
      final running = fly(s);
      await Future<void>.delayed(Duration.zero);
      await s.search();
      expect(transport.log.where((l) => l == 'discover'), isEmpty);
      answer.complete(PlaybackHandoffOutcome.failed);
      await running;
    });
  });

  test('the phone a fly goes to is known by its client id and stays listed', () async {
    final answer = Completer<PlaybackHandoffOutcome>();
    transport.answer = (_) => answer.future;
    final s = sender();
    await s.search();
    transport.beacons.add([fakeHost('iPhone van Michel')]);
    await Future<void>.delayed(Duration.zero);
    final running = fly(s);
    await Future<void>.delayed(Duration.zero);

    // A new beacon is a new object for the same phone.
    transport.beacons.add([fakeHost('iPhone van Michel')]);
    await Future<void>.delayed(Duration.zero);
    expect(s.isHandingTo(s.hosts.single), isTrue);

    // Its beacon drops out: the busy row stays instead of the empty state.
    transport.beacons.add([]);
    await Future<void>.delayed(Duration.zero);
    expect(s.visibleHosts.map((h) => h.name), ['iPhone van Michel']);

    answer.complete(PlaybackHandoffOutcome.failed);
    await running;
    expect(s.visibleHosts, isEmpty);
  });
}

class _ThrowingConnect extends FakeHandoffTransport {
  @override
  Future<void> connect(host) async => throw StateError('no route');
}
