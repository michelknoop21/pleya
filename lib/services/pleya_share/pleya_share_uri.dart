import 'pleya_share_protocol.dart';

/// The `pleya-share://pair?…` deep link encoded in the host's QR code so a guest
/// can pair by scanning instead of typing the 6-digit code and host IP.
///
/// Carries everything the join flow needs: candidate host IPs, the port, the
/// one-time pairing code, and the salt. Scanning fills the join form and pairs
/// in one tap via the existing `PleyaShareChannel.pair`.
class PleyaSharePairUri {
  final List<String> ips;
  final int port;
  final String code;
  final String saltB64;

  const PleyaSharePairUri({required this.ips, required this.port, required this.code, required this.saltB64});

  static const String scheme = 'pleya-share';
  static const String host = 'pair';

  String build() => Uri(
    scheme: scheme,
    host: host,
    queryParameters: {'ips': ips.join(','), 'port': '$port', 'code': code, 'salt': saltB64},
  ).toString();

  /// Parse a scanned string, or null when it isn't a valid pair link (so the
  /// scanner can ignore unrelated QR codes).
  static PleyaSharePairUri? tryParse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != scheme || uri.host != host) return null;
    final q = uri.queryParameters;
    final code = q['code'];
    final salt = q['salt'];
    if (code == null || !RegExp(r'^\d{6}$').hasMatch(code) || salt == null || salt.isEmpty) return null;
    final ips = (q['ips'] ?? '').split(',').where((s) => s.isNotEmpty).toList();
    final port = int.tryParse(q['port'] ?? '') ?? PleyaShareProtocol.sharePort;
    if (ips.isEmpty) return null;
    return PleyaSharePairUri(ips: ips, port: port, code: code, saltB64: salt);
  }
}
