// Pleya Fly Meenemen (A-23e), the phone side: an Apple TV beacon that says it
// plays makes the phone ask what (a peek), and the one tap asks for the
// session and joins it.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/providers/companion_remote_provider.dart';
import 'package:pleya/services/companion_remote/fly_follow_puller.dart';
import 'package:pleya/services/companion_remote/pleya_fly_follow.dart';

const _session = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

class _FakeTransport implements FlyFollowTransport {
  final hosts = StreamController<List<DiscoveredHost>>.broadcast();
  final asks = <bool>[];
  final log = <String>[];
  FlyFollowAnswer Function(bool peek) answer = (peek) => FlyFollowAnswer.offer(_offer(session: !peek));
  bool free = true;
  bool _listening = false;
  Completer<void>? discoverGate;

  @override
  Future<Stream<List<DiscoveredHost>>?> discover() async {
    await discoverGate?.future;
    _listening = true;
    return hosts.stream;
  }

  @override
  void stopDiscovery() => _listening = false;

  @override
  bool get listening => _listening;

  @override
  bool begin() => free;

  @override
  void end() => log.add('end');

  @override
  Future<void> connect(DiscoveredHost host) async => log.add('connect:${host.name}');

  @override
  Future<FlyFollowAnswer> ask({required bool peek}) async {
    asks.add(peek);
    return answer(peek);
  }

  @override
  Future<void> leave() async => log.add('leave');
}

FlyFollowOffer _offer({bool session = false}) => FlyFollowOffer(
  serverId: 'srv-1',
  itemId: 'item-9',
  positionMs: 4602000,
  title: 'Dune: Part Two',
  from: 'Woonkamer',
  sessionId: session ? _session : null,
);

DiscoveredHost _tv({bool playing = true, String platform = 'tvOS'}) => DiscoveredHost(
  authContextId: 'ctx',
  clientId: 'tv-1',
  name: 'Woonkamer',
  platform: platform,
  port: 1,
  ips: const ['10.0.0.2'],
  playing: playing,
);

final _movie = MediaItem(id: 'item-9', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Dune: Part Two');

void main() {
  late _FakeTransport transport;
  late List<FlyFollowOffer> joined;
  late FlyFollowPuller puller;
  late DateTime now;
  MediaItem? reachable;

  setUp(() {
    transport = _FakeTransport();
    joined = [];
    reachable = _movie;
    now = DateTime(2026, 11, 8, 20);
    puller = FlyFollowPuller(
      transport: transport,
      resolveItem: (serverId, itemId) async => reachable,
      join: (offer) async => joined.add(offer),
      clock: () => now,
    );
  });

  tearDown(() => puller.dispose());

  Future<void> beacon(List<DiscoveredHost> hosts) async {
    transport.hosts.add(hosts);
    await pumpEventQueue();
  }

  test('a playing Apple TV gets one peek and becomes the card', () async {
    await puller.start();
    await beacon([_tv()]);
    await beacon([_tv()]); // the next beacon does not ask again

    expect(transport.asks, [true]);
    expect(transport.log, ['connect:Woonkamer', 'leave', 'end']);
    final card = puller.card!;
    expect(card.tv.name, 'Woonkamer');
    expect(card.title, 'Dune: Part Two');
    expect(card.canFollow, isTrue);
    expect(card.offer!.positionMs, 4602000);
  });

  test('negative control: an Apple TV without the playing flag is never asked', () async {
    await puller.start();
    await beacon([_tv(playing: false), _tv(platform: 'iOS')]);

    expect(transport.asks, isEmpty);
    expect(puller.card, isNull);
  });

  test('one tap asks for the session and joins it', () async {
    await puller.start();
    await beacon([_tv()]);

    expect(await puller.take(), isTrue);
    expect(transport.asks, [true, false]);
    expect(joined.single.sessionId, _session);
    expect(joined.single.itemId, 'item-9');
  });

  test('an answer without a session joins nothing', () async {
    transport.answer = (peek) => FlyFollowAnswer.offer(_offer());
    await puller.start();
    await beacon([_tv()]);

    expect(await puller.take(), isFalse);
    expect(joined, isEmpty);
  });

  test('the card goes when the Apple TV stops', () async {
    await puller.start();
    await beacon([_tv()]);
    expect(puller.card, isNotNull);

    await beacon([_tv(playing: false)]);
    expect(puller.card, isNull);
  });

  test('a profile that cannot reach the server shows the title without a button', () async {
    reachable = null;
    await puller.start();
    await beacon([_tv()]);

    final card = puller.card!;
    expect(card.block, FlyFollowCardBlock.unreachable);
    expect(card.canFollow, isFalse);
    expect(await puller.take(), isFalse);
    expect(transport.asks, [true]);
  });

  test('live TV on the Apple TV shows the title and the reason', () async {
    transport.answer = (peek) => const FlyFollowAnswer.refused(FlyFollowRefusal.unsupported, title: 'NPO 1');
    await puller.start();
    await beacon([_tv()]);

    expect(puller.card!.title, 'NPO 1');
    expect(puller.card!.block, FlyFollowCardBlock.unsupported);
  });

  test('nothing to follow: no card', () async {
    transport.answer = (peek) => const FlyFollowAnswer.refused(FlyFollowRefusal.nothing);
    await puller.start();
    await beacon([_tv()]);

    expect(puller.card, isNull);
  });

  test('a remote session in use is not taken over: asked again after the wait', () async {
    transport.free = false;
    await puller.start();
    await beacon([_tv()]);
    expect(transport.asks, isEmpty);

    transport.free = true;
    await beacon([_tv()]);
    expect(transport.asks, isEmpty, reason: 'not before the first wait');
    now = now.add(FlyFollowPuller.firstRetryWait);
    await beacon([_tv()]);
    expect(transport.asks, [true]);
  });

  test('an Apple TV that fails to answer is asked again, each time after a longer wait', () async {
    transport.answer = (peek) => const FlyFollowAnswer.refused(FlyFollowRefusal.failed);
    await puller.start();
    await beacon([_tv()]);
    expect(transport.asks, [true]);
    expect(puller.card, isNull);

    // Negative control: within the wait the beacon does not trigger a new connection.
    await beacon([_tv()]);
    expect(transport.asks, [true]);

    now = now.add(FlyFollowPuller.firstRetryWait);
    await beacon([_tv()]);
    expect(transport.asks, [true, true], reason: 'a failed answer is retried');

    // The second wait is twice as long.
    now = now.add(FlyFollowPuller.firstRetryWait);
    await beacon([_tv()]);
    expect(transport.asks, [true, true]);
    now = now.add(FlyFollowPuller.firstRetryWait);
    transport.answer = (peek) => FlyFollowAnswer.offer(_offer(session: !peek));
    await beacon([_tv()]);
    expect(transport.asks, [true, true, true]);
    expect(puller.card, isNotNull);
  });

  test('a stop while discovery starts leaves no listener behind', () async {
    transport.discoverGate = Completer<void>();
    final starting = puller.start();
    puller.stop();
    transport.discoverGate!.complete();
    await starting;
    expect(transport.listening, isFalse);
  });
}
