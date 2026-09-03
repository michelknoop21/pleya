/// Canonical multi-server fixture for Pleya Unified TV 2026
/// (docs/tvos-unified-experience.md hoofdstuk 28), shared by service-,
/// provider-, widget- and verify-tests as those phases land.
///
/// Built purely from types that already exist today — [MediaItem],
/// [MediaLibrary], [ExternalIds], [HealthStatus] — because the unified
/// catalog types ([UnifiedMediaSource]/[UnifiedMediaGroup]) don't exist yet;
/// they arrive in fase 1 (docs/DECISIONS.md#dec-063). Fase 0 lays the fixture
/// down, it does not consume it.
///
/// What this fixture proves, per hoofdstuk 28:
///
/// - **Strong merge.** Dune 2021 carries the same TMDB id
///   ([kDune2021Tmdb]) on Server A and Server B.
/// - **Remakes stay apart.** Dune 1984 has a different TMDB id from Dune
///   2021 despite sharing a title.
/// - **Conflicting ids never auto-merge.** Collision (2020) has the *same*
///   title and year on Server A and Server B, but a *different* TMDB id on
///   each ([kCollisionTmdbOnServerA] vs. [kCollisionTmdbOnServerB]).
/// - **Editions.** Collision is a Theatrical edition on Server A (Plex
///   `editionTitle`) and a Director's Cut on Server B (Jellyfin
///   `MediaVersion.name` — Jellyfin has no `editionTitle` field).
/// - **Diverging progress.** Dune 2021's [MediaItem.viewOffsetMs] differs
///   between Server A and Server B.
/// - **Diverging episode coverage.** Severance has two seasons on Server A
///   and only season 1 on Server B.
/// - **Hidden sources.** Silo lives in a hidden library on Server C
///   ([MediaLibrary.hidden]).
/// - **Partial coverage, auth failure, late reconnect.** Server C ships two
///   *alternate* [HealthStatus] fixtures ([serverCHealthOffline],
///   [serverCHealthAuthError]) instead of one fixed health: a real server is
///   never both offline and auth-errored at once, so tests pick the variant
///   the scenario needs.
///
/// Server C is [MediaBackend.pleyaServer]. The approved mockups show "Emby"
/// for the third source, but Pleya has no Emby backend — read it as Pleya
/// Server (DEC-063; hoofdstuk 33.6 conflictpunt 3).
library;

import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart' show HealthStatus;
import 'package:pleya/media/media_version.dart';
import 'package:pleya/utils/external_ids.dart';

/// An item paired with the external ids its server reported for it, in the
/// shape `MediaIdentity.candidate`/`MediaIdentity.pickMatch` consume.
typedef FixtureCandidate = ({MediaItem item, ExternalIds ids});

// -- Server identity ---------------------------------------------------------

const kServerAId = 'server-a';
const kServerBId = 'server-b';
const kServerCId = 'server-c';

const kServerAName = 'Server A';
const kServerBName = 'Server B';
const kServerCName = 'Server C';

/// Server A (Plex) has Live TV; Server B (Jellyfin) does not; Server C is
/// covered by [serverCHealthOffline]/[serverCHealthAuthError] instead of a
/// capability flag, since neither health variant can serve anything.
const kServerAHasLiveTv = true;
const kServerBHasLiveTv = false;

// -- External ids -------------------------------------------------------------

const kDune2021Tmdb = 438631;
const kDune1984Tmdb = 900001;
const kOppenheimerTmdb = 900002;
const kSeveranceTmdb = 900003;
const kSiloTmdb = 900004;
const kCollisionTmdbOnServerA = 900010;
const kCollisionTmdbOnServerB = 900020;

// -- Library ids ---------------------------------------------------------------

const kLibraryAMovies = 'lib-a-movies';
const kLibraryATv = 'lib-a-tv';
const kLibraryBMovies = 'lib-b-movies';
const kLibraryBTv = 'lib-b-tv';
const kLibraryCMovies = 'lib-c-movies';
const kLibraryCHiddenTv = 'lib-c-tv-hidden';

// -- Libraries -----------------------------------------------------------------

List<MediaLibrary> serverALibraries() => const [
  MediaLibrary(
    id: kLibraryAMovies,
    backend: MediaBackend.plex,
    title: 'Movies',
    kind: MediaKind.movie,
    serverId: kServerAId,
    serverName: kServerAName,
  ),
  MediaLibrary(
    id: kLibraryATv,
    backend: MediaBackend.plex,
    title: 'TV Shows',
    kind: MediaKind.show,
    serverId: kServerAId,
    serverName: kServerAName,
  ),
];

List<MediaLibrary> serverBLibraries() => const [
  MediaLibrary(
    id: kLibraryBMovies,
    backend: MediaBackend.jellyfin,
    title: 'Movies',
    kind: MediaKind.movie,
    serverId: kServerBId,
    serverName: kServerBName,
  ),
  MediaLibrary(
    id: kLibraryBTv,
    backend: MediaBackend.jellyfin,
    title: 'Shows',
    kind: MediaKind.show,
    serverId: kServerBId,
    serverName: kServerBName,
  ),
];

/// Server C's TV library is hidden — proves "hidden sources" (hoofdstuk 28)
/// independently of the server's own online/offline/auth-error state.
List<MediaLibrary> serverCLibraries() => const [
  MediaLibrary(
    id: kLibraryCMovies,
    backend: MediaBackend.pleyaServer,
    title: 'Movies',
    kind: MediaKind.movie,
    serverId: kServerCId,
    serverName: kServerCName,
  ),
  MediaLibrary(
    id: kLibraryCHiddenTv,
    backend: MediaBackend.pleyaServer,
    title: 'Shows',
    kind: MediaKind.show,
    serverId: kServerCId,
    serverName: kServerCName,
    hidden: true,
  ),
];

// -- Server A candidates (Plex) -------------------------------------------------

List<FixtureCandidate> serverACandidates() => [
  (
    item: MediaItem(
      id: 'a-dune-2021',
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      guid: 'plex://movie/dune-2021',
      title: 'Dune',
      year: 2021,
      durationMs: 9300000, // 155 min
      viewOffsetMs: 2520000, // 42 min
      libraryId: kLibraryAMovies,
      libraryTitle: 'Movies',
      serverId: kServerAId,
      serverName: kServerAName,
      mediaVersions: const [
        MediaVersion(id: 'a-dune-2021-v1', width: 3840, height: 2160, videoResolution: '4k', videoCodec: 'hevc'),
      ],
    ),
    ids: const ExternalIds(tmdb: kDune2021Tmdb),
  ),
  (
    item: MediaItem(
      id: 'a-dune-1984',
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      guid: 'plex://movie/dune-1984',
      title: 'Dune',
      year: 1984,
      durationMs: 7920000, // 132 min
      libraryId: kLibraryAMovies,
      libraryTitle: 'Movies',
      serverId: kServerAId,
      serverName: kServerAName,
    ),
    ids: const ExternalIds(tmdb: kDune1984Tmdb),
  ),
  (
    item: MediaItem(
      id: 'a-severance',
      backend: MediaBackend.plex,
      kind: MediaKind.show,
      guid: 'plex://show/severance',
      title: 'Severance',
      libraryId: kLibraryATv,
      libraryTitle: 'TV Shows',
      childCount: 2,
      serverId: kServerAId,
      serverName: kServerAName,
    ),
    ids: const ExternalIds(tmdb: kSeveranceTmdb),
  ),
  (
    item: MediaItem(
      id: 'a-severance-s1',
      backend: MediaBackend.plex,
      kind: MediaKind.season,
      title: 'Season 1',
      parentId: 'a-severance',
      parentTitle: 'Severance',
      index: 1,
      libraryId: kLibraryATv,
      serverId: kServerAId,
      serverName: kServerAName,
    ),
    ids: const ExternalIds(),
  ),
  (
    item: MediaItem(
      id: 'a-severance-s1e1',
      backend: MediaBackend.plex,
      kind: MediaKind.episode,
      title: 'Good News About Hell',
      grandparentId: 'a-severance',
      grandparentTitle: 'Severance',
      parentId: 'a-severance-s1',
      parentIndex: 1,
      index: 1,
      libraryId: kLibraryATv,
      serverId: kServerAId,
      serverName: kServerAName,
    ),
    ids: const ExternalIds(),
  ),
  (
    item: MediaItem(
      id: 'a-severance-s2',
      backend: MediaBackend.plex,
      kind: MediaKind.season,
      title: 'Season 2',
      parentId: 'a-severance',
      parentTitle: 'Severance',
      index: 2,
      libraryId: kLibraryATv,
      serverId: kServerAId,
      serverName: kServerAName,
    ),
    ids: const ExternalIds(),
  ),
  (
    item: MediaItem(
      id: 'a-severance-s2e1',
      backend: MediaBackend.plex,
      kind: MediaKind.episode,
      title: 'Hello, Ms. Cobel',
      grandparentId: 'a-severance',
      grandparentTitle: 'Severance',
      parentId: 'a-severance-s2',
      parentIndex: 2,
      index: 1,
      libraryId: kLibraryATv,
      serverId: kServerAId,
      serverName: kServerAName,
    ),
    ids: const ExternalIds(),
  ),
  (
    item: MediaItem.plex(
      id: 'a-collision',
      kind: MediaKind.movie,
      guid: 'plex://movie/collision-2020-a',
      title: 'Collision',
      year: 2020,
      durationMs: 6300000,
      editionTitle: 'Theatrical Cut',
      libraryId: kLibraryAMovies,
      libraryTitle: 'Movies',
      serverId: kServerAId,
      serverName: kServerAName,
    ),
    ids: const ExternalIds(tmdb: kCollisionTmdbOnServerA),
  ),
];

// -- Server B candidates (Jellyfin) ---------------------------------------------

List<FixtureCandidate> serverBCandidates() => [
  (
    item: MediaItem(
      id: 'b-dune-2021',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.movie,
      title: 'Dune',
      year: 2021,
      durationMs: 9300000,
      viewOffsetMs: 900000, // 15 min — deliberately different from Server A
      libraryId: kLibraryBMovies,
      libraryTitle: 'Movies',
      serverId: kServerBId,
      serverName: kServerBName,
      mediaVersions: const [
        MediaVersion(id: 'b-dune-2021-v1', width: 1920, height: 1080, videoResolution: '1080', videoCodec: 'h264'),
      ],
    ),
    ids: const ExternalIds(tmdb: kDune2021Tmdb),
  ),
  (
    item: MediaItem(
      id: 'b-oppenheimer',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.movie,
      title: 'Oppenheimer',
      year: 2023,
      durationMs: 10800000,
      libraryId: kLibraryBMovies,
      libraryTitle: 'Movies',
      serverId: kServerBId,
      serverName: kServerBName,
    ),
    ids: const ExternalIds(tmdb: kOppenheimerTmdb),
  ),
  (
    item: MediaItem(
      id: 'b-severance',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.show,
      title: 'Severance',
      libraryId: kLibraryBTv,
      libraryTitle: 'Shows',
      childCount: 1,
      serverId: kServerBId,
      serverName: kServerBName,
    ),
    ids: const ExternalIds(tmdb: kSeveranceTmdb),
  ),
  (
    item: MediaItem(
      id: 'b-severance-s1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.season,
      title: 'Season 1',
      parentId: 'b-severance',
      parentTitle: 'Severance',
      index: 1,
      libraryId: kLibraryBTv,
      serverId: kServerBId,
      serverName: kServerBName,
    ),
    ids: const ExternalIds(),
  ),
  (
    item: MediaItem(
      id: 'b-severance-s1e1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.episode,
      title: 'Good News About Hell',
      grandparentId: 'b-severance',
      grandparentTitle: 'Severance',
      parentId: 'b-severance-s1',
      parentIndex: 1,
      index: 1,
      libraryId: kLibraryBTv,
      serverId: kServerBId,
      serverName: kServerBName,
    ),
    ids: const ExternalIds(),
  ),
  (
    item: MediaItem(
      id: 'b-collision',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.movie,
      title: 'Collision',
      year: 2020,
      durationMs: 6300000,
      libraryId: kLibraryBMovies,
      libraryTitle: 'Movies',
      serverId: kServerBId,
      serverName: kServerBName,
      mediaVersions: const [MediaVersion(id: 'b-collision-v1', width: 1920, height: 1080, name: "Director's Cut")],
    ),
    ids: const ExternalIds(tmdb: kCollisionTmdbOnServerB),
  ),
];

// -- Server C candidates (Pleya Server) ------------------------------------------

List<FixtureCandidate> serverCCandidates() => [
  (
    item: MediaItem(
      id: 'c-dune-2021',
      backend: MediaBackend.pleyaServer,
      kind: MediaKind.movie,
      title: 'Dune',
      year: 2021,
      durationMs: 9300000,
      libraryId: kLibraryCMovies,
      libraryTitle: 'Movies',
      serverId: kServerCId,
      serverName: kServerCName,
    ),
    ids: const ExternalIds(tmdb: kDune2021Tmdb),
  ),
  (
    item: MediaItem(
      id: 'c-silo',
      backend: MediaBackend.pleyaServer,
      kind: MediaKind.show,
      title: 'Silo',
      libraryId: kLibraryCHiddenTv,
      libraryTitle: 'Shows',
      serverId: kServerCId,
      serverName: kServerCName,
    ),
    ids: const ExternalIds(tmdb: kSiloTmdb),
  ),
];

// -- Server C health variants -----------------------------------------------
//
// A server is never both offline and auth-errored at once, so these are two
// separate fixtures rather than one combined state — a test picks whichever
// variant the scenario needs (hoofdstuk 28: "offline"; "auth-errorvariant").

HealthStatus serverCHealthOffline() => HealthStatus.offline;

HealthStatus serverCHealthAuthError() => HealthStatus.authError;
