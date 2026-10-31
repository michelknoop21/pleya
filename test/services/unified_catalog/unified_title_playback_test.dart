/// One title across its sources: which concrete item a play starts, what
/// follows it, and which copies hear about it (DEC-XXX "Eén titel over servers
/// heen"). Runs on plain [MediaItem]s and fake clients, no widget tree.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_coverage_state.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_route_context.dart';
import 'package:pleya/services/unified_catalog/source_episode_index.dart';
import 'package:pleya/services/unified_catalog/unified_title_playback.dart';

class _Client implements MediaServerClient {
  _Client(this.episodes, {this.seasons = const [], this.failing = false, this.hangs = false});

  final List<MediaItem> episodes;
  final List<MediaItem> seasons;
  final bool failing;
  final bool hangs;
  int reads = 0;

  @override
  Future<List<MediaItem>> fetchPlayableDescendants(String parentId) async {
    reads++;
    if (hangs) return Completer<List<MediaItem>>().future;
    if (failing) throw StateError('server down');
    return episodes;
  }

  @override
  Future<List<MediaItem>> fetchChildren(String parentId) async => seasons;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _hour = 60 * 60 * 1000;

MediaItem _show(String server, {String id = 'show', String? library}) => MediaItem(
  id: '$id-$server',
  backend: MediaBackend.plex,
  kind: MediaKind.show,
  title: 'Severance',
  serverId: server,
  serverName: server,
  libraryId: library,
);

MediaItem _movie(String server, {int? viewOffsetMs, int? durationMs, int? lastViewedAt}) => MediaItem(
  id: 'film-$server',
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Sintel',
  serverId: server,
  serverName: server,
  durationMs: durationMs ?? 2 * _hour,
  viewOffsetMs: viewOffsetMs,
  lastViewedAt: lastViewedAt,
);

MediaItem _episode(
  String server,
  int season,
  int episode, {
  int? viewOffsetMs,
  int? lastViewedAt,
  int? viewCount,
  int? durationMs,
}) => MediaItem(
  id: 'ep-$server-$season-$episode',
  backend: MediaBackend.plex,
  kind: MediaKind.episode,
  title: 'S${season}E$episode',
  grandparentId: 'show-$server',
  parentIndex: season,
  index: episode,
  durationMs: durationMs ?? _hour,
  viewOffsetMs: viewOffsetMs,
  lastViewedAt: lastViewedAt,
  viewCount: viewCount,
);

UnifiedMediaRouteContext _route(List<MediaItem> items, {required String chosen, String? page}) {
  final sources = [for (final item in items) UnifiedMediaSource.fromItem(item)];
  final keys = [for (final s in sources) s.sourceKey];
  final chosenKey = keys.firstWhere((k) => k.startsWith('$chosen:'));
  return UnifiedMediaRouteContext(
    groupId: 'g',
    identity: CanonicalMediaIdentity.show(title: 'Severance'),
    sourceKey: chosenKey,
    pageSourceKey: page == null ? chosenKey : keys.firstWhere((k) => k.startsWith('$page:')),
    titleSources: sources,
    availableSourceKeys: keys,
    coverage: SourceCoverageState.none,
    intent: UnifiedActivationIntent.details,
  );
}

UnifiedTitlePlayback _title(
  List<MediaItem> items, {
  required String chosen,
  String? page,
  Map<String, _Client> clients = const {},
  Set<String> offline = const {},
  Set<String> authRejected = const {},
  Set<String> hiddenServers = const {},
  Set<String> hiddenLibraries = const {},
  bool restricted = false,
  MediaItem Function(MediaItem)? fresh,
  Duration secondaryWait = const Duration(seconds: 3),
}) {
  final route = _route(items, chosen: chosen, page: page);
  final chosenFirst = [
    ...route.titleSources.where((s) => s.sourceKey == route.sourceKey),
    ...route.titleSources.where((s) => s.sourceKey != route.sourceKey),
  ];
  return UnifiedTitlePlayback(
    routeContext: route,
    sources: chosenFirst,
    secondaryWait: secondaryWait,
    gate: UnifiedSourceGate(
      clientFor: (id) => clients[id.value],
      isOnline: (id) => !offline.contains(id.value),
      isAuthRejected: (id) => authRejected.contains(id.value),
      isVisible: (id) => !hiddenServers.contains(id.value),
      hiddenLibraryKeys: () => hiddenLibraries,
      isRestrictedProfile: () async => restricted,
      fresh: fresh,
    ),
  );
}

void main() {
  group('which item a play of an episode starts', () {
    test('the episode on the page plays from the chosen server, matched on its numbers', () async {
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([_episode('page', 2, 3)]),
          'chosen': _Client([_episode('chosen', 2, 3), _episode('chosen', 2, 4)]),
        },
      );

      final target = await title.targetFor(_episode('page', 2, 3).copyWith(serverId: 'page'));

      expect(target.item.globalKey, 'chosen:ep-chosen-2-3');
    });

    test('an episode the chosen server lacks plays from a server that has it, without asking', () async {
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([_episode('page', 2, 3)]),
          'chosen': _Client([_episode('chosen', 2, 4)]),
        },
      );

      final target = await title.targetFor(_episode('page', 2, 3).copyWith(serverId: 'page'));

      expect(target.item.serverId, 'page');
    });

    test('the page copy comes before a third server', () async {
      final title = _title(
        [_show('page'), _show('chosen'), _show('third')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([_episode('page', 1, 1)]),
          'chosen': _Client(const []),
          'third': _Client([_episode('third', 1, 1)]),
        },
      );

      final target = await title.targetFor(_episode('page', 1, 1).copyWith(serverId: 'page'));

      expect(target.item.serverId, 'page');
    });

    test('a third server fills in when the page\'s server has gone', () async {
      final title = _title(
        [_show('page'), _show('chosen'), _show('third')],
        chosen: 'chosen',
        page: 'page',
        offline: {'page'},
        clients: {
          'page': _Client([_episode('page', 1, 1)]),
          'chosen': _Client(const []),
          'third': _Client([_episode('third', 1, 1)]),
        },
      );

      final target = await title.targetFor(_episode('page', 1, 1).copyWith(serverId: 'page'));

      expect(target.item.serverId, 'third');
    });

    test('the position of another source carries over when the runtimes match', () async {
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([_episode('page', 1, 1, viewOffsetMs: 600000, lastViewedAt: 2000)]),
          'chosen': _Client([_episode('chosen', 1, 1)]),
        },
      );

      final target = await title.targetFor(_episode('page', 1, 1, viewOffsetMs: 600000).copyWith(serverId: 'page'));

      expect(target.item.serverId, 'chosen');
      expect(target.carriedResume, const Duration(milliseconds: 600000));
    });

    test('a position does not cross to an episode of a very different length', () async {
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([_episode('page', 1, 1, viewOffsetMs: 600000, lastViewedAt: 2000)]),
          'chosen': _Client([_episode('chosen', 1, 1, durationMs: 2 * _hour)]),
        },
      );

      final target = await title.targetFor(_episode('page', 1, 1).copyWith(serverId: 'page'));

      expect(target.carriedResume, isNull);
    });

    test('two rows with one code name nothing, so that server does not count as having it', () async {
      final doubled = [_episode('chosen', 1, 1), _episode('chosen', 1, 1).copyWith(id: 'other-cut')];
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([_episode('page', 1, 1)]),
          'chosen': _Client(doubled),
        },
      );

      final target = await title.targetFor(_episode('page', 1, 1).copyWith(serverId: 'page'));

      expect(target.item.serverId, 'page');
    });

    test('an episode without numbers stays where it is', () async {
      final client = _Client(const []);
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {'chosen': client},
      );
      final unnumbered = MediaItem(
        id: 'loose',
        backend: MediaBackend.plex,
        kind: MediaKind.episode,
        grandparentId: 'show-page',
        serverId: 'page',
      );

      final target = await title.targetFor(unnumbered);

      expect(target.item, same(unnumbered));
      expect(client.reads, 0);
    });

    test('an episode of another series on the same page is left alone', () async {
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {'chosen': _Client(const [])},
      );
      final other = _episode('page', 1, 1).copyWith(serverId: 'page', grandparentId: 'another-show');

      expect(title.holds(other), isFalse);
      expect((await title.targetFor(other)).item, same(other));
    });
  });

  group('rights travel with every read', () {
    test('a server with an auth error is not asked', () async {
      final rejected = _Client([_episode('chosen', 1, 1)]);
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        authRejected: {'chosen'},
        clients: {
          'page': _Client([_episode('page', 1, 1)]),
          'chosen': rejected,
        },
      );

      final target = await title.targetFor(_episode('page', 1, 1).copyWith(serverId: 'page'));

      expect(rejected.reads, 0);
      expect(target.item.serverId, 'page');
    });

    test('a hidden library does not fill a gap', () async {
      final hiddenSource = _Client([_episode('third', 1, 1)]);
      final title = _title(
        [_show('page'), _show('chosen'), _show('third', library: 'kids')],
        chosen: 'chosen',
        page: 'page',
        hiddenLibraries: {'third:kids'},
        clients: {'page': _Client(const []), 'chosen': _Client(const []), 'third': hiddenSource},
      );

      await title.targetFor(_episode('page', 1, 1).copyWith(serverId: 'page'));

      expect(hiddenSource.reads, 0);
    });

    test('a server hidden from the profile does not fill a gap', () async {
      final hiddenSource = _Client([_episode('third', 1, 1)]);
      final title = _title(
        [_show('page'), _show('chosen'), _show('third')],
        chosen: 'chosen',
        page: 'page',
        hiddenServers: {'third'},
        clients: {'page': _Client(const []), 'chosen': _Client(const []), 'third': hiddenSource},
      );

      await title.targetFor(_episode('page', 1, 1).copyWith(serverId: 'page'));

      expect(hiddenSource.reads, 0);
    });

    test('a children\'s profile does not reach a third server for a missing episode', () async {
      final third = _Client([_episode('third', 1, 2)]);
      final title = _title(
        [_show('page'), _show('chosen'), _show('third')],
        chosen: 'chosen',
        page: 'page',
        restricted: true,
        clients: {
          'page': _Client([_episode('page', 1, 1)]),
          'chosen': _Client([_episode('chosen', 1, 1)]),
          'third': third,
        },
      );

      final next = await title.neighbourOf(_episode('chosen', 1, 1).copyWith(serverId: 'chosen'), forward: true);

      expect(third.reads, 0);
      expect(next, isNull);
    });

    test('a children\'s profile does not reach a third server through a group item either', () async {
      final mine = _episode('chosen', 1, 1).copyWith(serverId: 'chosen');
      final title = _title(
        [mine, _episode('third', 1, 1).copyWith(serverId: 'third')],
        chosen: 'chosen',
        page: 'chosen',
        offline: {'chosen'},
        restricted: true,
        clients: {'chosen': _Client(const []), 'third': _Client(const [])},
      );

      final target = await title.targetFor(mine);

      expect(target.item.serverId, 'chosen', reason: 'it fails on its own server, it does not move to the third');
    });

    test('a restriction that cannot be read counts as a restriction', () async {
      final third = _Client(const []);
      final route = _route([_show('page'), _show('chosen'), _show('third')], chosen: 'chosen', page: 'page');
      final title = UnifiedTitlePlayback(
        routeContext: route,
        sources: route.titleSources,
        gate: UnifiedSourceGate(
          clientFor: (id) => id.value == 'third' ? third : _Client(const []),
          isOnline: (_) => true,
          isAuthRejected: (_) => false,
          isVisible: (_) => true,
          hiddenLibraryKeys: () => const {},
          isRestrictedProfile: () async => throw StateError('no profile'),
        ),
      );

      await title.targetFor(_episode('page', 1, 1).copyWith(serverId: 'page'));

      expect(third.reads, 0);
    });
  });

  group('a slow or failing second server', () {
    test('does not hold up a play', () async {
      final title = _title(
        [_show('chosen'), _show('slow')],
        chosen: 'chosen',
        secondaryWait: Duration.zero,
        clients: {
          'chosen': _Client([_episode('chosen', 1, 1)]),
          'slow': _Client(const [], hangs: true),
        },
      );

      final target = await title
          .targetFor(_episode('chosen', 1, 1).copyWith(serverId: 'chosen'))
          .timeout(const Duration(seconds: 1));

      expect(target.item.serverId, 'chosen');
    });

    test('a failed read is asked again next time, a good one is not', () async {
      final failing = _Client(const [], failing: true);
      final good = _Client([_episode('chosen', 1, 1)]);
      final title = _title(
        [_show('chosen'), _show('bad')],
        chosen: 'chosen',
        clients: {'chosen': good, 'bad': failing},
      );
      final episode = _episode('chosen', 1, 1).copyWith(serverId: 'chosen');

      await title.targetFor(episode);
      await pumpEventQueue();
      await title.targetFor(episode);

      expect(failing.reads, 2);
      expect(good.reads, 1);
    });
  });

  group('the next episode', () {
    MediaItem on(String server, int season, int episode) =>
        _episode(server, season, episode).copyWith(serverId: server);

    test('the queue of the chosen server decides while it has the episode', () async {
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([_episode('page', 1, 1), _episode('page', 1, 2)]),
          'chosen': _Client([_episode('chosen', 1, 1), _episode('chosen', 1, 2)]),
        },
      );
      final queued = on('chosen', 1, 2);

      final next = await title.neighbourOf(on('chosen', 1, 1), forward: true, queued: queued);

      expect(next?.globalKey, queued.globalKey);
    });

    test('a gap on the chosen server is filled from another source', () async {
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([_episode('page', 1, 1), _episode('page', 1, 2), _episode('page', 1, 3)]),
          'chosen': _Client([_episode('chosen', 1, 1), _episode('chosen', 1, 3)]),
        },
      );

      final next = await title.neighbourOf(on('chosen', 1, 1), forward: true, queued: on('chosen', 1, 3));

      expect(next?.globalKey, 'page:ep-page-1-2');
    });

    test('after a borrowed episode the play returns to the chosen server', () async {
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([_episode('page', 1, 1), _episode('page', 1, 2), _episode('page', 1, 3)]),
          'chosen': _Client([_episode('chosen', 1, 1), _episode('chosen', 1, 3)]),
        },
      );

      final next = await title.neighbourOf(on('page', 1, 2), forward: true, queued: on('page', 1, 3));

      expect(next?.serverId, 'chosen');
      expect(next?.index, 3);
    });

    test('the end of the chosen server is not the end of the series', () async {
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([_episode('page', 1, 1), _episode('page', 2, 1)]),
          'chosen': _Client([_episode('chosen', 1, 1)]),
        },
      );

      final next = await title.neighbourOf(on('chosen', 1, 1), forward: true);

      expect(next?.globalKey, 'page:ep-page-2-1');
    });

    test('the position of the next episode on another source travels along', () async {
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([_episode('page', 1, 1), _episode('page', 1, 2, viewOffsetMs: 90000, lastViewedAt: 2000)]),
          'chosen': _Client([_episode('chosen', 1, 1), _episode('chosen', 1, 2)]),
        },
      );

      final next = await title.neighbourOf(on('chosen', 1, 1), forward: true, queued: on('chosen', 1, 2));

      expect(next?.serverId, 'chosen');
      expect(next?.viewOffsetMs, 90000);
    });

    test('another server\'s Special is not a gap', () async {
      // Aired between the two: by date alone it would be next.
      MediaItem aired(MediaItem episode, String date) => episode.copyWith(originallyAvailableAt: date);
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([
            aired(_episode('page', 1, 1), '2022-02-01'),
            aired(_episode('page', 0, 1), '2022-02-02'),
            aired(_episode('page', 1, 2), '2022-02-03'),
          ]),
          'chosen': _Client([
            aired(_episode('chosen', 1, 1), '2022-02-01'),
            aired(_episode('chosen', 1, 2), '2022-02-03'),
          ]),
        },
      );
      final queued = on('chosen', 1, 2);

      final next = await title.neighbourOf(on('chosen', 1, 1), forward: true, queued: queued);

      expect(next?.globalKey, queued.globalKey);
    });

    test('a queue that stopped on another server does not answer for a borrowed episode', () async {
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([_episode('page', 1, 4), _episode('page', 1, 5)]),
          'chosen': _Client([_episode('chosen', 1, 4)]),
        },
      );

      final next = await title.neighbourOf(on('page', 1, 5), forward: true, queued: on('chosen', 1, 4));

      expect(next, isNull, reason: 'E5 is the last one anywhere, and the queue stands behind it');
    });

    test('a queue on another server says nothing, also when no list answers', () async {
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {'page': _Client(const [], failing: true), 'chosen': _Client(const [], failing: true)},
      );

      final next = await title.neighbourOf(on('page', 1, 5), forward: true, queued: on('chosen', 1, 7));

      expect(next, isNull);
    });

    test('a queue pointing the wrong way is not followed', () async {
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([_episode('page', 1, 1), _episode('page', 1, 2), _episode('page', 1, 3)]),
          'chosen': _Client([_episode('chosen', 1, 1), _episode('chosen', 1, 2), _episode('chosen', 1, 3)]),
        },
      );

      final previous = await title.neighbourOf(on('chosen', 1, 2), forward: false, queued: on('chosen', 1, 3));

      expect(previous?.index, 1);
    });

    test('the previous episode comes from the merged order too', () async {
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([_episode('page', 1, 1), _episode('page', 1, 2)]),
          'chosen': _Client([_episode('chosen', 1, 2)]),
        },
      );

      final previous = await title.neighbourOf(on('chosen', 1, 2), forward: false);

      expect(previous?.globalKey, 'page:ep-page-1-1');
    });
  });

  group('where a series continues', () {
    test('a source further along moves the page on', () async {
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([_episode('page', 1, 1), _episode('page', 1, 2), _episode('page', 1, 3)]),
          'chosen': _Client([
            _episode('chosen', 1, 1, viewCount: 1),
            _episode('chosen', 1, 2, viewOffsetMs: 600000, lastViewedAt: 2000),
          ]),
        },
      );

      final onDeck = await title.onDeckAcross(_episode('page', 1, 1).copyWith(serverId: 'page'));

      expect(onDeck?.globalKey, 'page:ep-page-1-2');
    });

    test('the next episode after the last one watched anywhere', () async {
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([_episode('page', 1, 1), _episode('page', 1, 2), _episode('page', 1, 3)]),
          'chosen': _Client([_episode('chosen', 1, 1, viewCount: 1), _episode('chosen', 1, 2, viewCount: 1)]),
        },
      );

      final onDeck = await title.onDeckAcross(null);

      expect(onDeck?.globalKey, 'page:ep-page-1-3');
    });

    test('an episode in progress on the page\'s own source stays: the viewer may be rewatching', () async {
      final watched = [for (var e = 2; e <= 10; e++) _episode('page', 1, e, viewCount: 1, lastViewedAt: 1000)];
      final rewatch = _episode('page', 1, 1, viewOffsetMs: 600000, lastViewedAt: 5000, viewCount: 1);
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([rewatch, ...watched, _episode('page', 1, 11)]),
          'chosen': _Client([_episode('chosen', 1, 1)]),
        },
      );
      final own = rewatch.copyWith(serverId: 'page');

      expect(await title.onDeckAcross(own), same(own));
    });

    test('another source that is provably newer moves past an episode in progress', () async {
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([
            _episode('page', 1, 1, viewOffsetMs: 600000, lastViewedAt: 1000),
            _episode('page', 1, 2),
            _episode('page', 1, 3),
          ]),
          'chosen': _Client([_episode('chosen', 1, 2, viewCount: 1, lastViewedAt: 1000 + 3600)]),
        },
      );
      final own = _episode('page', 1, 1, viewOffsetMs: 600000, lastViewedAt: 1000).copyWith(serverId: 'page');

      final onDeck = await title.onDeckAcross(own);

      expect(onDeck?.globalKey, 'page:ep-page-1-3');
    });

    test('a position inside the clock margin proves nothing', () async {
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([
            _episode('page', 1, 1, viewOffsetMs: 600000, lastViewedAt: 1000),
            _episode('page', 1, 2),
            _episode('page', 1, 3),
          ]),
          'chosen': _Client([_episode('chosen', 1, 2, viewCount: 1, lastViewedAt: 1010)]),
        },
      );
      final own = _episode('page', 1, 1, viewOffsetMs: 600000, lastViewedAt: 1000).copyWith(serverId: 'page');

      expect(await title.onDeckAcross(own), same(own));
    });

    test('the page\'s own answer stands when it is further', () async {
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([_episode('page', 1, 1), _episode('page', 1, 4)]),
          'chosen': _Client([_episode('chosen', 1, 1, viewCount: 1)]),
        },
      );
      final own = _episode('page', 1, 4).copyWith(serverId: 'page');

      expect(await title.onDeckAcross(own), same(own));
    });

    test('nothing started anywhere leaves the page alone', () async {
      final title = _title(
        [_show('page'), _show('chosen')],
        chosen: 'chosen',
        page: 'page',
        clients: {
          'page': _Client([_episode('page', 1, 1)]),
          'chosen': _Client([_episode('chosen', 1, 1)]),
        },
      );

      expect(await title.onDeckAcross(null), isNull);
    });
  });

  group('the copies a write goes to', () {
    test('a film reaches every other source', () async {
      final title = _title([_movie('a'), _movie('b'), _movie('c')], chosen: 'a');

      final copies = await title.copiesOf(_movie('a'));

      expect(copies.map((c) => c.serverId), ['b', 'c']);
    });

    test('an episode reaches its copy on every other source, the list of a server now offline included', () async {
      final clients = {
        'chosen': _Client([_episode('chosen', 1, 1)]),
        'other': _Client([_episode('other', 1, 1)]),
      };
      final offline = <String>{};
      final title = _title([_show('chosen'), _show('other')], chosen: 'chosen', clients: clients, offline: offline);
      await title.prime();
      offline.add('other');

      final copies = await title.copiesOf(_episode('chosen', 1, 1).copyWith(serverId: 'chosen'));

      expect(copies.map((c) => c.globalKey), ['other:ep-other-1-1']);
    });

    test('a rejected token and a hidden library get no write', () async {
      final title = _title(
        [_movie('a'), _movie('b').copyWith(libraryId: 'kids'), _movie('c')],
        chosen: 'a',
        authRejected: {'c'},
        hiddenLibraries: {'b:kids'},
      );

      expect(await title.copiesOf(_movie('a')), isEmpty);
    });

    test('a season is found by its number', () async {
      final season = MediaItem(id: 'season-1', backend: MediaBackend.plex, kind: MediaKind.season, index: 1);
      final title = _title(
        [_show('chosen'), _show('other')],
        chosen: 'chosen',
        clients: {
          'chosen': _Client(const []),
          'other': _Client(const [], seasons: [season]),
        },
      );
      final mine = season.copyWith(id: 'mine', serverId: 'chosen', parentId: 'show-chosen');

      final copies = await title.copiesOf(mine);

      expect(copies.single.globalKey, 'other:season-1');
    });
  });

  group('a film', () {
    test('the chosen source plays, with the live position of the session', () {
      final title = _title(
        [_movie('page', viewOffsetMs: 40 * 60000, lastViewedAt: 1000), _movie('chosen')],
        chosen: 'chosen',
        page: 'page',
        fresh: (item) => item.serverId == 'page' ? item.copyWith(viewOffsetMs: 50 * 60000) : item,
      );

      final target = title.movieTarget(_movie('page', viewOffsetMs: 40 * 60000, lastViewedAt: 1000));

      expect(target.item.serverId, 'chosen');
      expect(target.carriedResume, const Duration(minutes: 50));
    });

    test('a different film on the page is left alone', () {
      final title = _title([_movie('page'), _movie('chosen')], chosen: 'chosen', page: 'page');
      final other = _movie('page').copyWith(id: 'other');

      expect(title.movieTarget(other).item, same(other));
    });
  });

  test('a list holds each number once and answers for nothing else', () {
    final list = SourceEpisodes([_episode('a', 1, 1), _episode('a', 1, 2)]);

    expect(list.at((season: 1, episode: 2))?.index, 2);
    expect(list.at((season: 3, episode: 1)), isNull);
  });
}
