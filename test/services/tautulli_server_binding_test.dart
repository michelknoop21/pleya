import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/services/tautulli/tautulli_server_binding.dart';

/// Rating keys are per-server integers, so resolving one against the wrong Plex
/// server does not fail: it opens a different title. These pin who is allowed
/// to guess and who is not.
void main() {
  const owned = {'server-a', 'server-b'};
  bool isOwner(ServerId id) => owned.contains(id);

  ServerId? bind(String? identifier, List<String> servers) =>
      tautulliMonitoredServer(machineIdentifier: identifier, serverIds: servers, isOwnerOrAdmin: isOwner);

  test('the reported server wins over the first one in the list', () {
    expect(bind('server-b', ['server-a', 'server-b']), ServerId('server-b'));
  });

  test('a reported server nobody connected resolves to nothing', () {
    expect(bind('server-c', ['server-a', 'server-b']), isNull);
  });

  // Sessions paired before the identifier was recorded have none. One owned
  // server is the only defensible reading of "the server Tautulli watches".
  test('without an identifier a single owned server is used', () {
    expect(bind(null, ['server-a']), ServerId('server-a'));
    expect(bind('   ', ['server-a']), ServerId('server-a'));
  });

  test('without an identifier two owned servers stay unresolved', () {
    expect(bind(null, ['server-a', 'server-b']), isNull);
  });

  test('a server this profile does not own is not a candidate to fall back to', () {
    expect(bind(null, ['server-a', 'someone-elses']), ServerId('server-a'));
    expect(bind(null, ['someone-elses']), isNull);
  });

  test('no servers at all resolves to nothing', () {
    expect(bind('server-a', const []), isNull);
    expect(bind(null, const []), isNull);
  });
}
