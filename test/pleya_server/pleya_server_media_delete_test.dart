/// Deleting a title on Pleya Server (`DELETE /items/{id}`, chapter 17h): only
/// behind the `media_delete` capability, and a partial delete never reads as a
/// success. Real client over a mocked HTTP client.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/server_administration.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/pleya_server_client.dart';
import 'package:pleya/widgets/media_deletion_failure_message.dart';

http.Response _json(Object? body, {int status = 200}) =>
    http.Response(body == null ? '' : jsonEncode(body), status, headers: const {'content-type': 'application/json'});

final _item = MediaItem(
  id: 'item-1',
  backend: MediaBackend.pleyaServer,
  kind: MediaKind.movie,
  title: 'Sintel',
  serverId: 'srv-1',
  libraryId: 'lib-1',
);

Future<PleyaServerClient> _client({
  required bool mediaDelete,
  required List<String> requests,
  http.Response? answer,
}) async {
  final client = PleyaServerClient.create(
    PleyaServerConnection(
      id: 'pleyaServer.srv-1',
      baseUrl: 'http://nas.lan:8832',
      serverId: 'srv-1',
      serverName: 'Zolder',
      userName: 'michel',
      refreshToken: 'rt-1',
      role: 'owner',
      createdAt: DateTime.utc(2026, 11, 13),
    ),
    httpClientFactory: () => MockClient((request) async {
      final path = request.url.path.replaceFirst('/pleya/v1', '');
      if (path == '/auth/refresh') {
        return _json(const {
          'access_token': 'at',
          'refresh_token': 'rt-2',
          'token_type': 'bearer',
          'expires_in_ms': 900000,
        });
      }
      if (path == '/info') {
        return _json({
          'protocol': {'major': 1, 'feature_level': 1, 'profile': 'full'},
          'server': {'id': 'srv-1'},
          'capabilities': {
            'browse': true,
            'search': true,
            'artwork': true,
            'watch_state': true,
            'users': true,
            'administration': true,
            'media_delete': mediaDelete,
          },
          'auth': {
            'methods': ['password'],
            'setup_required': false,
          },
        });
      }
      requests.add('${request.method} $path');
      return answer ?? _json({'removed_files': 2, 'removed_items': 1});
    }),
  );
  await client.refreshCapabilities();
  final manager = MultiServerManager();
  addTearDown(manager.dispose);
  manager.debugRegisterClientForTesting(client);
  return client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('without media_delete nothing is offered and nothing is sent', () async {
    final requests = <String>[];
    final client = await _client(mediaDelete: false, requests: requests);

    expect((client as MediaDeletionGate).supportsMediaDeletion, isFalse);
    expect(await client.deleteMediaItem(_item), isFalse);
    expect(requests, isEmpty);
  });

  test('with media_delete the item is deleted on the server', () async {
    final requests = <String>[];
    final client = await _client(mediaDelete: true, requests: requests);

    expect((client as MediaDeletionGate).supportsMediaDeletion, isTrue);
    expect(await client.deleteMediaItem(_item), isTrue);
    expect(requests, ['DELETE /items/item-1']);
  });

  test('a file that stayed behind is an error that says what stayed', () async {
    final requests = <String>[];
    final client = await _client(
      mediaDelete: true,
      requests: requests,
      answer: _json({
        'error': {
          'code': 'library.media_delete_incomplete',
          'message': 'some files of this item could not be deleted',
          'retryable': false,
          'details': {
            'removed_files': 1,
            'removed_items': 0,
            'failed': [
              {'path': 'Sintel (2010)/Sintel (2010) {edition-4K}.mkv', 'reason': 'symlink'},
            ],
          },
        },
      }, status: 409),
    );

    Object? caught;
    try {
      await client.deleteMediaItem(_item);
    } catch (e) {
      caught = e;
    }
    expect(caught, isA<MediaDeletionIncompleteException>());
    final incomplete = caught! as MediaDeletionIncompleteException;
    expect(incomplete.removedFiles, 1);
    expect(incomplete.removedItems, 0);
    // A file stayed, so the title is still on the server and stays in the UI.
    expect(incompleteDeletionRemovedTitle(incomplete, MediaKind.movie), isFalse);
    expect(incomplete.failedPaths, ['Sintel (2010)/Sintel (2010) {edition-4K}.mkv']);
    expect(
      mediaDeletionFailureMessage(incomplete, MediaBackend.pleyaServer),
      contains('Sintel (2010) {edition-4K}.mkv'),
    );
    expect(requests, ['DELETE /items/item-1']);
  });

  test('a partial delete only drops the title when the server removed it', () {
    const gone = MediaDeletionIncompleteException(removedFiles: 2, failedPaths: ['poster.jpg'], removedItems: 1);
    const kept = MediaDeletionIncompleteException(removedFiles: 1, failedPaths: ['film.mkv']);
    expect(incompleteDeletionRemovedTitle(gone, MediaKind.movie), isTrue);
    expect(incompleteDeletionRemovedTitle(kept, MediaKind.movie), isFalse);
    // A series with one episode gone still has the others.
    expect(incompleteDeletionRemovedTitle(gone, MediaKind.show), isFalse);
  });

  group('a refused delete names its reason', () {
    for (final (code, reason, status, text) in [
      ('library.media_delete_unavailable', 'disabled', 409, () => t.mediaMenu.pleyaDeletionDisabled),
      ('library.media_delete_unavailable', 'read_only', 409, () => t.mediaMenu.pleyaDeletionReadOnly),
      ('library.media_delete_unavailable', 'root_overlap', 409, () => t.mediaMenu.pleyaDeletionRootOverlap),
      ('library.scan_in_progress', null, 409, () => t.mediaMenu.pleyaDeletionScanInProgress),
      ('storage.unavailable', null, 503, () => t.mediaMenu.pleyaDeletionStorageUnavailable),
    ]) {
      test('$code ${reason ?? ''}', () async {
        final client = await _client(
          mediaDelete: true,
          requests: <String>[],
          answer: _json({
            'error': {
              'code': code,
              'message': 'refused',
              'retryable': status == 503,
              if (reason != null) 'details': {'reason': reason},
            },
          }, status: status),
        );
        Object? caught;
        try {
          await client.deleteMediaItem(_item);
        } catch (e) {
          caught = e;
        }
        expect(caught, isNotNull);
        expect(mediaDeletionFailureMessage(caught!, MediaBackend.pleyaServer), text());
      });
    }
  });
}
