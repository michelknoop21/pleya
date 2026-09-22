import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_server_user_profile.dart';
import 'package:pleya/media/pleya_profile_language_preferences.dart';
import 'package:pleya/services/pleya_profile_language_preference_store.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';

import '../test_helpers/prefs.dart';

/// The one-time seed from a server profile has to survive not having one yet.
///
/// `ensureInitialised` has two doors. `TrackManager` awaits the profile fetch
/// before knocking; the language settings page reads whatever the provider
/// holds right now, which is null on an offline start, before the fetch lands,
/// or after it failed (`UserProfileProvider.refreshProfileSettings` is
/// best-effort and leaves the field untouched on every failure path).
///
/// Marking the profile seeded on such a call spent the single chance without
/// having taken anything over, and nothing gives it back: both doors are
/// guarded on the same flag. The viewer then kept the app defaults instead of
/// the languages their Plex or Jellyfin profile already carried.
class _ServerProfile implements MediaServerUserProfile {
  const _ServerProfile({
    this.defaultAudioLanguage,
    this.defaultSubtitleLanguage,
    this.defaultSubtitleLanguages,
    this.subtitleMode,
  });

  @override
  bool get autoSelectAudio => true;

  @override
  final String? defaultAudioLanguage;

  /// Plex exposes a ranked list here; this fixture only needs the primary.
  @override
  List<String>? get defaultAudioLanguages => null;

  @override
  final String? defaultSubtitleLanguage;

  @override
  final List<String>? defaultSubtitleLanguages;

  @override
  final SubtitlePlaybackMode? subtitleMode;
}

const _dutchProfile = _ServerProfile(
  defaultAudioLanguage: 'eng',
  defaultSubtitleLanguage: 'nld',
  defaultSubtitleLanguages: ['nld', 'eng'],
  subtitleMode: SubtitlePlaybackMode.always,
);

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    PleyaProfileLanguagePreferenceStore.resetForTesting();
    await (await StorageService.getInstance()).clearActiveProfileId();
    await (await SettingsService.getInstance()).write(
      SettingsService.pleyaProfileLanguagePreferences,
      const <String, PleyaProfileLanguagePreferences>{},
    );
  });

  group('a missing server profile does not consume the seed', () {
    test('the settings page opening first still leaves the seed for the player', () async {
      // Door one: the language page, before the profile fetch landed.
      await PleyaProfileLanguagePreferenceStore.ensureInitialised(null);

      var stored = await PleyaProfileLanguagePreferenceStore.read();
      expect(stored.seeded, isFalse, reason: 'nothing was taken over, so nothing is done');

      // Door two: playback starts, and by then the profile is there.
      await PleyaProfileLanguagePreferenceStore.ensureInitialised(_dutchProfile);

      stored = await PleyaProfileLanguagePreferenceStore.read();
      expect(stored.audioLanguage, 'eng');
      expect(stored.subtitleLanguage, 'nld');
      expect(stored.subtitleFallbackLanguage, 'eng');
      expect(stored.subtitlePolicy, SubtitleDisplayPolicy.always);
      expect(stored.seeded, isTrue);
    });

    test('repeated null calls never consume it either', () async {
      for (var i = 0; i < 3; i++) {
        await PleyaProfileLanguagePreferenceStore.ensureInitialised(null);
      }
      await PleyaProfileLanguagePreferenceStore.ensureInitialised(_dutchProfile);

      expect((await PleyaProfileLanguagePreferenceStore.read()).subtitleLanguage, 'nld');
    });
  });

  group('the seed still runs exactly once', () {
    test('a second server profile cannot overwrite the first', () async {
      await PleyaProfileLanguagePreferenceStore.ensureInitialised(_dutchProfile);
      await PleyaProfileLanguagePreferenceStore.ensureInitialised(
        const _ServerProfile(defaultAudioLanguage: 'deu', defaultSubtitleLanguage: 'deu'),
      );

      final stored = await PleyaProfileLanguagePreferenceStore.read();
      expect(stored.audioLanguage, 'eng', reason: 'the first seed owns it');
      expect(stored.subtitleLanguage, 'nld');
    });

    test('a viewer who already chose is not overwritten, and the seed closes', () async {
      await PleyaProfileLanguagePreferenceStore.write(const PleyaProfileLanguagePreferences(subtitleLanguage: 'fra'));

      await PleyaProfileLanguagePreferenceStore.ensureInitialised(_dutchProfile);

      final stored = await PleyaProfileLanguagePreferenceStore.read();
      expect(stored.subtitleLanguage, 'fra', reason: 'a deliberate choice outranks any server');
      expect(stored.seeded, isTrue, reason: 'and no server signing in later may reopen the question');
    });

    test('a row the viewer deliberately cleared is not re-seeded months later', () async {
      // "Gebruik globale voorkeur" puts a row back to empty, which makes the
      // preference `isUnset` again. Holding the latch open for a null profile
      // means that state survives until a server profile shows up, so without
      // a latch set at the edit itself the seed cannot tell a deliberate "no
      // opinion" from never-touched, and overwrites it.
      await PleyaProfileLanguagePreferenceStore.ensureInitialised(null);
      await PleyaProfileLanguagePreferenceStore.updateFromViewer((p) => p.copyWith(audioLanguage: 'fra'));
      await PleyaProfileLanguagePreferenceStore.updateFromViewer((p) => p.copyWith(clearAudioLanguage: true));

      expect((await PleyaProfileLanguagePreferenceStore.read()).isUnset, isTrue, reason: 'back to no opinion');

      await PleyaProfileLanguagePreferenceStore.ensureInitialised(_dutchProfile);

      final stored = await PleyaProfileLanguagePreferenceStore.read();
      expect(stored.audioLanguage, isNull, reason: 'the viewer cleared it on purpose');
      expect(stored.subtitleLanguage, isNull);
    });
  });

  group('the legacy switch migration has its own latch', () {
    test('an edited switch is not clobbered by a later call without a server profile', () async {
      // The migration used to share the seed's latch. Leaving the seed open for
      // a null profile must not let the migration run a second time and put the
      // old device-wide pref back over what the viewer set on the page.
      final settings = await SettingsService.getInstance();
      await settings.write(SettingsService.rememberTrackSelections, true);

      await PleyaProfileLanguagePreferenceStore.ensureInitialised(null);
      await PleyaProfileLanguagePreferenceStore.update((p) => p.copyWith(rememberPerSeries: false));

      await PleyaProfileLanguagePreferenceStore.ensureInitialised(null);

      expect(
        (await PleyaProfileLanguagePreferenceStore.read()).rememberPerSeries,
        isFalse,
        reason: 'the viewer turned it off after the migration had already run',
      );
    });

    test('the legacy switches still migrate on the first call', () async {
      final settings = await SettingsService.getInstance();
      await settings.write(SettingsService.rememberTrackSelections, false);
      await settings.write(SettingsService.writeSeriesLanguageToServer, false);

      await PleyaProfileLanguagePreferenceStore.ensureInitialised(null);

      final stored = await PleyaProfileLanguagePreferenceStore.read();
      expect(stored.rememberPerSeries, isFalse);
      expect(stored.mirrorToPlex, isFalse);
    });
  });

  group('an install that already ran the old initialisation is left alone', () {
    test('a stored seeded flag counts as a completed migration', () {
      // No `mg` key: written by a build where one flag answered both
      // questions. Re-running the migration there would put the legacy device
      // prefs back over whatever the viewer has set since.
      final restored = PleyaProfileLanguagePreferences.fromJson(const {'sd': true, 'rp': false, 'u': 1});

      expect(restored.seeded, isTrue);
      expect(restored.migratedLegacySwitches, isTrue);
      expect(restored.rememberPerSeries, isFalse);
    });
  });
}
