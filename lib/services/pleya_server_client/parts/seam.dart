part of '../../pleya_server_client.dart';

/// What the shell provides to the parts.
///
/// Declared in one place rather than repeated per part, so the three feature
/// mixins agree on the signature by construction instead of by care. A part
/// that needs something new adds it here, and the compiler points at the shell
/// until it is there.
mixin _PleyaServerRequests {
  ServerId get serverId;
  String? get serverName;
  PleyaServerConnection get connection;
  PleyaServerSession get _session;
  PleyaServerCursorLedger get _cursors;

  /// Capabilities as the server last reported them. Every call in a part gates
  /// on this: an endpoint the server says it does not have is not worth a
  /// round-trip, and the answer would be a 404 the UI has to interpret.
  PleyaCapabilities get wireCapabilities;

  /// GET a protocol path and hand back its JSON object, or null.
  Future<Map<String, dynamic>?> _getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
    Duration? timeout,
    AbortController? abort,
  });
}
