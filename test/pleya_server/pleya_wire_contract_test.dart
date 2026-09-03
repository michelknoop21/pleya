import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/models/pleya_server/pleya_wire.dart';
import 'package:pleya/models/pleya_server/pleya_wire_library.dart';

/// The Dart wire types are a hand transcription of
/// `docs/pleya-protocol/v1/openapi.yaml`, so the only thing that keeps them
/// honest is reading the same fixtures the contract validator reads.
///
/// `scripts/check_protocol.sh` proves the fixtures match the schema and
/// `pleya_server/scripts/verify-protocol.sh` proves a running server matches
/// it too. This test closes the third side: the client parses what both of
/// those bless. All three read `examples/manifest.json`, so a fixture added on
/// one side cannot go unchecked on another.
void main() {
  final examples = Directory('docs/pleya-protocol/v1/examples');

  Map<String, dynamic> load(String file) =>
      jsonDecode(File('${examples.path}/$file').readAsStringSync()) as Map<String, dynamic>;

  final manifest = load('manifest.json');
  final fixtures = (manifest['fixtures'] as List).cast<Map<String, dynamic>>();

  /// Schemas no Dart type reads in this phase. Listing them rather than
  /// skipping them silently means the phase that adds one has to remove a line,
  /// not discover a hole.
  ///
  /// It was empty after PS-4 and is not empty after PS-9. The eight schemas
  /// below all belong to the management surface: creating a household member,
  /// setting their library permissions, and looking at or ending the sessions
  /// of a device. PS-9 deliberately ships that as an API plus a documented
  /// `curl` recipe and no screen at all (DEC-067); the screen is PS-11A, and
  /// building a Dart type for a response nothing renders would be exactly the
  /// kind of pulled-forward work the phase rules forbid.
  ///
  /// The app's own side of PS-9 is not deferred and is tested elsewhere:
  /// `capabilities.sessions` in `pleya_wire_contract_test` below, and the
  /// device fields on login in `pleya_server_sessions_test.dart`.
  const deferredSchemas = <String>{
    'User',
    'UserList',
    'CreateUserRequest',
    'UpdateUserRequest',
    'PermissionsRequest',
    'LibraryPermissionList',
    'Session',
    'SessionList',
  };

  final parsers = <String, void Function(Map<String, dynamic>)>{
    'Info': (json) {
      final info = PleyaInfo.fromJson(json);
      expect(info.major, 1);
      expect(info.serverId, isNotEmpty);
    },
    'ServerDetail': (json) => PleyaServerDetail.fromJson(json),
    'TokenPair': (json) => PleyaTokenPair.fromJson(json),
    'StreamToken': (json) => PleyaStreamToken.fromJson(json),
    'ErrorEnvelope': (json) => PleyaError.fromJson(json),
    'LibraryList': (json) => PleyaLibrary.listFromJson(json),
    'Item': (json) => PleyaItem.fromJson(json),
    'ItemPage': (json) => PleyaItemPage.fromJson(json),
    'UserState': (json) => PleyaUserState.fromJson(json),
    'WatchStatePage': (json) => PleyaWatchStateEntry.pageFromJson(json),
    'StreamSession': (json) => PleyaStreamSession.fromJson(json),
    'WatchStateEvent': (json) {
      // Round-trip: parse the fixture and write it back. That proves the type
      // reads the contract's shape and produces it, which is what matters for a
      // request body the server validates with a closed schema.
      final event = PleyaWatchStateEvent.fromJson(json);
      final written = event.toJson(ownership: true);
      expect(written['item_id'], json['item_id']);
      expect(written['session_id'], json['session_id']);
      expect(written['position_ms'], json['position_ms']);
      expect(written['explicit_action'], json['explicit_action']);
      if (json.containsKey('cause')) expect(written['cause'], json['cause']);
      if (json.containsKey('base_revision')) expect(written['base_revision'], json['base_revision']);
      if (json['backlog'] == true) expect(written['backlog'], isTrue);
    },
  };

  group('every fixture in the manifest', () {
    test('is either parsed by a wire type or explicitly deferred', () {
      final schemas = {for (final fixture in fixtures) fixture['schema'] as String};
      final unhandled = schemas.difference(parsers.keys.toSet()).difference(deferredSchemas);
      expect(
        unhandled,
        isEmpty,
        reason: 'a schema appeared in the manifest that no Dart type reads and no phase deferred',
      );
    });

    test('covers the 46 fixtures the contract ships', () {
      expect(fixtures, hasLength(46));
    });

    for (final fixture in fixtures) {
      final file = fixture['file'] as String;
      final schema = fixture['schema'] as String;
      if (deferredSchemas.contains(schema)) continue;
      test('$file parses as $schema', () {
        parsers[schema]!(load(file));
      });
    }
  });

  group('Info', () {
    test('capabilities read exactly what the server sent', () {
      final info = PleyaInfo.fromJson(load('info.json'));
      expect(info.capabilities.browse, isTrue);
      expect(info.capabilities.search, isTrue);
      expect(info.capabilities.artwork, isTrue);
      expect(info.capabilities.watchState, isTrue);
      expect(info.capabilities.playbackPlan, isFalse);
      expect(info.capabilities.transcode, isFalse);
      expect(info.capabilities.users, isFalse);
    });

    test('a PS-9 server advertises users and sessions', () {
      final info = PleyaInfo.fromJson(load('info_ps9.json'));
      expect(info.capabilities.users, isTrue);
      expect(info.capabilities.sessions, isTrue);
      // And the phases that come later are still off, so the flag genuinely
      // negotiates rather than being read as "new server, everything on".
      expect(info.capabilities.playbackPlan, isFalse);
      expect(info.capabilities.transcode, isFalse);
      expect(info.capabilities.downloads, isFalse);
    });

    test('a PS-4 server says no to sessions, so the device fields stay off the wire', () {
      final info = PleyaInfo.fromJson(load('info_ps4.json'));
      expect(info.capabilities.sessions, isFalse);
    });

    test('the pre-connection default claims nothing at all', () {
      const unknown = PleyaCapabilities.unknown;
      expect(unknown.browse, isFalse);
      expect(unknown.search, isFalse);
      expect(unknown.artwork, isFalse);
      expect(unknown.watchState, isFalse);
    });

    test('an absent optional capability reads as false, not as missing', () {
      final capabilities = PleyaCapabilities.fromJson(const {
        'browse': true,
        'search': true,
        'artwork': true,
        'watch_state': false,
      });
      expect(capabilities.transcode, isFalse);
      expect(capabilities.downloads, isFalse);
      expect(capabilities.realtime, isFalse);
    });

    test('setup_required survives, because it decides which flow runs first', () {
      expect(PleyaInfo.fromJson(load('info_setup_required.json')).auth.setupRequired, isTrue);
      expect(PleyaInfo.fromJson(load('info.json')).auth.setupRequired, isFalse);
    });

    test('an unknown auth method is kept rather than dropped or fatal', () {
      final auth = PleyaAuthInfo.fromJson(const {
        'methods': ['password', 'webauthn'],
        'setup_required': false,
      });
      expect(auth.methods, ['password', 'webauthn']);
      expect(auth.supportsPassword, isTrue);
    });
  });

  group('unknown-safe enums', () {
    test('an unknown item kind parses to null instead of throwing', () {
      final json = load('item_movie.json')..['kind'] = 'concert';
      expect(PleyaItem.fromJson(json).kind, isNull);
    });

    test('a page drops items of an unknown kind and keeps the rest', () {
      final json = load('library_items_page.json');
      final items = (json['items'] as List).cast<Map<String, dynamic>>();
      final extended = Map<String, dynamic>.from(json)
        ..['items'] = [
          ...items,
          {...items.first, 'id': 'unknown-kind-1', 'kind': 'concert'},
        ];
      final page = PleyaItemPage.fromJson(extended);
      expect(page.items, hasLength(items.length + 1));
      expect(page.knownItems, hasLength(items.length));
    });

    test('an unknown library kind parses to null instead of throwing', () {
      expect(PleyaLibraryKind.tryParse('music'), isNull);
      expect(PleyaLibraryKind.tryParse('movies'), PleyaLibraryKind.movies);
    });

    test('an unknown subtitle format parses to null instead of throwing', () {
      expect(PleyaSubtitleFormat.tryParse('teletext'), isNull);
      expect(PleyaSubtitleFormat.tryParse('srt'), PleyaSubtitleFormat.srt);
    });
  });

  group('closed enums', () {
    test('sort keys spell descending with a leading minus and nothing else', () {
      expect(PleyaSortKey.title.query(descending: false), 'title');
      expect(PleyaSortKey.title.query(descending: true), '-title');
      expect(PleyaSortKey.addedAt.query(descending: true), '-added_at');
      expect(PleyaSortKey.year.query(descending: false), 'year');
    });

    test('hub ids are the three the contract defines', () {
      expect(PleyaHubId.values.map((hub) => hub.wire), ['recently_added', 'continue_watching', 'next_up']);
    });
  });

  group('pagination', () {
    test('a cursor page reports more, a last page does not', () {
      expect(PleyaItemPage.fromJson(load('library_items_page.json')).hasMore, isTrue);
      expect(PleyaItemPage.fromJson(load('library_items_last_page.json')).hasMore, isFalse);
    });

    test('an empty hub is an empty page and not an error', () {
      final page = PleyaItemPage.fromJson(load('hub_continue_watching_empty.json'));
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.totalEstimate, 0);
    });

    test('no hits is an empty list, per the contract', () {
      expect(PleyaItemPage.fromJson(load('search_empty.json')).items, isEmpty);
    });
  });

  group('items', () {
    test('a movie carries its versions, streams and watch position', () {
      final item = PleyaItem.fromJson(load('item_movie.json'));
      expect(item.kind, PleyaItemKind.movie);
      expect(item.versions, hasLength(1));
      expect(item.versions.single.videoStreams, hasLength(1));
      expect(item.versions.single.audioStreams.single.channels, 6);
      expect(item.versions.single.subtitleStreams, hasLength(2));
      expect(item.userState?.positionMs, 1830000);
      expect(item.userState?.watched, isFalse);
      expect(item.artwork.posterId, isNotNull);
      expect(item.artwork.backdropId, isNull);
    });

    test('an external subtitle has a url and no index, embedded is the reverse', () {
      final item = PleyaItem.fromJson(load('item_movie.json'));
      final subtitles = item.versions.single.subtitleStreams;
      final external = subtitles.firstWhere((s) => s.isExternal);
      final embedded = subtitles.firstWhere((s) => !s.isExternal);
      expect(external.url, isNotNull);
      expect(external.index, isNull);
      expect(embedded.url, isNull);
      expect(embedded.index, isNotNull);
    });

    test('three editions of one title stay three versions', () {
      final item = PleyaItem.fromJson(load('item_movie_with_edition.json'));
      expect(item.versions.map((v) => v.edition), ["Theatrical Cut", "Final Cut", "Director's Cut"]);
      expect(item.versions.map((v) => v.fileCount), [1, 1, 2]);
    });

    test('a show carries episode counts and no versions', () {
      final item = PleyaItem.fromJson(load('item_show.json'));
      expect(item.kind, PleyaItemKind.show);
      expect(item.childCount, 9);
      expect(item.episodeCount, 208);
      expect(item.watchedEpisodeCount, 41);
      expect(item.versions, isEmpty);
      expect(item.userState, isNull);
    });

    test('an episode carries its parent and its number', () {
      final item = PleyaItem.fromJson(load('item_episode.json'));
      expect(item.kind, PleyaItemKind.episode);
      expect(item.parentId, isNotNull);
      expect(item.index, 9);
      expect(item.userState?.watched, isTrue);
    });

    test('added_at parses as UTC, not as local time', () {
      final item = PleyaItem.fromJson(load('item_movie.json'));
      expect(item.addedAt.isUtc, isTrue);
      expect(item.addedAt, DateTime.utc(2026, 6, 18, 21, 34, 2));
    });
  });

  group('errors', () {
    test('the code is machine-readable and the domain falls out of it', () {
      final error = PleyaError.fromJson(load('error_not_found.json'));
      expect(error.code, 'library.not_found');
      expect(error.domain, 'library');
      expect(error.retryable, isFalse);
    });

    test('a rate limit is retryable and says how long to wait', () {
      final error = PleyaError.fromJson(load('error_rate_limited.json'));
      expect(error.retryable, isTrue);
      expect(error.retryAfterMs, 30000);
    });

    test('a body that is not an error envelope yields null, never an exception', () {
      expect(PleyaError.tryParse(const {'items': []}), isNull);
      expect(PleyaError.tryParse('<html>502 Bad Gateway</html>'), isNull);
      expect(PleyaError.tryParse(null), isNull);
    });
  });

  group('a broken response fails loudly', () {
    test('a missing required field throws instead of defaulting', () {
      final json = load('item_movie.json')..remove('title');
      expect(() => PleyaItem.fromJson(json), throwsA(isA<PleyaWireFormatException>()));
    });

    test('a required field of the wrong type throws instead of coercing', () {
      final json = load('item_movie.json')..['added_at'] = 1750000000;
      expect(() => PleyaItem.fromJson(json), throwsA(isA<PleyaWireFormatException>()));
    });

    test('a timestamp that will not parse throws instead of becoming now', () {
      final json = load('item_movie.json')..['added_at'] = 'yesterday';
      expect(() => PleyaItem.fromJson(json), throwsA(isA<PleyaWireFormatException>()));
    });

    test('an unknown response field is ignored, per compatibility rule 1', () {
      final json = load('item_movie.json')..['summary'] = 'A field PS-7 will add';
      expect(PleyaItem.fromJson(json).title, 'Grease');
    });
  });
}
