import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/watchlist_entry.dart';
import 'package:pleya/media/watchlist_scope.dart';
import 'package:pleya/utils/external_ids.dart';

final plexScope = WatchlistScopeId(
  profileId: 'profile-1',
  backend: MediaBackend.plex,
  accountId: 'account-1',
  userId: 'home-user-1',
);

final jellyfinScope = WatchlistScopeId(
  profileId: 'profile-1',
  backend: MediaBackend.jellyfin,
  accountId: 'jf-machine-1',
  userId: 'jf-user-1',
);

final otherScope = WatchlistScopeId(
  profileId: 'profile-1',
  backend: MediaBackend.jellyfin,
  accountId: 'jf-machine-2',
  userId: 'jf-user-2',
);

MediaItem discoverItem({String title = 'Sintel', String? titleSort, String id = 'abc'}) {
  return MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: title, titleSort: titleSort);
}

MediaItem serverItem({String id = '4711', String serverId = 'machine-1'}) {
  return MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Sintel', serverId: serverId);
}

WatchlistEntry entry({
  String key = 'plex:abc',
  MediaItem? item,
  List<WatchlistMembership>? memberships,
  ExternalIds externalIds = const ExternalIds(),
  String? guid,
  String? posterRef,
  WatchlistAvailability availability = WatchlistAvailability.unknown,
  bool coverageComplete = false,
  MediaItem? lastKnownMatch,
}) {
  return WatchlistEntry(
    key: key,
    kind: MediaKind.movie,
    item: item ?? discoverItem(),
    guid: guid,
    externalIds: externalIds,
    posterRef: posterRef,
    memberships: memberships ?? [WatchlistMembership(scope: plexScope, remoteKey: 'abc', addedAt: 1000)],
    availability: availability,
    coverageComplete: coverageComplete,
    lastKnownMatch: lastKnownMatch,
  );
}

void main() {
  group('WatchlistMembership', () {
    test('rejects an empty remote key, because a membership without one cannot be removed', () {
      expect(
        () => WatchlistMembership(scope: plexScope, remoteKey: ''),
        throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'remoteKey')),
      );
    });

    test('compares on scope, key and timestamp', () {
      final a = WatchlistMembership(scope: plexScope, remoteKey: 'abc', addedAt: 1);
      expect(a, WatchlistMembership(scope: plexScope, remoteKey: 'abc', addedAt: 1));
      expect(a, isNot(WatchlistMembership(scope: jellyfinScope, remoteKey: 'abc', addedAt: 1)));
      expect(a, isNot(WatchlistMembership(scope: plexScope, remoteKey: 'other', addedAt: 1)));
      expect(a, isNot(WatchlistMembership(scope: plexScope, remoteKey: 'abc', addedAt: 2)));
    });
  });

  group('WatchlistEntry invariants', () {
    test('an entry without memberships does not exist', () {
      expect(() => entry(memberships: []), throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'memberships')));
    });

    test('an entry needs a canonical key', () {
      expect(() => entry(key: ''), throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'key')));
    });

    test('the membership list cannot be mutated behind the entry back', () {
      final memberships = [WatchlistMembership(scope: plexScope, remoteKey: 'abc')];
      final e = entry(memberships: memberships);

      memberships.add(WatchlistMembership(scope: jellyfinScope, remoteKey: 'jf-1'));

      expect(e.memberships, hasLength(1));
      expect(() => e.memberships.add(WatchlistMembership(scope: jellyfinScope, remoteKey: 'jf-1')), throwsA(anything));
    });
  });

  group('WatchlistEntry.addedAt', () {
    test('is the newest timestamp across memberships', () {
      final e = entry(
        memberships: [
          WatchlistMembership(scope: jellyfinScope, remoteKey: 'jf-1', addedAt: 500),
          WatchlistMembership(scope: plexScope, remoteKey: 'abc', addedAt: 9000),
        ],
      );

      expect(e.addedAt, 9000);
    });

    test('ignores memberships without a timestamp', () {
      final e = entry(
        memberships: [
          WatchlistMembership(scope: jellyfinScope, remoteKey: 'jf-1'),
          WatchlistMembership(scope: plexScope, remoteKey: 'abc', addedAt: 42),
        ],
      );

      expect(e.addedAt, 42);
    });

    test('is null when no source reported one', () {
      expect(
        entry(
          memberships: [WatchlistMembership(scope: plexScope, remoteKey: 'abc')],
        ).addedAt,
        isNull,
      );
    });
  });

  group('WatchlistEntry.mergeWith', () {
    test('joins memberships instead of dropping the other source', () {
      final fromPlex = entry(
        memberships: [WatchlistMembership(scope: plexScope, remoteKey: 'abc', addedAt: 100)],
      );
      final fromJellyfin = entry(
        key: 'imdb:tt0111161',
        memberships: [WatchlistMembership(scope: jellyfinScope, remoteKey: 'jf-1', addedAt: 200)],
      );

      final merged = fromPlex.mergeWith(fromJellyfin);

      expect(merged.memberships, hasLength(2));
      expect(merged.membershipFor(plexScope)?.remoteKey, 'abc');
      expect(merged.membershipFor(jellyfinScope)?.remoteKey, 'jf-1');
    });

    test('keeps the identity of the entry that was merged into', () {
      final merged = entry(key: 'plex:abc').mergeWith(entry(key: 'imdb:tt0111161'));

      expect(merged.key, 'plex:abc');
    });

    test('the same scope on both sides keeps the newer timestamp', () {
      final stale = entry(
        memberships: [WatchlistMembership(scope: plexScope, remoteKey: 'abc', addedAt: 100)],
      );
      final fresh = entry(
        memberships: [WatchlistMembership(scope: plexScope, remoteKey: 'abc', addedAt: 900)],
      );

      expect(stale.mergeWith(fresh).memberships, hasLength(1));
      expect(stale.mergeWith(fresh).addedAt, 900);
      expect(fresh.mergeWith(stale).addedAt, 900);
    });

    test('fills in missing guid, poster and external ids from the other source', () {
      final sparse = entry(externalIds: const ExternalIds(tmdb: 278));
      final rich = entry(
        guid: 'plex://movie/abc',
        posterRef: 'poster-ref',
        externalIds: const ExternalIds(imdb: 'tt0111161', tvdb: 73141),
      );

      final merged = sparse.mergeWith(rich);

      expect(merged.guid, 'plex://movie/abc');
      expect(merged.posterRef, 'poster-ref');
      expect(merged.externalIds.imdb, 'tt0111161');
      expect(merged.externalIds.tmdb, 278);
      expect(merged.externalIds.tvdb, 73141);
    });

    test('the resolve result travels as one unit, from whichever side got further', () {
      final match = serverItem();
      final unresolved = entry();
      final resolved = entry(
        availability: WatchlistAvailability.available,
        coverageComplete: true,
        lastKnownMatch: match,
      );

      final merged = unresolved.mergeWith(resolved);

      expect(merged.availability, WatchlistAvailability.available);
      expect(merged.coverageComplete, isTrue);
      expect(merged.lastKnownMatch, match);
    });

    test('an available side is never downgraded by a notFound side', () {
      final available = entry(availability: WatchlistAvailability.available, lastKnownMatch: serverItem());
      final notFound = entry(availability: WatchlistAvailability.notFound, coverageComplete: true);

      expect(available.mergeWith(notFound).availability, WatchlistAvailability.available);
      expect(notFound.mergeWith(available).availability, WatchlistAvailability.available);
      expect(notFound.mergeWith(available).lastKnownMatch, isNotNull);
    });
  });

  group('WatchlistEntry.withoutMembership', () {
    test('removing walks every membership and the title only leaves at the last one', () {
      final e = entry(
        memberships: [
          WatchlistMembership(scope: plexScope, remoteKey: 'abc'),
          WatchlistMembership(scope: jellyfinScope, remoteKey: 'jf-1'),
        ],
      );

      final afterPlex = e.withoutMembership(plexScope);
      expect(afterPlex, isNotNull);
      expect(afterPlex!.memberships.single.scope, jellyfinScope);

      expect(afterPlex.withoutMembership(jellyfinScope), isNull);

      // The original is untouched, so a compensating write can put it back.
      expect(e.memberships, hasLength(2));
    });

    test('an unrelated scope changes nothing', () {
      final e = entry();
      expect(e.withoutMembership(jellyfinScope), same(e));
    });
  });

  group('WatchlistEntry sorting', () {
    final priority = {plexScope: 0, jellyfinScope: 1};

    WatchlistEntry at(
      String key, {
      required WatchlistScopeId scope,
      int position = 0,
      int? addedAt,
      String title = 'Title',
    }) {
      return entry(
        key: key,
        item: discoverItem(title: title),
        memberships: [WatchlistMembership(scope: scope, remoteKey: key, addedAt: addedAt, sourcePosition: position)],
      );
    }

    test('two real timestamps compare on time, newest first', () {
      final older = at('a', scope: jellyfinScope, addedAt: 100);
      final newer = at('b', scope: jellyfinScope, addedAt: 900);

      final sorted = [older, newer]..sort(WatchlistEntry.byRecentlyAdded(priority));

      expect(sorted.map((e) => e.key), ['b', 'a']);
    });

    test('the newest membership speaks for a merged entry', () {
      final old = at('a', scope: jellyfinScope, addedAt: 100);
      final recent = entry(
        key: 'b',
        memberships: [
          WatchlistMembership(scope: jellyfinScope, remoteKey: 'b', addedAt: 50),
          WatchlistMembership(scope: plexScope, remoteKey: 'b', addedAt: 900),
        ],
      );

      final sorted = [old, recent]..sort(WatchlistEntry.byRecentlyAdded(priority));

      expect(sorted.map((e) => e.key), ['b', 'a']);
    });

    test('a source without timestamps keeps the order that source gave', () {
      final first = at('a', scope: plexScope, position: 0);
      final second = at('b', scope: plexScope, position: 1);
      final third = at('c', scope: plexScope, position: 2);

      final sorted = [third, first, second]..sort(WatchlistEntry.byRecentlyAdded(priority));

      expect(sorted.map((e) => e.key), ['a', 'b', 'c']);
    });

    test('no timestamp is ever invented from a position', () {
      final plexNewest = at('plex-first', scope: plexScope, position: 0);
      final jellyfinAncient = at('jf-old', scope: jellyfinScope, addedAt: 1);

      final sorted = [jellyfinAncient, plexNewest]..sort(WatchlistEntry.byRecentlyAdded(priority));

      expect(sorted.map((e) => e.key), [
        'plex-first',
        'jf-old',
      ], reason: 'incomparable pairs fall back to source priority, not to a synthetic timestamp');
      expect(plexNewest.addedAt, isNull, reason: 'a position must never surface as a timestamp');
    });

    test('source priority decides between two sources that cannot be compared on time', () {
      final fromJellyfin = at('jf', scope: jellyfinScope, position: 0);
      final fromPlex = at('plex', scope: plexScope, position: 5);

      final sorted = [fromJellyfin, fromPlex]..sort(WatchlistEntry.byRecentlyAdded(priority));

      expect(sorted.map((e) => e.key), ['plex', 'jf']);
    });

    test('a merged entry ranks by its best-placed source', () {
      final merged = entry(
        key: 'merged',
        memberships: [
          WatchlistMembership(scope: jellyfinScope, remoteKey: 'x', sourcePosition: 0),
          WatchlistMembership(scope: plexScope, remoteKey: 'y', sourcePosition: 3),
        ],
      );
      final plexOnly = at('plex-only', scope: plexScope, position: 7);

      final sorted = [plexOnly, merged]..sort(WatchlistEntry.byRecentlyAdded(priority));

      expect(sorted.map((e) => e.key), ['merged', 'plex-only']);
      expect(merged.rankWithin(priority), (0, 3));
    });

    test('the order does not depend on the order the list came in', () {
      final entries = [
        at('a', scope: plexScope, position: 0, title: 'Alpha'),
        at('b', scope: plexScope, position: 1, title: 'Beta'),
        at('c', scope: jellyfinScope, position: 0, title: 'Gamma'),
        at('d', scope: jellyfinScope, addedAt: 500, title: 'Delta'),
      ];

      final oneWay = [...entries]..sort(WatchlistEntry.byRecentlyAdded(priority));
      final otherWay = [...entries.reversed]..sort(WatchlistEntry.byRecentlyAdded(priority));

      expect(otherWay.map((e) => e.key), oneWay.map((e) => e.key));
    });

    test('an entry from a source that is gone sorts last, not first', () {
      final orphan = at('orphan', scope: otherScope, position: 0);
      final known = at('known', scope: jellyfinScope, position: 9);

      final sorted = [orphan, known]..sort(WatchlistEntry.byRecentlyAdded(priority));

      expect(sorted.map((e) => e.key), ['known', 'orphan']);
    });

    test('title order uses the sort title and is case-insensitive', () {
      final theMatrix = entry(
        key: 'm',
        item: discoverItem(title: 'The Matrix', titleSort: 'Matrix, The'),
      );
      final avatar = entry(
        key: 'a',
        item: discoverItem(title: 'avatar'),
      );

      final sorted = [theMatrix, avatar]..sort(WatchlistEntry.compareByTitle);

      expect(sorted.map((e) => e.key), ['a', 'm']);
    });

    test('equal titles break on key so the order is total', () {
      final first = entry(
        key: 'a',
        item: discoverItem(title: 'Same'),
      );
      final second = entry(
        key: 'b',
        item: discoverItem(title: 'Same'),
      );

      expect(WatchlistEntry.compareByTitle(first, second), lessThan(0));
      expect(WatchlistEntry.compareByTitle(second, first), greaterThan(0));
    });
  });

  group('WatchlistEntry.copyWith', () {
    test('keeps identity and memberships while the resolve result moves on', () {
      final match = serverItem();
      final resolved = entry().copyWith(
        availability: WatchlistAvailability.available,
        coverageComplete: true,
        lastKnownMatch: match,
      );

      expect(resolved.key, 'plex:abc');
      expect(resolved.memberships, hasLength(1));
      expect(resolved.availability, WatchlistAvailability.available);
      expect(resolved.coverageComplete, isTrue);
      expect(resolved.lastKnownMatch, match);
    });

    test('cannot be used to empty the memberships', () {
      expect(() => entry().copyWith(memberships: []), throwsA(isA<ArgumentError>()));
    });
  });
}
