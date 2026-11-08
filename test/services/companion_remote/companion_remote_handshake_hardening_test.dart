import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/companion_remote/companion_remote_peer_service.dart';
import 'package:pleya/services/companion_remote/remote_auth_context.dart';
import 'package:pleya/services/companion_remote/remote_auth_service.dart';

// The host side of the handshake around an identity check that takes time
// (a Pleya Server ticket, DEC-XXX): one auth per connection, nothing adopted
// once the client left, a malformed nonce refused, and a host that cannot
// reach its own server does not hold that against the client.
void main() {
  final auth = RemoteAuthService.instance;
  final secret = List<int>.generate(32, (i) => 100 + i);

  late CompanionRemotePeerService host;
  late int port;
  late Completer<bool> verdict;
  var verifyCalls = 0;

  Future<void> startHost(Future<bool> Function() verify) async {
    host = CompanionRemotePeerService();
    final context = RemoteAuthContext(
      id: auth.computeAuthContextId(secret),
      backend: 'test',
      connectionId: 'c1',
      homeSecret: secret,
      discoveryKey: const [],
      clientIdentifier: 'host-client',
      userUuid: 'u-host',
      allowedUserUuids: const ['u-anna'],
      verifyIdentity: (_, _, _) {
        verifyCalls++;
        return verify();
      },
    );
    port = (await host.createSessionForContexts('Apple TV', 'tvOS', [context])).port;
  }

  setUp(() {
    verifyCalls = 0;
    verdict = Completer<bool>();
  });
  tearDown(() => host.disconnect());

  /// Opens a connection and returns it with a ready auth message.
  Future<(WebSocket, StreamIterator<dynamic>, String)> open({int nonceLength = 32}) async {
    final socket = await WebSocket.connect('ws://127.0.0.1:$port/ws');
    final frames = StreamIterator<dynamic>(socket);
    await frames.moveNext();
    final challenge = jsonDecode(frames.current as String) as Map<String, dynamic>;
    final hostNonce = base64Decode(challenge['nonce'] as String);
    final clientNonce = auth.generateNonce().take(nonceLength).toList();
    final tag = auth.computeAuthTag(
      homeSecret: secret,
      hostNonce: hostNonce,
      clientNonce: clientNonce,
      hostClientId: 'host-client',
      userUUID: 'u-anna',
      clientIdentifier: 'raw',
      deviceName: 'raw',
      platform: 'test',
    );
    final message = jsonEncode({
      'type': 'auth',
      'authContextId': auth.computeAuthContextId(secret),
      'clientNonce': base64Encode(clientNonce),
      'userUUID': 'u-anna',
      'clientIdentifier': 'raw',
      'deviceName': 'raw',
      'platform': 'test',
      'authTag': tag,
    });
    return (socket, frames, message);
  }

  String kind(dynamic frame) {
    try {
      return (jsonDecode(frame as String) as Map<String, dynamic>)['type'] as String;
    } catch (_) {
      return 'encrypted';
    }
  }

  test('a second auth on the same connection while the first is checked is ignored', () async {
    await startHost(() => verdict.future);
    final (socket, frames, message) = await open();
    socket
      ..add(message)
      ..add(message);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    verdict.complete(true);
    await frames.moveNext().timeout(const Duration(seconds: 5));
    expect(kind(frames.current), 'encrypted');
    expect(verifyCalls, 1, reason: 'one handshake per connection');
    await socket.close();
  });

  test('a client that left while its identity was checked is not adopted', () async {
    await startHost(() => verdict.future);
    final (socket, frames, message) = await open();
    socket.add(message);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await socket.close();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    verdict.complete(true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(host.isConnected, isFalse);
    expect(host.clientUserUuid, isNull);
  });

  test('a client nonce that is not 32 bytes is refused', () async {
    await startHost(() async => true);
    final (socket, frames, message) = await open(nonceLength: 16);
    socket.add(message);
    await frames.moveNext().timeout(const Duration(seconds: 5));
    expect(kind(frames.current), 'authFailed');
    expect(verifyCalls, 0);
    await socket.close();
  });

  test('a host that cannot check (its server is unreachable) does not count it against the client', () async {
    await startHost(() async => throw const SocketException('server unreachable'));
    final (socket, frames, message) = await open();
    socket.add(message);
    await frames.moveNext().timeout(const Duration(seconds: 5));
    expect(kind(frames.current), 'authFailed');
    expect(host.debugFailedAuthAttempts('127.0.0.1'), 0);
    await socket.close();
  });

  test('negative control: a disproven identity does count against the client', () async {
    await startHost(() async => false);
    final (socket, frames, message) = await open();
    socket.add(message);
    await frames.moveNext().timeout(const Duration(seconds: 5));
    expect(kind(frames.current), 'authFailed');
    expect(host.debugFailedAuthAttempts('127.0.0.1'), 1);
    await socket.close();
  });
}
