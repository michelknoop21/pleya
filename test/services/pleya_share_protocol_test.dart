import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/pleya_share/pleya_share_channel.dart';
import 'package:pleya/services/pleya_share/pleya_share_pairing.dart';
import 'package:pleya/services/pleya_share/pleya_share_protocol.dart';

void main() {
  group('HttpByteRange.parse', () {
    test('full range bytes=0-99', () {
      final r = HttpByteRange.parse('bytes=0-99', 100)!;
      expect(r.start, 0);
      expect(r.end, 99);
      expect(r.length, 100);
      expect(r.contentRange, 'bytes 0-99/100');
    });

    test('open-ended bytes=50-', () {
      final r = HttpByteRange.parse('bytes=50-', 100)!;
      expect(r.start, 50);
      expect(r.end, 99);
      expect(r.length, 50);
    });

    test('suffix bytes=-10 returns last 10 bytes', () {
      final r = HttpByteRange.parse('bytes=-10', 100)!;
      expect(r.start, 90);
      expect(r.end, 99);
    });

    test('suffix longer than file clamps to whole file', () {
      final r = HttpByteRange.parse('bytes=-500', 100)!;
      expect(r.start, 0);
      expect(r.end, 99);
    });

    test('end beyond total clamps', () {
      final r = HttpByteRange.parse('bytes=10-9999', 100)!;
      expect(r.end, 99);
    });

    test('start beyond total is unsatisfiable', () {
      expect(() => HttpByteRange.parse('bytes=100-', 100), throwsA(isA<RangeNotSatisfiableException>()));
      expect(() => HttpByteRange.parse('bytes=200-300', 100), throwsA(isA<RangeNotSatisfiableException>()));
    });

    test('zero-length suffix is unsatisfiable', () {
      expect(() => HttpByteRange.parse('bytes=-0', 100), throwsA(isA<RangeNotSatisfiableException>()));
    });

    test('absent, malformed, or multi-range headers return null', () {
      expect(HttpByteRange.parse(null, 100), isNull);
      expect(HttpByteRange.parse('bytes=', 100), isNull);
      expect(HttpByteRange.parse('bytes=a-b', 100), isNull);
      expect(HttpByteRange.parse('bytes=0-10,20-30', 100), isNull);
      expect(HttpByteRange.parse('items=0-10', 100), isNull);
    });

    test('unknown total returns null', () {
      expect(HttpByteRange.parse('bytes=0-10', 0), isNull);
    });
  });

  group('item id encoding', () {
    test('round-trips content URIs and paths', () {
      for (final id in [
        'content://com.android.externalstorage.documents/tree/primary%3AMovies/doc/x.mkv',
        '/private/var/mobile/Containers/Data/Application/x/Movies/Film (2024).mp4',
      ]) {
        expect(PleyaShareProtocol.decodeItemId(PleyaShareProtocol.encodeItemId(id)), id);
      }
    });
  });

  group('PleyaSharePairing', () {
    test('same code+salt derives same key; different code differs', () async {
      final salt = PleyaSharePairing.randomBytes(16);
      final a = await PleyaSharePairing.derivePairingKey('123456', salt);
      final b = await PleyaSharePairing.derivePairingKey('123456', salt);
      final c = await PleyaSharePairing.derivePairingKey('654321', salt);
      expect(a, b);
      expect(a, isNot(c));
    });

    test('auth tag verifies and rejects wrong key/context', () async {
      final key = PleyaSharePairing.randomBytes(32);
      final hostNonce = PleyaSharePairing.randomBytes(32);
      final clientNonce = PleyaSharePairing.randomBytes(32);
      final tag = PleyaSharePairing.computeAuthTag(
        key: key,
        hostNonce: hostNonce,
        clientNonce: clientNonce,
        context: 'pair',
      );
      expect(
        PleyaSharePairing.verifyAuthTag(
          received: tag,
          key: key,
          hostNonce: hostNonce,
          clientNonce: clientNonce,
          context: 'pair',
        ),
        isTrue,
      );
      expect(
        PleyaSharePairing.verifyAuthTag(
          received: tag,
          key: PleyaSharePairing.randomBytes(32),
          hostNonce: hostNonce,
          clientNonce: clientNonce,
          context: 'pair',
        ),
        isFalse,
      );
      expect(
        PleyaSharePairing.verifyAuthTag(
          received: tag,
          key: key,
          hostNonce: hostNonce,
          clientNonce: clientNonce,
          context: 'reconnect',
        ),
        isFalse,
      );
    });

    test('encrypted payload round-trips and rejects tampering', () async {
      final key = PleyaSharePairing.randomBytes(32);
      final hostNonce = PleyaSharePairing.randomBytes(32);
      final clientNonce = PleyaSharePairing.randomBytes(32);
      final session = await PleyaSharePairing.deriveSessionKey(key, hostNonce, clientNonce);
      final payload = {'pairId': 'abc', 'token': 'xyz'};
      final encrypted = await PleyaSharePairing.encryptPayload(session, payload);
      expect(await PleyaSharePairing.decryptPayload(session, encrypted), payload);

      final other = await PleyaSharePairing.deriveSessionKey(key, clientNonce, hostNonce);
      expect(() => PleyaSharePairing.decryptPayload(other, encrypted), throwsA(anything));
    });

    test('pair code is 6 digits', () {
      for (var i = 0; i < 50; i++) {
        expect(PleyaSharePairing.generatePairCode(), matches(RegExp(r'^\d{6}$')));
      }
    });
  });

  group('gatewayCandidatesFrom', () {
    test('derives .1/.129/.254 per /24, deduped, excluding own addresses', () {
      final candidates = PleyaShareChannel.gatewayCandidatesFrom(['172.20.10.4', '172.20.10.9', '192.168.1.23']);
      expect(candidates, containsAll(['172.20.10.1', '192.168.1.1', '192.168.1.129', '192.168.1.254']));
      expect(candidates.toSet().length, candidates.length, reason: 'deduped');
    });

    test('own address on .1 is excluded (device itself is the gateway)', () {
      expect(PleyaShareChannel.gatewayCandidatesFrom(['192.168.43.1']), isNot(contains('192.168.43.1')));
    });

    test('garbage input yields nothing', () {
      expect(PleyaShareChannel.gatewayCandidatesFrom(['not-an-ip', '']), isEmpty);
    });
  });

  group('PairingRateLimiter', () {
    test('locks out after 5 failures and recovers after lockout window', () {
      final limiter = PairingRateLimiter();
      final t0 = DateTime(2026, 1, 1);
      for (var i = 0; i < 4; i++) {
        limiter.recordFailure('1.2.3.4', now: t0);
      }
      expect(limiter.isLockedOut('1.2.3.4', now: t0), isFalse);
      limiter.recordFailure('1.2.3.4', now: t0);
      expect(limiter.isLockedOut('1.2.3.4', now: t0), isTrue);
      expect(limiter.isLockedOut('5.6.7.8', now: t0), isFalse);
      expect(limiter.isLockedOut('1.2.3.4', now: t0.add(const Duration(seconds: 31))), isFalse);
    });

    test('reset clears failures', () {
      final limiter = PairingRateLimiter();
      final t0 = DateTime(2026, 1, 1);
      for (var i = 0; i < 5; i++) {
        limiter.recordFailure('1.2.3.4', now: t0);
      }
      limiter.reset('1.2.3.4');
      expect(limiter.isLockedOut('1.2.3.4', now: t0), isFalse);
    });
  });
}
