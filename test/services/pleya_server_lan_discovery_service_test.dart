import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/pleya_server_lan_discovery_service.dart';

List<int> _reply(Map<String, Object?> fields) => utf8.encode(jsonEncode(fields));

Map<String, Object?> _valid([Map<String, Object?> extra = const {}]) => {
  'app': 'pleya-server',
  'v': 1,
  'id': 'srv-1',
  'name': 'Thuis',
  'port': 8832,
  'scheme': 'http',
  ...extra,
};

void main() {
  final sender = InternetAddress('192.168.1.20');
  DiscoveredPleyaServer? parse(Map<String, Object?> fields) =>
      PleyaServerLanDiscoveryService.parseDiscoveryResponse(_reply(fields), sender);

  group('PleyaServerLanDiscoveryService.parseDiscoveryResponse', () {
    test('builds the address from the sender, the scheme and the port', () {
      final server = parse(_valid());

      expect(server, isNotNull);
      expect(server!.address, 'http://192.168.1.20:8832');
      expect(server.id, 'srv-1');
      expect(server.name, 'Thuis');
    });

    test('a url in the reply never replaces the sender', () {
      for (final url in [
        'https://nas.thuis.example:8443/',
        'http://192.168.1.20:8832@evil.example.com',
        'https://evil.example.com/a/b?x=1#f',
      ]) {
        expect(parse(_valid({'url': url}))!.address, 'http://192.168.1.20:8832', reason: url);
      }
    });

    test('skips another app and another version', () {
      expect(parse(_valid({'app': 'jellyfin'})), isNull);
      expect(parse(_valid({'v': 2})), isNull);
      expect(parse(_valid({'v': '1'})), isNull);
    });

    test('skips a reply without an id, a port or a known scheme', () {
      expect(parse(_valid({'id': ' '})), isNull);
      expect(parse(_valid({'port': 0})), isNull);
      expect(parse(_valid({'port': 70000})), isNull);
      expect(parse(_valid({'port': '8832'})), isNull);
      expect(parse(_valid({'scheme': 'ftp'})), isNull);
    });

    test('ignores unknown fields and names a nameless server', () {
      final server = parse(_valid({'name': '', 'later': true}));

      expect(server!.name, 'Pleya Server');
    });

    test('skips what is not a small JSON object', () {
      expect(PleyaServerLanDiscoveryService.parseDiscoveryResponse(utf8.encode('not json'), sender), isNull);
      expect(PleyaServerLanDiscoveryService.parseDiscoveryResponse(utf8.encode('[1]'), sender), isNull);
      expect(PleyaServerLanDiscoveryService.parseDiscoveryResponse(const [], sender), isNull);
      expect(parse(_valid({'name': 'x' * 600})), isNull);
    });

    test('puts an IPv6 sender in brackets', () {
      final server = PleyaServerLanDiscoveryService.parseDiscoveryResponse(
        _reply(_valid()),
        InternetAddress('fe80::1'),
      );

      expect(server!.address, 'http://[fe80::1]:8832');
    });
  });

  test('sorts by name, then address', () {
    final sorted = PleyaServerLanDiscoveryService.sortDiscoveredServers(const [
      DiscoveredPleyaServer(address: 'http://192.168.1.30:8832', id: 'c', name: 'Zolder'),
      DiscoveredPleyaServer(address: 'http://192.168.1.20:8832', id: 'b', name: 'thuis'),
      DiscoveredPleyaServer(address: 'http://192.168.1.10:8832', id: 'a', name: 'Thuis'),
    ]);

    expect(sorted.map((s) => s.id), ['a', 'b', 'c']);
  });

  // Code review of 14 November 2026: deduplicating on the claimed id let a
  // copy that answered first hide the real server.
  test('discover keeps two servers that claim the same id from two addresses', () async {
    final own = await _ownIPv4();
    if (own == null) {
      markTestSkipped('no non-loopback IPv4 interface');
      return;
    }
    final probe = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final copy = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final sub = probe.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? d;
      while ((d = probe.receive()) != null) {
        // The real one answers from the probed socket, the copy from another
        // port with the same id and another advertised port.
        probe.send(_reply(_valid({'port': 8832})), d!.address, d.port);
        copy.send(_reply(_valid({'port': 9999})), d.address, d.port);
      }
    });
    addTearDown(() async {
      await sub.cancel();
      probe.close();
      copy.close();
    });

    final found = await PleyaServerLanDiscoveryService().discover(
      responseWindow: const Duration(milliseconds: 300),
      broadcastAddress: own,
      port: probe.port,
    );

    expect(found.map((s) => s.address).toSet(), {'http://${own.address}:8832', 'http://${own.address}:9999'});
    expect(found.every((s) => s.id == 'srv-1'), isTrue);
  });

  // The real socket path, against a stand-in that answers like the server
  // does. Sent to this machine's own address because a test may not broadcast
  // onto whatever network the machine happens to be on.
  test('discover finds a server that answers the probe and no one else', () async {
    final own = await _ownIPv4();
    if (own == null) {
      markTestSkipped('no non-loopback IPv4 interface');
      return;
    }
    final server = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final probes = <String>[];
    final sub = server.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? d;
      while ((d = server.receive()) != null) {
        probes.add(utf8.decode(d!.data));
        if (utf8.decode(d.data) != PleyaServerLanDiscoveryService.discoveryMessage) continue;
        server.send(_reply(_valid({'port': 8832})), d.address, d.port);
        server.send(_reply(_valid({'app': 'something-else', 'id': 'srv-2'})), d.address, d.port);
      }
    });
    addTearDown(() async {
      await sub.cancel();
      server.close();
    });

    final found = await PleyaServerLanDiscoveryService().discover(
      responseWindow: const Duration(milliseconds: 300),
      broadcastAddress: own,
      port: server.port,
    );

    expect(probes, isNotEmpty);
    expect(found, hasLength(1), reason: 'two rounds, one server: deduplicated on id');
    expect(found.single.id, 'srv-1');
    expect(found.single.address, 'http://${own.address}:8832');
  });
}

Future<InternetAddress?> _ownIPv4() async {
  for (final interface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
    for (final address in interface.addresses) {
      if (!address.isLoopback) return address;
    }
  }
  return null;
}
