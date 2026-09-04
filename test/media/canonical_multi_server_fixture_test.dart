import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart' show HealthStatus;

import 'canonical_multi_server_fixture.dart';

FixtureCandidate _byId(List<FixtureCandidate> candidates, String id) =>
    candidates.firstWhere((c) => c.item.id == id, orElse: () => throw StateError('no candidate with id $id'));

void main() {
  group('canonical multi-server fixture (hoofdstuk 28)', () {
    test('Dune 2021 shares one TMDB id across Server A and Server B — proves strong merge', () {
      final a = _byId(serverACandidates(), 'a-dune-2021');
      final b = _byId(serverBCandidates(), 'b-dune-2021');
      expect(a.ids.tmdb, kDune2021Tmdb);
      expect(b.ids.tmdb, kDune2021Tmdb);
      expect(a.item.title, b.item.title);
      expect(a.item.year, b.item.year);
    });

    test('Dune 1984 is a different TMDB id from Dune 2021 despite the shared title — remakes stay apart', () {
      final remake = _byId(serverACandidates(), 'a-dune-1984');
      final original = _byId(serverACandidates(), 'a-dune-2021');
      expect(remake.item.title, original.item.title);
      expect(remake.ids.tmdb, isNot(original.ids.tmdb));
    });

    test('Collision has the same title and year but a conflicting TMDB id on each server', () {
      final a = _byId(serverACandidates(), 'a-collision');
      final b = _byId(serverBCandidates(), 'b-collision');
      expect(a.item.title, b.item.title);
      expect(a.item.year, b.item.year);
      expect(a.ids.tmdb, isNot(b.ids.tmdb));
    });

    test('Collision carries an edition per server: Theatrical on A (Plex), Director\'s Cut on B (Jellyfin)', () {
      final a = _byId(serverACandidates(), 'a-collision');
      final b = _byId(serverBCandidates(), 'b-collision');
      expect(a.item.editionTitle, 'Theatrical Cut');
      expect(b.item.editionTitle, isNull); // Jellyfin has no editionTitle field
      expect(b.item.mediaVersions?.single.name, "Director's Cut");
    });

    test('Dune 2021 progress differs between Server A and Server B', () {
      final a = _byId(serverACandidates(), 'a-dune-2021');
      final b = _byId(serverBCandidates(), 'b-dune-2021');
      expect(a.item.viewOffsetMs, isNot(b.item.viewOffsetMs));
    });

    test('Severance has two seasons on Server A and only season 1 on Server B', () {
      final aSeasons = serverACandidates().where((c) => c.item.kind == MediaKind.season).toList();
      final bSeasons = serverBCandidates().where((c) => c.item.kind == MediaKind.season).toList();
      expect(aSeasons, hasLength(2));
      expect(bSeasons, hasLength(1));
    });

    test('Silo lives in a hidden library on Server C', () {
      final silo = _byId(serverCCandidates(), 'c-silo');
      final library = serverCLibraries().firstWhere((l) => l.id == silo.item.libraryId);
      expect(library.hidden, isTrue);
    });

    test('Server C is Pleya Server, never Emby — Pleya has no Emby backend', () {
      for (final candidate in serverCCandidates()) {
        expect(candidate.item.backend.id, 'pleyaServer');
      }
      for (final library in serverCLibraries()) {
        expect(library.backend.id, 'pleyaServer');
      }
    });

    test('Server C health has two distinct, mutually exclusive variants', () {
      expect(serverCHealthOffline(), HealthStatus.offline);
      expect(serverCHealthAuthError(), HealthStatus.authError);
      expect(serverCHealthOffline(), isNot(serverCHealthAuthError()));
    });

    test('Server A has Live TV, Server B does not', () {
      expect(kServerAHasLiveTv, isTrue);
      expect(kServerBHasLiveTv, isFalse);
    });
  });
}
