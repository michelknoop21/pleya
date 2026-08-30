/// Covers docs/qa/tvos-unified-edge-cases.md register C (C1-C24) at the
/// grouping-outcome level — which sources actually end up merged — plus
/// DEC-063's Pleya Server/local isolation and hoofdstuk 4.7/11.5/11.9's
/// representative-selection and group-id contracts. Pure identity-primitive
/// coverage (bucketing, tokens) lives in
/// test/media/canonical_media_identity_test.dart.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_version.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/identity_evidence.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/services/unified_catalog/grouping_service.dart';
import 'package:pleya/utils/external_ids.dart';

import '../media/canonical_multi_server_fixture.dart';

GroupingCandidate _candidateFromItem(MediaItem item, {ExternalIds ids = const ExternalIds()}) {
  final identity = canonicalIdentityOf(item) ?? CanonicalMediaIdentity.opaque();
  final scope = identity.granularity.name;
  final tokens = {
    ...guidTokens(scope: scope, guid: item.guid, kind: item.kind),
    ...externalIdTokens(scope: scope, ids: ids),
  };
  return GroupingCandidate(
    source: UnifiedMediaSource.fromItem(item, externalIds: ids),
    evidence: IdentityEvidence(identity: identity, strongTokens: tokens),
  );
}

GroupingCandidate _candidateFromFixture(FixtureCandidate fixture) => _candidateFromItem(fixture.item, ids: fixture.ids);

void main() {
  group('groupUnifiedMediaSources', () {
    test('empty input returns no groups', () {
      expect(groupUnifiedMediaSources(const []), isEmpty);
    });

    test('C1: the same TMDB id across two servers merges into one group with both sources', () {
      final duneA = serverACandidates().firstWhere((c) => c.item.id == 'a-dune-2021');
      final duneB = serverBCandidates().firstWhere((c) => c.item.id == 'b-dune-2021');

      final groups = groupUnifiedMediaSources([_candidateFromFixture(duneA), _candidateFromFixture(duneB)]);

      expect(groups, hasLength(1));
      expect(groups.single.sources, hasLength(2));
      expect(groups.single.sources.map((s) => s.sourceKey), containsAll([duneA.item.globalKey, duneB.item.globalKey]));
    });

    test('C9: a remake with the same title but a different year stays a separate group', () {
      final dune2021 = serverACandidates().firstWhere((c) => c.item.id == 'a-dune-2021');
      final dune1984 = serverACandidates().firstWhere((c) => c.item.id == 'a-dune-1984');

      final groups = groupUnifiedMediaSources([_candidateFromFixture(dune2021), _candidateFromFixture(dune1984)]);

      expect(groups, hasLength(2));
      expect(groups.every((g) => g.sources.length == 1), isTrue);
    });

    test('C7: same title and year but conflicting tmdb ids never merge', () {
      final collisionA = serverACandidates().firstWhere((c) => c.item.id == 'a-collision');
      final collisionB = serverBCandidates().firstWhere((c) => c.item.id == 'b-collision');

      final groups = groupUnifiedMediaSources([_candidateFromFixture(collisionA), _candidateFromFixture(collisionB)]);

      expect(groups, hasLength(2));
      expect(groups.every((g) => g.sources.length == 1), isTrue);
    });

    test('C13: two editions of the same film on the same server merge, keeping both sources', () {
      final theatrical = MediaItem.plex(
        id: 'm-theatrical',
        kind: MediaKind.movie,
        title: 'Collision',
        year: 2020,
        editionTitle: 'Theatrical Cut',
        serverId: 'server-x',
        serverName: 'Server X',
      );
      final directors = MediaItem.plex(
        id: 'm-directors',
        kind: MediaKind.movie,
        title: 'Collision',
        year: 2020,
        editionTitle: "Director's Cut",
        serverId: 'server-x',
        serverName: 'Server X',
      );
      const ids = ExternalIds(tmdb: 555);

      final groups = groupUnifiedMediaSources([
        _candidateFromItem(theatrical, ids: ids),
        _candidateFromItem(directors, ids: ids),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.sources, hasLength(2));
    });

    test('DEC-063: a Pleya Server source never merges with Plex/Jellyfin, even with matching strong evidence', () {
      final duneA = serverACandidates().firstWhere((c) => c.item.id == 'a-dune-2021');
      final duneC = serverCCandidates().firstWhere((c) => c.item.id == 'c-dune-2021');

      final groups = groupUnifiedMediaSources([_candidateFromFixture(duneA), _candidateFromFixture(duneC)]);

      expect(groups, hasLength(2));
      expect(groups.every((g) => g.sources.length == 1), isTrue);
    });

    test('DEC-063: two Pleya Server sources never merge with each other either', () {
      final item1 = MediaItem(
        id: 'ps-1',
        backend: MediaBackend.pleyaServer,
        kind: MediaKind.movie,
        title: 'Dune',
        year: 2021,
        serverId: 'ps-a',
        serverName: 'PS A',
      );
      final item2 = MediaItem(
        id: 'ps-2',
        backend: MediaBackend.pleyaServer,
        kind: MediaKind.movie,
        title: 'Dune',
        year: 2021,
        serverId: 'ps-b',
        serverName: 'PS B',
      );
      const ids = ExternalIds(tmdb: 999);

      final groups = groupUnifiedMediaSources([
        _candidateFromItem(item1, ids: ids),
        _candidateFromItem(item2, ids: ids),
      ]);

      expect(groups, hasLength(2));
    });

    test('C19: a server contributing two candidates to one bucket never weak-fallback-merges either of them', () {
      final serverAFoo1 = MediaItem(
        id: 'a-foo-1',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'Foo',
        year: 2020,
        serverId: 'server-a',
        serverName: 'A',
      );
      final serverAFoo2 = MediaItem(
        id: 'a-foo-2',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'Foo',
        year: 2020,
        serverId: 'server-a',
        serverName: 'A',
      );
      final serverBFoo = MediaItem(
        id: 'b-foo',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.movie,
        title: 'Foo',
        year: 2020,
        serverId: 'server-b',
        serverName: 'B',
      );

      final groups = groupUnifiedMediaSources([
        _candidateFromItem(serverAFoo1),
        _candidateFromItem(serverAFoo2),
        _candidateFromItem(serverBFoo),
      ]);

      expect(groups, hasLength(3));
      expect(groups.every((g) => g.sources.length == 1), isTrue);
    });

    test('two sources with no strong evidence still merge via title+year when unambiguous', () {
      final a = MediaItem(
        id: 'a-1',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'Local Indie Film',
        year: 2019,
        serverId: 'server-a',
        serverName: 'A',
      );
      final b = MediaItem(
        id: 'b-1',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.movie,
        title: 'Local Indie Film',
        year: 2019,
        serverId: 'server-b',
        serverName: 'B',
      );

      final groups = groupUnifiedMediaSources([_candidateFromItem(a), _candidateFromItem(b)]);

      expect(groups, hasLength(1));
      expect(groups.single.sources, hasLength(2));
    });

    test('C23: a bridging item that would connect two disagreeing tmdb values keeps the whole component apart', () {
      final item1 = MediaItem(
        id: 's1',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'X',
        year: 2020,
        serverId: 'srv-1',
        serverName: '1',
      );
      final item2 = MediaItem(
        id: 's2',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.movie,
        title: 'X',
        year: 2020,
        serverId: 'srv-2',
        serverName: '2',
      );
      final item3 = MediaItem(
        id: 's3',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.movie,
        title: 'X',
        year: 2020,
        serverId: 'srv-3',
        serverName: '3',
      );

      // item1~item2 share tmdb:100; item2~item3 share imdb:tt1 — transitively
      // one component — but item1 and item3 disagree on tmdb (100 vs 200).
      final groups = groupUnifiedMediaSources([
        _candidateFromItem(item1, ids: const ExternalIds(tmdb: 100)),
        _candidateFromItem(item2, ids: const ExternalIds(tmdb: 100, imdb: 'tt1')),
        _candidateFromItem(item3, ids: const ExternalIds(tmdb: 200, imdb: 'tt1')),
      ]);

      expect(groups, hasLength(3));
      expect(groups.every((g) => g.sources.length == 1), isTrue);
    });

    // Confirmed independently against an unauthorized remote commit's claim
    // (see fase-2 handoff) against this function's own documented ordering
    // contract before writing this test.
    test('a namespace-conflict split places each singleton at its own original index, not all at the first', () {
      final item1 = MediaItem(
        id: 's1',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'X',
        year: 2020,
        serverId: 'srv-1',
        serverName: '1',
      );
      final unrelated = MediaItem(
        id: 'unrelated',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'Completely Different Title',
        year: 1999,
        serverId: 'srv-unrelated',
        serverName: 'unrelated',
      );
      final item2 = MediaItem(
        id: 's2',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.movie,
        title: 'X',
        year: 2020,
        serverId: 'srv-2',
        serverName: '2',
      );
      final item3 = MediaItem(
        id: 's3',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.movie,
        title: 'X',
        year: 2020,
        serverId: 'srv-3',
        serverName: '3',
      );

      // Same transitive-conflict shape as C23 (item1~item2 share tmdb:100,
      // item2~item3 share imdb:tt1, item1/item3 disagree on tmdb) but with an
      // unrelated candidate sitting between item1 and item2 in the input.
      // The component still splits into three singletons; each one must land
      // at its own original index, not all bunched at item1's — the
      // function's own doc comment says a group appears "at the position of
      // the first candidate that belongs to it", and for a singleton that is
      // the member itself.
      final groups = groupUnifiedMediaSources([
        _candidateFromItem(item1, ids: const ExternalIds(tmdb: 100)),
        _candidateFromItem(unrelated),
        _candidateFromItem(item2, ids: const ExternalIds(tmdb: 100, imdb: 'tt1')),
        _candidateFromItem(item3, ids: const ExternalIds(tmdb: 200, imdb: 'tt1')),
      ]);

      expect(groups, hasLength(4));
      expect(groups.every((g) => g.sources.length == 1), isTrue);
      expect(
        groups.map((g) => g.sources.single.item.id),
        ['s1', 'unrelated', 's2', 's3'],
        reason: 'the unrelated candidate must stay at its own position, not get pushed after the whole split group',
      );
    });

    test('every source from the input appears in exactly one output group — none dropped, none duplicated', () {
      final all = [
        ...serverACandidates(),
        ...serverBCandidates(),
        ...serverCCandidates(),
      ].map(_candidateFromFixture).toList();

      final groups = groupUnifiedMediaSources(all);

      final totalSources = groups.fold<int>(0, (sum, g) => sum + g.sources.length);
      expect(totalSources, all.length);
      final allKeys = groups.expand((g) => g.sources.map((s) => s.sourceKey)).toSet();
      expect(allKeys, hasLength(all.length));
    });

    test('representative source (hoofdstuk 4.7) prefers richer metadata and artwork over a bare duplicate', () {
      final bare = MediaItem(
        id: 'bare',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'Dune',
        year: 2021,
        serverId: 'server-a',
        serverName: 'A',
      );
      final rich = MediaItem(
        id: 'rich',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.movie,
        title: 'Dune',
        year: 2021,
        summary: 'A rich synopsis.',
        genres: const ['Sci-Fi'],
        rating: 8.5,
        artPath: '/art.jpg',
        thumbPath: '/thumb.jpg',
        serverId: 'server-b',
        serverName: 'B',
      );
      const ids = ExternalIds(tmdb: 1);

      final groups = groupUnifiedMediaSources([_candidateFromItem(bare, ids: ids), _candidateFromItem(rich, ids: ids)]);

      expect(groups.single.representativeSourceKey, rich.globalKey);
    });

    test('C22: group id is independent of member order', () {
      final duneA = serverACandidates().firstWhere((c) => c.item.id == 'a-dune-2021');
      final duneB = serverBCandidates().firstWhere((c) => c.item.id == 'b-dune-2021');

      final forward = groupUnifiedMediaSources([_candidateFromFixture(duneA), _candidateFromFixture(duneB)]);
      final backward = groupUnifiedMediaSources([_candidateFromFixture(duneB), _candidateFromFixture(duneA)]);

      expect(forward.single.groupId, backward.single.groupId);
    });

    test('a single-source group with no strong evidence still gets a stable, non-empty group id', () {
      final a = MediaItem(
        id: 'a-1',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'Nobody Knows This Film',
        year: 2019,
        serverId: 'server-a',
        serverName: 'A',
      );

      final groups = groupUnifiedMediaSources([_candidateFromItem(a)]);

      expect(groups.single.groupId, isNotEmpty);
    });

    test('groups appear at the position of the first candidate that belongs to them', () {
      final movieX = MediaItem(
        id: 'x',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'X',
        year: 2001,
        serverId: 'server-a',
        serverName: 'A',
      );
      final duneA = serverACandidates().firstWhere((c) => c.item.id == 'a-dune-2021');
      final duneB = serverBCandidates().firstWhere((c) => c.item.id == 'b-dune-2021');

      final groups = groupUnifiedMediaSources([
        _candidateFromFixture(duneA),
        _candidateFromItem(movieX),
        _candidateFromFixture(duneB),
      ]);

      expect(groups, hasLength(2));
      expect(groups.first.sources.first.item.id, 'a-dune-2021');
    });

    test('C14: a source keeps its own MediaVersions untouched through grouping', () {
      final item = MediaItem(
        id: 'a-1',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'Dune',
        year: 2021,
        serverId: 'server-a',
        serverName: 'A',
        mediaVersions: const [
          MediaVersion(id: 'v1', height: 2160),
          MediaVersion(id: 'v2', height: 1080),
        ],
      );

      final groups = groupUnifiedMediaSources([_candidateFromItem(item)]);

      expect(groups.single.sources.single.item.mediaVersions, hasLength(2));
    });

    test('C16: an alternate/original title alone never merges without shared strong evidence', () {
      final localized = MediaItem(
        id: 'a-1',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'De Wraak van Dune',
        year: 2021,
        serverId: 'server-a',
        serverName: 'A',
      );
      final original = MediaItem(
        id: 'b-1',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.movie,
        title: 'Dune',
        year: 2021,
        serverId: 'server-b',
        serverName: 'B',
      );

      final withoutEvidence = groupUnifiedMediaSources([_candidateFromItem(localized), _candidateFromItem(original)]);
      expect(withoutEvidence, hasLength(2));

      const ids = ExternalIds(tmdb: 438631);
      final withEvidence = groupUnifiedMediaSources([
        _candidateFromItem(localized, ids: ids),
        _candidateFromItem(original, ids: ids),
      ]);
      expect(withEvidence, hasLength(1));
      expect(withEvidence.single.sources, hasLength(2));
    });

    test('C17: a shared strong id still merges two sources that disagree on year', () {
      final wrongYear = MediaItem(
        id: 'a-1',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'Dune',
        year: 2020,
        serverId: 'server-a',
        serverName: 'A',
      );
      final rightYear = MediaItem(
        id: 'b-1',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.movie,
        title: 'Dune',
        year: 2021,
        serverId: 'server-b',
        serverName: 'B',
      );
      const ids = ExternalIds(tmdb: 438631);

      final groups = groupUnifiedMediaSources([
        _candidateFromItem(wrongYear, ids: ids),
        _candidateFromItem(rightYear, ids: ids),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.sources, hasLength(2));
    });

    test('C24: a Pleya Server item with no external ids and no guid still forms a valid group', () {
      final item = MediaItem(
        id: 'ps-1',
        backend: MediaBackend.pleyaServer,
        kind: MediaKind.movie,
        title: 'Local Only Film',
        serverId: 'ps-a',
        serverName: 'PS A',
      );

      final groups = groupUnifiedMediaSources([_candidateFromItem(item)]);

      expect(groups, hasLength(1));
      expect(groups.single.sources.single.sourceKey, item.globalKey);
      expect(groups.single.groupId, isNotEmpty);
    });

    test('two different episodes of the same show never merge, even sharing the same show title', () {
      final ep1 = MediaItem(
        id: 'e1',
        backend: MediaBackend.plex,
        kind: MediaKind.episode,
        grandparentTitle: 'Severance',
        parentIndex: 1,
        index: 1,
        serverId: 'server-a',
        serverName: 'A',
      );
      final ep2 = MediaItem(
        id: 'e2',
        backend: MediaBackend.plex,
        kind: MediaKind.episode,
        grandparentTitle: 'Severance',
        parentIndex: 1,
        index: 2,
        serverId: 'server-a',
        serverName: 'A',
      );

      final groups = groupUnifiedMediaSources([_candidateFromItem(ep1), _candidateFromItem(ep2)]);

      expect(groups, hasLength(2));
    });
  });
}
