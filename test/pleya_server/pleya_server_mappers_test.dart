import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_stream.dart';
import 'package:pleya/models/pleya_server/pleya_wire_library.dart';
import 'package:pleya/services/pleya_server_mappers.dart';

/// The mapper is the backend boundary: above it nothing knows Pleya Protocol,
/// below it nothing knows the app's model. These tests read the same fixtures
/// the contract test reads, so a wire change that survives parsing still has to
/// survive translation.
void main() {
  final examples = Directory('docs/pleya-protocol/v1/examples');
  Map<String, dynamic> load(String file) =>
      jsonDecode(File('${examples.path}/$file').readAsStringSync()) as Map<String, dynamic>;

  const serverId = '0198f2a1-7c3e-7b21-9f44-1c2d3e4f5a6b';

  MediaItem mapFixture(String file, {PleyaItem? parent, PleyaItem? grandparent, String? libraryId}) =>
      PleyaServerMappers.mediaItem(
        PleyaItem.fromJson(load(file)),
        serverId: serverId,
        serverName: 'Zolder',
        libraryId: libraryId,
        parent: parent,
        grandparent: grandparent,
      );

  group('libraries', () {
    test('map to the neutral library with their own backend', () {
      final libraries = PleyaLibrary.listFromJson(load('libraries.json'));
      final mapped = [
        for (final l in libraries) PleyaServerMappers.library(l, serverId: serverId, serverName: 'Zolder'),
      ];
      expect(mapped, hasLength(3));
      expect(mapped.every((l) => l.backend == MediaBackend.pleyaServer), isTrue);
      expect(mapped[0].title, 'Films');
      expect(mapped[0].kind, MediaKind.movie);
      expect(mapped[1].kind, MediaKind.show);
      expect(mapped[0].serverId, serverId);
    });

    test('a library of a kind this build does not know maps to unknown, not to a throw', () {
      final library = PleyaLibrary.fromJson(const {
        'id': 'lib-9',
        'title': 'Concerten',
        'kind': 'concerts',
        'item_count': 3,
      });
      expect(PleyaServerMappers.library(library, serverId: serverId).kind, MediaKind.unknown);
    });
  });

  group('a movie', () {
    test('keeps title, year, duration and watch position', () {
      final item = mapFixture('item_movie.json', libraryId: 'lib-1');
      expect(item, isA<PleyaServerMediaItem>());
      expect(item.backend, MediaBackend.pleyaServer);
      expect(item.kind, MediaKind.movie);
      expect(item.title, 'Grease');
      expect(item.year, 1978);
      expect(item.durationMs, 6720000);
      expect(item.viewOffsetMs, 1830000);
      expect(item.viewCount, 0);
      expect(item.libraryId, 'lib-1');
      expect(item.serverId, serverId);
    });

    test('added_at becomes app-standard seconds, not milliseconds', () {
      final item = mapFixture('item_movie.json');
      expect(item.addedAt, DateTime.utc(2026, 6, 18, 21, 34, 2).millisecondsSinceEpoch ~/ 1000);
    });

    test('artwork becomes a path the client can turn back into an id', () {
      final item = mapFixture('item_movie.json');
      expect(item.thumbPath, isNotNull);
      expect(PleyaServerMappers.artworkIdFromPath(item.thumbPath), '0198f2c0-0001-7000-8000-000000000001');
      expect(item.artPath, isNull);
    });

    test('the version carries resolution derived from the video stream', () {
      final version = mapFixture('item_movie.json').mediaVersions!.single;
      expect(version.width, 1920);
      expect(version.height, 1080);
      expect(version.videoResolution, '1080');
      expect(version.videoCodec, 'h264');
      expect(version.container, 'mkv');
    });

    test('streams arrive as video, audio, subtitle with labels filled in', () {
      final streams = mapFixture('item_movie.json').mediaVersions!.single.parts.single.streams;
      expect(streams.map((s) => s.kind), [
        MediaStreamKind.video,
        MediaStreamKind.audio,
        MediaStreamKind.subtitle,
        MediaStreamKind.subtitle,
      ]);
      final audio = streams.firstWhere((s) => s.kind == MediaStreamKind.audio);
      expect(audio.channels, 6);
      expect(audio.selected, isTrue);
      expect(audio.displayTitle, isNotEmpty);
    });

    test('only the external subtitle counts as external', () {
      final subtitles = mapFixture(
        'item_movie.json',
      ).mediaVersions!.single.parts.single.streams.where((s) => s.kind == MediaStreamKind.subtitle).toList();
      expect(subtitles.where((s) => s.isExternal), hasLength(1));
      final external = subtitles.firstWhere((s) => s.isExternal);
      expect(PleyaServerMappers.subtitleIdFromPath(external.sidecarPath), '0198f2b2-0001-7000-8000-000000000001');
      expect(subtitles.firstWhere((s) => !s.isExternal).sidecarPath, isNull);
    });

    test('HDR and Dolby Vision are not guessed from bit depth', () {
      final video = mapFixture(
        'item_movie.json',
      ).mediaVersions!.single.parts.single.streams.firstWhere((s) => s.kind == MediaStreamKind.video);
      expect(video.hdr, isFalse);
      expect(video.dolbyVision, isFalse);
      expect(video.dolbyVisionProfile, isNull);
    });
  });

  group('editions', () {
    test('three cuts become three versions the picker can tell apart', () {
      final versions = mapFixture('item_movie_with_edition.json').mediaVersions!;
      expect(versions.map((v) => v.name), ["Theatrical Cut", "Final Cut", "Director's Cut"]);
      expect(versions.map((v) => v.displayLabel).toSet(), hasLength(3));
    });

    test('a version spanning two files still maps to one part', () {
      final versions = mapFixture('item_movie_with_edition.json').mediaVersions!;
      final multifile = versions.last;
      expect(multifile.parts, hasLength(1));
      expect(multifile.parts.single.id, multifile.id);
    });
  });

  group('shows and episodes', () {
    test('a show keeps its episode counts on the neutral leaf fields', () {
      final show = mapFixture('item_show.json');
      expect(show.kind, MediaKind.show);
      expect(show.childCount, 9);
      expect(show.leafCount, 208);
      expect(show.viewedLeafCount, 41);
      expect(show.mediaVersions, isEmpty);
    });

    test('an episode with its ancestors gets show and season columns', () {
      final season = PleyaItem.fromJson(const {
        'id': '0198f2b0-1111-7000-8000-000000000004',
        'kind': 'season',
        'title': 'Season 2',
        'added_at': '2026-01-04T08:00:00Z',
        'index': 2,
        'parent_id': '0198f2b0-1111-7000-8000-000000000002',
      });
      final show = PleyaItem.fromJson(load('item_show.json'));
      final episode = mapFixture('item_episode.json', parent: season, grandparent: show);
      expect(episode.kind, MediaKind.episode);
      expect(episode.index, 9);
      expect(episode.parentId, season.id);
      expect(episode.parentTitle, 'Season 2');
      expect(episode.parentIndex, 2);
      expect(episode.grandparentId, show.id);
      expect(episode.grandparentTitle, 'How I Met Your Mother');
    });

    test('an episode without ancestors keeps ids and leaves titles empty', () {
      final episode = mapFixture('item_episode.json');
      expect(episode.parentId, '0198f2b0-1111-7000-8000-000000000004');
      expect(episode.parentTitle, isNull);
      expect(episode.grandparentTitle, isNull);
    });

    test('a watched episode maps play count and the watched flag', () {
      final episode = mapFixture('item_episode.json');
      expect(episode.viewCount, 2);
      expect(episode.isWatched, isTrue);
    });
  });

  group('a page of items', () {
    test('items of an unknown kind never reach the app model', () {
      final json = load('library_items_page.json');
      final raw = (json['items'] as List).cast<Map<String, dynamic>>();
      final page = PleyaItemPage.fromJson({
        ...json,
        'items': [
          ...raw,
          {...raw.first, 'id': 'unknown-1', 'kind': 'concert'},
        ],
      });
      final mapped = PleyaServerMappers.items(page.items, serverId: serverId);
      expect(mapped, hasLength(raw.length));
      expect(mapped.every((item) => item.kind != MediaKind.unknown), isTrue);
    });

    test('ancestors passed in are applied per item, not to the first one only', () {
      final show = PleyaItem.fromJson(load('item_show.json'));
      final season = PleyaItem.fromJson(const {
        'id': '0198f2b0-1111-7000-8000-000000000004',
        'kind': 'season',
        'title': 'Season 2',
        'added_at': '2026-01-04T08:00:00Z',
        'index': 2,
        'parent_id': '0198f2b0-1111-7000-8000-000000000002',
      });
      final episodes = PleyaItemPage.fromJson(load('children_episodes.json')).items;
      final mapped = PleyaServerMappers.items(
        episodes,
        serverId: serverId,
        parents: {season.id: season, show.id: show},
      );
      expect(mapped, isNotEmpty);
      for (final episode in mapped.where((e) => e.kind == MediaKind.episode && e.parentId == season.id)) {
        expect(episode.grandparentTitle, 'How I Met Your Mother');
      }
    });
  });

  group('the artwork and subtitle path prefixes', () {
    test('do not claim a path they did not build', () {
      expect(PleyaServerMappers.artworkIdFromPath('/library/metadata/12345/thumb'), isNull);
      expect(PleyaServerMappers.artworkIdFromPath(null), isNull);
      expect(PleyaServerMappers.artworkIdFromPath('pleya-artwork:'), isNull);
      expect(PleyaServerMappers.subtitleIdFromPath('/Videos/abc/Subtitles/1/Stream.srt'), isNull);
    });

    test('round-trip an id', () {
      expect(PleyaServerMappers.artworkIdFromPath(PleyaServerMappers.artworkPath('art-1')), 'art-1');
      expect(PleyaServerMappers.subtitleIdFromPath(PleyaServerMappers.subtitlePath('sub-1')), 'sub-1');
    });
  });
}
