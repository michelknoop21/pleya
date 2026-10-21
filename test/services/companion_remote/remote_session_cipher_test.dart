import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/companion_remote/remote_auth_service.dart';
import 'package:pleya/services/companion_remote/remote_session_cipher.dart';

void main() {
  final key = List<int>.generate(32, (i) => i);

  Future<List<List<int>>> peerFrames(List<String> messages, {required bool isHost}) async {
    final sender = RemoteSessionCipher()..start(key);
    return [for (final m in messages) (await sender.encrypt(m, isHost: isHost))!];
  }

  group('receive order (A-23d)', () {
    test('frames handed over without awaiting decrypt in arrival order', () async {
      final frames = await peerFrames(['one', 'two', 'three'], isHost: true);
      final receiver = RemoteSessionCipher()..start(key);

      // Same shape as two socket listeners firing on one TCP read.
      final results = await Future.wait([for (final f in frames) receiver.decrypt(f, fromHost: true)]);

      expect(results, ['one', 'two', 'three']);
      expect(receiver.consecutiveFailures, 0);
    });

    test('negative control: counters read before the earlier frame finished fail', () async {
      final frames = await peerFrames(['one', 'two'], isHost: true);
      final auth = RemoteAuthService.instance;

      // What the receiver did before the chain: both read expectedCounter 0.
      final first = auth.decrypt(frames[0], key, fromHost: true, expectedCounter: 0);
      final second = auth.decrypt(frames[1], key, fromHost: true, expectedCounter: 0);

      expect(utf8.decode(await first), 'one');
      await expectLater(second, throwsA(anything));
    });

    test('a frame that does not authenticate does not advance the counter', () async {
      final frames = await peerFrames(['one', 'two'], isHost: true);
      final receiver = RemoteSessionCipher()..start(key);

      await expectLater(receiver.decrypt(List<int>.filled(32, 7), fromHost: true), throwsA(anything));
      expect(receiver.consecutiveFailures, 1);
      expect(await receiver.decrypt(frames[0], fromHost: true), 'one');
      expect(receiver.consecutiveFailures, 0);
    });

    test('a frame queued for an earlier session is dropped by the new one', () async {
      final oldFrames = await peerFrames(['old'], isHost: true);
      final receiver = RemoteSessionCipher()..start(key);
      final stale = receiver.decrypt(oldFrames.first, fromHost: true);

      receiver.start(List<int>.generate(32, (i) => 100 + i));

      expect(await stale, isNull);
      expect(receiver.consecutiveFailures, 0);
    });

    test('without a key nothing is decrypted', () async {
      expect(await RemoteSessionCipher().decrypt(<int>[1, 2, 3], fromHost: true), isNull);
    });
  });

  group('send order', () {
    test('overlapping encrypts never share a counter', () async {
      final sender = RemoteSessionCipher()..start(key);
      final frames = await Future.wait([sender.encrypt('a', isHost: true), sender.encrypt('b', isHost: true)]);
      final receiver = RemoteSessionCipher()..start(key);

      expect(await receiver.decrypt(frames[0]!, fromHost: true), 'a');
      expect(await receiver.decrypt(frames[1]!, fromHost: true), 'b');
    });

    test('a frame encrypted for an earlier session is discarded', () async {
      final sender = RemoteSessionCipher()..start(key);
      final pending = sender.encrypt('old', isHost: true);
      sender.start(List<int>.generate(32, (i) => 100 + i));

      expect(await pending, isNull);
      // The new session still starts at counter 0.
      final frame = (await sender.encrypt('new', isHost: true))!;
      final receiver = RemoteSessionCipher()..start(List<int>.generate(32, (i) => 100 + i));
      expect(await receiver.decrypt(frame, fromHost: true), 'new');
    });

    test('queued sends run one after the other', () async {
      final cipher = RemoteSessionCipher()..start(key);
      final order = <String>[];
      cipher.runSend(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        order.add('a');
      });
      cipher.runSend(() async => order.add('b'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(order, ['a', 'b']);
    });
  });
}
