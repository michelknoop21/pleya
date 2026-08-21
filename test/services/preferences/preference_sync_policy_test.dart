import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/preferences/preference_sync_policy.dart';
import 'package:pleya/services/preferences/preference_sync_scope.dart';
import 'package:pleya/services/settings_export_service.dart';

/// The registry replaces an allow-by-default denylist. That inversion is the
/// point: under the old rule every new preference opted itself into iCloud
/// unless somebody remembered to forbid it, which is how a LAN address and a
/// set of per-tracker library filters ended up syncing.
void main() {
  group('unknown is local-only', () {
    test('a preference nobody registered does not sync and does not export', () {
      const invented = 'some_setting_added_next_tuesday';

      expect(PreferenceSyncPolicyRegistry.isRegistered(invented), isFalse);
      expect(PreferenceSyncPolicyRegistry.maySync(invented), isFalse);
      expect(PreferenceSyncPolicyRegistry.isExportable(invented), isFalse);
      expect(PreferenceSyncPolicyRegistry.policyFor(invented).scope, PreferenceScopeKind.deviceLocal);
    });

    test('the longest matching prefix wins over a shorter one', () {
      // `pleya_share_` is a secret prefix; a longer, more specific registration
      // must be able to override it without reordering a map.
      expect(PreferenceSyncPolicyRegistry.policyFor('pleya_share_tokens').sensitivity, PreferenceSensitivity.secret);
    });
  });

  group('what may sync', () {
    test('ordinary global preferences do', () {
      for (final key in ['subtitle_font_size', 'theme_mode', 'auto_play_next_episode', 'seek_time_small']) {
        expect(PreferenceSyncPolicyRegistry.maySync(key), isTrue, reason: key);
        expect(PreferenceSyncPolicyRegistry.policyFor(key).scope, PreferenceScopeKind.global, reason: key);
      }
    });

    test('the library families are profile-scoped', () {
      for (final key in [
        'hidden_libraries',
        'library_order',
        'library_filters',
        'library_sort_srv:1',
        'library_grouping_srv:1',
        'library_tab_srv:1',
        'library_filters_srv:1',
      ]) {
        expect(PreferenceSyncPolicyRegistry.isProfileScoped(key), isTrue, reason: key);
      }
    });

    test('the home-row families are held back, and not because of serverId', () {
      // `serverId` is the server's own machine identifier for both Plex and
      // Jellyfin, so that half travels fine. It is `hub.identifier`, the second
      // half of `homeRowId`, that has not been shown to be identical on two
      // devices for the same hub.
      for (final key in ['home_row_order', 'hidden_home_rows']) {
        expect(PreferenceSyncPolicyRegistry.maySync(key), isFalse, reason: key);
      }
      expect(
        PreferenceSyncPolicyRegistry.maySync('hidden_libraries'),
        isTrue,
        reason: 'the library families do travel: their identity is server-owned',
      );
    });

    test('secrets never leave, in an export or otherwise', () {
      for (final key in [
        'plex_token',
        'token',
        'credential_vault_key_v1',
        'seerr_session',
        'tautulli_session',
        'pleya_share_tokens',
        'pleya_share_guests',
        'pleya_share_relay_host_id',
        'trakt_access_token',
        'mal_refresh_token',
      ]) {
        final policy = PreferenceSyncPolicyRegistry.policyFor(key);
        expect(policy.sensitivity, PreferenceSensitivity.secret, reason: key);
        expect(policy.icloudSyncable, isFalse, reason: key);
        expect(policy.exportable, isFalse, reason: key);
      }
    });

    test('device-local preferences stay put, including the two that used to sync by accident', () {
      for (final key in [
        'custom_download_path',
        'enable_hardware_decoding',
        'enable_hdr',
        'audio_passthrough',
        'start_in_fullscreen',
        'force_tv_mode',
        'volume',
        // A LAN address. It synced under the old denylist, and on another
        // network it points at nothing or at somebody else's machine.
        'companion_remote_last_host_address',
        // Fell outside the `trakt_`/`mal_` prefixes, so it synced too.
        'tracker_library_filter_mode_trakt',
        'tracker_library_filter_ids_trakt',
      ]) {
        expect(PreferenceSyncPolicyRegistry.maySync(key), isFalse, reason: key);
      }
    });

    test('the iCloud toggle itself does not sync, or two devices fight over it', () {
      expect(PreferenceSyncPolicyRegistry.maySync('icloud_sync_enabled'), isFalse);
    });
  });

  group('reserved namespaces', () {
    test('the legacy `flutter.` store is not this engine\'s business', () {
      for (final key in ['flutter.local_progress_abc', 'flutter.subtitle_font_size', 'flutter.anything']) {
        expect(PreferenceSyncPolicyRegistry.maySync(key), isFalse, reason: key);
        expect(PreferenceSyncPolicyRegistry.isRegistered(key), isFalse, reason: key);
      }
    });

    test('a `flutter.`-prefixed key never becomes syncable by matching a registered name', () {
      // Without the reserved-prefix check this would match nothing and fall
      // through to local-only anyway, but the guard has to be explicit: the
      // frozen migration copies carry real preference names.
      expect(PreferenceSyncPolicyRegistry.maySync('flutter.theme_mode'), isFalse);
    });

    test('the cloud namespace marker is never treated as a preference', () {
      expect(PreferenceSyncPolicyRegistry.maySync('__syncFormatVersion'), isFalse);
      expect(PreferenceSyncPolicyRegistry.maySync('__p2/global/theme_mode'), isFalse);
    });
  });

  test('the export service asks the registry instead of keeping its own copy', () {
    // One registration, one answer. This used to be a second hand-maintained
    // list of five keys and four prefixes inside the export service.
    for (final key in ['hidden_libraries', 'library_sort_x', 'subtitle_font_size', 'plex_token']) {
      expect(
        SettingsExportService.isUserScopedBaseKey(key),
        PreferenceSyncPolicyRegistry.isProfileScoped(key),
        reason: key,
      );
    }
  });

  test('every declared preference key is registered, so none falls through by accident', () {
    // The registry is deny-by-default, which is right, but a forgotten
    // registration is then silent: the preference simply stops syncing. This
    // scans the declarations and demands an answer for each one. A new
    // preference makes it red until somebody decides what it is.
    final patterns = [RegExp(r"Pref[a-zA-Z<>]*\(\s*'([a-z0-9_.]+)'"), RegExp(r"super\(\s*'([a-z0-9_.]+)'")];
    final declared = <String>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart') || entity.path.endsWith('.freezed.dart')) continue;
      final src = entity.readAsStringSync();
      for (final pattern in patterns) {
        for (final match in pattern.allMatches(src)) {
          declared.add(match.group(1)!);
        }
      }
    }

    final unregistered = declared.where((k) => !PreferenceSyncPolicyRegistry.isRegistered(k)).toList()..sort();
    expect(
      unregistered,
      isEmpty,
      reason:
          'These preferences have no entry in PreferenceSyncPolicyRegistry, so they are local-only by '
          'default. That may well be correct, but it has to be written down: add each one with the '
          'scope and sensitivity it deserves.\n${unregistered.join('\n')}',
    );
  });

  group('the Tautulli integration blob stays on the device', () {
    // Arrived with the Tautulli work while phase A was in flight. It is an
    // encrypted admin credential for a server, so the only correct answer on
    // both paths is no.
    const key = 'tautulli_integration_abc123';

    test('it is not syncable', () {
      expect(PreferenceSyncPolicyRegistry.maySync(key), isFalse);
      expect(PreferenceSyncPolicyRegistry.isRegistered(key), isFalse);
    });

    test('it is not exportable', () {
      expect(SettingsExportService.isExportable(key), isFalse);
    });
  });
}
