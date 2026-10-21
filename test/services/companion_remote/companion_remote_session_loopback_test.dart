import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/models/companion_remote/remote_command.dart';
import 'package:pleya/services/companion_remote/companion_remote_peer_service.dart';
import 'package:pleya/services/companion_remote/remote_auth_context.dart';
import 'package:pleya/services/companion_remote/remote_auth_service.dart';
import 'package:pleya/services/companion_remote/remote_session_cipher.dart';

void main() {
  final secret = List<int>.generate(32, (i) => 200 - i);
  final auth = RemoteAuthService.instance;
  final context = RemoteAuthContext(
    id: auth.computeAuthContextId(secret),
    backend: 'test',
    connectionId: 'c1',
    homeSecret: secret,
    discoveryKey: const [],
    clientIdentifier: 'host-client',
    userUuid: 'user-1',
    allowedUserUuids: const ['user-1'],
  );

  late CompanionRemotePeerService host;
  final clients = <CompanionRemotePeerService>[];

  setUp(() => host = CompanionRemotePeerService());
  tearDown(() async {
    for (final c in clients) {
      await c.disconnect();
    }
    clients.clear();
    await host.disconnect();
  });

  Future<CompanionRemotePeerService> join(int port) async {
    final client = CompanionRemotePeerService();
    clients.add(client);
    await client.joinSessionWithContexts('TV', 'tvos', '127.0.0.1:$port', [context], authContextId: context.id);
    return client;
  }

  test('commands sent back to back right after auth all arrive, in both directions', () async {
    final session = await host.createSessionForContexts('iPhone', 'ios', [context]);
    final hostGot = <RemoteCommandType>[];
    host.onCommandReceived.listen((c) => hostGot.add(c.type));
    // Like deviceInfo + handoff: written straight after the connection is up.
    host.onDeviceConnected.listen((_) {
      host.sendCommand(const RemoteCommand(type: RemoteCommandType.home));
      host.sendCommand(const RemoteCommand(type: RemoteCommandType.dpadUp));
    });

    final client = CompanionRemotePeerService();
    clients.add(client);
    final clientGot = <RemoteCommandType>[];
    client.onCommandReceived.listen((c) => clientGot.add(c.type));
    await client.joinSessionWithContexts('TV', 'tvos', '127.0.0.1:${session.port}', [
      context,
    ], authContextId: context.id);
    client.sendCommand(const RemoteCommand(type: RemoteCommandType.select));
    client.sendCommand(const RemoteCommand(type: RemoteCommandType.back));
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(clientGot, containsAllInOrder([RemoteCommandType.home, RemoteCommandType.dpadUp]));
    expect(hostGot, containsAllInOrder([RemoteCommandType.select, RemoteCommandType.back]));
  });

  test('three undecryptable frames drop the client, the host keeps listening', () async {
    final session = await host.createSessionForContexts('iPhone', 'ios', [context]);
    final dropped = host.onDeviceDisconnected.first;

    final socket = await WebSocket.connect('ws://127.0.0.1:${session.port}/ws');
    addTearDown(() => socket.close());
    final frames = StreamIterator<dynamic>(socket);
    await frames.moveNext();
    final challenge = jsonDecode(frames.current as String) as Map<String, dynamic>;
    final hostNonce = base64Decode(challenge['nonce'] as String);
    final clientNonce = auth.generateNonce();
    final tag = auth.computeAuthTag(
      homeSecret: secret,
      hostNonce: hostNonce,
      clientNonce: clientNonce,
      hostClientId: context.clientIdentifier,
      userUUID: context.userUuid,
      clientIdentifier: 'raw-client',
      deviceName: 'raw',
      platform: 'test',
    );
    socket.add(
      jsonEncode({
        'type': 'auth',
        'authContextId': context.id,
        'clientNonce': base64Encode(clientNonce),
        'userUUID': context.userUuid,
        'clientIdentifier': 'raw-client',
        'deviceName': 'raw',
        'platform': 'test',
        'authTag': tag,
      }),
    );
    final cipher = RemoteSessionCipher()..start(await auth.deriveSessionEncKey(secret, hostNonce, clientNonce));
    await frames.moveNext();
    expect(jsonDecode((await cipher.decrypt(frames.current, fromHost: true))!)['type'], 'authSuccess');

    for (var i = 0; i < 3; i++) {
      socket.add(List<int>.filled(40, 9));
    }
    await dropped.timeout(const Duration(seconds: 5));

    expect(host.isServerRunning, isTrue);
    final again = await join(session.port).timeout(const Duration(seconds: 5));
    expect(again.isConnected, isTrue);
  });
}
