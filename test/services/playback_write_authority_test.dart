import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/playback_write_authority.dart';

// Coverage:
//   - A fresh authority is held; taking again is a no-op that does not notify.
//   - A foreign `playing` for the same item revokes; an echo of this session
//     or an event for another item does not.
//   - Revocation is sticky until a deliberate action takes it back.
//   - retakeAfterRefresh reads backend state BEFORE taking, and does not take
//     when that read fails.

ObservedPlaybackAuthority _authority() => ObservedPlaybackAuthority(sessionId: 'session-a', itemId: 'item-1');

void main() {
  test('a fresh authority is held', () {
    expect(_authority().isHeld, isTrue);
    expect(_authority().isRevoked, isFalse);
    expect(_authority().revokedBySessionId, isNull);
  });

  test('taking an already-held authority does not notify', () {
    final authority = _authority();
    var notifications = 0;
    authority.addListener(() => notifications++);

    authority.take(reason: 'start');

    expect(notifications, 0);
    expect(authority.isHeld, isTrue);
  });

  test('a foreign playing for the same item revokes', () {
    final authority = _authority();
    var notifications = 0;
    authority.addListener(() => notifications++);

    final revoked = authority.observeForeignPlaying(itemId: 'item-1', sessionId: 'session-b');

    expect(revoked, isTrue);
    expect(authority.isRevoked, isTrue);
    expect(authority.revokedBySessionId, 'session-b');
    expect(notifications, 1);
  });

  test('an echo of this session never revokes', () {
    final authority = _authority();

    final revoked = authority.observeForeignPlaying(itemId: 'item-1', sessionId: 'session-a');

    expect(revoked, isFalse);
    expect(authority.isHeld, isTrue);
  });

  test('a playing for another item never revokes', () {
    final authority = _authority();

    final revoked = authority.observeForeignPlaying(itemId: 'item-2', sessionId: 'session-b');

    expect(revoked, isFalse);
    expect(authority.isHeld, isTrue);
  });

  test('a second foreign observation does not revoke twice', () {
    final authority = _authority();
    authority.observeForeignPlaying(itemId: 'item-1', sessionId: 'session-b');

    var notifications = 0;
    authority.addListener(() => notifications++);
    final revokedAgain = authority.observeForeignPlaying(itemId: 'item-1', sessionId: 'session-c');

    expect(revokedAgain, isFalse);
    expect(authority.revokedBySessionId, 'session-b');
    expect(notifications, 0);
  });

  test('revocation is sticky until a deliberate action takes it back', () {
    final authority = _authority();
    authority.observeForeignPlaying(itemId: 'item-1', sessionId: 'session-b');
    expect(authority.isRevoked, isTrue);

    authority.take(reason: 'user pressed play');

    expect(authority.isHeld, isTrue);
    expect(authority.revokedBySessionId, isNull);
  });

  test('taking back after revocation notifies exactly once', () {
    final authority = _authority();
    authority.observeForeignPlaying(itemId: 'item-1', sessionId: 'session-b');

    var notifications = 0;
    authority.addListener(() => notifications++);
    authority.take(reason: 'seek');
    authority.take(reason: 'seek again');

    expect(notifications, 1);
  });

  test('an explicit revoke works without an observation', () {
    final authority = _authority();

    authority.revoke(reason: 'watch together handed over');

    expect(authority.isRevoked, isTrue);
    expect(authority.revokedBySessionId, isNull);
  });

  test('revoking twice does not notify twice', () {
    final authority = _authority();
    authority.revoke(reason: 'first');

    var notifications = 0;
    authority.addListener(() => notifications++);
    authority.revoke(reason: 'second');

    expect(notifications, 0);
  });

  group('retakeAfterRefresh', () {
    test('reads backend state before taking the authority back', () async {
      final authority = _authority();
      authority.observeForeignPlaying(itemId: 'item-1', sessionId: 'session-b');

      final order = <String>[];
      await authority.retakeAfterRefresh(() async {
        // The whole point of the ordering: at this moment the authority must
        // still be revoked, so nothing this player does can be written yet.
        order.add('refresh(held=${authority.isHeld})');
      }, reason: 'app resumed');
      order.add('after(held=${authority.isHeld})');

      expect(order, ['refresh(held=false)', 'after(held=true)']);
    });

    test('does not take the authority when the refresh fails', () async {
      final authority = _authority();
      authority.observeForeignPlaying(itemId: 'item-1', sessionId: 'session-b');

      await expectLater(
        authority.retakeAfterRefresh(() async => throw StateError('offline'), reason: 'app resumed'),
        throwsStateError,
      );

      expect(authority.isRevoked, isTrue);
    });

    test('is a no-op on an authority that was never revoked', () async {
      final authority = _authority();
      var refreshes = 0;

      await authority.retakeAfterRefresh(() async => refreshes++, reason: 'app resumed');

      expect(refreshes, 1);
      expect(authority.isHeld, isTrue);
    });
  });
}
