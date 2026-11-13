/// The surfaces that draw plain items (Home rows, hero and search on iPad and
/// desktop) show a title that is on two servers once, through the same
/// grouping the unified surfaces use.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/carried_external_ids.dart';
import 'package:pleya/services/unified_catalog/one_card_per_title.dart';

MediaItem _plex(String id, String title, {int? year, int? tmdb, String? summary, MediaKind kind = MediaKind.movie}) =>
    MediaItem.plex(
      id: id,
      kind: kind,
      title: title,
      year: year,
      summary: summary,
      guid: 'plex://${kind.name}/$id',
      serverId: 'srv-plex',
      serverName: 'Plex',
      raw: {
        'Guid': [
          if (tmdb != null) {'id': 'tmdb://$tmdb'},
        ],
      },
    );

MediaItem _jellyfin(String id, String title, {int? year, int? tmdb, MediaKind kind = MediaKind.movie}) =>
    MediaItem.jellyfin(
      id: id,
      kind: kind,
      title: title,
      year: year,
      serverId: 'srv-jf',
      serverName: 'Jellyfin',
      raw: {
        'ProviderIds': {if (tmdb != null) 'Tmdb': '$tmdb'},
      },
    );

MediaItem _pleya(String id, String title, {int? tmdb, bool applied = true}) => MediaItem(
  id: id,
  backend: MediaBackend.pleyaServer,
  kind: MediaKind.movie,
  title: title,
  serverId: 'srv-pleya',
  serverName: 'Pleya',
  raw: {
    pleyaExternalIdsRawKey: {'tmdb': ?tmdb},
    if (applied) pleyaExternalIdsSourceKey: 'applied',
  },
);

void main() {
  test('the same number under another title and year is one card, at the first copy', () {
    final other = _plex('p2', 'Arrival', year: 2016, tmdb: 329865);
    final items = [
      _jellyfin('j1', 'Léon: The Professional', year: 1995, tmdb: 101),
      other,
      _plex('p1', 'Léon', year: 1994, tmdb: 101, summary: 'A hitman.'),
    ];

    final result = oneCardPerProvenTitle(items);

    expect(result.map((i) => i.id), [
      'p1',
      'p2',
    ], reason: 'the fuller copy represents the title, where the first stood');
  });

  test('Plex, Jellyfin and Pleya Server copies of one film fold to one', () {
    final result = oneCardPerProvenTitle([
      _plex('p1', 'Dune', year: 2021, tmdb: 438631),
      _jellyfin('j1', 'Dune: Part One', year: 2021, tmdb: 438631),
      _pleya('s1', 'Dune (2021)', tmdb: 438631),
    ]);

    expect(result, hasLength(1));
  });

  test('a remake with its own number stays its own card', () {
    final items = [_plex('p1', 'Dune', year: 2021, tmdb: 438631), _jellyfin('j1', 'Dune', year: 1984, tmdb: 841)];

    expect(oneCardPerProvenTitle(items), same(items));
  });

  test('a film and a series sharing a number are different namespaces', () {
    final items = [
      _plex('p1', 'Fargo', year: 1996, tmdb: 275),
      _jellyfin('j1', 'Fargo', year: 2014, tmdb: 275, kind: MediaKind.show),
    ];

    expect(oneCardPerProvenTitle(items), same(items));
  });

  test('a Pleya Server number the server did not apply is no proof', () {
    final items = [_plex('p1', 'Dune', year: 2021, tmdb: 438631), _pleya('s1', 'Dune', tmdb: 438631, applied: false)];

    expect(oneCardPerProvenTitle(items), same(items));
  });

  test('a Pleya Server copy never folds on title and year alone', () {
    final items = [_plex('p1', 'Dune', year: 2021), _pleya('s1', 'Dune')];

    expect(oneCardPerProvenTitle(items), same(items));
  });

  test('a local folder copy is never folded', () {
    final local = MediaItem(
      id: 'l1',
      backend: MediaBackend.local,
      kind: MediaKind.movie,
      title: 'Dune',
      year: 2021,
      serverId: 'srv-local',
    );
    final items = [_plex('p1', 'Dune', year: 2021, tmdb: 438631), local];

    expect(oneCardPerProvenTitle(items), same(items));
  });

  test('episodes and items without a server pass through in place', () {
    MediaItem episode(String id, String server) => MediaItem(
      id: id,
      backend: MediaBackend.plex,
      kind: MediaKind.episode,
      title: 'Pilot',
      grandparentTitle: 'Harbourlight',
      parentIndex: 1,
      index: 1,
      serverId: server,
    );
    final orphan = MediaItem(id: 'o', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Dune', year: 2021);
    final items = [
      episode('e1', 'srv-plex'),
      _plex('p1', 'Dune', year: 2021, tmdb: 438631),
      orphan,
      episode('e2', 'srv-jf'),
      _jellyfin('j1', 'Dune', year: 2021, tmdb: 438631),
    ];

    final ids = oneCardPerProvenTitle(items).map((i) => i.id).toList();
    expect(ids, hasLength(4));
    expect([ids[0], ids[2], ids[3]], ['e1', 'o', 'e2']);
    expect(ids[1], isIn(['p1', 'j1']), reason: 'one copy, where the first one stood');
  });

  test('a hub is folded once per instance and left alone when nothing merges', () {
    final plain = MediaHub(id: 'h1', title: 'Row', type: 'movie', items: [_plex('p1', 'Dune', tmdb: 438631)]);
    final mixed = MediaHub(
      id: 'h2',
      title: 'Row',
      type: 'movie',
      items: [_plex('p1', 'Dune', tmdb: 438631), _jellyfin('j1', 'Dune', tmdb: 438631)],
    );

    expect(hubWithOneCardPerProvenTitle(plain), same(plain));
    final folded = hubWithOneCardPerProvenTitle(mixed);
    expect(folded.items, hasLength(1));
    expect(folded.id, 'h2');
    expect(hubWithOneCardPerProvenTitle(mixed), same(folded));
  });
}
