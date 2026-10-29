import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/track_language_choice.dart';
import 'package:pleya/services/opened_file.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/services/track_preference_store.dart';

import '../test_helpers/prefs.dart';

MediaItem _episode(String id, {String? show}) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.episode, grandparentId: show);

MediaItem _movie(String id) => MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie);

void main() {
  // resetSharedPreferencesForTest drops the singletons, but the active profile
  // and the stored map can still survive into the next test, which would make
  // the scoping cases pass or fail depending on order. Clear both explicitly.
  setUp(() async {
    resetSharedPreferencesForTest();
    TrackPreferenceStore.resetForTesting();
    final previousDeviceName = TrackPreferenceStore.deviceNameProvider;
    TrackPreferenceStore.deviceNameProvider = () async => 'Fixture';
    addTearDown(() {
      TrackPreferenceStore.deviceNameProvider = previousDeviceName;
      TrackPreferenceStore.resetForTesting();
    });
    await (await StorageService.getInstance()).clearActiveProfileId();
    await (await SettingsService.getInstance()).write(
      SettingsService.trackLanguagePreferences,
      const <String, TrackLanguageChoice>{},
    );
  });

  test('remote clear failure leaves the remembered choice available for retry', () async {
    final item = _movie('m');
    await TrackPreferenceStore.saveAudio(item, language: 'nld');
    await expectLater(
      TrackPreferenceStore.clearKey(
        'm',
        clearRemote: () async {
          throw StateError('offline');
        },
      ),
      throwsStateError,
    );
    expect((await TrackPreferenceStore.read(item))?.audioLanguage, 'nld');
    await TrackPreferenceStore.clearKey('m', clearRemote: () async {});
    expect(await TrackPreferenceStore.read(item), isNull);
  });

  test('remote clear finishing after a profile switch cannot clear the new profile', () async {
    final storage = await StorageService.getInstance();
    final item = _movie('m');
    await storage.setActiveProfileId('one');
    await TrackPreferenceStore.saveAudio(item, language: 'nld');
    await storage.setActiveProfileId('two');
    await TrackPreferenceStore.saveAudio(item, language: 'eng');
    await storage.setActiveProfileId('one');
    final started = Completer<void>();
    final finish = Completer<void>();
    final clearing = TrackPreferenceStore.clearKey(
      'm',
      clearRemote: () {
        started.complete();
        return finish.future;
      },
    );
    await started.future.timeout(const Duration(seconds: 2));
    await storage.setActiveProfileId('two');
    finish.complete();
    await clearing;
    expect((await TrackPreferenceStore.read(item))?.audioLanguage, 'eng');
  });

  test('Pleya preference provenance carries the remote scope through storage', () async {
    final item = MediaItem(
      id: 'ep',
      backend: MediaBackend.pleyaServer,
      kind: MediaKind.episode,
      grandparentId: 'series',
      serverId: 'nas',
    );
    await TrackPreferenceStore.saveAudio(item, language: 'nld');
    final stored = await TrackPreferenceStore.read(item);
    expect(stored?.provenance?.toJson()['bk'], 'pleyaServer');
    expect(stored?.provenance?.toJson()['si'], 'series');
  });

  test('choices for two accounts on one Pleya server remain independent', () async {
    final item = MediaItem(id: 'm', backend: MediaBackend.pleyaServer, kind: MediaKind.movie, serverId: 'srv');
    await TrackPreferenceStore.saveAudio(item, language: 'eng', serverAccountId: 'one');
    await TrackPreferenceStore.saveAudio(item, language: 'nld', serverAccountId: 'two');
    expect((await TrackPreferenceStore.read(item, serverAccountId: 'one'))?.audioLanguage, 'eng');
    expect((await TrackPreferenceStore.read(item, serverAccountId: 'two'))?.audioLanguage, 'nld');
    final rows = await TrackPreferenceStore.readAllForActiveScope();
    expect(rows, hasLength(2));
    final serialized = TrackLanguageChoice.fromJson(
      rows.singleWhere((row) => row.choice.provenance?.serverAccountId == 'two').choice.toJson(),
    );
    expect(serialized.provenance?.serverAccountId, 'two');
  });

  test('sync never lets a newer server cache replace explicit language intent', () {
    final explicit = jsonEncode({
      'plex-home-plex.a1b2c3d4e5f60718-e434272903092b4e|show': {'a': 'fra', 'u': 1},
    });
    final cache = jsonEncode({
      'plex-home-plex.a1b2c3d4e5f60718-e434272903092b4e|show': {'a': 'nld', 'sr': true, 'u': 2},
    });
    final merge = TrackPreferenceStore.mergeFamily();
    final inbound = jsonDecode(merge.inbound(explicit, cache)! as String) as Map<String, dynamic>;
    final outbound = jsonDecode(merge.outbound!(cache, explicit)! as String) as Map<String, dynamic>;
    expect(inbound['plex-home-plex.a1b2c3d4e5f60718-e434272903092b4e|show']['a'], 'fra');
    expect(outbound['plex-home-plex.a1b2c3d4e5f60718-e434272903092b4e|show']['a'], 'fra');
  });

  group('review cache boundaries', () {
    final item = MediaItem(id: 'm', backend: MediaBackend.pleyaServer, kind: MediaKind.movie, serverId: 'srv');
    test('a partial manual choice does not promote untouched cached fields', () async {
      await TrackPreferenceStore.cacheServerChoice(
        item,
        const TrackLanguageChoice(audioLanguage: 'nld', updatedAt: 1),
        serverAccountId: 'one',
      );
      await TrackPreferenceStore.saveSubtitle(item, off: true, serverAccountId: 'one');
      final choice = await TrackPreferenceStore.read(item, serverAccountId: 'one');
      expect(choice?.subtitlesOff, isTrue);
      expect(choice?.audioLanguage, isNull);
      expect(choice?.fromServer, isFalse);
    });
    test('a legacy explicit override survives repeated remote cache refreshes', () async {
      await TrackPreferenceStore.saveAudio(item, language: 'eng');
      await TrackPreferenceStore.cacheServerChoice(
        item,
        const TrackLanguageChoice(audioLanguage: 'nld', updatedAt: 1),
        serverAccountId: 'one',
      );
      expect((await TrackPreferenceStore.read(item, serverAccountId: 'one'))?.audioLanguage, 'eng');
    });
    test('a partial write keeps explicit legacy intent even when an account cache exists', () async {
      await TrackPreferenceStore.cacheServerChoice(
        item,
        const TrackLanguageChoice(audioLanguage: 'nld', updatedAt: 1),
        serverAccountId: 'one',
      );
      await TrackPreferenceStore.saveAudio(item, language: 'eng');
      await TrackPreferenceStore.saveSubtitle(item, off: true, serverAccountId: 'one');
      final choice = await TrackPreferenceStore.read(item, serverAccountId: 'one');
      expect(choice?.audioLanguage, 'eng');
      expect(choice?.subtitlesOff, isTrue);
    });
    test('remote cache merge cannot modify a local-only profile', () {
      final local = jsonEncode({
        'local-profile|show': {'a': 'nld', 'sr': true, 'u': 1},
      });
      final remote = jsonEncode({
        'local-profile|show': {'a': 'eng', 'u': 2},
      });
      final result =
          jsonDecode(TrackPreferenceStore.mergeFamily().inbound(local, remote)! as String) as Map<String, dynamic>;
      expect(result['local-profile|show']['a'], 'nld');
    });
  });

  group('keying', () {
    test('an opened file stores nothing: its key would be a local path', () async {
      final opened = openedFileItem('/var/mobile/Documents/Vakantie.mkv');

      await TrackPreferenceStore.saveAudio(opened, language: 'nld');
      await TrackPreferenceStore.saveSubtitle(opened, language: 'eng');

      expect(await TrackPreferenceStore.read(opened), isNull);
      expect((await SettingsService.getInstance()).read(SettingsService.trackLanguagePreferences), isEmpty);
    });

    test('every episode of a show resolves to the same entry', () async {
      await TrackPreferenceStore.saveAudio(_episode('ep1', show: 'show7'), language: 'nld');

      expect((await TrackPreferenceStore.read(_episode('ep2', show: 'show7')))?.audioLanguage, 'nld');
      expect((await TrackPreferenceStore.read(_episode('ep9', show: 'show7')))?.audioLanguage, 'nld');
    });

    test('a different show does not inherit the choice', () async {
      await TrackPreferenceStore.saveAudio(_episode('ep1', show: 'show7'), language: 'nld');
      expect(await TrackPreferenceStore.read(_episode('ep1', show: 'show8')), isNull);
    });

    test('a movie keys on itself', () async {
      await TrackPreferenceStore.saveAudio(_movie('mv1'), language: 'jpn');
      expect((await TrackPreferenceStore.read(_movie('mv1')))?.audioLanguage, 'jpn');
      expect(await TrackPreferenceStore.read(_movie('mv2')), isNull);
    });
  });

  group('profile scoping', () {
    for (final subtitle in [false, true]) {
      test(
        'scoped ${subtitle ? 'subtitle' : 'audio'} write stops after profile changes during provenance await',
        () async {
          final storage = await StorageService.getInstance();
          final settings = await SettingsService.getInstance();
          await storage.setActiveProfileId('profile-a');
          TrackPreferenceStore.resetForTesting();
          final previousProvider = TrackPreferenceStore.deviceNameProvider;
          final started = Completer<void>();
          final deviceName = Completer<String>();
          TrackPreferenceStore.deviceNameProvider = () {
            started.complete();
            return deviceName.future;
          };
          addTearDown(() {
            TrackPreferenceStore.deviceNameProvider = previousProvider;
            TrackPreferenceStore.resetForTesting();
          });
          var current = true;
          final item = _episode('ep1', show: 'show7');
          final pending = subtitle
              ? TrackPreferenceStore.saveSubtitle(item, language: 'nld', isCurrent: () => current)
              : TrackPreferenceStore.saveAudio(item, language: 'nld', isCurrent: () => current);
          await started.future;
          current = false;
          await storage.setActiveProfileId('profile-b');
          deviceName.complete('Fixture');
          await pending;
          expect(settings.read(SettingsService.trackLanguagePreferences), isEmpty);
        },
      );
    }
    // Two Plex Home users on one device watch the same show. Neither should
    // start an episode in the other's language.
    test('a profile switch does not surface the previous profile choice', () async {
      final storage = await StorageService.getInstance();

      await storage.setActiveProfileId('profile-a');
      await TrackPreferenceStore.saveAudio(_episode('ep1', show: 'show7'), language: 'nld');
      expect((await TrackPreferenceStore.read(_episode('ep1', show: 'show7')))?.audioLanguage, 'nld');

      await storage.setActiveProfileId('profile-b');
      expect(await TrackPreferenceStore.read(_episode('ep1', show: 'show7')), isNull);

      await TrackPreferenceStore.saveAudio(_episode('ep1', show: 'show7'), language: 'eng');
      expect((await TrackPreferenceStore.read(_episode('ep1', show: 'show7')))?.audioLanguage, 'eng');

      await storage.setActiveProfileId('profile-a');
      expect((await TrackPreferenceStore.read(_episode('ep1', show: 'show7')))?.audioLanguage, 'nld');
    });

    test('signed-out playback is its own namespace', () async {
      final storage = await StorageService.getInstance();
      await TrackPreferenceStore.saveAudio(_episode('ep1', show: 'show7'), language: 'fre');

      await storage.setActiveProfileId('profile-a');
      expect(await TrackPreferenceStore.read(_episode('ep1', show: 'show7')), isNull);
    });
  });

  group('subtitles', () {
    test('an explicit off is stored as a decision, not as absence', () async {
      final item = _episode('ep1', show: 'show7');
      await TrackPreferenceStore.saveSubtitle(item, off: true);

      final choice = await TrackPreferenceStore.read(item);
      expect(choice!.subtitlesOff, isTrue);
      expect(choice.subtitleLanguage, isNull);
      expect(choice.hasSubtitle, isTrue);
    });

    test('choosing a language after an off clears the off', () async {
      final item = _episode('ep1', show: 'show7');
      await TrackPreferenceStore.saveSubtitle(item, off: true);
      await TrackPreferenceStore.saveSubtitle(item, language: 'nld', forced: true);

      final choice = await TrackPreferenceStore.read(item);
      expect(choice!.subtitlesOff, isFalse);
      expect(choice.subtitleLanguage, 'nld');
      expect(choice.subtitleForced, isTrue);
    });

    test('audio and subtitle choices live side by side', () async {
      final item = _episode('ep1', show: 'show7');
      await TrackPreferenceStore.saveAudio(item, language: 'nld', title: 'Main');
      await TrackPreferenceStore.saveSubtitle(item, language: 'eng');

      final choice = await TrackPreferenceStore.read(item);
      expect(choice!.audioLanguage, 'nld');
      expect(choice.audioTitle, 'Main');
      expect(choice.subtitleLanguage, 'eng');
    });
  });

  group('concurrent writes', () {
    // TrackSelectionService fires the audio and the subtitle callback in the
    // same synchronous stretch when both choices come from a remembered
    // preference, so both are in flight at once. They hit the same entry, and
    // copyWithAudio / copyWithSubtitle each carry the other modality's fields
    // along, so a writer working from a stale snapshot wipes the other choice.
    //
    // These two cases hold with the write lock removed as well: nothing
    // suspends between the read and the cache write today. They guard the
    // invariant, not a reproduced failure; see the note on the store.
    test('a simultaneous audio and subtitle write both survive', () async {
      final item = _episode('ep1', show: 'show7');

      // Grab both futures before awaiting either: awaiting the first one would
      // sequence them and stop testing the race.
      final audio = TrackPreferenceStore.saveAudio(item, language: 'nld', title: 'Nederlands');
      final subtitle = TrackPreferenceStore.saveSubtitle(item, language: 'eng', title: 'English');
      await Future.wait([audio, subtitle]);

      final choice = await TrackPreferenceStore.read(item);
      expect(choice!.audioLanguage, 'nld');
      expect(choice.audioTitle, 'Nederlands');
      expect(choice.subtitleLanguage, 'eng');
      expect(choice.subtitleTitle, 'English');
    });

    // The whole map is written as one value, so two different titles are as
    // exposed as two modalities of one title. The queue also has to run in the
    // order the writes were offered, not in whatever order they happen to
    // finish.
    test('simultaneous writes for two titles keep both entries, last offered wins', () async {
      final showA = _episode('ep1', show: 'showA');
      final showB = _episode('ep1', show: 'showB');
      final other = _episode('ep2', show: 'showA');

      final first = TrackPreferenceStore.saveAudio(showA, language: 'nld');
      final second = TrackPreferenceStore.saveAudio(showB, language: 'eng');
      final third = TrackPreferenceStore.saveAudio(other, language: 'jpn');
      await Future.wait([first, second, third]);

      expect((await TrackPreferenceStore.read(showB))?.audioLanguage, 'eng');
      // showA was written twice; the later offer is the one that stuck.
      expect((await TrackPreferenceStore.read(showA))?.audioLanguage, 'jpn');
    });
  });

  group('storage hygiene', () {
    test('the map is capped, dropping the least recently written entries', () async {
      final settings = await SettingsService.getInstance();
      final overflowing = {
        for (var i = 0; i < TrackPreferenceStore.maxEntries + 10; i++)
          '|show$i': TrackLanguageChoice(audioLanguage: 'eng', updatedAt: i),
      };
      await settings.write(SettingsService.trackLanguagePreferences, overflowing);

      // One more write triggers the cap.
      await TrackPreferenceStore.saveAudio(_episode('ep1', show: 'newest'), language: 'nld');

      final stored = settings.read(SettingsService.trackLanguagePreferences);
      expect(stored.length, TrackPreferenceStore.maxEntries);
      expect(stored.containsKey('|newest'), isTrue);
      // Oldest timestamps go first.
      expect(stored.containsKey('|show0'), isFalse);
      expect(stored.containsKey('|show${TrackPreferenceStore.maxEntries + 9}'), isTrue);
    });

    test('round-trips through the JSON encoding', () async {
      final item = _episode('ep1', show: 'show7');
      await TrackPreferenceStore.saveAudio(item, language: 'nld', title: 'Main');
      await TrackPreferenceStore.saveSubtitle(item, language: 'eng', title: 'SDH', forced: true);

      // Force a decode from the raw string rather than an in-memory hit.
      final settings = await SettingsService.getInstance();
      final decoded = settings.read(SettingsService.trackLanguagePreferences)['|show7']!;
      final reparsed = TrackLanguageChoice.fromJson(decoded.toJson().cast<String, dynamic>());

      expect(reparsed.audioLanguage, 'nld');
      expect(reparsed.audioTitle, 'Main');
      expect(reparsed.subtitleLanguage, 'eng');
      expect(reparsed.subtitleTitle, 'SDH');
      expect(reparsed.subtitleForced, isTrue);
      expect(reparsed.subtitlesOff, isFalse);
    });
  });
}
