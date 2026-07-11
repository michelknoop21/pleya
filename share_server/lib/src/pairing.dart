import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

/// Pairing/auth crypto — wire-compatible with the app's
/// `lib/services/pleya_share/pleya_share_pairing.dart`. Keep in sync.
class PleyaSharePairing {
  PleyaSharePairing._();

  static final _hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: 32);
  static final _aesGcm = AesGcm.with256bits();
  static final _random = Random.secure();

  static String generatePairCode() => (_random.nextInt(900000) + 100000).toString();

  static List<int> randomBytes(int length) => List<int>.generate(length, (_) => _random.nextInt(256));

  static Future<List<int>> derivePairingKey(String code, List<int> salt) async {
    final key = await _hkdf.deriveKey(
      secretKey: SecretKey(utf8.encode(code)),
      nonce: salt,
      info: utf8.encode('pleya-share-pair-v1'),
    );
    return key.extractBytes();
  }

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

  static Future<List<int>> deriveSessionKey(List<int> key, List<int> hostNonce, List<int> clientNonce) async {
    final derived = await _hkdf.deriveKey(
      secretKey: SecretKey(key),
      nonce: [...hostNonce, ...clientNonce],
      info: utf8.encode('pleya-share-session-v1'),
    );
    return derived.extractBytes();
  }

  static Future<String> encryptPayload(List<int> sessionKey, Map<String, Object?> payload) async {
    final nonce = randomBytes(12);
    final box = await _aesGcm.encrypt(utf8.encode(jsonEncode(payload)), secretKey: SecretKey(sessionKey), nonce: nonce);
    return base64Encode([...nonce, ...box.cipherText, ...box.mac.bytes]);
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

/// Per-IP failed-attempt rate limiter (5 failures → 30s lockout).
class PairingRateLimiter {
  static const int maxFailures = 5;
  static const Duration lockout = Duration(seconds: 30);

  final Map<String, ({int failures, DateTime lastFailure})> _state = {};

  bool isLockedOut(String ip) {
    final entry = _state[ip];
    if (entry == null || entry.failures < maxFailures) return false;
    if (DateTime.now().difference(entry.lastFailure) > lockout) {
      _state.remove(ip);
      return false;
    }
    return true;
  }

  void recordFailure(String ip) {
    final entry = _state[ip];
    _state[ip] = (failures: (entry?.failures ?? 0) + 1, lastFailure: DateTime.now());
  }

  void reset(String ip) => _state.remove(ip);
}
