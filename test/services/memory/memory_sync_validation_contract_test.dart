import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/memory/memory_validation.dart';

void main() {
  test('client and server share the same owned-fact and validation vectors', () {
    final vectors =
        jsonDecode(File('pleya_server/internal/memory/testdata/validation.json').readAsStringSync()) as List;
    for (final raw in vectors) {
      final row = raw as Map<String, dynamic>;
      expect(checkMemoryValue(row['value'] as String).value != null, row['valid'], reason: row['value'] as String);
    }
  });
}
