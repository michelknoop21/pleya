import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/services/plex_auth_service.dart';
import 'package:pleya/services/preferences/portable_server_ids.dart';
import 'package:pleya/services/preferences/preference_value_portability.dart';

/// Key scoping is not enough for the library families: their values carry
/// `serverId:libraryId` entries, so a correctly namespaced record can still
/// hold state that means nothing on the other device.
///
/// The plan assumed `serverId` was a locally assigned connection id. It is not.
/// For Plex it is `PlexServer.clientIdentifier` from plex.tv's `/resources`,
/// for Jellyfin the server's own `machineId`; both are the same everywhere.
/// Only the local-folder and Pleya Share backends key on a locally generated
/// `connection.id`.
void main() {
  PlexServer plexServer(String clientIdentifier) => PlexServer(
    name: 'server',
    clientIdentifier: clientIdentifier,
    accessToken: 'token',
    connections: const [],
    owned: true,
  );

  PlexAccountConnection plexAccount(List<String> serverIds) => PlexAccountConnection(
    id: 'conn-plex',
    createdAt: DateTime(2026, 8, 21),
    accountToken: 'token',
    clientIdentifier: 'device-client-id',
    accountLabel: 'michel',
    servers: serverIds.map(plexServer).toList(),
  );

  group('which backends hand out a portable server identity', () {
    test('Plex servers do: the id comes from plex.tv, not from this device', () {
      final ids = PortableServerIds.fromConnections([
        plexAccount(['plex-machine-a', 'plex-machine-b']),
      ]);

      expect(ids.contains('plex-machine-a'), isTrue);
      expect(ids.contains('plex-machine-b'), isTrue);
    });

    test('a local folder does not: its id is a locally generated row key', () {
      final ids = PortableServerIds.fromConnections([
        LocalFolderConnection(
          id: 'local-row-1',
          createdAt: DateTime(2026, 8, 21),
          directoryUri: 'file:///Volumes/Media',
          displayName: 'Movies',
        ),
      ]);

      expect(ids.contains('local-row-1'), isFalse);
      expect(ids.length, 0);
    });

    test('an empty registry makes nothing portable, rather than everything', () {
      const ids = PortableServerIds.empty();

      expect(ids.contains('anything'), isFalse);
      expect(noServerIdIsPortable('anything'), isFalse);
    });
  });

  group('filtering entries', () {
    bool isPortable(String id) => id == 'plex-machine' || id == 'jellyfin-machine';

    test('a portable entry travels and a local-folder one does not', () {
      expect(PreferenceValuePortability.isPortableEntry('plex-machine:12', isPortable), isTrue);
      expect(PreferenceValuePortability.isPortableEntry('local-row-1:12', isPortable), isFalse);
    });

    test('an entry with no server id at all stays home', () {
      // Origin cannot be established, so it is not "probably fine".
      expect(PreferenceValuePortability.isPortableEntry('bare-value', isPortable), isFalse);
      expect(PreferenceValuePortability.isPortableEntry(':12', isPortable), isFalse);
    });

    test('a library id containing a colon survives the split', () {
      expect(PreferenceValuePortability.serverIdOf('plex-machine:sec:12'), 'plex-machine');
    });

    test('a mixed list splits cleanly and keeps its order', () {
      const entries = ['plex-machine:1', 'local-row-1:2', 'jellyfin-machine:3', 'local-row-1:4'];

      expect(PreferenceValuePortability.portableEntries(entries, isPortable), ['plex-machine:1', 'jellyfin-machine:3']);
      expect(PreferenceValuePortability.localOnlyEntries(entries, isPortable), ['local-row-1:2', 'local-row-1:4']);
    });

    test('a per-library key travels whole or not at all', () {
      expect(
        PreferenceValuePortability.isPortableScopedKey('library_sort_plex-machine:12', 'library_sort_', isPortable),
        isTrue,
      );
      expect(
        PreferenceValuePortability.isPortableScopedKey('library_sort_local-row-1:12', 'library_sort_', isPortable),
        isFalse,
      );
    });
  });

  group('merging a remote list back', () {
    bool isPortable(String id) => id == 'plex-machine';

    test('local-only entries survive a remote apply that never saw them', () {
      // The other device has no local folder, so its list simply lacks those
      // entries. Reading that absence as a removal would wipe them.
      final merged = PreferenceValuePortability.mergeKeepingLocalOnly(
        ['plex-machine:1', 'plex-machine:9'],
        ['plex-machine:1', 'local-row-1:2'],
        isPortable,
      );

      expect(merged, ['plex-machine:1', 'plex-machine:9', 'local-row-1:2']);
    });

    test('a portable entry removed remotely really does go', () {
      final merged = PreferenceValuePortability.mergeKeepingLocalOnly(
        ['plex-machine:1'],
        ['plex-machine:1', 'plex-machine:2', 'local-row-1:3'],
        isPortable,
      );

      expect(merged, ['plex-machine:1', 'local-row-1:3']);
    });

    test('a non-portable entry in the incoming list is refused, not adopted', () {
      final merged = PreferenceValuePortability.mergeKeepingLocalOnly(
        ['plex-machine:1', 'someone-elses-local-row:5'],
        const [],
        isPortable,
      );

      expect(merged, ['plex-machine:1']);
    });

    test('merging twice changes nothing', () {
      final once = PreferenceValuePortability.mergeKeepingLocalOnly(['plex-machine:1'], ['local-row-1:2'], isPortable);
      final twice = PreferenceValuePortability.mergeKeepingLocalOnly(['plex-machine:1'], once, isPortable);

      expect(twice, once);
    });
  });
}
