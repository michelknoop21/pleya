import 'package:pleya/connection/connection.dart';
import 'package:pleya/services/pleya_server_client.dart';
import 'package:pleya_verify_fixture_server/pleya_fake_server.dart';

export 'package:pleya_verify_fixture_server/pleya_fake_server.dart';

/// App-specific integration for [PleyaFakeServer]: the routing kernel is
/// pure and has no dependency on this app (it lives in
/// pleya_verify/fixture_server, shared with a real dart:io fixture server —
/// see Deel B Fase 1/2 of the Pleya Verify plan), so [connection] and
/// [client] — the two methods that need [PleyaServerConnection]/
/// [PleyaServerClient] — are added back here as extension methods instead.
extension PleyaFakeServerAppIntegration on PleyaFakeServer {
  PleyaServerConnection connection({String refreshToken = 'rt-1'}) => PleyaServerConnection(
    id: 'pleyaServer.srv-1',
    baseUrl: 'http://nas.lan:8832',
    serverId: 'srv-1',
    serverName: 'Zolder',
    userName: 'michel',
    refreshToken: refreshToken,
    createdAt: DateTime.utc(2026, 8, 19),
  );

  PleyaServerClient client() => PleyaServerClient.create(connection(), httpClientFactory: asHttpClient);
}
