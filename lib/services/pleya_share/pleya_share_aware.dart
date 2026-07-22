import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pleya_aware/pleya_aware.dart';

import '../../utils/app_logger.dart';

/// Wi-Fi Aware transport for Pleya Share: a pure byte-pipe on top of the
/// existing HTTP protocol. Purely additive next to LAN/hotspot/cable/relay.
///
/// Host side: every incoming Aware stream is piped 1:1 to the local share
/// HTTP server (auth, Range/206, multi-client all work unchanged). Guest
/// side: a loopback TCP server pipes each connection (mpv, channel) into its
/// own Aware stream to the host.
class PleyaShareAwareHost {
  final int hostPort;

  /// Injectable for tests: defaults to the real plugin.
  final Stream<AwareStream> Function() incomingStreams;
  final Future<bool> Function() isSupported;
  final Future<void> Function(String serviceInfo) publish;

  StreamSubscription<AwareStream>? _sub;

  PleyaShareAwareHost({
    required this.hostPort,
    Stream<AwareStream> Function()? incomingStreams,
    Future<bool> Function()? isSupported,
    Future<void> Function(String serviceInfo)? publish,
  }) : incomingStreams = incomingStreams ?? (() => PleyaAware.incomingStreams),
       isSupported = isSupported ?? PleyaAware.isSupported,
       publish = publish ?? PleyaAware.startPublishing;

  Future<void> start(String serviceInfo) async {
    if (!await isSupported()) return;
    _sub = incomingStreams().listen(_bridge);
    try {
      await publish(serviceInfo);
      appLogger.i('PleyaShare: Wi-Fi Aware publishing as $serviceInfo');
    } catch (e) {
      appLogger.d('PleyaShare: aware publish failed', error: e);
      await _sub?.cancel();
      _sub = null;
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await PleyaAware.stopPublishing();
    } catch (_) {}
  }

  Future<void> _bridge(AwareStream stream) async {
    Socket? socket;
    try {
      socket = await Socket.connect(InternetAddress.loopbackIPv4, hostPort);
      final toHost = stream.input.listen(socket.add, onDone: () => socket?.close(), onError: (_) => socket?.close());
      await socket.listen((bytes) => stream.write(Uint8List.fromList(bytes))).asFuture<void>().catchError((_) {});
      await toHost.cancel();
    } catch (e) {
      appLogger.d('PleyaShare: aware host bridge failed', error: e);
    } finally {
      await stream.close();
      socket?.destroy();
    }
  }
}

/// Guest-side loopback proxy: HTTP against `http://127.0.0.1:<port>` becomes
/// one Aware stream per connection.
class PleyaShareAwareProxy {
  final AwareHost host;

  /// Injectable for tests.
  final Future<AwareStream> Function(AwareHost host) connect;

  ServerSocket? _server;

  PleyaShareAwareProxy({required this.host, Future<AwareStream> Function(AwareHost)? connect})
    : connect = connect ?? PleyaAware.connect;

  int get port => _server?.port ?? 0;
  String get proxyBaseUrl => 'http://127.0.0.1:$port';

  Future<void> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_bridge, onError: (Object e) => appLogger.d('PleyaShare: aware proxy error', error: e));
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  Future<void> _bridge(Socket socket) async {
    AwareStream? stream;
    try {
      stream = await connect(host);
      final fromHost = stream.input.listen(
        socket.add,
        onDone: () => socket.destroy(),
        onError: (_) => socket.destroy(),
      );
      await socket.listen((bytes) => stream?.write(Uint8List.fromList(bytes))).asFuture<void>().catchError((_) {});
      await fromHost.cancel();
    } catch (e) {
      appLogger.d('PleyaShare: aware proxy bridge failed', error: e);
    } finally {
      await stream?.close();
      socket.destroy();
    }
  }
}
