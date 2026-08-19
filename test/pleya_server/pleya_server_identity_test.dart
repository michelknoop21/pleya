import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';

/// PS-3 acceptance criterion 5: `MediaBackend.fromString` knows the new value
/// before a row is written with it.
///
/// This is the one failure in this area that is silent by construction.
/// `fromString` exists to tolerate legacy cache rows and falls back to Plex,
/// so a missing case does not throw, does not warn, and does not fail any
/// other test. It just relabels every Pleya Server item as Plex, and the first
/// visible symptom is a Plex code path running against a Pleya Server id.
void main() {
  group('MediaBackend', () {
    test('fromString knows pleyaServer and does not fall back to plex', () {
      expect(MediaBackend.fromString('pleyaServer'), MediaBackend.pleyaServer);
    });

    test('fromString accepts every id the enum can produce', () {
      for (final backend in MediaBackend.values) {
        expect(MediaBackend.fromString(backend.id), backend, reason: 'id "${backend.id}" must survive a round-trip');
      }
    });

    test('fromString keeps the documented fallbacks for null and unknown', () {
      expect(MediaBackend.fromString(null), MediaBackend.plex);
      expect(MediaBackend.fromString('emby'), MediaBackend.plex);
    });

    test('id round-trips through fromId', () {
      for (final backend in MediaBackend.values) {
        expect(MediaBackend.fromId(backend.id), backend);
      }
      expect(MediaBackend.pleyaServer.id, 'pleyaServer');
    });

    test('fromId throws on an unknown id instead of guessing', () {
      expect(() => MediaBackend.fromId('pleyaserver'), throwsA(isA<ArgumentError>()));
    });
  });

  group('ConnectionKind.pleyaServer', () {
    test('id round-trips and maps to its own backend', () {
      expect(ConnectionKind.fromId('pleyaServer'), ConnectionKind.pleyaServer);
      expect(ConnectionKind.pleyaServer.id, 'pleyaServer');
      expect(ConnectionKind.pleyaServer.backend, MediaBackend.pleyaServer);
    });

    test('is not folded into local the way pleyaShare is', () {
      expect(ConnectionKind.pleyaShare.backend, MediaBackend.local);
      expect(ConnectionKind.pleyaServer.backend, isNot(MediaBackend.local));
    });
  });

  group('PleyaServerConnection serialization', () {
    final base = PleyaServerConnection(
      id: 'pleyaServer.0198f2a1-7c3e-7b21-9f44-1c2d3e4f5a6b',
      baseUrl: 'http://nas.home.lan:8832',
      serverId: '0198f2a1-7c3e-7b21-9f44-1c2d3e4f5a6b',
      serverName: 'Zolder',
      userName: 'michel',
      refreshToken: 'rt-opaque-secret',
      createdAt: DateTime.utc(2026, 8, 19),
      lastAuthenticatedAt: DateTime.utc(2026, 8, 19, 12, 30),
    );

    test('round-trips through toConfigJson / fromConfigJson', () {
      final restored = PleyaServerConnection.fromConfigJson(
        id: base.id,
        json: base.toConfigJson(),
        status: ConnectionStatus.online,
        createdAt: base.createdAt,
        lastAuthenticatedAt: base.lastAuthenticatedAt,
      );
      expect(restored.baseUrl, base.baseUrl);
      expect(restored.serverId, base.serverId);
      expect(restored.serverName, base.serverName);
      expect(restored.userName, base.userName);
      expect(restored.refreshToken, base.refreshToken);
      expect(restored.kind, ConnectionKind.pleyaServer);
      expect(restored.backend, MediaBackend.pleyaServer);
    });

    test('carries no access token, because those rotate and expire', () {
      expect(base.toConfigJson().keys, isNot(contains('accessToken')));
    });

    test('carries no cached capabilities, because /info is the source of truth', () {
      expect(base.toConfigJson().keys, isNot(contains('capabilities')));
    });

    test('a half-written row degrades instead of throwing', () {
      final restored = PleyaServerConnection.fromConfigJson(
        id: 'pleyaServer.x',
        json: const {},
        status: ConnectionStatus.unknown,
        createdAt: DateTime.utc(2026, 8, 19),
      );
      expect(restored.baseUrl, '');
      expect(restored.refreshToken, '');
      expect(restored.serverName, 'Pleya Server');
    });
  });

  group('PleyaServerMediaItem', () {
    final item = MediaItem(
      id: '0198f2b0-1111-7000-8000-000000000001',
      backend: MediaBackend.pleyaServer,
      kind: MediaKind.movie,
      title: 'Grease',
      year: 1978,
      serverId: '0198f2a1-7c3e-7b21-9f44-1c2d3e4f5a6b',
    );

    test('the compat factory dispatches to its own union variant', () {
      expect(item, isA<PleyaServerMediaItem>());
      expect(item.backend, MediaBackend.pleyaServer);
    });

    test('survives a JSON round-trip without changing backend', () {
      final json = item.toJson();
      expect(json['backend'], 'pleyaServer');
      final restored = MediaItem.fromJson(json);
      expect(restored, isA<PleyaServerMediaItem>());
      expect(restored.backend, MediaBackend.pleyaServer);
      expect(restored.id, item.id);
      expect(restored.title, 'Grease');
      expect(restored.year, 1978);
    });
  });
}
