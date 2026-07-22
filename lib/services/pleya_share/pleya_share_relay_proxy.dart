import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../utils/app_logger.dart';
import 'pleya_share_pairing.dart';
import 'pleya_share_relay.dart';

/// Guest side of the Pleya Share relay: a loopback HTTP proxy that turns
/// every request into sealed relay frames and streams the host's reply back.
/// `PleyaShareChannel` (and mpv, and the download pipeline) simply point at
/// `http://127.0.0.1:<port>` and the whole existing protocol works unchanged
/// over the internet.
class PleyaShareRelayProxy {
  final String relayHostId;

  /// Sealing key material: the guest's pairSecret bytes, or — during first
  /// pairing via QR — the pairing key derived from the code + salt.
  final List<int> keyMaterial;
  final String? pairId;
  final String? baseUrl;

  HttpServer? _server;
  PleyaShareRelaySocket? _socket;
  PleyaShareRelaySealer? _sealer;
  int _nextId = 0;
  final Map<String, StreamController<PleyaShareRelayFrame>> _pending = {};

  PleyaShareRelayProxy({required this.relayHostId, required this.keyMaterial, this.pairId, this.baseUrl});

  int get port => _server?.port ?? 0;
  String get proxyBaseUrl => 'http://127.0.0.1:$port';

  /// Join the host's relay room and start the loopback server. Throws when
  /// the relay is unreachable or the host isn't in the room.
  Future<void> start({Duration hostWait = const Duration(seconds: 10)}) async {
    _sealer = PleyaShareRelaySealer(await PleyaSharePairing.deriveRelayKey(keyMaterial));
    final socket = PleyaShareRelaySocket(baseUrl: baseUrl);
    socket.messages.listen(_onEnvelope);
    // A dead relay socket must not leave in-flight HTTP requests hanging
    // forever — end their frame streams so the handlers unwind.
    socket.onClosed = () {
      for (final pending in _pending.values) {
        unawaited(pending.close());
      }
      _pending.clear();
    };
    await socket.connect(
      room: PleyaShareRelay.roomId(relayHostId),
      peerId: 'ps-guest-${base64UrlEncode(PleyaSharePairing.randomBytes(9))}',
      create: false,
    );
    _socket = socket;
    if (_hostPeer == null) {
      // Host may still be reconnecting to the room — wait briefly.
      final joined = Completer<void>();
      socket.onPeerJoined = (_) {
        if (_hostPeer != null && !joined.isCompleted) joined.complete();
      };
      try {
        await joined.future.timeout(hostWait);
      } on TimeoutException {
        await stop();
        throw StateError('PleyaShare: host not present on relay');
      } finally {
        socket.onPeerJoined = null;
      }
    }
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleRequest, onError: (Object e) => appLogger.d('PleyaShare: relay proxy error', error: e));
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    await _socket?.close();
    _socket?.dispose();
    _socket = null;
    for (final pending in _pending.values) {
      unawaited(pending.close());
    }
    _pending.clear();
  }

  String? get _hostPeer {
    final expected = PleyaShareRelay.hostPeerId(relayHostId);
    return (_socket?.peers.contains(expected) ?? false) ? expected : null;
  }

  Future<void> _onEnvelope(({String from, Map<String, dynamic> envelope}) msg) async {
    final PleyaShareRelayFrame frame;
    try {
      frame = await _sealer!.unseal(msg.envelope);
    } catch (_) {
      return;
    }
    _pending[frame.id]?.add(frame);
  }

  Future<void> _sendFrame(PleyaShareRelayFrame frame) async {
    final host = _hostPeer;
    final sealer = _sealer;
    if (host == null || sealer == null) throw StateError('relay host gone');
    _socket?.sendTo(host, await sealer.seal(frame, pairId: pairId, pairing: pairId == null));
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final id = 'r${_nextId++}';
    // ignore: close_sinks — closed in the finally below.
    final frames = _pending[id] = StreamController<PleyaShareRelayFrame>();
    try {
      final body = request.method == 'POST' ? await utf8.decoder.bind(request).join() : null;
      final range = request.headers.value(HttpHeaders.rangeHeader);
      await _sendFrame(
        PleyaShareRelayFrame(
          id: id,
          kind: 'req',
          fields: {
            'm': request.method,
            'p': request.uri.toString(),
            if (body != null && body.isNotEmpty) 'b': body,
            'range': ?range,
          },
        ),
      );

      var chunksSinceAck = 0;
      var gotResp = false;
      // Only the wait for the FIRST frame gets a timeout: after `resp` the
      // pace is guest-driven (mpv reads, acks flow) and a paused player may
      // legitimately go quiet for many minutes. A dead socket ends the
      // stream via onClosed above instead.
      final iterator = StreamIterator(frames.stream);
      while (gotResp ? await iterator.moveNext() : await iterator.moveNext().timeout(const Duration(seconds: 30))) {
        final frame = iterator.current;
        switch (frame.kind) {
          case 'resp':
            gotResp = true;
            request.response.statusCode = (frame.fields['status'] as num?)?.toInt() ?? 500;
            final headers = (frame.fields['headers'] as Map?)?.cast<String, Object?>() ?? const {};
            for (final entry in headers.entries) {
              if (entry.value != null) request.response.headers.set(entry.key, '${entry.value}');
            }
          case 'data':
            request.response.add(base64Decode(frame.fields['c'] as String));
            if (++chunksSinceAck >= PleyaShareRelay.ackWindow) {
              chunksSinceAck = 0;
              await _sendFrame(PleyaShareRelayFrame(id: id, kind: 'ack'));
            }
          case 'end':
            await request.response.close();
            return;
          case 'err':
            if (!gotResp) request.response.statusCode = HttpStatus.badGateway;
            await request.response.close();
            return;
        }
      }
      // Stream ended without 'end' (relay dropped) — close what we have.
      await request.response.close();
    } catch (e) {
      // Player closed the connection (or the tunnel died) — tell the host to
      // stop serving instead of letting it stream into the void.
      appLogger.d('PleyaShare: relay proxy request failed', error: e);
      try {
        await _sendFrame(PleyaShareRelayFrame(id: id, kind: 'cancel'));
      } catch (_) {}
      try {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      } catch (_) {}
    } finally {
      unawaited(_pending.remove(id)?.close());
    }
  }
}
