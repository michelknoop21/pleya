import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/main.dart';

void main() {
  PleyaShareConnection share() => PleyaShareConnection(
    id: 's',
    hostName: 'h',
    pairId: 'p',
    pairSecret: 'x',
    lastKnownIps: const ['1.2.3.4'],
    port: 48634,
    createdAt: DateTime(2026),
  );
  PlexAccountConnection plex() => PlexAccountConnection(
    id: 'p',
    accountToken: 't',
    clientIdentifier: 'c',
    accountLabel: 'l',
    createdAt: DateTime(2026),
  );

  test('hasLanCapableConnections: share/local count, cloud-only does not', () {
    expect(hasLanCapableConnections([plex()]), isFalse);
    expect(hasLanCapableConnections([plex(), share()]), isTrue);
    expect(
      hasLanCapableConnections([
        LocalFolderConnection(id: 'l', directoryUri: 'file:///x', displayName: 'X', createdAt: DateTime(2026)),
      ]),
      isTrue,
    );
    expect(hasLanCapableConnections(const []), isFalse);
  });
}
