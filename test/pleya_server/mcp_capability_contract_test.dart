import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/models/pleya_server/pleya_wire.dart';

void main() {
  test('MCP-capability leest de actieve fixture en blijft uit op oudere servers', () {
    Map<String, dynamic> fixture(String name) =>
        jsonDecode(File('docs/pleya-protocol/v1/examples/$name.json').readAsStringSync()) as Map<String, dynamic>;
    expect(PleyaInfo.fromJson(fixture('info_mcp')).capabilities.mcp, isTrue);
    expect(PleyaInfo.fromJson(fixture('info')).capabilities.mcp, isFalse);
    expect(PleyaCapabilities.unknown.mcp, isFalse);
  });
}
