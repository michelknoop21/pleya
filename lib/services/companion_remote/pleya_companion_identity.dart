import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../models/pleya_server/pleya_wire_companion.dart';

/// Asks the Pleya Server for a ticket bound to [deviceKey] (base64url).
typedef PleyaTicketFetch = Future<PleyaCompanionTicket> Function(String deviceKey);

/// Who a device is on one Pleya Server, proven with a server-signed ticket
/// (DEC-XXX).
///
/// The shared secret of a Pleya Server context only says which Home; anyone
/// in the household can derive it for any member. Identity comes from here:
/// the server signs a ticket about the signed-in user (`sub`) and this
/// device's Ed25519 key (`cnf`), and the client signs the handshake
/// transcript with that key. A host accepts the claimed user only when the
/// server's signature, the server id, the expiry, `sub` and the transcript
/// signature all check out, so a member cannot pose as another member and a
/// ticket overheard on the LAN cannot be replayed.
///
/// The device key lives in memory for the life of this object; the ticket is
/// fetched when needed and again shortly before it expires. The server's
/// public key comes with every ticket, so a host learns it from its own.
class PleyaCompanionIdentity {
  PleyaCompanionIdentity({required this.serverId, required this.fetch, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final String serverId;

  /// Replaced on each rebuild, so a later fetch uses the current session.
  PleyaTicketFetch fetch;

  final DateTime Function() _now;
  static final _ed25519 = Ed25519();

  /// Clock difference tolerated between the two devices.
  static const skew = Duration(seconds: 60);
  static const _ticketPrefix = 'plc1';

  SimpleKeyPair? _device;
  String? _deviceKey;
  PleyaCompanionTicket? _ticket;
  Future<PleyaCompanionTicket>? _inflight;

  Future<PleyaCompanionTicket> _currentTicket({bool force = false}) async {
    final ticket = _ticket;
    if (!force && ticket != null && ticket.expiresAt.isAfter(_now().add(const Duration(minutes: 1)))) {
      return ticket;
    }
    return _inflight ??= () async {
      try {
        _device ??= await _ed25519.newKeyPair();
        _deviceKey ??= _b64(((await _device!.extractPublicKey())).bytes);
        return _ticket = await fetch(_deviceKey!);
      } finally {
        _inflight = null;
      }
    }();
  }

  /// Client side: the ticket and this device's signature over [transcript].
  Future<Map<String, String>> prove(List<int> transcript) async {
    final ticket = await _currentTicket();
    final signature = await _ed25519.sign(transcript, keyPair: _device!);
    return {'ticket': ticket.ticket, 'ticketSig': _b64(signature.bytes)};
  }

  /// Fetches a ticket now, so an account whose server cannot issue one gets
  /// no context and no beacon. Throws when the server cannot.
  Future<void> ensureTicket() => _currentTicket();

  /// Host side: whether [auth] proves [claimedUser] on this server for this
  /// [transcript]. False for anything the client sent that does not check
  /// out, malformed input included; throws only when this host cannot get
  /// its own ticket (the server key), which is not the client's fault.
  Future<bool> verify(Map<String, dynamic> auth, List<int> transcript, String claimedUser) async {
    final ticket = auth['ticket'];
    final ticketSig = auth['ticketSig'];
    if (ticket is! String || ticketSig is! String || claimedUser.isEmpty) return false;
    // A real ticket is a few hundred characters; this bounds what is parsed
    // before the signature is checked.
    if (ticket.length > 2048 || ticketSig.length > 128) return false;
    final parts = ticket.split('.');
    if (parts.length != 3 || parts[0] != _ticketPrefix) return false;
    final Map<String, dynamic> payload;
    final List<int> serverSig;
    final List<int> deviceSig;
    final List<int> deviceKey;
    try {
      final decoded = jsonDecode(utf8.decode(_unb64(parts[1])));
      if (decoded is! Map<String, dynamic>) return false;
      payload = decoded;
      final cnf = payload['cnf'];
      if (cnf is! String) return false;
      serverSig = _unb64(parts[2]);
      deviceSig = _unb64(ticketSig);
      deviceKey = _unb64(cnf);
    } on FormatException {
      return false;
    }
    final kid = payload['kid'];
    final exp = payload['exp'];
    final iat = payload['iat'];
    if (kid is! String || exp is! int || iat is! int) return false;
    if (serverSig.length != 64 || deviceSig.length != 64 || deviceKey.length != 32) return false;

    final serverKey = await _serverKey(kid);
    if (serverKey == null) return false;
    final signed = await _ed25519.verify(
      utf8.encode('${parts[0]}.${parts[1]}'),
      signature: Signature(serverSig, publicKey: SimplePublicKey(serverKey, type: KeyPairType.ed25519)),
    );
    if (!signed) return false;

    if (payload['srv'] != serverId || payload['sub'] != claimedUser) return false;
    final now = _now();
    if (!now.isBefore(DateTime.fromMillisecondsSinceEpoch(exp * 1000).add(skew))) return false;
    if (DateTime.fromMillisecondsSinceEpoch(iat * 1000).isAfter(now.add(skew))) return false;

    return _ed25519.verify(
      transcript,
      signature: Signature(deviceSig, publicKey: SimplePublicKey(deviceKey, type: KeyPairType.ed25519)),
    );
  }

  /// The server key for [kid], learned from this device's own ticket. An
  /// unknown kid (the server rotated) asks once for a fresh ticket.
  /// At most once a minute, so made-up kids cannot make the host hammer the
  /// server.
  Future<List<int>?> _serverKey(String kid) async {
    var ticket = await _currentTicket();
    final last = _lastForced;
    if (ticket.keyId != kid && (last == null || _now().difference(last) > const Duration(minutes: 1))) {
      _lastForced = _now();
      ticket = await _currentTicket(force: true);
    }
    return ticket.keyId == kid ? _unb64(ticket.publicKey) : null;
  }

  DateTime? _lastForced;

  static String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  static List<int> _unb64(String value) => base64Url.decode(base64Url.normalize(value));
}
