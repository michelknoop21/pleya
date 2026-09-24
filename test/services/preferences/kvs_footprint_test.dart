import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/track_language_choice.dart';
import 'package:pleya/services/preferences/preference_revision_store.dart';
import 'package:pleya/services/preferences/preference_sync_scope.dart';
import 'package:pleya/services/settings_export_service.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/track_preference_store.dart';

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

  /// What a record costs since DEC-131: the typed value plus a stamp of the
  /// shape the coordinator writes (a millisecond timestamp and a v4 uuid).
  String enveloped(String type, Object? value) =>
      json.encode({'type': type, 'value': value, 't': 1758700000000, 'd': '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e'});

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

  /// v2: namespaced keys, the same values. Measures the key growth alone; the
  /// envelope's cost has its own test below.
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

  test('the envelope on every record still leaves half the store free', () {
    var v2 = 0;
    const prefix = PreferenceSyncScope.cloudNamespacePrefix;
    for (var i = 0; i < globalPrefs; i++) {
      v2 += bytesOf('${prefix}global/a_reasonably_long_preference_name_$i', enveloped('int', 42));
    }
    final libs = libraryKeys();
    final profilePrefix = '${prefix}profile/$homeUuid/';
    v2 += bytesOf('${profilePrefix}hidden_libraries', enveloped('string', json.encode(libs)));
    v2 += bytesOf('${profilePrefix}library_order', enveloped('string', json.encode(libs)));
    for (final lib in libs) {
      v2 += bytesOf('${profilePrefix}library_sort_$lib', enveloped('string', '{"key":"titleSort","descending":false}'));
      v2 += bytesOf('${profilePrefix}library_grouping_$lib', enveloped('string', 'movies'));
      v2 += bytesOf('${profilePrefix}library_tab_$lib', enveloped('string', 'Recommended'));
    }
    // ignore: avoid_print
    print('KVS footprint with envelope: v2 ${v2 ~/ 1024} KB, plus frozen v1 ${v1Footprint() ~/ 1024} KB');
    expect(v1Footprint() + v2, lessThan(kvsTotalBytes ~/ 2));
  });

  test('tombstones for everything a reset touched and every library ever seen still fit', () {
    // Since DEC-131 a removal is a tombstone and nothing clears it. A reset
    // tombstones every resettable preference, set or not, and a library that
    // disappears keeps its per-library tombstones. So the store holds a key
    // for every key the account ever saw: here the current libraries plus as
    // many that are gone, each with their three per-library keys.
    const prefix = PreferenceSyncScope.cloudNamespacePrefix;
    final profilePrefix = '${prefix}profile/$homeUuid/';
    final tombstone = json.encode({'x': true, 't': 1758700000000, 'd': '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e'});
    final libs = libraryKeys();
    final everSeen = [...libs, for (final lib in libs) '${lib}_gone'];

    var keys = 0;
    var bytes = 0;
    void add(String key, String value) {
      keys++;
      bytes += bytesOf(key, value);
    }

    // The globals after a reset: all tombstones.
    for (var i = 0; i < globalPrefs; i++) {
      add('${prefix}global/a_reasonably_long_preference_name_$i', tombstone);
    }
    // The live per-library values of today, and tombstones for the gone ones.
    add('${profilePrefix}hidden_libraries', enveloped('string', json.encode(libs)));
    add('${profilePrefix}library_order', enveloped('string', json.encode(libs)));
    for (final lib in everSeen) {
      final gone = !libs.contains(lib);
      add('${profilePrefix}library_sort_$lib', gone ? tombstone : enveloped('string', '{"key":"titleSort"}'));
      add('${profilePrefix}library_grouping_$lib', gone ? tombstone : enveloped('string', 'movies'));
      add('${profilePrefix}library_tab_$lib', gone ? tombstone : enveloped('string', 'Recommended'));
    }

    // ignore: avoid_print
    print('KVS footprint with tombstones: $keys keys, ${bytes ~/ 1024} KB');
    expect(keys, lessThan(1024), reason: 'the store caps the number of keys at 1024');
    expect(bytes + v1Footprint(), lessThan(kvsTotalBytes ~/ 2));
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

  test('the series language map at its cap, tombstones included, stays well under the per-value cap', () {
    // The worst case the store allows: the cap of live entries, each with long
    // track and show titles and the full provenance, plus the cap of
    // tombstones, all under a real Plex Home scope and a logical series key.
    // Measured the way the coordinator sends it: typed, stamped, JSON inside
    // JSON, so every quote in the map is escaped once more.
    const perValueCap = 100 * 1024;
    const cap = TrackPreferenceStore.maxEntries;
    const scope = 'plex-home-plex.0123456789abcdef-fedcba9876543210';
    String key(String kind, int i) =>
        '$scope|show:guid:plex://show/5d9c086c46115600$kind${i.toString().padLeft(6, '0')}';
    const live = TrackLanguageChoice(
      audioLanguage: 'eng',
      audioTitle: 'English (Dolby TrueHD Atmos 7.1)',
      subtitleLanguage: 'nld',
      subtitleTitle: 'Nederlands (SDH, forced songs)',
      subtitleForced: true,
      provenance: TrackChoiceProvenance(
        title: 'The Lord of the Rings: The Rings of Power (2022)',
        posterPath: '/library/metadata/1234567/thumb/1758700000',
        serverId: plexMachineId,
        seasonNumber: 12,
        episodeNumber: 123,
        deviceName: 'Woonkamer Apple TV 4K (3e generatie)',
      ),
      updatedAt: 1758700000000,
    );
    final map = {
      for (var i = 0; i < cap; i++) key('aa', i): live,
      for (var i = 0; i < cap; i++) key('bb', i): const TrackLanguageChoice(updatedAt: 1758700000000),
    };
    final typedValue = SettingsExportService.encodeValue(SettingsService.trackLanguagePreferences.encode(map))!;
    final wire = encodeStampedRecord(typedValue, (
      at: 1758700000000,
      device: '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e',
      deleted: false,
    ));
    final bytes = utf8.encode(wire).length;

    // ignore: avoid_print
    print('track_language_preferences worst case: $cap live + $cap tombstones = ${bytes ~/ 1024} KB of 100 KB');
    expect(bytes, lessThan(perValueCap * 3 ~/ 4), reason: 'a quarter of the ceiling left for longer, non-Latin titles');
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
