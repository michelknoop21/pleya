import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

/// Crypto for Pleya Share pairing and reconnect authentication.
///
/// Pairing: the host shows a 6-digit code; both sides derive
/// `pairingKey = HKDF(code, salt)` and prove knowledge via an HMAC
/// challenge-response. On success the host hands the guest a long-lived
/// 32-byte `pairSecret` (encrypted with a session key derived from the
/// pairing key + both nonces). Reconnects run the same challenge-response
/// against the stored pairSecret — no code needed.
class PleyaSharePairing {
  PleyaSharePairing._();

  static final _hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: 32);
  static final _aesGcm = AesGcm.with256bits();
  static final _random = Random.secure();

  static String generatePairCode() => (_random.nextInt(900000) + 100000).toString();

  static List<int> randomBytes(int length) => List<int>.generate(length, (_) => _random.nextInt(256));

  /// Derive the ephemeral pairing key from the displayed code + host salt.
  static Future<List<int>> derivePairingKey(String code, List<int> salt) async {
    final key = await _hkdf.deriveKey(
      secretKey: SecretKey(utf8.encode(code)),
      nonce: salt,
      info: utf8.encode('pleya-share-pair-v1'),
    );
    return key.extractBytes();
  }

  /// HMAC auth tag over the handshake transcript; used both for code pairing
  /// (key = pairingKey) and reconnect (key = pairSecret).
  static String computeAuthTag({
    required List<int> key,
    required List<int> hostNonce,
    required List<int> clientNonce,
    required String context,
  }) {
    final msg = <int>[...utf8.encode('pleya-share-auth-v1|$context|'), ...hostNonce, ...clientNonce];
    return crypto.Hmac(crypto.sha256, key).convert(msg).toString();
  }

  static bool verifyAuthTag({
    required String received,
    required List<int> key,
    required List<int> hostNonce,
    required List<int> clientNonce,
    required String context,
  }) {
    final expected = computeAuthTag(key: key, hostNonce: hostNonce, clientNonce: clientNonce, context: context);
    return constantTimeEquals(expected, received);
  }

  /// Key for E2E-encrypting relay frames, derived from the pairSecret
  /// (reconnect) or the pairing key (first pairing). The relay server only
  /// ever sees sealed frames plus room-routing metadata.
  static Future<List<int>> deriveRelayKey(List<int> secret) async {
    final derived = await _hkdf.deriveKey(
      secretKey: SecretKey(secret),
      nonce: utf8.encode('relay'),
      info: utf8.encode('pleya-share-relay-v1'),
    );
    return derived.extractBytes();
  }

  /// Session key for encrypting the pairing response payload.
  static Future<List<int>> deriveSessionKey(List<int> key, List<int> hostNonce, List<int> clientNonce) async {
    final derived = await _hkdf.deriveKey(
      secretKey: SecretKey(key),
      nonce: [...hostNonce, ...clientNonce],
      info: utf8.encode('pleya-share-session-v1'),
    );
    return derived.extractBytes();
  }

  /// AES-256-GCM with a random 12-byte nonce prepended to the ciphertext.
  static Future<String> encryptPayload(List<int> sessionKey, Map<String, Object?> payload) async {
    final nonce = randomBytes(12);
    final box = await _aesGcm.encrypt(utf8.encode(jsonEncode(payload)), secretKey: SecretKey(sessionKey), nonce: nonce);
    return base64Encode([...nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  static Future<Map<String, Object?>> decryptPayload(List<int> sessionKey, String encoded) async {
    final data = base64Decode(encoded);
    if (data.length < 12 + 16) throw ArgumentError('Encrypted payload too short');
    final box = SecretBox(
      data.sublist(12, data.length - 16),
      nonce: data.sublist(0, 12),
      mac: Mac(data.sublist(data.length - 16)),
    );
    final plain = await _aesGcm.decrypt(box, secretKey: SecretKey(sessionKey));
    return jsonDecode(utf8.decode(plain)) as Map<String, Object?>;
  }

  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}

/// Per-IP failed-attempt rate limiter (5 failures → 30s lockout), matching
/// the companion-remote policy.
class PairingRateLimiter {
  static const int maxFailures = 5;
  static const Duration lockout = Duration(seconds: 30);

  final Map<String, ({int failures, DateTime lastFailure})> _state = {};

  bool isLockedOut(String ip, {DateTime? now}) {
    final entry = _state[ip];
    if (entry == null || entry.failures < maxFailures) return false;
    if ((now ?? DateTime.now()).difference(entry.lastFailure) > lockout) {
      _state.remove(ip);
      return false;
    }
    return true;
  }

  void recordFailure(String ip, {DateTime? now}) {
    final entry = _state[ip];
    _state[ip] = (failures: (entry?.failures ?? 0) + 1, lastFailure: now ?? DateTime.now());
  }

  void reset(String ip) => _state.remove(ip);
}
