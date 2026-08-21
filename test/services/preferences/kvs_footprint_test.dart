import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/preferences/preference_sync_scope.dart';

/// Does keeping v1 frozen alongside v2 fit in the key-value store?
///
/// `NSUbiquitousKeyValueStore` gives one megabyte for everything, so "we now
/// hold two copies of the settings" is a claim that needs a number rather than
/// a shrug. It is measured here on a deliberately unkind account: many servers,
/// many libraries, long identifiers.
///
/// Why this is nothing like dual-write. Frozen v1 does not grow: no v2 client
/// writes it, so its size is whatever the last old client left and it only ever
/// shrinks as those clients disappear. Dual-write would have both copies
/// growing together, forever.
void main() {
  // KVS total, all keys and values together.
  const int kvsTotalBytes = 1024 * 1024;

  // A realistic worst case rather than a comfortable one:
  // - a Plex machine identifier is 40 hex characters;
  // - a Plex Home user UUID is 32;
  // - a heavy account: 4 servers, 12 libraries each.
  const String plexMachineId = '0123456789abcdef0123456789abcdef01234567';
  const String homeUuid = '6f1d2b3c4e5a4b7c8d9e0f1a2b3c4d5e';
  const int servers = 4;
  const int librariesPerServer = 12;
  const int globalPrefs = 70; // the registered global preferences, generously

  int bytesOf(String key, String value) => utf8.encode(key).length + utf8.encode(value).length;

  String typed(String type, Object? value) => json.encode({'type': type, 'value': value});

  List<String> libraryKeys() => [
    for (var s = 0; s < servers; s++)
      for (var l = 0; l < librariesPerServer; l++) '$plexMachineId$s:$l',
  ];

  /// v1: flat base keys, bare typed values.
  int v1Footprint() {
    var total = 0;
    for (var i = 0; i < globalPrefs; i++) {
      total += bytesOf('a_reasonably_long_preference_name_$i', typed('int', 42));
    }
    final libs = libraryKeys();
    total += bytesOf('hidden_libraries', typed('string', json.encode(libs)));
    total += bytesOf('library_order', typed('string', json.encode(libs)));
    for (final lib in libs) {
      total += bytesOf('library_sort_$lib', typed('string', '{"key":"titleSort","descending":false}'));
      total += bytesOf('library_grouping_$lib', typed('string', 'movies'));
      total += bytesOf('library_tab_$lib', typed('string', 'Recommended'));
    }
    return total;
  }

  /// v2: namespaced keys, the same values. The envelope is not on the wire yet
  /// for scalars, so this measures the key growth, which is the part that
  /// worried us.
  int v2Footprint() {
    const prefix = PreferenceSyncScope.cloudNamespacePrefix;
    var total = 0;
    for (var i = 0; i < globalPrefs; i++) {
      total += bytesOf('${prefix}global/a_reasonably_long_preference_name_$i', typed('int', 42));
    }
    final libs = libraryKeys();
    final profilePrefix = '${prefix}profile/$homeUuid/';
    total += bytesOf('${profilePrefix}hidden_libraries', typed('string', json.encode(libs)));
    total += bytesOf('${profilePrefix}library_order', typed('string', json.encode(libs)));
    for (final lib in libs) {
      total += bytesOf('${profilePrefix}library_sort_$lib', typed('string', '{"key":"titleSort","descending":false}'));
      total += bytesOf('${profilePrefix}library_grouping_$lib', typed('string', 'movies'));
      total += bytesOf('${profilePrefix}library_tab_$lib', typed('string', 'Recommended'));
    }
    return total;
  }

  test('frozen v1 plus v2 fits the KVS budget with room to spare', () {
    final v1 = v1Footprint();
    final v2 = v2Footprint();
    final combined = v1 + v2;

    // Printed so the number is in the record, not only in an assertion.
    // ignore: avoid_print
    print('KVS footprint: v1 frozen ${v1 ~/ 1024} KB + v2 ${v2 ~/ 1024} KB = ${combined ~/ 1024} KB of 1024 KB');

    expect(combined, lessThan(kvsTotalBytes), reason: 'the cutover must not itself be a quota failure');
    expect(
      combined,
      lessThan(kvsTotalBytes ~/ 2),
      reason: 'and it should leave at least half the store free, not squeak in',
    );
  });

  test('the v2 key prefix is what grows, and the growth is bounded', () {
    final v1 = v1Footprint();
    final v2 = v2Footprint();

    expect(v2, greaterThan(v1), reason: 'namespacing costs bytes; the point is knowing how many');
    expect(
      (v2 - v1) / v1,
      lessThan(1.0),
      reason: 'the prefix must not more than double the payload on a heavy account',
    );
  });

  test('a single profile-scoped value stays under the per-value cap', () {
    const prefix = PreferenceSyncScope.cloudNamespacePrefix;
    const perValueCap = 100 * 1024;
    final libs = libraryKeys();
    final biggest = bytesOf('${prefix}profile/$homeUuid/hidden_libraries', typed('string', json.encode(libs)));

    expect(biggest, lessThan(perValueCap));
  });

  test('frozen v1 is bounded by what already exists, so it cannot grow after the cutover', () {
    // Nothing in the v2 client writes a flat key, which is what makes the
    // combined figure a ceiling rather than a starting point. The contract is
    // enforced by v2_cutover_test.dart; this records why the budget holds.
    final v1 = v1Footprint();
    expect(v1, greaterThan(0));
    expect(
      v1 + v2Footprint(),
      lessThan(kvsTotalBytes),
      reason: 'the ceiling, not a trend: no v2 write ever adds to the v1 half',
    );
  });
}
