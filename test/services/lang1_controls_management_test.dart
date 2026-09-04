/// LANG1 / DEC-096, negatieve controles C en G, plus het terugvalcontract.
///
/// Deze controles raken de globale laag en het beheer ervan. Ze verwijzen naar
/// `PleyaProfileLanguagePreferenceStore` en `TrackPreferenceStore.clear`, die
/// vóór de bouwronde niet bestaan: dit bestand compileert daarom niet op de
/// oude code, en dat is de vastgelegde rode uitkomst voor C en G.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/pleya_profile_language_preferences.dart';
import 'package:pleya/media/track_language_choice.dart';
import 'package:pleya/mpv/mpv.dart';
import 'package:pleya/services/pleya_profile_language_preference_store.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/services/track_preference_store.dart';
import 'package:pleya/services/track_selection_service.dart';

import '../test_helpers/prefs.dart';

MediaItem _episode(String id, {String show = 'show7'}) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.episode, grandparentId: show);

SubtitleTrack _sub(String id, {String? lang}) => SubtitleTrack(id: id, language: lang);

AudioTrack _audio(String id, {String? lang}) => AudioTrack(id: id, language: lang);

class _StubPlayer implements Player {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TrackSelectionService _svc({
  required MediaItem metadata,
  TrackLanguageChoice? sticky,
  PleyaProfileLanguagePreferences? global,
}) => TrackSelectionService(player: _StubPlayer(), metadata: metadata, stickyChoice: sticky, globalPreferences: global);

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    await (await StorageService.getInstance()).clearActiveProfileId();
    await (await SettingsService.getInstance()).write(
      SettingsService.trackLanguagePreferences,
      const <String, TrackLanguageChoice>{},
    );
    await (await SettingsService.getInstance()).write(
      SettingsService.pleyaProfileLanguagePreferences,
      const <String, PleyaProfileLanguagePreferences>{},
    );
  });

  // ────────────────────────────────────────────────────────────────
  // CONTROL C — de globale voorkeur komt uit het Pleya-profiel
  // ────────────────────────────────────────────────────────────────
  group('CONTROL C — het Pleya-profiel is de eigenaar van de globale voorkeur', () {
    test('de globale voorkeur geldt zonder serie-override, ongeacht de backend', () async {
      await PleyaProfileLanguagePreferenceStore.write(
        const PleyaProfileLanguagePreferences(subtitleLanguage: 'nld', audioLanguage: 'eng'),
      );

      final plex = MediaItem(id: 'p1', backend: MediaBackend.plex, kind: MediaKind.episode, grandparentId: 'showA');
      final jellyfin = MediaItem(
        id: 'j1',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.episode,
        grandparentId: 'showB',
      );

      final global = await PleyaProfileLanguagePreferenceStore.read();

      for (final item in [plex, jellyfin]) {
        final service = _svc(metadata: item, global: global);
        expect(
          service.selectSubtitleTrack([_sub('1', lang: 'eng'), _sub('2', lang: 'nld')], null, null).track.language,
          'nld',
          reason: 'DEC-096 lid 5: het Pleya-profiel geldt voor alle content, ook over backends heen',
        );
        expect(
          service.selectAudioTrack([_audio('1', lang: 'eng'), _audio('2', lang: 'jpn')], null)?.track.language,
          'eng',
        );
      }
    });

    test('de voorkeur is profielgebonden en lekt niet naar een ander profiel', () async {
      final storage = await StorageService.getInstance();

      await storage.setActiveProfileId('profile-a');
      await PleyaProfileLanguagePreferenceStore.write(const PleyaProfileLanguagePreferences(subtitleLanguage: 'nld'));

      await storage.setActiveProfileId('profile-b');
      expect((await PleyaProfileLanguagePreferenceStore.read()).subtitleLanguage, isNull);

      await storage.setActiveProfileId('profile-a');
      expect((await PleyaProfileLanguagePreferenceStore.read()).subtitleLanguage, 'nld');
    });
  });

  // ────────────────────────────────────────────────────────────────
  // Terugvalcontract (DEC-096 lid 3), hoort bij de globale laag
  // ────────────────────────────────────────────────────────────────
  group('terugvalcontract — gewenste taal, dan de terugvaltaal, dan uit', () {
    test('ontbreekt de gewenste taal, dan speelt de ingestelde terugvaltaal', () {
      final service = _svc(
        metadata: _episode('ep2'),
        sticky: const TrackLanguageChoice(subtitleLanguage: 'eng', updatedAt: 1),
        global: const PleyaProfileLanguagePreferences(subtitleFallbackLanguage: 'nld'),
      );

      final result = service.selectSubtitleTrack([_sub('2', lang: 'nld'), _sub('3', lang: 'fre')], null, null);

      expect(result.track.language, 'nld');
    });

    test('ontbreekt ook de terugvaltaal, dan gaan de ondertitels uit', () {
      final service = _svc(
        metadata: _episode('ep2'),
        sticky: const TrackLanguageChoice(subtitleLanguage: 'eng', updatedAt: 1),
        global: const PleyaProfileLanguagePreferences(subtitleFallbackLanguage: 'nld'),
      );

      final result = service.selectSubtitleTrack([_sub('3', lang: 'fre'), _sub('4', lang: 'deu')], null, null);

      expect(result.track.id, 'no', reason: 'DEC-096 lid 3: nooit de eerste beschikbare ondertiteltrack');
    });

    test('een terugval wijzigt de serievoorkeur en de globale voorkeur niet', () async {
      await TrackPreferenceStore.saveSubtitle(_episode('ep1'), language: 'eng');
      await PleyaProfileLanguagePreferenceStore.write(
        const PleyaProfileLanguagePreferences(subtitleLanguage: 'nld', subtitleFallbackLanguage: 'nld'),
      );

      final service = _svc(
        metadata: _episode('ep2'),
        sticky: await TrackPreferenceStore.read(_episode('ep2')),
        global: await PleyaProfileLanguagePreferenceStore.read(),
      );
      service.selectSubtitleTrack([_sub('2', lang: 'nld')], null, null);

      expect((await TrackPreferenceStore.read(_episode('ep2')))?.subtitleLanguage, 'eng');
      expect((await PleyaProfileLanguagePreferenceStore.read()).subtitleLanguage, 'nld');
    });
  });

  // ────────────────────────────────────────────────────────────────
  // CONTROL G — "Gebruik globale voorkeur" wist de serie-override
  // ────────────────────────────────────────────────────────────────
  group('CONTROL G — gebruik globale voorkeur', () {
    test('de serie-override verdwijnt volledig en het profiel geldt weer', () async {
      await PleyaProfileLanguagePreferenceStore.write(
        const PleyaProfileLanguagePreferences(subtitleLanguage: 'nld', audioLanguage: 'nld'),
      );
      await TrackPreferenceStore.saveSubtitle(_episode('s1e1'), language: 'eng');
      await TrackPreferenceStore.saveAudio(_episode('s1e1'), language: 'eng');
      expect(await TrackPreferenceStore.read(_episode('s1e1')), isNotNull);

      await TrackPreferenceStore.clear(_episode('s1e1'));

      expect(
        await TrackPreferenceStore.read(_episode('s1e2')),
        isNull,
        reason: 'geen lege override laten staan die de globale resolutie alsnog blokkeert',
      );

      final service = _svc(
        metadata: _episode('s1e2'),
        sticky: await TrackPreferenceStore.read(_episode('s1e2')),
        global: await PleyaProfileLanguagePreferenceStore.read(),
      );
      expect(
        service.selectSubtitleTrack([_sub('1', lang: 'eng'), _sub('2', lang: 'nld')], null, null).track.language,
        'nld',
      );
    });

    test('het wissen overleeft een herstart van de opslag', () async {
      await TrackPreferenceStore.saveSubtitle(_episode('s1e1'), language: 'eng');
      await TrackPreferenceStore.clear(_episode('s1e1'));

      // Zelfde onderliggende prefs, verse singletons: precies wat een herstart
      // van de app met de opslag doet.
      SettingsService.resetForTesting();
      expect(await TrackPreferenceStore.read(_episode('s1e1')), isNull);
    });

    test('een serie zonder override raakt niet aan een andere serie', () async {
      await TrackPreferenceStore.saveSubtitle(_episode('a1', show: 'showA'), language: 'eng');
      await TrackPreferenceStore.saveSubtitle(_episode('b1', show: 'showB'), language: 'fre');

      await TrackPreferenceStore.clear(_episode('a1', show: 'showA'));

      expect(await TrackPreferenceStore.read(_episode('a1', show: 'showA')), isNull);
      expect((await TrackPreferenceStore.read(_episode('b1', show: 'showB')))?.subtitleLanguage, 'fre');
    });
  });
}
