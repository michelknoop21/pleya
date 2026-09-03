/// The rows the fase-6 discovery goldens browse.
///
/// ## Why these are shaped the way they are
///
/// Hoofdstuk 10.2a's landing is row-based, and the focused card is wide while
/// its neighbours stay compact. That makes discovery fixtures a different
/// problem from the fase-5 catalogus ones. A grid fixture only has to vary
/// colour and source count; a rail fixture has to carry enough *content* that
/// the expanded state has something real to expand into — a synopsis that can
/// overflow, a title that can wrap, an episode that knows which season it is
/// from — because an expanded card holding placeholder text proves nothing
/// about whether the design works.
///
/// So every case here is reachable by name and exists to picture one specific
/// thing that could go wrong:
///
/// * [tvDiscoveryFilmsRow] — mixed palettes, mixed source counts, mixed watch
///   state, and deliberately two incomplete rows: one title with a poster but
///   no landscape art, and one with no artwork at all. Both are states a real
///   server produces, and a rail that only ever renders complete artwork has
///   never been asked the interesting question.
/// * [tvDiscoverySeriesRow] — the same chrome, a different library. A shelf of
///   series skews lighter and warmer than a shelf of films and should be
///   allowed to, so these palettes start from the bright end.
/// * [tvDiscoveryContinueWatchingRow] — concrete episodes with season, episode,
///   runtime and offset, so "S2 E4 · 18 min resterend" is *computed from the
///   fixture* rather than hardcoded in a widget. A widget that hardcodes it
///   passes a golden and lies on a device.
/// * [tvDiscoveryLongTitleGroup] and [tvDiscoveryLongSynopsisGroup] — long
///   enough to break a naive layout at the tvOS canvas (1038x584).
/// * [tvDiscoveryThreeSourceGroup] — exactly three sources, so a "3 bronnen"
///   reading is provable rather than plausible.
///
/// ## What stays honest
///
/// Sources are real `UnifiedMediaSource.fromItem` projections and the watch
/// state is a real `UnifiedWatchState`, exactly as the fase-5 helpers build
/// them. A fixture that fakes those would picture a code path the product never
/// takes. Group ids are literal strings, not derived from a loop index, so
/// reordering a row is a visible diff rather than a silent renumbering.
///
/// The artwork indices line up with `TvDiscoveryArtwork`'s palette, which is
/// what makes a card in one row the same card in another.
library;

import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';

import 'tv_discovery_artwork.dart';

/// One minute, in the milliseconds every runtime and offset below is written
/// in. Spelled out because the interesting fixtures are the ones where a
/// reviewer has to be able to check the arithmetic by eye.
const int kTvDiscoveryMinuteMs = 60 * 1000;

/// The servers the discovery fixtures spread across, in the order a multi
/// source group uses them.
const List<({String id, String name, MediaBackend backend})> kTvDiscoveryServers = [
  (id: 'nas', name: 'NAS', backend: MediaBackend.plex),
  (id: 'attic', name: 'Zolder', backend: MediaBackend.jellyfin),
  (id: 'shed', name: 'Schuur', backend: MediaBackend.pleyaServer),
];

/// A film or show for a discovery row.
///
/// [artwork] drives both images at once, because in discovery they are two
/// views of one title and letting them drift apart by accident would defeat the
/// helper. [wideArtwork] exists for the one case that has a poster and no
/// landscape art: pass `false` and `artPath` stays null, which is what makes
/// the poster-fallback path picturable instead of theoretical.
MediaItem tvDiscoveryItem({
  required String id,
  required String title,
  int? year = 2024,
  String? summary,
  String? genre,
  int? durationMs = 112 * kTvDiscoveryMinuteMs,
  int? viewOffsetMs,
  int? viewCount,
  int? childCount,
  int? leafCount,
  int? viewedLeafCount,
  String serverId = 'nas',
  String serverName = 'NAS',
  MediaBackend backend = MediaBackend.plex,
  MediaKind kind = MediaKind.movie,

  /// Null renders the no-artwork panel on both paths — a real state, and one
  /// the rail has to survive.
  int? artwork,
  bool wideArtwork = true,
}) => MediaItem(
  id: id,
  backend: backend,
  kind: kind,
  title: title,
  year: year,
  summary: summary,
  durationMs: durationMs,
  viewOffsetMs: viewOffsetMs,
  viewCount: viewCount,
  childCount: childCount,
  leafCount: leafCount,
  viewedLeafCount: viewedLeafCount,
  genres: genre == null ? null : [genre],
  serverId: serverId,
  serverName: serverName,
  thumbPath: artwork == null ? null : TvDiscoveryArtwork.pathFor(artwork),
  artPath: artwork == null || !wideArtwork ? null : TvDiscoveryArtwork.widePathFor(artwork),
  // clearLogoPath stays null on purpose. The artwork seam has no logo panel, so
  // filling it would paint a gradient where a wordmark belongs and quietly hide
  // the title-text fallback that most libraries actually get.
);

/// One episode of [showTitle], with everything a Continue Watching card needs
/// to *derive* its context line: which season, which episode, how long it runs
/// and how far in the viewer got.
MediaItem tvDiscoveryEpisode({
  required String id,
  required String showTitle,
  required String episodeTitle,
  required int season,
  required int episode,
  required int durationMs,
  required int viewOffsetMs,
  String? summary,
  int? year = 2024,
  String serverId = 'nas',
  String serverName = 'NAS',
  MediaBackend backend = MediaBackend.plex,
  int? artwork,
  bool wideArtwork = true,
}) => MediaItem(
  id: id,
  backend: backend,
  kind: MediaKind.episode,
  title: episodeTitle,
  year: year,
  summary: summary,
  grandparentTitle: showTitle,
  parentIndex: season,
  index: episode,
  durationMs: durationMs,
  viewOffsetMs: viewOffsetMs,
  serverId: serverId,
  serverName: serverName,
  // An episode's own `thumbPath` *is* its 16:9 still on both backends, and the
  // 2:3 poster a compact tile draws belongs to its show — which is exactly the
  // distinction `discoveryWideArtPath`/`discoveryPosterPath` route on. Modelling
  // the episode's thumb as a poster would make the fixture agree with a tile
  // that had the rule backwards.
  thumbPath: artwork == null ? null : TvDiscoveryArtwork.widePathFor(artwork),
  grandparentThumbPath: artwork == null ? null : TvDiscoveryArtwork.pathFor(artwork),
  artPath: artwork == null || !wideArtwork ? null : TvDiscoveryArtwork.widePathFor(artwork),
);

/// A movie group, built the way the product builds one.
UnifiedMediaGroup tvDiscoveryGroup(String id, List<MediaItem> items, {bool watched = false, bool inProgress = false}) =>
    _group(
      id,
      items,
      CanonicalMediaIdentity.movie(title: items.first.title, year: items.first.year),
      watched: watched,
      inProgress: inProgress,
    );

/// A show group. Same shape, `CanonicalMediaIdentity.show`, because a Series
/// card that is secretly a movie group pictures a code path the Series landing
/// never takes.
UnifiedMediaGroup tvDiscoveryShowGroup(
  String id,
  List<MediaItem> items, {
  bool watched = false,
  bool inProgress = false,
}) => _group(
  id,
  items,
  CanonicalMediaIdentity.show(title: items.first.title, year: items.first.year),
  watched: watched,
  inProgress: inProgress,
);

/// A Continue Watching group whose sources are all the **same** episode of one
/// show, held on one or more servers.
///
/// The identity is the episode's — show title plus season plus episode — and
/// that is hoofdstuk 11.8, not a detail: Verder kijken groups on the exact
/// aflevering, so two servers holding the viewer at S01E08 are one entry with
/// two sources, while S01E08 and S02E03 are two entries. A fixture that put
/// two different episodes in one group would encode a card the identity layer
/// can no longer produce.
UnifiedMediaGroup tvDiscoveryEpisodeGroup(String id, List<MediaItem> episodes, {String? showTitle}) {
  assert(
    episodes.every((e) => e.parentIndex == episodes.first.parentIndex && e.index == episodes.first.index),
    'a Continue Watching group is one exact episode (hoofdstuk 11.8), not a series',
  );
  return _group(
    id,
    episodes,
    CanonicalMediaIdentity.episode(
      showTitle: showTitle ?? episodes.first.grandparentTitle,
      seasonIndex: episodes.first.parentIndex,
      episodeIndex: episodes.first.index,
    ),
    inProgress: true,
  );
}

UnifiedMediaGroup _group(
  String id,
  List<MediaItem> items,
  CanonicalMediaIdentity identity, {
  bool watched = false,
  bool inProgress = false,
}) {
  final sources = [for (final item in items) UnifiedMediaSource.fromItem(item)];
  return UnifiedMediaGroup(
    groupId: id,
    identity: identity,
    sources: sources,
    representativeSourceKey: sources.first.sourceKey,
    watchState: UnifiedWatchState(
      representativeSourceKey: sources.first.sourceKey,
      isWatched: watched,
      hasActiveProgress: inProgress,
      lastViewedAt: inProgress || watched ? 1 : null,
    ),
  );
}

/// A discovery row's worth of films.
///
/// Every entry carries both a poster and a landscape panel except two, and
/// those two are the reason the row is worth rendering: `disc-film-no-wide` has
/// a poster and no `artPath`, so the expanded card has to fall back rather than
/// draw nothing, and `disc-film-no-art` has neither, so the rail has to survive
/// a title its server has no image for at all.
///
/// Watch state is mixed on purpose. A row of identically-untouched cards proves
/// nothing about whether a resume bar, a watched tick and a source badge can
/// coexist in one rail at the sizes hoofdstuk 10.2a asks for.
List<UnifiedMediaGroup> tvDiscoveryFilmsRow() => [
  tvDiscoveryGroup('disc-film-harbour', [
    tvDiscoveryItem(
      id: 'disc-film-harbour-nas',
      title: 'The Long Harbour',
      year: 2023,
      genre: 'Drama',
      summary:
          'A retired ferry captain agrees to make one last winter crossing, and finds the passenger '
          'list holds someone he spent thirty years avoiding.',
      artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.warmOrange),
      durationMs: 118 * kTvDiscoveryMinuteMs,
      viewOffsetMs: 41 * kTvDiscoveryMinuteMs,
    ),
  ], inProgress: true),
  tvDiscoveryGroup('disc-film-signal', [
    for (var s = 0; s < 2; s++)
      tvDiscoveryItem(
        id: 'disc-film-signal-${kTvDiscoveryServers[s].id}',
        title: 'Blue Signal',
        year: 2022,
        genre: 'Science fiction',
        summary:
            'Two radio astronomers on opposite sides of the world hear the same six seconds of noise, '
            'and disagree completely about what it means.',
        artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.brightBlue),
        durationMs: 106 * kTvDiscoveryMinuteMs,
        serverId: kTvDiscoveryServers[s].id,
        serverName: kTvDiscoveryServers[s].name,
        backend: kTvDiscoveryServers[s].backend,
      ),
  ]),
  tvDiscoveryGroup('disc-film-canopy', [
    tvDiscoveryItem(
      id: 'disc-film-canopy-nas',
      title: 'Under the Canopy',
      year: 2021,
      genre: 'Documentary',
      summary:
          'A year spent at the top of a rainforest, filmed entirely from walkways strung between the '
          'tallest trees, where almost nothing ever touches the ground.',
      artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.greenNature),
      durationMs: 94 * kTvDiscoveryMinuteMs,
      viewCount: 1,
    ),
  ], watched: true),
  tvDiscoveryGroup('disc-film-kite', [
    tvDiscoveryItem(
      id: 'disc-film-kite-nas',
      title: 'Paper Kite Parade',
      year: 2024,
      genre: 'Animation',
      summary:
          'Every spring a town builds one enormous kite together, and this year the job falls to the '
          'child least able to keep a secret.',
      artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.familyAnimation),
      durationMs: 88 * kTvDiscoveryMinuteMs,
    ),
  ]),
  tvDiscoveryGroup('disc-film-neighbours', [
    for (var s = 0; s < 2; s++)
      tvDiscoveryItem(
        id: 'disc-film-neighbours-${kTvDiscoveryServers[s].id}',
        title: 'The Neighbours Downstairs',
        year: 2020,
        genre: 'Comedy',
        summary:
            'A noise complaint escalates through eleven increasingly formal letters before either '
            'household considers simply knocking.',
        artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.lightComedy),
        durationMs: 97 * kTvDiscoveryMinuteMs,
        serverId: kTvDiscoveryServers[s].id,
        serverName: kTvDiscoveryServers[s].name,
        backend: kTvDiscoveryServers[s].backend,
      ),
  ]),
  tvDiscoveryGroup('disc-film-arcade', [
    tvDiscoveryItem(
      id: 'disc-film-arcade-nas',
      title: 'Arcade Midnight',
      year: 2019,
      genre: 'Thriller',
      summary:
          'The last arcade in the city closes at three, and the person who locks up has been counting '
          'the same missing token for a decade.',
      artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.neon),
      durationMs: 101 * kTvDiscoveryMinuteMs,
      viewOffsetMs: 12 * kTvDiscoveryMinuteMs,
    ),
  ], inProgress: true),
  tvDiscoveryGroup('disc-film-quarry', [
    tvDiscoveryItem(
      id: 'disc-film-quarry-nas',
      title: 'Quarry Road',
      year: 2018,
      genre: 'Drama',
      summary:
          'Three siblings return to sell a house none of them wants, and spend the weekend discovering '
          'how differently each of them remembers it.',
      artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.darkDrama),
      durationMs: 124 * kTvDiscoveryMinuteMs,
    ),
  ]),
  // Poster, no landscape art. The expanded card has to fall back to the 2:3
  // image rather than render an empty wide frame.
  tvDiscoveryGroup('disc-film-no-wide', [
    tvDiscoveryItem(
      id: 'disc-film-no-wide-nas',
      title: 'Salt and Compass',
      year: 2017,
      genre: 'Adventure',
      summary:
          'A cartographer walks a coastline that her own maps insist is two kilometres shorter than it '
          'turns out to be.',
      artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.desertEpic),
      wideArtwork: false,
      durationMs: 109 * kTvDiscoveryMinuteMs,
    ),
  ]),
  // No artwork at all.
  tvDiscoveryGroup('disc-film-no-art', [
    tvDiscoveryItem(
      id: 'disc-film-no-art-nas',
      title: 'Unlisted Reel',
      year: 2016,
      genre: 'Classic',
      summary: 'A print with no title card, no credits and a projectionist who claims never to have shown it.',
      durationMs: 76 * kTvDiscoveryMinuteMs,
    ),
  ]),
  tvDiscoveryThreeSourceGroup(),
  tvDiscoveryLongTitleGroup(),
  tvDiscoveryLongSynopsisGroup(),
];

/// The Series counterpart, and deliberately *not* the films list retitled.
///
/// The chrome must be identical so the two landings can be compared side by
/// side; what differs is the library. These skew to the brighter end of
/// `TvDiscoveryArtwork`'s set, because a shelf of series is not a shelf of
/// films and the pictures should say so.
///
/// `leafCount` / `viewedLeafCount` are set rather than `viewCount`: a show's
/// watched state is a leaf count in this codebase, so a fixture that reached
/// for `viewCount` would light up a tick the product would not.
List<UnifiedMediaGroup> tvDiscoverySeriesRow() => [
  tvDiscoveryShowGroup('disc-show-kites', [
    tvDiscoveryItem(
      id: 'disc-show-kites-nas',
      title: 'Kite Street',
      year: 2022,
      kind: MediaKind.show,
      genre: 'Family',
      summary:
          'A children\'s workshop on a narrow street takes on one impossible commission per season, and '
          'never quite finishes on time.',
      artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.familyAnimation),
      childCount: 3,
      leafCount: 24,
      viewedLeafCount: 9,
      durationMs: null,
    ),
  ], inProgress: true),
  tvDiscoveryShowGroup('disc-show-bakery', [
    for (var s = 0; s < 2; s++)
      tvDiscoveryItem(
        id: 'disc-show-bakery-${kTvDiscoveryServers[s].id}',
        title: 'The Corner Bakery',
        year: 2021,
        kind: MediaKind.show,
        genre: 'Comedy',
        summary: 'Twelve amateur bakers, one very small kitchen, and a judge who has never once said what he means.',
        artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.lightComedy),
        childCount: 5,
        durationMs: null,
        serverId: kTvDiscoveryServers[s].id,
        serverName: kTvDiscoveryServers[s].name,
        backend: kTvDiscoveryServers[s].backend,
      ),
  ]),
  tvDiscoveryShowGroup('disc-show-tides', [
    tvDiscoveryItem(
      id: 'disc-show-tides-nas',
      title: 'Tides of the North',
      year: 2020,
      kind: MediaKind.show,
      genre: 'Documentary',
      summary: 'Four coastlines, four seasons, and the small communities that plan their year around the water.',
      artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.greenNature),
      // Deliberately singular, because the Series context line is the one thing
      // meant to read differently from a film's and it has to handle "1 seizoen".
      childCount: 1,
      durationMs: null,
    ),
  ]),
  tvDiscoveryShowGroup('disc-show-atlas', [
    tvDiscoveryItem(
      id: 'disc-show-atlas-nas',
      title: 'Atlas Unbound',
      year: 2023,
      kind: MediaKind.show,
      genre: 'Science fiction',
      summary: 'A survey ship maps a system that appears to have been mapped already, by someone using the same forms.',
      artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.brightBlue),
      childCount: 2,
      leafCount: 16,
      viewedLeafCount: 16,
      durationMs: null,
    ),
  ], watched: true),
  tvDiscoveryShowGroup('disc-show-lantern', [
    tvDiscoveryItem(
      id: 'disc-show-lantern-nas',
      title: 'Lantern Hour',
      year: 2019,
      kind: MediaKind.show,
      genre: 'Romance',
      summary: 'Two people keep meeting at the same tram stop, always at dusk, and never on purpose.',
      artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.pastelRomance),
      childCount: 4,
      durationMs: null,
    ),
  ]),
  tvDiscoveryShowGroup('disc-show-glasshouse', [
    for (var s = 0; s < 3; s++)
      tvDiscoveryItem(
        id: 'disc-show-glasshouse-${kTvDiscoveryServers[s].id}',
        title: 'The Glasshouse',
        year: 2018,
        kind: MediaKind.show,
        genre: 'Thriller',
        summary: 'A botanical institute runs one experiment it has never published, and one gardener starts reading.',
        artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.neon),
        childCount: 3,
        durationMs: null,
        serverId: kTvDiscoveryServers[s].id,
        serverName: kTvDiscoveryServers[s].name,
        backend: kTvDiscoveryServers[s].backend,
      ),
  ]),
  tvDiscoveryShowGroup('disc-show-quiet', [
    tvDiscoveryItem(
      id: 'disc-show-quiet-nas',
      title: 'The Quiet Ward',
      year: 2017,
      kind: MediaKind.show,
      genre: 'Drama',
      summary: 'A night shift in a hospital wing scheduled for demolition, told one room at a time.',
      artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.darkDrama),
      childCount: 2,
      durationMs: null,
    ),
  ]),
  tvDiscoveryShowGroup('disc-show-no-art', [
    tvDiscoveryItem(
      id: 'disc-show-no-art-nas',
      title: 'Undocumented Series',
      year: 2016,
      kind: MediaKind.show,
      genre: 'Classic',
      summary: 'A run of episodes the archive holds but has never catalogued.',
      childCount: 1,
      durationMs: null,
    ),
  ]),
];

/// Continue Watching: concrete episodes plus one film, with the numbers a
/// context line is supposed to be *derived* from.
///
/// `disc-cw-harbourlight` is the one every widget should be tested against
/// first: season 2, episode 4, a 48-minute runtime and a 30-minute offset, so a
/// correct card reads "S2 E4 · 18 min resterend" and an incorrect one reads
/// something a reviewer can check by subtraction. Nothing in this row is round
/// by accident.
///
/// `disc-cw-two-servers` is the case a single-source model gets wrong: one
/// episode the viewer is partway through on two different servers, on two
/// different backends, at two different offsets. Both sources are preserved
/// (hoofdstuk 4.2 never drops one) and the group is identified at exact-episode
/// granularity (hoofdstuk 11.8). See [tvDiscoveryEpisodeGroup].
List<UnifiedMediaGroup> tvDiscoveryContinueWatchingRow() => [
  tvDiscoveryEpisodeGroup('disc-cw-harbourlight', [
    tvDiscoveryEpisode(
      id: 'disc-cw-harbourlight-nas',
      showTitle: 'Harbourlight',
      episodeTitle: 'The Fourth Crossing',
      season: 2,
      episode: 4,
      // 48 minutes long, 30 minutes in: 18 minutes remaining, exactly.
      durationMs: 48 * kTvDiscoveryMinuteMs,
      viewOffsetMs: 30 * kTvDiscoveryMinuteMs,
      summary: 'The ferry runs late for the first time in nine years, and nobody on board can agree on why.',
      artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.warmOrange),
    ),
  ]),
  tvDiscoveryEpisodeGroup('disc-cw-glasshouse', [
    tvDiscoveryEpisode(
      id: 'disc-cw-glasshouse-nas',
      showTitle: 'The Glasshouse',
      episodeTitle: 'Specimen Nine',
      season: 1,
      episode: 6,
      // 52 minutes long, 5 minutes in: 47 remaining — a barely-started row, so
      // the progress bar has to stay visible at a very small fill.
      durationMs: 52 * kTvDiscoveryMinuteMs,
      viewOffsetMs: 5 * kTvDiscoveryMinuteMs,
      summary: 'A cutting goes missing from a locked room that only two people can open.',
      artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.neon),
    ),
  ]),
  tvDiscoveryEpisodeGroup('disc-cw-almost-done', [
    tvDiscoveryEpisode(
      id: 'disc-cw-almost-done-nas',
      showTitle: 'Tides of the North',
      episodeTitle: 'Spring Tide',
      season: 3,
      episode: 12,
      // 44 minutes long, 42 in: 2 remaining — the other end of the bar, where a
      // rounded-up label would read "0 min" and look broken.
      durationMs: 44 * kTvDiscoveryMinuteMs,
      viewOffsetMs: 42 * kTvDiscoveryMinuteMs,
      summary: 'The last week of the season, filmed on the one day the water stays still.',
      artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.greenNature),
    ),
  ]),
  // One episode, two servers, two backends — and two different offsets, so a
  // card that averaged its sources' progress away would be visible.
  tvDiscoveryEpisodeGroup('disc-cw-two-servers', [
    tvDiscoveryEpisode(
      id: 'disc-cw-two-servers-nas',
      showTitle: 'Kite Street',
      episodeTitle: 'The Tail End',
      season: 1,
      episode: 8,
      durationMs: 26 * kTvDiscoveryMinuteMs,
      viewOffsetMs: 11 * kTvDiscoveryMinuteMs,
      summary: 'The workshop misses a deadline and decides to make the delay part of the design.',
      artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.familyAnimation),
      serverId: 'nas',
      serverName: 'NAS',
      backend: MediaBackend.plex,
    ),
    tvDiscoveryEpisode(
      id: 'disc-cw-two-servers-attic',
      showTitle: 'Kite Street',
      episodeTitle: 'The Tail End',
      season: 1,
      episode: 8,
      durationMs: 26 * kTvDiscoveryMinuteMs,
      viewOffsetMs: 20 * kTvDiscoveryMinuteMs,
      summary: 'The workshop misses a deadline and decides to make the delay part of the design.',
      artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.familyAnimation),
      serverId: 'attic',
      serverName: 'Zolder',
      backend: MediaBackend.jellyfin,
    ),
  ], showTitle: 'Kite Street'),
  // A film in progress belongs in this row too: Continue Watching is not an
  // episode list, and a rail that only knows how to render an episode context
  // line has a hole in it.
  tvDiscoveryGroup('disc-cw-film', [
    tvDiscoveryItem(
      id: 'disc-cw-film-nas',
      title: 'The Long Harbour',
      year: 2023,
      genre: 'Drama',
      summary:
          'A retired ferry captain agrees to make one last winter crossing, and finds the passenger '
          'list holds someone he spent thirty years avoiding.',
      artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.warmOrange),
      // 118 minutes long, 41 in: 77 remaining, which is where a "1 u 17 m"
      // rendering diverges from a "77 min" one.
      durationMs: 118 * kTvDiscoveryMinuteMs,
      viewOffsetMs: 41 * kTvDiscoveryMinuteMs,
    ),
  ], inProgress: true),
];

/// Exactly three sources, on three different servers and three different
/// backends, so a "3 bronnen" reading is provable rather than plausible.
///
/// Three and not two on purpose: two is the count a boolean can fake.
UnifiedMediaGroup tvDiscoveryThreeSourceGroup() => tvDiscoveryGroup('disc-film-three-sources', [
  for (var s = 0; s < 3; s++)
    tvDiscoveryItem(
      id: 'disc-film-three-sources-${kTvDiscoveryServers[s].id}',
      title: 'Wintering',
      year: 2015,
      genre: 'Drama',
      summary:
          'A mountain research station keeps three people through a season that turns out to be five '
          'weeks longer than anyone budgeted for.',
      artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.coldNoir),
      durationMs: 131 * kTvDiscoveryMinuteMs,
      serverId: kTvDiscoveryServers[s].id,
      serverName: kTvDiscoveryServers[s].name,
      backend: kTvDiscoveryServers[s].backend,
    ),
]);

/// A title long enough to break a naive layout at the tvOS canvas.
///
/// Not padding: it is the shape real archive titles take — a name, a subtitle
/// after a colon, and a parenthetical edition — which is precisely the string
/// that wraps to three lines in a box designed for two and pushes the metadata
/// under the card.
UnifiedMediaGroup tvDiscoveryLongTitleGroup() => tvDiscoveryGroup('disc-film-long-title', [
  tvDiscoveryItem(
    id: 'disc-film-long-title-nas',
    title:
        'The Extraordinarily Long and Somewhat Unnecessary Title of the Restored Director\'s Cut: '
        'Part Two — The Reckoning (Extended Anniversary Edition)',
    year: 2014,
    genre: 'Epic',
    summary: 'The version nobody asked for, restored from the only surviving print, at its full original length.',
    artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.monochromeClassic),
    durationMs: 214 * kTvDiscoveryMinuteMs,
  ),
]);

/// A synopsis long enough that an expanded discovery card has to decide what to
/// do with it — clamp, fade or overflow — rather than getting away with a
/// sentence that happens to fit.
UnifiedMediaGroup tvDiscoveryLongSynopsisGroup() => tvDiscoveryGroup('disc-film-long-synopsis', [
  tvDiscoveryItem(
    id: 'disc-film-long-synopsis-nas',
    title: 'Observatory',
    year: 2013,
    genre: 'Science fiction',
    summary:
        'When the last remaining optical observatory on the ridge is scheduled for decommissioning, its '
        'three permanent staff decide to spend the final winter completing a survey that no funding body '
        'has approved and no journal has agreed to publish. What begins as a quiet act of stubbornness '
        'turns into something closer to an argument about what the work was ever for, conducted over '
        'eleven weeks of bad weather, failing equipment and a telescope that has outlived every person '
        'who ever signed off on it. By the time the road reopens in spring, none of them can agree on '
        'what they found, and all three have written it down differently.',
    artwork: TvDiscoveryArtwork.indexOfMood(TvDiscoveryMood.deepSpace),
    durationMs: 137 * kTvDiscoveryMinuteMs,
  ),
]);
