import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../utils/app_logger.dart';
import 'pleya_share_pairing.dart';
import 'pleya_share_relay.dart';

/// Host side of the Pleya Share relay: joins the host's relay room and
/// replays incoming sealed frames as HTTP requests against the host's own
/// loopback server, streaming the response back as frames. Reuses the full
/// existing HTTP protocol (pairing, auth, /library, ranged /stream) with
/// zero route changes.
class PleyaShareRelayListener {
  final String relayHostId;
  final int hostPort;
  final String? baseUrl;

  /// Resolves the relay key for an envelope: guest secret bytes for a known
  /// pairId, or the current pairing key when `pair:true` (QR code pairing).
  final Future<List<int>?> Function({String? pairId, required bool pairing}) resolveKey;

  PleyaShareRelaySocket? _socket;
  Timer? _retry;
  bool _running = false;
  final HttpClient _http = HttpClient();

  /// Pending acks per (peer, frame id) so streamed responses can flow-control.
  final Map<String, Completer<void>> _acks = {};

  /// Streams the guest aborted (player closed the connection) — the serve
  /// loop stops without sending further frames.
  final Set<String> _cancelled = {};

  /// How long a paused guest may sit between acks before the stream is
  /// abandoned. Generous: a viewer pausing mid-episode must not kill the
  /// tunnel. Overridable for tests.
  Duration ackTimeout = const Duration(minutes: 5);

  /// Delay before re-attempting the relay connection. Overridable for tests.
  Duration retryDelay = const Duration(seconds: 15);

  PleyaShareRelayListener({required this.relayHostId, required this.hostPort, required this.resolveKey, this.baseUrl});

  bool get isConnected => _socket?.isConnected ?? false;

  Future<void> start() async {
    _running = true;
    await _ensureConnected();
  }

  Future<void> stop() async {
    _running = false;
    _retry?.cancel();
    _retry = null;
    await _socket?.close();
    _socket?.dispose();
    _socket = null;
    _http.close(force: true);
  }

  /// Force a fresh relay connection (e.g. after a network switch left the
  /// socket bound to a dead interface).
  Future<void> reconnect() async {
    if (!_running) return;
    _retry?.cancel();
    _retry = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      socket.onClosed = null;
      await socket.close();
      socket.dispose();
    }
    await _ensureConnected();
  }

  Future<void> _ensureConnected() async {
    if (!_running || isConnected) return;
    final socket = PleyaShareRelaySocket(baseUrl: baseUrl);
    try {
      socket.messages.listen(_onEnvelope);
      socket.onClosed = _scheduleRetry;
      await socket.connect(
        room: PleyaShareRelay.roomId(relayHostId),
        peerId: PleyaShareRelay.hostPeerId(relayHostId),
        create: true,
      );
      _socket = socket;
      appLogger.i('PleyaShare: relay listener up (room ${PleyaShareRelay.roomId(relayHostId)})');
    } catch (e) {
      // No internet / relay down — keep retrying quietly while hosting.
      appLogger.d('PleyaShare: relay connect failed', error: e);
      socket.dispose();
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (!_running) return;
    _socket = null;
    _retry?.cancel();
    _retry = Timer(retryDelay, _ensureConnected);
  }

  Future<void> _onEnvelope(({String from, Map<String, dynamic> envelope}) msg) async {
    final envelope = msg.envelope;
    final pairing = envelope['pair'] == true;
    final pairId = envelope['pairId'] as String?;
    final key = await resolveKey(pairId: pairId, pairing: pairing);
    if (key == null) return;
    final sealer = PleyaShareRelaySealer(await PleyaSharePairing.deriveRelayKey(key));
    final PleyaShareRelayFrame frame;
    try {
      frame = await sealer.unseal(envelope);
    } catch (_) {
      return; // Tampered or wrong-key frame — drop.
    }
    switch (frame.kind) {
      case 'req':
        unawaited(_serve(msg.from, sealer, frame, pairId: pairId, pairing: pairing));
      case 'ack':
        _acks.remove('${msg.from}|${frame.id}')?.complete();
      case 'cancel':
        _cancelled.add('${msg.from}|${frame.id}');
        _acks.remove('${msg.from}|${frame.id}')?.complete();
    }
  }

  Future<void> _send(
    String to,
    PleyaShareRelaySealer sealer,
    PleyaShareRelayFrame frame, {
    String? pairId,
    bool pairing = false,
  }) async {
    _socket?.sendTo(to, await sealer.seal(frame, pairId: pairId, pairing: pairing));
  }

  Future<void> _serve(
    String to,
    PleyaShareRelaySealer sealer,
    PleyaShareRelayFrame frame, {
    String? pairId,
    bool pairing = false,
  }) async {
    Future<void> reply(PleyaShareRelayFrame f) => _send(to, sealer, f, pairId: pairId, pairing: pairing);
    final cancelKey = '$to|${frame.id}';
    try {
      final method = frame.fields['m'] as String? ?? 'GET';
      final path = frame.fields['p'] as String? ?? '/';
      final request = await _http.openUrl(method, Uri.parse('http://127.0.0.1:$hostPort$path'));
      final range = frame.fields['range'] as String?;
      if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
      final auth = frame.fields['auth'] as String?;
      if (auth != null) request.headers.set(HttpHeaders.authorizationHeader, auth);
      final body = frame.fields['b'] as String?;
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(body);
      }
      final response = await request.close();
      await reply(
        PleyaShareRelayFrame(
          id: frame.id,
          kind: 'resp',
          fields: {
            'status': response.statusCode,
            'headers': {
              for (final name in const [
                HttpHeaders.contentTypeHeader,
                HttpHeaders.contentRangeHeader,
                HttpHeaders.contentLengthHeader,
                HttpHeaders.acceptRangesHeader,
              ])
                if (response.headers.value(name) != null) name: response.headers.value(name),
            },
          },
        ),
      );
      var sinceAck = 0;
      final buffer = BytesBuilder(copy: false);
      Future<void> flush() async {
        if (buffer.isEmpty) return;
        await reply(PleyaShareRelayFrame(id: frame.id, kind: 'data', fields: {'c': base64Encode(buffer.takeBytes())}));
        if (++sinceAck >= PleyaShareRelay.ackWindow) {
          sinceAck = 0;
          final ack = _acks[cancelKey] = Completer<void>();
          await ack.future.timeout(ackTimeout);
        }
      }

      await for (final chunk in response) {
        if (_cancelled.remove(cancelKey)) return; // Guest aborted — stop quietly.
        buffer.add(chunk);
        if (buffer.length >= PleyaShareRelay.chunkSize) await flush();
      }
      if (_cancelled.remove(cancelKey)) return;
      await flush();
      await reply(PleyaShareRelayFrame(id: frame.id, kind: 'end'));
    } catch (e) {
      appLogger.d('PleyaShare: relay request failed', error: e);
      _acks.remove(cancelKey);
      try {
        await reply(PleyaShareRelayFrame(id: frame.id, kind: 'err'));
      } catch (_) {}
    } finally {
      _cancelled.remove(cancelKey);
    }
  }
}
