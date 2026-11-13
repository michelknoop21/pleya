import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../utils/app_logger.dart';
import '../utils/udp_broadcast_sockets.dart';

/// A Pleya Server that answered the probe on the home network.
///
/// Found is not trusted: this is an address to try and a name to show, and
/// nothing else. [id] is what the server claims; the add screen compares it
/// with `server.id` from `GET /info` before it shows a sign-in form.
class DiscoveredPleyaServer {
  final String address;
  final String id;
  final String name;

  const DiscoveredPleyaServer({required this.address, required this.id, required this.name});
}

/// Finds Pleya Servers on the local network (protocol chapter 5.1).
///
/// One UDP broadcast per interface, the same shape as the Jellyfin discovery:
/// two rounds 350 ms apart, then a listening window. A server only answers
/// when its operator switched discovery on, so an empty result is normal.
class PleyaServerLanDiscoveryService {
  static const int discoveryPort = 48635;
  static const String discoveryMessage = 'who is PleyaServer?';

  /// The server keeps its reply under this; anything larger is not a reply.
  static const int maxReplyBytes = 512;

  static const String _app = 'pleya-server';
  static const int _version = 1;

  Future<List<DiscoveredPleyaServer>> discover({
    Duration responseWindow = const Duration(milliseconds: 1300),
    InternetAddress? broadcastAddress,
    int port = discoveryPort,
  }) async {
    UdpBroadcastSocketSet? socketSet;
    final discovered = <String, DiscoveredPleyaServer>{};
    try {
      socketSet = await UdpBroadcastSockets.bind();
      socketSet.listen((datagram) {
        final server = parseDiscoveryResponse(datagram.data, datagram.address);
        if (server == null) return;
        discovered.putIfAbsent(server.id, () => server);
      }, debugLabel: 'Pleya Server LAN discovery');

      final packet = utf8.encode(discoveryMessage);
      final target = broadcastAddress ?? UdpBroadcastSockets.limitedBroadcastAddress;
      socketSet.send(packet, target, port);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      socketSet.send(packet, target, port);
      await Future<void>.delayed(responseWindow);
    } catch (e, st) {
      appLogger.w('Pleya Server LAN discovery failed', error: e, stackTrace: st);
    } finally {
      await socketSet?.close();
    }
    return sortDiscoveredServers(discovered.values);
  }

  static List<DiscoveredPleyaServer> sortDiscoveredServers(Iterable<DiscoveredPleyaServer> servers) {
    final sorted = servers.toList()
      ..sort((a, b) {
        final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        if (name != 0) return name;
        final address = a.address.compareTo(b.address);
        if (address != 0) return address;
        return a.id.compareTo(b.id);
      });
    return List.unmodifiable(sorted);
  }

  /// Turns one datagram into a server, or null when it is not a reply this
  /// build understands.
  ///
  /// The address comes from [sender], the source of the datagram, plus the
  /// `scheme` and `port` in the reply: a server in a container does not know
  /// its own LAN address. Nothing in the reply can name another host: an
  /// answer on the network could otherwise send a sign-in anywhere.
  static DiscoveredPleyaServer? parseDiscoveryResponse(List<int> data, InternetAddress sender) {
    if (data.isEmpty || data.length > maxReplyBytes) return null;
    try {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['app'] != _app || decoded['v'] != _version) return null;

      final id = _text(decoded['id']);
      if (id == null) return null;

      final address = _senderUrl(sender, decoded['scheme'], decoded['port']);
      if (address == null) return null;

      return DiscoveredPleyaServer(address: address, id: id, name: _text(decoded['name']) ?? 'Pleya Server');
    } catch (_) {
      return null;
    }
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _senderUrl(InternetAddress sender, Object? scheme, Object? port) {
    if (scheme != 'http' && scheme != 'https') return null;
    if (port is! int || port < 1 || port > 65535) return null;
    final host = sender.type == InternetAddressType.IPv6 ? '[${sender.address}]' : sender.address;
    return '$scheme://$host:$port';
  }
}
