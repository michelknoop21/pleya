import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/watchlist_scope.dart';

WatchlistScopeId scope({
  String profileId = 'profile-1',
  MediaBackend backend = MediaBackend.plex,
  String accountId = 'account-1',
  String userId = 'user-1',
}) {
  return WatchlistScopeId(profileId: profileId, backend: backend, accountId: accountId, userId: userId);
}

void main() {
  group('WatchlistScopeId equality', () {
    test('same components compare and hash equal', () {
      expect(scope(), scope());
      expect(scope().hashCode, scope().hashCode);
    });

    test('every component is part of the identity', () {
      expect(scope(profileId: 'other'), isNot(scope()));
      expect(scope(backend: MediaBackend.jellyfin), isNot(scope()));
      expect(scope(accountId: 'other'), isNot(scope()));
      expect(scope(userId: 'other'), isNot(scope()));
    });
  });

  group('WatchlistScopeId.storageKey', () {
    test('two profiles on the same Jellyfin server with different users do not share a key', () {
      final michel = scope(
        profileId: 'profile-michel',
        backend: MediaBackend.jellyfin,
        accountId: 'jf-machine-1',
        userId: 'jf-user-michel',
      );
      final kid = scope(
        profileId: 'profile-kid',
        backend: MediaBackend.jellyfin,
        accountId: 'jf-machine-1',
        userId: 'jf-user-kid',
      );

      expect(michel.storageKey, isNot(kid.storageKey));
    });

    test('two profiles bound to the same Jellyfin user still do not share a key', () {
      final a = scope(profileId: 'profile-a', backend: MediaBackend.jellyfin, accountId: 'm1', userId: 'u1');
      final b = scope(profileId: 'profile-b', backend: MediaBackend.jellyfin, accountId: 'm1', userId: 'u1');

      expect(a.storageKey, isNot(b.storageKey));
    });

    test('the same account on two backends does not share a key', () {
      final plex = scope(backend: MediaBackend.plex, accountId: 'shared', userId: 'shared');
      final jellyfin = scope(backend: MediaBackend.jellyfin, accountId: 'shared', userId: 'shared');

      expect(plex.storageKey, isNot(jellyfin.storageKey));
    });

    test('a component containing the separator cannot shift the component boundary', () {
      // The naive join `[profileId, backend, accountId, userId].join(':')`
      // gives both of these `a:b:plex:c:d`.
      final shifted = scope(profileId: 'a:b', accountId: 'c', userId: 'd');
      final plain = scope(profileId: 'a', accountId: 'b:c', userId: 'd');

      expect(shifted.storageKey, isNot(plain.storageKey));
    });

    test('empty components do not collapse into each other', () {
      final emptyProfile = scope(profileId: '', accountId: 'a', userId: 'b');
      final emptyAccount = scope(profileId: 'a', accountId: '', userId: 'b');
      final emptyUser = scope(profileId: 'a', accountId: 'b', userId: '');
      final allEmpty = scope(profileId: '', accountId: '', userId: '');

      final keys = {emptyProfile.storageKey, emptyAccount.storageKey, emptyUser.storageKey, allEmpty.storageKey};
      expect(keys, hasLength(4));
    });

    test('unicode and percent signs survive without colliding', () {
      final unicode = scope(profileId: 'Zoë 🎬', accountId: 'ä', userId: 'ü');
      final percentEncodedLookalike = scope(profileId: 'Zo%C3%AB 🎬', accountId: 'ä', userId: 'ü');

      expect(unicode.storageKey, isNot(percentEncodedLookalike.storageKey));
    });

    test('a very long user id stays distinct from its own prefix', () {
      final long = scope(userId: 'u' * 4096);
      final longer = scope(userId: 'u' * 4097);

      expect(long.storageKey, isNot(longer.storageKey));
      expect(long.storageKey.length, lessThan(longer.storageKey.length));
    });

    test('no encoded component can contain the separator', () {
      final hostile = scope(profileId: ':::', backend: MediaBackend.jellyfin, accountId: 'a:b/c?d#e', userId: '%3A');

      // Four components, so exactly three separators, wherever the values put
      // colons of their own.
      expect(hostile.storageKey.split(':'), hasLength(4));
    });

    test('the key is stable across calls', () {
      final s = scope();
      expect(s.storageKey, s.storageKey);
      expect(scope().storageKey, s.storageKey);
    });

    test('toString carries the key so logs stay traceable', () {
      expect(scope().toString(), contains(scope().storageKey));
    });
  });
}
