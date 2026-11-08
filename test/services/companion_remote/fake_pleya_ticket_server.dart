import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:pleya/models/pleya_server/pleya_wire_companion.dart';
import 'package:pleya/services/companion_remote/pleya_companion_identity.dart';

String b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// Signs companion tickets the way `auth.MintCompanionTicket` does on the
/// server: `plc1.<payload>.<Ed25519 over "plc1.<payload>">` (DEC-XXX).
class FakePleyaTicketServer {
  FakePleyaTicketServer._(this.serverId, this._key, this.publicKey, this.keyId);

  static Future<FakePleyaTicketServer> create(String serverId, {int seed = 1}) async {
    final key = await Ed25519().newKeyPairFromSeed(List.filled(32, seed));
    final pub = (await key.extractPublicKey()).bytes;
    return FakePleyaTicketServer._(serverId, key, b64(pub), b64(crypto.sha256.convert(pub).bytes.take(8).toList()));
  }

  final String serverId;
  final SimpleKeyPair _key;
  final String publicKey;
  final String keyId;

  /// What the server hands the device of [userId]: always a ticket about
  /// that user, whatever the device would like.
  PleyaTicketFetch fetchFor(String userId, {Duration ttl = const Duration(minutes: 10), DateTime? issuedAt}) =>
      (deviceKey) async {
        final iat = issuedAt ?? DateTime.now();
        final exp = iat.add(ttl);
        final payload = {
          'kid': keyId,
          'srv': serverId,
          'sub': userId,
          'iat': iat.millisecondsSinceEpoch ~/ 1000,
          'exp': exp.millisecondsSinceEpoch ~/ 1000,
          'cnf': deviceKey,
        };
        final body = 'plc1.${b64(utf8.encode(jsonEncode(payload)))}';
        final sig = await Ed25519().sign(utf8.encode(body), keyPair: _key);
        return PleyaCompanionTicket(
          ticket: '$body.${b64(sig.bytes)}',
          expiresAt: exp,
          keyId: keyId,
          publicKey: publicKey,
        );
      };

  PleyaCompanionIdentity identityFor(String userId) =>
      PleyaCompanionIdentity(serverId: serverId, fetch: fetchFor(userId));
}
