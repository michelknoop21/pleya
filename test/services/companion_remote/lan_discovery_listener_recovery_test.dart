import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/companion_remote/lan_discovery_service.dart';

class _Socket extends Stream<RawSocketEvent> implements RawDatagramSocket {
  final events = StreamController<RawSocketEvent>.broadcast();
  bool closed = false;
  @override
  StreamSubscription<RawSocketEvent> listen(
    void Function(RawSocketEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => events.stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  void close() {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _turn() => Future<void>.delayed(Duration.zero);

void main() {
  for (final done in [false, true]) {
    test('listener ${done ? 'close' : 'bad descriptor'} clears active state so the puller can relisten', () async {
      final sockets = <_Socket>[];
      final service = LanDiscoveryService(
        listenerSocketFactory: () async {
          final socket = _Socket();
          sockets.add(socket);
          return socket;
        },
      );
      addTearDown(() async {
        service.dispose();
        for (final s in sockets) {
          if (!s.events.isClosed) await s.events.close();
        }
      });
      service.startListeningForContexts(const []);
      await _turn();
      expect(service.isListening, isTrue);
      if (done) {
        await sockets.first.events.close();
      } else {
        sockets.first.events.addError(const SocketException('Bad file descriptor'));
      }
      await _turn();
      expect(service.isListening, isFalse);
      expect(sockets.first.closed, isTrue);
      service.startListeningForContexts(const []);
      await _turn();
      expect(service.isListening, isTrue);
      expect(sockets, hasLength(2));
    });
  }
  test('late listener bind after stop cannot resurrect a suspended listener', () async {
    final pending = Completer<RawDatagramSocket>();
    final socket = _Socket();
    final service = LanDiscoveryService(listenerSocketFactory: () => pending.future);
    addTearDown(() async {
      service.dispose();
      await socket.events.close();
    });
    service.startListeningForContexts(const []);
    service.stopListening();
    pending.complete(socket);
    await _turn();
    expect(service.isListening, isFalse);
    expect(socket.closed, isTrue);
  });
}
