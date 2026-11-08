import 'pleya_wire_parse.dart';

/// `CompanionTicket` (DEC-XXX): a short-lived, server-signed statement of who
/// this device's user is, bound to the device key it was asked with. A host
/// on the LAN checks it with [publicKey] without asking the server.
class PleyaCompanionTicket {
  const PleyaCompanionTicket({
    required this.ticket,
    required this.expiresAt,
    required this.keyId,
    required this.publicKey,
  });

  final String ticket;
  final DateTime expiresAt;
  final String keyId;

  /// The server's Ed25519 public key, base64url without padding.
  final String publicKey;

  factory PleyaCompanionTicket.fromJson(Map<String, dynamic> json) => PleyaCompanionTicket(
    ticket: str(json, 'ticket'),
    expiresAt: timestamp(json, 'expires_at'),
    keyId: str(json, 'key_id'),
    publicKey: str(json, 'public_key'),
  );

  /// `CompanionTicketRequest`.
  static Map<String, dynamic> request(String deviceKey) => {'device_key': deviceKey};
}
