@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_identity.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/identity_evidence.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/services/pleya_server_auth_service.dart';
import 'package:pleya/services/pleya_server_client.dart';
import 'package:pleya/services/unified_catalog/grouping_service.dart';
import 'package:pleya/utils/external_ids.dart';

/// The unified chain against a real Pleya Server process: the Go server's
/// answer, the wire parser, the client adapter, the identity evidence and the
/// grouping, with nothing faked on the server side.
///
/// Skipped without an address, because a suite that needs a server to be green
/// is not a suite. It is meant for a throwaway local server, never for the NAS
/// (AGENTS.md: tests never touch the NAS). Run:
///
/// ```sh
/// PLEYA_LIVE_BASE_URL=http://127.0.0.1:18832 PLEYA_LIVE_USER=tester PLEYA_LIVE_PASS=... \
///   PLEYA_LIVE_TITLE=Severance PLEYA_LIVE_YEAR=2022 PLEYA_LIVE_TMDB=95396 \
///   flutter test test/pleya_server/pleya_server_external_ids_live_test.dart --tags live
/// ```
///
/// [title], [year] and [tmdb] name a show the server has matched; the test
/// also expects one more show on the server that it has not matched.
void main() {
  final env = Platform.environment;
  final baseUrl = env['PLEYA_LIVE_BASE_URL'] ?? '';
  final user = env['PLEYA_LIVE_USER'] ?? '';
  final pass = env['PLEYA_LIVE_PASS'] ?? '';
  final title = env['PLEYA_LIVE_TITLE'] ?? '';
  final year = int.tryParse(env['PLEYA_LIVE_YEAR'] ?? '');
  final tmdb = int.tryParse(env['PLEYA_LIVE_TMDB'] ?? '');

  if (baseUrl.isEmpty || user.isEmpty || pass.isEmpty || title.isEmpty || tmdb == null) {
    test('live external ids', () {}, skip: 'set PLEYA_LIVE_BASE_URL, _USER, _PASS, _TITLE, _YEAR and _TMDB');
    return;
  }

  setUp(() => HttpOverrides.global = null);

  late PleyaServerClient client;

  setUpAll(() async {
    final auth = PleyaServerAuthService();
    final result = await auth.login(baseUrl: baseUrl, username: user, password: pass);
    final connection = PleyaServerConnection(
      id: pleyaServerConnectionId(serverId: result.info.serverId, userId: result.userId),
      baseUrl: baseUrl,
      serverId: result.info.serverId,
      serverName: 'Live',
      userName: result.userName,
      refreshToken: result.tokens.refreshToken,
      status: ConnectionStatus.online,
      createdAt: DateTime.now(),
      lastAuthenticatedAt: DateTime.now(),
    );
    client = PleyaServerClient.create(connection);
    await client.refreshCapabilities();
  });

  tearDownAll(() => client.close());

  Future<List<MediaItem>> allShows() async {
    final libraries = await client.fetchLibraries();
    final shows = <MediaItem>[];
    for (final library in libraries.where((l) => l.kind == MediaKind.show)) {
      shows.addAll((await client.fetchLibraryContent(library.id, const LibraryQuery(limit: 100))).items);
    }
    return shows;
  }

  test('the matched show carries its TMDB number over the real wire, an unmatched one carries none', () async {
    final shows = await allShows();
    final matched = shows.firstWhere((s) => s.title == title);
    final ids = await client.fetchExternalIds(matched.id);

    // ignore: avoid_print
    print('LIVE ${matched.title} (${matched.year}) id=${matched.id} external_ids=$ids');
    expect(ids, ExternalIds(tmdb: tmdb));

    final others = shows.where((s) => s.title != title).toList();
    expect(others, isNotEmpty, reason: 'the live server should also hold an unmatched show');
    for (final other in others) {
      // ignore: avoid_print
      print('LIVE ${other.title} (${other.year}) external_ids=${await client.fetchExternalIds(other.id)}');
    }
    expect(await client.fetchExternalIds(others.first.id), const ExternalIds());
  });

  test('the real server item folds with a Plex-shaped source of the same series, and not with a remake', () async {
    final matched = (await allShows()).firstWhere((s) => s.title == title);
    final plexSame = MediaItem(
      id: 'plex-1',
      backend: MediaBackend.plex,
      kind: MediaKind.show,
      title: title,
      year: year,
      serverId: 'plex-srv',
      serverName: 'Plex',
    );
    final plexRemake = MediaItem(
      id: 'plex-2',
      backend: MediaBackend.plex,
      kind: MediaKind.show,
      title: title,
      year: year,
      serverId: 'plex-srv',
      serverName: 'Plex',
    );

    GroupingCandidate candidate(MediaItem item, ExternalIds ids) {
      final identity = canonicalIdentityOf(item)!;
      return GroupingCandidate(
        source: UnifiedMediaSource.fromItem(item, externalIds: ids),
        evidence: IdentityEvidence(
          identity: identity,
          strongTokens: externalIdTokens(scope: identity.granularity.name, ids: ids),
        ),
      );
    }

    final realIds = await client.fetchExternalIds(matched.id);
    final folded = groupUnifiedMediaSources([
      candidate(plexSame, ExternalIds(tmdb: tmdb)),
      candidate(matched, realIds),
    ]);
    expect(folded, hasLength(1));
    expect(folded.single.sources.map((s) => s.backend), unorderedEquals([MediaBackend.plex, MediaBackend.pleyaServer]));

    final apart = groupUnifiedMediaSources([
      candidate(plexRemake, ExternalIds(tmdb: tmdb + 1)),
      candidate(matched, realIds),
    ]);
    expect(apart, hasLength(2));
  });

  test(
    'findAllByIdentity on the real server finds the matched show by number and nothing for another number',
    () async {
      final hit = await client.findAllByIdentity(
        MediaIdentity(
          externalIds: ExternalIds(tmdb: tmdb),
          title: title,
          year: year,
          kind: MediaKind.show,
        ),
      );
      expect(hit.map((m) => m.title), [title]);

      final miss = await client.findAllByIdentity(
        MediaIdentity(
          externalIds: ExternalIds(tmdb: tmdb + 1),
          title: title,
          year: year,
          kind: MediaKind.show,
        ),
      );
      expect(miss, isEmpty);
    },
  );
}
