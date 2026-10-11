import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya/widgets/media_deletion_failure_message.dart';

MediaServerHttpException _badRequest() =>
    MediaServerHttpException(type: MediaServerHttpErrorType.unknown, statusCode: 400);

/// A Plex client whose only answer is [prefs]; [requests] records every path.
PlexClient _plexClient(http.Response Function() prefs, List<String> requests) {
  final client = PlexClient.forTesting(
    config: PlexConfig(
      baseUrl: 'https://plex.example',
      token: 'token',
      clientIdentifier: 'client-id',
      product: 'Pleya',
      version: 'test',
    ),
    serverId: ServerId('server-1'),
    serverName: 'Plex',
    httpClient: MockClient((request) async {
      requests.add(request.url.path);
      return prefs();
    }),
  );
  addTearDown(client.close);
  return client;
}

http.Response _prefs(String settings) =>
    http.Response('{"MediaContainer":{"Setting":[$settings]}}', 200, headers: {'content-type': 'application/json'});

void main() {
  setUp(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    PlexApiCache.initialize(db);
  });

  group('mediaDeletionFailureMessage', () {
    test('names the setting only when Plex says it is off', () {
      expect(
        mediaDeletionFailureMessage(_badRequest(), MediaBackend.plex, plexAllowsMediaDeletion: false),
        t.mediaMenu.plexDeletionDisabled,
      );
    });

    test('points at the files when the setting is on', () {
      final message = mediaDeletionFailureMessage(_badRequest(), MediaBackend.plex, plexAllowsMediaDeletion: true);

      expect(message, t.mediaMenu.plexDeletionFilesNotRemovable);
      expect(message, isNot(t.mediaMenu.plexDeletionDisabled));
    });

    test('claims neither cause when the setting is unknown', () {
      final message = mediaDeletionFailureMessage(_badRequest(), MediaBackend.plex);

      expect(message, t.mediaMenu.plexDeletionRefusedUnknown);
      expect(message, isNot(t.mediaMenu.plexDeletionDisabled));
    });

    test('keeps the generic message for other failures and other backends', () {
      final offline = MediaServerHttpException(type: MediaServerHttpErrorType.connectionError);

      expect(mediaDeletionFailureMessage(offline, MediaBackend.plex), t.mediaMenu.mediaFailedToDelete);
      for (final backend in [MediaBackend.jellyfin, MediaBackend.local, MediaBackend.pleyaServer]) {
        expect(mediaDeletionFailureMessage(_badRequest(), backend), t.mediaMenu.mediaFailedToDelete);
      }
    });
  });

  group('resolveMediaDeletionFailureMessage', () {
    test('setting on: a 400 is not blamed on the setting', () async {
      final requests = <String>[];
      final client = _plexClient(() => _prefs('{"id":"allowMediaDeletion","value":true}'), requests);

      final message = await resolveMediaDeletionFailureMessage(_badRequest(), MediaBackend.plex, client);

      expect(message, isNot(t.mediaMenu.plexDeletionDisabled));
      expect(message, t.mediaMenu.plexDeletionFilesNotRemovable);
      expect(requests, ['/:/prefs']);
    });

    test('setting off: the existing message stays', () async {
      final client = _plexClient(() => _prefs('{"id":"allowMediaDeletion","value":false}'), []);

      expect(
        await resolveMediaDeletionFailureMessage(_badRequest(), MediaBackend.plex, client),
        t.mediaMenu.plexDeletionDisabled,
      );
    });

    test('setting as text is read the same way', () async {
      final client = _plexClient(() => _prefs('{"id":"allowMediaDeletion","value":"0"}'), []);

      expect(
        await resolveMediaDeletionFailureMessage(_badRequest(), MediaBackend.plex, client),
        t.mediaMenu.plexDeletionDisabled,
      );
    });

    test('setting missing from the answer: unknown', () async {
      final client = _plexClient(() => _prefs('{"id":"FriendlyName","value":"Plex"}'), []);

      expect(
        await resolveMediaDeletionFailureMessage(_badRequest(), MediaBackend.plex, client),
        t.mediaMenu.plexDeletionRefusedUnknown,
      );
    });

    test('prefs request fails: unknown', () async {
      final client = _plexClient(() => http.Response('', 403), []);

      expect(
        await resolveMediaDeletionFailureMessage(_badRequest(), MediaBackend.plex, client),
        t.mediaMenu.plexDeletionRefusedUnknown,
      );
    });

    test('no client: unknown, without a request', () async {
      expect(
        await resolveMediaDeletionFailureMessage(_badRequest(), MediaBackend.plex, null),
        t.mediaMenu.plexDeletionRefusedUnknown,
      );
    });

    test('other failures and other backends never ask the server', () async {
      final requests = <String>[];
      final plex = _plexClient(() => _prefs('{"id":"allowMediaDeletion","value":false}'), requests);
      final jellyfin = JellyfinClient.forTesting(
        connection: JellyfinConnection(
          id: 'jf-1',
          baseUrl: 'https://jellyfin.example',
          serverName: 'Jellyfin',
          serverMachineId: 'machine-1',
          userId: 'user-1',
          userName: 'User',
          accessToken: 'token',
          deviceId: 'device-1',
          createdAt: DateTime.utc(2026),
        ),
        httpClient: MockClient((request) async {
          requests.add(request.url.path);
          return http.Response('', 204);
        }),
      );
      addTearDown(jellyfin.close);
      final offline = MediaServerHttpException(type: MediaServerHttpErrorType.connectionError);

      expect(
        await resolveMediaDeletionFailureMessage(offline, MediaBackend.plex, plex),
        t.mediaMenu.mediaFailedToDelete,
      );
      expect(
        await resolveMediaDeletionFailureMessage(_badRequest(), MediaBackend.jellyfin, jellyfin),
        t.mediaMenu.mediaFailedToDelete,
      );
      expect(requests, isEmpty);
    });
  });
}
