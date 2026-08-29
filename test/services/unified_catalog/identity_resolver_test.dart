/// Covers docs/qa/tvos-unified-edge-cases.md register C20/C21, plus
/// [UnifiedIdentityResolver]'s own I/O-orchestration contract: only
/// duplicate-bucket items ever cost a fetch, concurrency stays bounded, and
/// results are cached per (server, target) within one resolution pass.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/services/unified_catalog/identity_resolver.dart';
import 'package:pleya/utils/external_ids.dart';

MediaItem _movie(String id, {String? title = 'Dune', int? year = 2021, String serverId = 'server-a'}) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: title, year: year, serverId: serverId);

ResolvableItem _resolvable(MediaItem item) {
  final identity = canonicalIdentityOf(item)!;
  return ResolvableItem(
    item: item,
    identity: identity,
    scope: 'movie',
    externalIdTarget: (serverId: item.serverId!, targetId: item.id),
  );
}

void main() {
  group('UnifiedIdentityResolver.resolveEvidence', () {
    test('empty input resolves to no evidence without any fetch', () async {
      var calls = 0;
      final resolver = UnifiedIdentityResolver(
        fetchExternalIds: (serverId, targetId) async {
          calls++;
          return const ExternalIds();
        },
      );

      final evidence = await resolver.resolveEvidence(const []);

      expect(evidence, isEmpty);
      expect(calls, 0);
    });

    test('an item alone in its bucket never costs a fetch', () async {
      var calls = 0;
      final resolver = UnifiedIdentityResolver(
        fetchExternalIds: (serverId, targetId) async {
          calls++;
          return const ExternalIds();
        },
      );

      final evidence = await resolver.resolveEvidence([_resolvable(_movie('a'))]);

      expect(calls, 0);
      expect(evidence.single.hasStrongEvidence, isFalse);
    });

    test('only items sharing a duplicate bucket cost a fetch', () async {
      final requested = <String>[];
      final resolver = UnifiedIdentityResolver(
        fetchExternalIds: (serverId, targetId) async {
          requested.add(targetId);
          return const ExternalIds(tmdb: 1);
        },
      );

      final items = [
        _resolvable(_movie('dup-1', title: 'Dune', year: 2021)),
        _resolvable(_movie('dup-2', title: 'Dune', year: 2021)),
        _resolvable(_movie('unique', title: 'Oppenheimer', year: 2023)),
      ];

      await resolver.resolveEvidence(items);

      expect(requested, containsAll(['dup-1', 'dup-2']));
      expect(requested, isNot(contains('unique')));
    });

    test('C20: a failed fetch degrades that item to guid-only evidence instead of failing the batch', () async {
      final resolver = UnifiedIdentityResolver(
        fetchExternalIds: (serverId, targetId) async {
          if (targetId == 'fails') throw Exception('network down');
          return const ExternalIds(tmdb: 1);
        },
      );

      final items = [
        _resolvable(_movie('fails', title: 'Dune', year: 2021)),
        _resolvable(_movie('succeeds', title: 'Dune', year: 2021)),
      ];

      final evidence = await resolver.resolveEvidence(items);

      expect(evidence, hasLength(2));
      expect(evidence[0].hasStrongEvidence, isFalse);
      expect(evidence[1].hasStrongEvidence, isTrue);
    });

    test('C21: evidence reflects whatever the fetcher returns *this* call — no hidden staleness', () async {
      var version = 1;
      final resolver = UnifiedIdentityResolver(
        fetchExternalIds: (serverId, targetId) async => ExternalIds(tmdb: version),
      );
      final items = [
        _resolvable(_movie('a', title: 'Dune', year: 2021)),
        _resolvable(_movie('b', title: 'Dune', year: 2021)),
      ];

      final first = await resolver.resolveEvidence(items);
      version = 2;
      final second = await resolver.resolveEvidence(items);

      expect(first.first.strongTokens.single.value, '1');
      expect(second.first.strongTokens.single.value, '2');
    });

    test('two items targeting the same (server, target) id fetch only once', () async {
      var calls = 0;
      final resolver = UnifiedIdentityResolver(
        fetchExternalIds: (serverId, targetId) async {
          calls++;
          return const ExternalIds(tmdb: 1);
        },
      );
      final shared = (serverId: 'server-a', targetId: 'shared-target');
      final items = [
        ResolvableItem(
          item: _movie('a', title: 'Dune', year: 2021),
          identity: CanonicalMediaIdentity.movie(title: 'Dune', year: 2021),
          scope: 'movie',
          externalIdTarget: shared,
        ),
        ResolvableItem(
          item: _movie('b', title: 'Dune', year: 2021),
          identity: CanonicalMediaIdentity.movie(title: 'Dune', year: 2021),
          scope: 'movie',
          externalIdTarget: shared,
        ),
      ];

      await resolver.resolveEvidence(items);

      expect(calls, 1);
    });

    test('concurrency never exceeds maxConcurrentFetches', () async {
      var inFlight = 0;
      var maxObserved = 0;
      final resolver = UnifiedIdentityResolver(
        maxConcurrentFetches: 2,
        fetchExternalIds: (serverId, targetId) async {
          inFlight++;
          if (inFlight > maxObserved) maxObserved = inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          inFlight--;
          return const ExternalIds(tmdb: 1);
        },
      );
      final items = [for (var i = 0; i < 6; i++) _resolvable(_movie('dup-$i', title: 'Dune', year: 2021))];

      await resolver.resolveEvidence(items);

      expect(maxObserved, lessThanOrEqualTo(2));
    });
  });
}
