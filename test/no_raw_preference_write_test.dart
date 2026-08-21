import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every preference write in `lib/` is accounted for.
///
/// Not every write has to go through [PreferenceSyncCoordinator]. Cache stamps,
/// credential blobs and migration flags have no business in a sync engine, and
/// rewriting them to raise a percentage would only make the engine harder to
/// reason about. What is not acceptable is a write nobody has classified,
/// because that is how a LAN address and a set of tracker filters ended up in
/// iCloud under the old allow-by-default rule.
///
/// So this guard demands four things of every raw write: a place in the
/// inventory, a category, a reason, and a count that changes when the file
/// does. Adding one turns this red until somebody says what it is.
enum WriteCategory {
  /// Goes through the coordinator. Only the pipeline's own plumbing is here.
  syncPreference,

  /// A real user preference that only means something on this device.
  deviceLocal,

  /// A token, session blob or key.
  secret,

  /// Caches, ETags, "already ran" markers, view state.
  runtimeCache,

  /// A copy of state the backend owns.
  backendMirror,

  /// One-time promotion of an old key or shape.
  legacyMigration,
}

class RawWriteRecord {
  const RawWriteRecord(this.category, this.count, this.reason);

  final WriteCategory category;

  /// How many raw write or remove calls the file is expected to contain.
  /// A changed count is the signal, so it has to be exact.
  final int count;

  final String reason;
}

void main() {
  // Ordered by the pipeline first, then by what the writes actually are.
  const inventory = <String, RawWriteRecord>{
    // -- The pipeline itself. These ARE the choke point.
    'lib/services/base_shared_preferences_service.dart': RawWriteRecord(
      WriteCategory.syncPreference,
      6,
      'the typed write helpers and the nullable-pref remove; every one of them ends in notifyMutation',
    ),
    'lib/services/preferences/preference_sync_coordinator.dart': RawWriteRecord(
      WriteCategory.syncPreference,
      4,
      'applies remote entries and persists its own revision metadata; re-reporting those would echo',
    ),
    'lib/services/preferences/preference_device_id.dart': RawWriteRecord(
      WriteCategory.runtimeCache,
      1,
      'the per-installation id revisions are signed with; generated once, registered as runtime cache '
      'so it can never sync',
    ),
    'lib/services/preferences/preference_legacy_bootstrap.dart': RawWriteRecord(
      WriteCategory.legacyMigration,
      2,
      'the marker that stops the one-time v1 cloud import running twice; local bookkeeping about a '
      'migration, registered as runtime cache',
    ),
    'lib/services/preferences/preference_quarantine.dart': RawWriteRecord(
      WriteCategory.runtimeCache,
      2,
      'the record of v1 cloud keys whose owning profile cannot be established; local bookkeeping about '
      'the cloud, not a preference',
    ),
    'lib/services/settings_export_service.dart': RawWriteRecord(
      WriteCategory.syncPreference,
      5,
      'writeTyped is the shared typed-write primitive used by import and remote apply',
    ),
    'lib/services/storage_service.dart': RawWriteRecord(
      WriteCategory.runtimeCache,
      13,
      'credentials, the legacy migration slots, and the per-server and per-profile caches; the library '
      'and home families all moved onto _writePreference/_removePreference, and so did the active-profile '
      'key, because switching profiles is a reconcile trigger',
    ),
    'lib/services/settings_service.dart': RawWriteRecord(
      WriteCategory.legacyMigration,
      12,
      'read-path promotions of renamed keys plus the reset sweep; both are batches the reset path pushes',
    ),

    // -- Credentials and sessions.
    'lib/services/credential_vault.dart': RawWriteRecord(
      WriteCategory.secret,
      1,
      'the device-local encryption key for DB-stored connection tokens',
    ),
    'lib/services/trackers/tracker_account_store.dart': RawWriteRecord(
      WriteCategory.secret,
      2,
      'tracker OAuth sessions, scoped per user',
    ),
    'lib/services/seerr/seerr_account_store.dart': RawWriteRecord(
      WriteCategory.secret,
      2,
      'Jellyseerr session, vault-encrypted with a device-local key so it is unusable elsewhere',
    ),
    'lib/services/tautulli/tautulli_account_store.dart': RawWriteRecord(
      WriteCategory.secret,
      2,
      'Tautulli API key: opens that server\'s whole admin API, so it never leaves the device',
    ),
    'lib/services/pleya_share/pleya_share_host_service.dart': RawWriteRecord(
      WriteCategory.secret,
      5,
      'share tokens, guest records and the relay host id; the legacy prefs store, outside this engine',
    ),
    'lib/services/pleya_share/pleya_share_client.dart': RawWriteRecord(
      WriteCategory.secret,
      3,
      'share item cache and pending watch state; the legacy prefs store, outside this engine',
    ),

    // -- Runtime state and caches.
    'lib/services/update_service.dart': RawWriteRecord(
      WriteCategory.runtimeCache,
      3,
      'skipped version and last-check stamp; per-install update bookkeeping',
    ),
    'lib/services/trackers/fribb_mapping_store.dart': RawWriteRecord(
      WriteCategory.runtimeCache,
      3,
      'HTTP ETag and last-check stamp for a downloaded mapping table',
    ),
    'lib/services/trackers/anime_lists_mapping_store.dart': RawWriteRecord(
      WriteCategory.runtimeCache,
      3,
      'HTTP ETag and last-check stamp for a downloaded mapping table',
    ),
    'lib/services/trakt/trakt_sync_queue.dart': RawWriteRecord(
      WriteCategory.runtimeCache,
      4,
      'the pending-sync queue and its corrupt-payload quarantine slot',
    ),
    'lib/services/local_server_match_service.dart': RawWriteRecord(
      WriteCategory.runtimeCache,
      1,
      'LAN discovery result; another network makes it wrong, and it is in the legacy prefs store',
    ),
    'lib/services/download_manager_service.dart': RawWriteRecord(
      WriteCategory.runtimeCache,
      1,
      'a one-time path-normalisation version marker',
    ),
    'lib/connection/connection_bootstrap.dart': RawWriteRecord(
      WriteCategory.legacyMigration,
      5,
      'the profile-migration-done flag and the Plex Home cache it invalidates',
    ),
    'lib/services/favorite_channels_repository.dart': RawWriteRecord(
      WriteCategory.backendMirror,
      3,
      'a mirror of the backend\'s Live TV favourites, in the legacy prefs store',
    ),

    // -- Local playback bookkeeping, in the store this engine does not own.
    'lib/services/local_folder_client.dart': RawWriteRecord(
      WriteCategory.runtimeCache,
      2,
      'local_progress_* and local_watched_* for the local-folder backend. These live in the legacy '
      'SharedPreferences store, which the migration copies once and never touches again, so the '
      'sync engine cannot see the live values and must not upload the frozen copies',
    ),
  };

  test('every raw preference write in lib/ is classified', () {
    final pattern = RegExp(r'\.(setBool|setInt|setDouble|setString|setStringList|remove)\(');
    final receiver = RegExp(r'(prefs|_prefs|preferences|_cache)\.$');
    final found = <String, int>{};

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart') || entity.path.endsWith('.freezed.dart')) continue;
      final relative = entity.path.replaceAll(r'\', '/');

      for (final line in entity.readAsLinesSync()) {
        for (final match in pattern.allMatches(line)) {
          if (!receiver.hasMatch(line.substring(0, match.start + 1))) continue;
          found[relative] = (found[relative] ?? 0) + 1;
        }
      }
    }

    final unclassified = found.keys.where((f) => !inventory.containsKey(f)).toList()..sort();
    expect(
      unclassified,
      isEmpty,
      reason:
          'A raw preference write appeared in a file nobody has classified. Route it through the '
          'coordinator, or add the file to the inventory in this test with a category and a reason.\n'
          '${unclassified.join('\n')}',
    );

    final drifted = <String>[];
    inventory.forEach((file, record) {
      final actual = found[file] ?? 0;
      if (actual != record.count) drifted.add('$file: expected ${record.count}, found $actual');
    });
    expect(
      drifted,
      isEmpty,
      reason:
          'The number of raw writes in a classified file changed. That is the signal: re-read the file, '
          'decide what the new write is, and update the count and the reason.\n${drifted.join('\n')}',
    );
  });

  test('the inventory totals are measured, not remembered', () {
    // These two numbers appear in the phase-A report, so they get measured here
    // rather than recalled. The grep that produced the plan's figure counted
    // matching *lines*; this counts matching *calls*, which is the number that
    // actually has to be classified.
    final total = inventory.values.fold<int>(0, (sum, r) => sum + r.count);
    expect(total, 85, reason: 'total raw preference writes still classified as staying outside the coordinator');
    expect(inventory.length, 23, reason: 'files containing them');
  });

  test('no category is a dumping ground', () {
    // A category with a single vague reason is how "unclassified" comes back
    // wearing a label. Every entry has to say something specific.
    for (final entry in inventory.entries) {
      expect(entry.value.reason.length, greaterThan(30), reason: '${entry.key} needs a real reason');
      expect(entry.value.count, greaterThan(0), reason: entry.key);
    }
  });
}
