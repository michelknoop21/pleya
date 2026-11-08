import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/companion_remote/playback_handoff.dart';
import 'package:pleya/services/companion_remote/pleya_fly_follow.dart';

const _session = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

FlyFollowOffer _offer({String? sessionId = _session, String? relayUrl}) => FlyFollowOffer(
  serverId: 'srv-1',
  itemId: 'item-9',
  positionMs: 4602000,
  title: 'Dune: Part Two',
  from: 'Woonkamer',
  sessionId: sessionId,
  relayUrl: relayUrl,
);

void main() {
  group('fly session id', () {
    test('is 26 characters of the upper-case alphabet, about 130 bits', () {
      final id = generateFlySessionId(Random(7));
      expect(id.length, flySessionIdLength);
      expect(isFlySessionId(id), isTrue);
      expect(id, id.toUpperCase());
      // 32 symbols, 26 positions.
      expect(26 * log(32) / ln2, greaterThanOrEqualTo(128));
    });

    test('two ids differ', () {
      expect(generateFlySessionId(), isNot(generateFlySessionId()));
    });

    test('a five-character Samen kijken code is no fly id', () {
      expect(isFlySessionId('AB12C'), isFalse);
      expect(isFlySessionId('abcdefghijklmnopqrstuvwxyz'), isFalse);
      expect(isFlySessionId('ABCDEFGHIJKLMNOPQRSTUVWXY1'), isFalse); // 1 is not in the alphabet
    });
  });

  group('offer payload', () {
    test('round-trips with session and relay', () {
      final data = _offer(relayUrl: 'https://relay.example').toData();
      final back = FlyFollowOffer.fromData(data)!;
      expect(back.serverId, 'srv-1');
      expect(back.itemId, 'item-9');
      expect(back.positionMs, 4602000);
      expect(back.title, 'Dune: Part Two');
      expect(back.from, 'Woonkamer');
      expect(back.sessionId, _session);
      expect(back.relayUrl, 'https://relay.example');
    });

    test('a peek carries no session and no relay', () {
      final data = _offer(sessionId: null).toData();
      expect(data.containsKey('sessionId'), isFalse);
      expect(data.containsKey('relayUrl'), isFalse);
      expect(FlyFollowOffer.fromData(data)!.sessionId, isNull);
    });

    test('rejects a short session id, a bad relay and a missing item', () {
      final good = _offer().toData();
      expect(FlyFollowOffer.fromData({...good, 'sessionId': 'AB12C'}), isNull);
      expect(FlyFollowOffer.fromData({...good, 'relayUrl': 'javascript:alert(1)'}), isNull);
      expect(FlyFollowOffer.fromData({...good, 'relayUrl': 42}), isNull);
      expect(FlyFollowOffer.fromData({...good, 'itemId': ''}), isNull);
      expect(FlyFollowOffer.fromData({...good, 'positionMs': -1}), isNull);
      expect(FlyFollowOffer.fromData(null), isNull);
    });
  });

  group('answer payload', () {
    test('an offer comes back as an offer', () {
      final parsed = parseFlyFollowAnswer(flyFollowAnswerData('r1', FlyFollowAnswer.offer(_offer())))!;
      expect(parsed.id, 'r1');
      expect(parsed.answer.offer!.sessionId, _session);
      expect(parsed.answer.refusal, isNull);
    });

    test('a refusal keeps its reason and title', () {
      final data = flyFollowAnswerData(
        'r2',
        const FlyFollowAnswer.refused(FlyFollowRefusal.unsupported, title: 'Journaal'),
      );
      final parsed = parseFlyFollowAnswer(data)!;
      expect(parsed.answer.offer, isNull);
      expect(parsed.answer.refusal, FlyFollowRefusal.unsupported);
      expect(parsed.answer.title, 'Journaal');
    });

    test('a malformed offer is a failure, not an offer', () {
      final parsed = parseFlyFollowAnswer({
        flyFollowAnswerKey: 'r3',
        flyFollowOfferKey: {..._offer().toData(), 'sessionId': 'SHORT'},
      })!;
      expect(parsed.answer.offer, isNull);
      expect(parsed.answer.refusal, FlyFollowRefusal.failed);
    });

    test('other syncState data is no answer', () {
      expect(parseFlyFollowAnswer({'playerActive': true}), isNull);
    });
  });

  group('answering on the Apple TV', () {
    Future<Map<String, dynamic>?> answer(
      Map<String, dynamic>? data,
      Future<FlyFollowAnswer> Function({required bool peek})? player,
    ) async {
      Map<String, dynamic>? sent;
      await answerFlyFollowRequest(data, player: player, send: (d) => sent = d);
      return sent;
    }

    test('without a player the answer is nothing', () async {
      final sent = await answer({flyFollowRequestKey: 'r1', flyFollowPeekKey: false}, null);
      expect(parseFlyFollowAnswer(sent)!.answer.refusal, FlyFollowRefusal.nothing);
    });

    test('a request without peek: false only peeks', () async {
      bool? peeked;
      Future<FlyFollowAnswer> player({required bool peek}) async {
        peeked = peek;
        return FlyFollowAnswer.offer(_offer(sessionId: null));
      }

      await answer({flyFollowRequestKey: 'r1'}, player);
      expect(peeked, isTrue);
      await answer({flyFollowRequestKey: 'r1', flyFollowPeekKey: 'no'}, player);
      expect(peeked, isTrue);
      await answer({flyFollowRequestKey: 'r1', flyFollowPeekKey: false}, player);
      expect(peeked, isFalse);
    });

    test('a request without an id gets no answer', () async {
      expect(await answer({flyFollowPeekKey: true}, null), isNull);
      expect(await answer({flyFollowRequestKey: 'x' * 65}, null), isNull);
    });

    test('a player that throws answers failed', () async {
      final sent = await answer({flyFollowRequestKey: 'r1'}, ({required peek}) => throw StateError('relay down'));
      expect(parseFlyFollowAnswer(sent)!.answer.refusal, FlyFollowRefusal.failed);
    });
  });

  group('tracker', () {
    test('matches the answer to its request and times out to failed', () async {
      final tracker = FlyFollowTracker();
      final waiting = tracker.wait('r1', const Duration(seconds: 5));
      tracker.handleSyncState(flyFollowAnswerData('other', FlyFollowAnswer.offer(_offer())));
      tracker.handleSyncState(flyFollowAnswerData('r1', FlyFollowAnswer.offer(_offer())));
      expect((await waiting).offer!.sessionId, _session);

      final late = await tracker.wait('r2', const Duration(milliseconds: 10));
      expect(late.refusal, FlyFollowRefusal.failed);
    });
  });

  group('Meenemen from the Apple TV picker', () {
    PlaybackHandoffRequest request({String? session = _session, String? relay}) => PlaybackHandoffRequest(
      id: 'h1',
      serverId: 'srv-1',
      itemId: 'item-9',
      positionMs: 1000,
      title: 'Dune',
      from: 'Woonkamer',
      followSessionId: session,
      relayUrl: relay,
    );

    test('the handoff request carries the session to follow', () {
      final back = PlaybackHandoffRequest.fromData(request(relay: 'https://relay.example').toData())!;
      expect(back.isFollow, isTrue);
      expect(back.followSessionId, _session);
      expect(back.relayUrl, 'https://relay.example');
      expect(back.withPlexUserToken('tok').followSessionId, _session);
    });

    test('a plain handoff stays a plain handoff', () {
      final back = PlaybackHandoffRequest.fromData(request(session: null).toData())!;
      expect(back.isFollow, isFalse);
      expect(back.toData().containsKey('followSession'), isFalse);
    });

    test('a follow that does not parse is dropped, never played as a full handoff', () {
      expect(PlaybackHandoffRequest.fromData({...request(session: null).toData(), 'followSession': 'AB12C'}), isNull);
      expect(PlaybackHandoffRequest.fromData({...request().toData(), 'relayUrl': 'ftp://x'}), isNull);
    });
  });
}
