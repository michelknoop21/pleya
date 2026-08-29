/// Covers docs/qa/tvos-unified-edge-cases.md register C (C1-C24) at the pure
/// identity-primitive level: bucketing, year agreement, and the strong-token
/// builders (`guidTokens`/`externalIdTokens`/`normalizeStableGuid`).
/// Grouping-level outcomes (which sources actually merge) are covered in
/// test/services/unified_grouping_service_test.dart.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/identity_evidence.dart';
import 'package:pleya/utils/external_ids.dart';

void main() {
  group('CanonicalMediaIdentity.bucketKey', () {
    test('movie bucket includes kind, normalized title, and year', () {
      final identity = CanonicalMediaIdentity.movie(title: 'Dune', year: 2021);
      expect(identity.bucketKey, 'movie:dune:2021');
    });

    test('C6/C9: different years never share a movie bucket (remakes, wrong-year titles)', () {
      final a = CanonicalMediaIdentity.movie(title: 'Dune', year: 2021);
      final b = CanonicalMediaIdentity.movie(title: 'Dune', year: 1984);
      expect(a.bucketKey, isNot(b.bucketKey));
    });

    test('C8: a movie without a year still buckets — year is omitted, not blocking', () {
      expect(CanonicalMediaIdentity.movie(title: 'Dune').bucketKey, 'movie:dune:');
    });

    test('C10: a movie and a show never share a bucket, even with the identical title', () {
      final movie = CanonicalMediaIdentity.movie(title: 'Silo', year: 2023);
      final show = CanonicalMediaIdentity.show(title: 'Silo', year: 2023);
      expect(movie.bucketKey, isNot(show.bucketKey));
    });

    test('episode bucket needs show title, season index and episode index', () {
      final identity = CanonicalMediaIdentity.episode(showTitle: 'Severance', seasonIndex: 1, episodeIndex: 1);
      expect(identity.bucketKey, 'episode:severance:1:1');
    });

    test('D6/D7: a missing season or episode index makes the episode bucket unusable', () {
      expect(CanonicalMediaIdentity.episode(showTitle: 'Severance', episodeIndex: 1).bucketKey, isNull);
      expect(CanonicalMediaIdentity.episode(showTitle: 'Severance', seasonIndex: 1).bucketKey, isNull);
    });

    test('D5: season 0 (specials) is a real, distinct, bucketable season index', () {
      final special = CanonicalMediaIdentity.episode(showTitle: 'Severance', seasonIndex: 0, episodeIndex: 1);
      expect(special.bucketKey, 'episode:severance:0:1');
    });

    test('C15: identical unicode/diacritic titles still bucket together', () {
      final a = CanonicalMediaIdentity.movie(title: 'Café', year: 2020);
      final b = CanonicalMediaIdentity.movie(title: 'Café', year: 2020);
      expect(a.bucketKey, equals(b.bucketKey));
    });

    test('a title with no alphanumeric characters, or no title at all, has no bucket', () {
      expect(CanonicalMediaIdentity.movie(title: '...', year: 2020).bucketKey, isNull);
      expect(CanonicalMediaIdentity.movie(year: 2020).bucketKey, isNull);
    });
  });

  group('CanonicalMediaIdentity.yearAgreesWith', () {
    test('C18: a missing year on either side never agrees', () {
      final withYear = CanonicalMediaIdentity.movie(title: 'Dune', year: 2021);
      final noYear = CanonicalMediaIdentity.movie(title: 'Dune');
      expect(withYear.yearAgreesWith(noYear), isFalse);
      expect(noYear.yearAgreesWith(withYear), isFalse);
    });

    test('equal known years agree', () {
      final a = CanonicalMediaIdentity.movie(title: 'Dune', year: 2021);
      final b = CanonicalMediaIdentity.movie(title: 'Dune', year: 2021);
      expect(a.yearAgreesWith(b), isTrue);
    });

    test('C17: differing years on the same title never agree', () {
      final a = CanonicalMediaIdentity.movie(title: 'Dune', year: 2021);
      final b = CanonicalMediaIdentity.movie(title: 'Dune', year: 2020);
      expect(a.yearAgreesWith(b), isFalse);
    });
  });

  group('canonicalIdentityOf', () {
    test('movie identity from title and year', () {
      final movie = MediaItem(id: '1', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Dune', year: 2021);
      expect(canonicalIdentityOf(movie), CanonicalMediaIdentity.movie(title: 'Dune', year: 2021));
    });

    test('C10: show identity is a different granularity than movie for the same title', () {
      final show = MediaItem(id: '1', backend: MediaBackend.plex, kind: MediaKind.show, title: 'Silo', year: 2023);
      expect(canonicalIdentityOf(show)!.granularity, CanonicalIdentityGranularity.show);
    });

    test('season identity uses the show title (grandparentTitle) and season index', () {
      final season = MediaItem(
        id: 's1',
        backend: MediaBackend.plex,
        kind: MediaKind.season,
        grandparentTitle: 'Severance',
        index: 1,
      );
      expect(canonicalIdentityOf(season), CanonicalMediaIdentity.season(showTitle: 'Severance', seasonIndex: 1));
    });

    test('season identity falls back to parentTitle when grandparentTitle is missing', () {
      final season = MediaItem(
        id: 's1',
        backend: MediaBackend.plex,
        kind: MediaKind.season,
        parentTitle: 'Severance',
        index: 1,
      );
      expect(canonicalIdentityOf(season), CanonicalMediaIdentity.season(showTitle: 'Severance', seasonIndex: 1));
    });

    test('episode identity uses show title, season index (parentIndex) and episode index', () {
      final episode = MediaItem(
        id: 'e1',
        backend: MediaBackend.plex,
        kind: MediaKind.episode,
        grandparentTitle: 'Severance',
        parentIndex: 1,
        index: 1,
      );
      expect(
        canonicalIdentityOf(episode),
        CanonicalMediaIdentity.episode(showTitle: 'Severance', seasonIndex: 1, episodeIndex: 1),
      );
    });

    test('D6: an episode missing its season index has no bucketable identity', () {
      final episode = MediaItem(
        id: 'e1',
        backend: MediaBackend.plex,
        kind: MediaKind.episode,
        grandparentTitle: 'Severance',
        index: 1,
      );
      expect(canonicalIdentityOf(episode)!.bucketKey, isNull);
    });

    test('unsupported kinds (collections, playlists, ...) have no identity', () {
      final playlist = MediaItem(id: 'p1', backend: MediaBackend.plex, kind: MediaKind.playlist, title: 'My playlist');
      expect(canonicalIdentityOf(playlist), isNull);
    });
  });

  group('CanonicalMediaIdentity.opaque', () {
    test('has no bucket key and never equals a real identity', () {
      final opaque = CanonicalMediaIdentity.opaque();
      expect(opaque.bucketKey, isNull);
      expect(opaque, isNot(CanonicalMediaIdentity.movie(title: 'Dune', year: 2021)));
    });
  });

  group('normalizeStableGuid', () {
    test('C4: a well-formed agent guid is stable evidence', () {
      expect(normalizeStableGuid('plex://movie/abc123'), 'plex://movie/abc123');
    });

    test('C11: the Plex "no agent matched" marker is never stable, legacy and current form', () {
      expect(normalizeStableGuid('com.plexapp.agents.none://abc'), isNull);
      expect(normalizeStableGuid('tv.plex.agents.none://abc'), isNull);
    });

    test('C12: a guid with no scheme is server-local, never stable evidence', () {
      expect(normalizeStableGuid('12345'), isNull);
    });

    test('null and blank guids are never stable evidence', () {
      expect(normalizeStableGuid(null), isNull);
      expect(normalizeStableGuid(''), isNull);
      expect(normalizeStableGuid('   '), isNull);
    });

    test('normalizes case so two servers reporting different casing still match', () {
      expect(normalizeStableGuid('Plex://Movie/ABC'), 'plex://movie/abc');
    });
  });

  group('guidTokens', () {
    test('C4: two sources with the identical stable guid produce the identical token', () {
      final a = guidTokens(scope: 'movie', guid: 'plex://movie/dune-2021', kind: MediaKind.movie);
      final b = guidTokens(scope: 'movie', guid: 'plex://movie/dune-2021', kind: MediaKind.movie);
      expect(a.single, b.single);
      expect(a.single.key, 'movie:guid:plex://movie/dune-2021');
    });

    test('an episode guid is always scoped to episode, even when the caller passes a different scope', () {
      final tokens = guidTokens(scope: 'show', guid: 'plex://episode/abc', kind: MediaKind.episode);
      expect(tokens.single.scope, 'episode');
    });

    test('C11/C12: unusable guids contribute no tokens', () {
      expect(guidTokens(scope: 'movie', guid: 'tv.plex.agents.none://x', kind: MediaKind.movie), isEmpty);
      expect(guidTokens(scope: 'movie', guid: null, kind: MediaKind.movie), isEmpty);
    });
  });

  group('externalIdTokens', () {
    test('C1: a shared tmdb id produces the identical token from two sources', () {
      final a = externalIdTokens(scope: 'movie', ids: const ExternalIds(tmdb: 438631));
      final b = externalIdTokens(scope: 'movie', ids: const ExternalIds(tmdb: 438631));
      expect(a.single, b.single);
    });

    test('C2: imdb tokens compare case-insensitively', () {
      final a = externalIdTokens(
        scope: 'movie',
        ids: const ExternalIds(imdb: 'tt1160419'),
      );
      final b = externalIdTokens(
        scope: 'movie',
        ids: const ExternalIds(imdb: 'TT1160419'),
      );
      expect(a.single, b.single);
    });

    test('C3: a shared tvdb id at show scope produces the identical token', () {
      final a = externalIdTokens(scope: 'show', ids: const ExternalIds(tvdb: 371980));
      final b = externalIdTokens(scope: 'show', ids: const ExternalIds(tvdb: 371980));
      expect(a.single, b.single);
    });

    test('C24: no external ids at all yields no tokens, without throwing', () {
      expect(externalIdTokens(scope: 'movie', ids: const ExternalIds()), isEmpty);
    });

    test('different namespaces never collide even with the same numeric value', () {
      final tmdb = externalIdTokens(scope: 'movie', ids: const ExternalIds(tmdb: 123));
      final tvdb = externalIdTokens(scope: 'movie', ids: const ExternalIds(tvdb: 123));
      expect(tmdb.single, isNot(tvdb.single));
    });

    test('all three namespaces build independent tokens from one ExternalIds', () {
      final tokens = externalIdTokens(
        scope: 'movie',
        ids: const ExternalIds(imdb: 'tt1', tmdb: 2, tvdb: 3),
      );
      expect(tokens, hasLength(3));
      expect(tokens.map((t) => t.namespace), containsAll(['imdb', 'tmdb', 'tvdb']));
    });
  });
}
