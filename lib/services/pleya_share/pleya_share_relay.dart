import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../utils/app_logger.dart';
import '../base_peer_service.dart';
import 'pleya_share_pairing.dart';

/// Relay transport for Pleya Share: lets a paired guest reach its host over
/// the internet (the Watch Together relay at ice.pleya.app) when no LAN path
/// works. Both sides bridge to the existing plain-HTTP protocol — the host
/// listener replays frames against its own loopback server, the guest proxy
/// serves frames back as loopback HTTP — so the wire protocol, auth, and
/// Range streaming are unchanged.
///
/// Every frame payload is AES-256-GCM sealed with a key derived from the
/// pairSecret (or, during first pairing, from the code+salt in the QR); the
/// relay only sees room routing and sealed blobs.
class PleyaShareRelay {
  PleyaShareRelay._();

  /// Same relay/signalling server Watch Together uses.
  static const String defaultBaseUrl = String.fromEnvironment('PLEYA_ICE_BASE', defaultValue: 'https://ice.pleya.app');

  static String relayUrl(String baseUrl) {
    final wsBase = baseUrl.replaceFirst(RegExp(r'^https://'), 'wss://').replaceFirst(RegExp(r'^http://'), 'ws://');
    return '$wsBase/relay';
  }

  static String roomId(String relayHostId) => 'ps-$relayHostId';
  static String hostPeerId(String relayHostId) => 'ps-host-$relayHostId';

  /// Chunk size for /stream bytes inside data frames (base64 in JSON).
  static const int chunkSize = 64 * 1024;

  /// Send window: chunks in flight before the sender waits for an ack.
  static const int ackWindow = 8;
}

/// One request/response frame on the relay, sealed end-to-end.
///
/// Kinds: `req` (method/path/body/range) → `resp` (status, headers) →
/// zero or more `data` (b64 chunk) → `end`. `ack` flows back from the
/// receiver every [PleyaShareRelay.ackWindow] chunks. `err` aborts.
class PleyaShareRelayFrame {
  final String id;
  final String kind;
  final Map<String, Object?> fields;

  const PleyaShareRelayFrame({required this.id, required this.kind, this.fields = const {}});

  Map<String, Object?> toJson() => {'id': id, 'k': kind, ...fields};

  static PleyaShareRelayFrame fromJson(Map<String, Object?> json) => PleyaShareRelayFrame(
    id: json['id'] as String,
    kind: json['k'] as String,
    fields: Map<String, Object?>.from(json)..removeWhere((key, _) => key == 'id' || key == 'k'),
  );
}

/// Codec sealing frames with the relay key; the outer envelope only carries
/// what the host needs to pick the right key (pairId, or pair:true for the
/// code-pairing flow).
class PleyaShareRelaySealer {
  final List<int> relayKey;

  const PleyaShareRelaySealer(this.relayKey);

  static Future<PleyaShareRelaySealer> fromSecret(List<int> secret) async =>
      PleyaShareRelaySealer(await PleyaSharePairing.deriveRelayKey(secret));

  Future<Map<String, Object?>> seal(PleyaShareRelayFrame frame, {String? pairId, bool pairing = false}) async => {
    'ps': 1,
    'pairId': ?pairId,
    if (pairing) 'pair': true,
    'sealed': await PleyaSharePairing.encryptPayload(relayKey, frame.toJson()),
  };

  /// Throws on tampered/foreign frames — callers treat that as "not for us".
  Future<PleyaShareRelayFrame> unseal(Map<String, dynamic> envelope) async =>
      PleyaShareRelayFrame.fromJson(await PleyaSharePairing.decryptPayload(relayKey, envelope['sealed'] as String));
}

/// Thin wrapper over the Watch Together relay WebSocket protocol: join or
/// create a room, sendTo peers, surface incoming `message` payloads.
/// Keepalive pings (15s/30s, same policy as Watch Together) detect NAT/idle
/// drops the socket would otherwise never notice; a pong timeout closes the
/// socket so the owner's retry path takes over.
class PleyaShareRelaySocket with KeepaliveMixin {
  final String baseUrl;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final _messages = StreamController<({String from, Map<String, dynamic> envelope})>.broadcast();
  final Set<String> peers = {};
  void Function(String peerId)? onPeerJoined;
  void Function()? onClosed;

  PleyaShareRelaySocket({String? baseUrl}) : baseUrl = baseUrl ?? PleyaShareRelay.defaultBaseUrl;

  Stream<({String from, Map<String, dynamic> envelope})> get messages => _messages.stream;
  bool get isConnected => _channel != null;

  @override
  Duration get pingInterval => const Duration(seconds: 15);
  @override
  Duration get pongTimeout => const Duration(seconds: 30);

  @override
  void sendPing() => _send({'type': 'ping'});

  @override
  void onPongTimeout() {
    appLogger.d('PleyaShare relay: pong timeout — closing socket');
    try {
      _channel?.sink.close();
    } catch (_) {}
  }

  /// Connect and create (host) or join (guest) [room] as [peerId]. Completes
  /// when the relay confirms, throws on relay error/timeout.
  Future<void> connect({required String room, required String peerId, required bool create}) async {
    final channel = WebSocketChannel.connect(Uri.parse(PleyaShareRelay.relayUrl(baseUrl)));
    await channel.ready;
    _channel = channel;
    final setup = Completer<void>();
    _subscription = channel.stream.listen(
      (data) => _handle(data as String, setup),
      onError: (Object e) {
        if (!setup.isCompleted) setup.completeError(e);
        _teardown();
      },
      onDone: () {
        if (!setup.isCompleted) {
          setup.completeError(StateError('relay closed during setup'));
        }
        _teardown();
      },
    );
    _send({'type': create ? 'create' : 'join', 'sessionId': room, 'peerId': peerId});
    await setup.future.timeout(const Duration(seconds: 10));
    startKeepalive();
  }

  void _handle(String raw, Completer<void> setup) {
    resetPongTimer();
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      switch (msg['type'] as String?) {
        case 'created':
          if (!setup.isCompleted) setup.complete();
        case 'joined':
          peers.addAll(((msg['peers'] as List?)?.cast<String>()) ?? const []);
          if (!setup.isCompleted) setup.complete();
        case 'peerJoined':
          final peerId = msg['peerId'] as String;
          peers.add(peerId);
          onPeerJoined?.call(peerId);
        case 'peerLeft':
          peers.remove(msg['peerId'] as String);
        case 'message':
          final from = msg['from'] as String?;
          final payload = msg['payload'];
          if (from != null && payload is Map<String, dynamic> && payload['ps'] == 1) {
            _messages.add((from: from, envelope: payload));
          }
        case 'error':
          final error = StateError('relay error: ${msg['code']} ${msg['message']}');
          if (!setup.isCompleted) setup.completeError(error);
          appLogger.d('PleyaShare relay: $error');
      }
    } catch (e) {
      appLogger.d('PleyaShare relay: bad server message', error: e);
    }
  }

  void sendTo(String peerId, Map<String, Object?> envelope) =>
      _send({'type': 'sendTo', 'to': peerId, 'payload': envelope});

  void _send(Map<String, Object?> msg) {
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (e) {
      appLogger.d('PleyaShare relay: send failed', error: e);
    }
  }

  void _teardown() {
    stopKeepalive();
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    peers.clear();
    onClosed?.call();
  }

  Future<void> close() async {
    stopKeepalive();
    final channel = _channel;
    _channel = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    onClosed = null;
    try {
      await channel?.sink.close();
    } catch (_) {}
    peers.clear();
  }

  void dispose() {
    unawaited(close());
    _messages.close();
  }
}
