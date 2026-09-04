/// LANG1 / DEC-096, negatieve controles A, B, D, E en F.
///
/// Deze controles beschrijven het bedoelde contract van DEC-096 en draaien
/// bewust rood op de code van vóór de bouwronde. Ze horen bij het onderscheid
/// tussen *intentie* (de taal die de kijker wil) en *resolutie* (de concrete
/// track die deze aflevering oplevert): een terugval is een resolutie en mag
/// nooit als intentie doorreizen naar de volgende aflevering.
///
/// De controles C en G staan in `lang1_controls_management_test.dart`, H en I
/// in `lang1_controls_identity_test.dart`.
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

// ── Fixtures ────────────────────────────────────────────────────────

MediaItem _episode(String id, {String show = 'show7'}) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.episode, grandparentId: show);

AudioTrack _audio(String id, {String? lang, String? title}) => AudioTrack(id: id, language: lang, title: title);

SubtitleTrack _sub(String id, {String? lang, String? title, bool isForced = false}) =>
    SubtitleTrack(id: id, language: lang, title: title, isForced: isForced);

class _StubPlayer implements Player {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TrackSelectionService _svc({required MediaItem metadata, TrackLanguageChoice? sticky}) =>
    TrackSelectionService(player: _StubPlayer(), metadata: metadata, stickyChoice: sticky);

TrackLanguageChoice _choice({String? audio, String? subtitle, bool subtitlesOff = false}) =>
    TrackLanguageChoice(audioLanguage: audio, subtitleLanguage: subtitle, subtitlesOff: subtitlesOff, updatedAt: 1);

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
  // CONTROL A — een terugval in aflevering N besmet aflevering N+1 niet
  // ────────────────────────────────────────────────────────────────
  group('CONTROL A — een terugval besmet de volgende aflevering niet', () {
    test('ondertitels: aflevering N viel terug op Nederlands, N+1 heeft Engels weer', () {
      // Serievoorkeur: Engelse ondertitels. Aflevering N had geen Engels, dus
      // Pleya viel terug op Nederlands en dát is de spelende track op het
      // moment dat de speler naar N+1 gaat.
      final fallbackThatPlayed = _sub('2', lang: 'nld');
      final service = _svc(
        metadata: _episode('ep4'),
        sticky: _choice(subtitle: 'eng'),
      );

      final result = service.selectSubtitleTrack(
        [_sub('1', lang: 'eng'), _sub('2', lang: 'nld')],
        fallbackThatPlayed,
        null,
      );

      expect(
        result.track.language,
        'eng',
        reason: 'DEC-096 lid 1: een terugval is geen uitdrukkelijke keuze en mag de serievoorkeur niet verdringen',
      );
      expect(
        result.priority,
        isNot(TrackSelectionPriority.navigation),
        reason: 'de doorgegeven track is de uitkomst van de vorige aflevering, niet de bedoeling van de kijker',
      );
    });

    test('ondertitels: een terugval op "uit" besmet de volgende aflevering niet', () {
      // Aflevering N had helemaal geen ondertitels, dus de speler stond op uit.
      final service = _svc(
        metadata: _episode('ep4'),
        sticky: _choice(subtitle: 'eng'),
      );

      final result = service.selectSubtitleTrack([_sub('1', lang: 'eng')], SubtitleTrack.off, null);

      expect(result.track.language, 'eng', reason: 'een lege trackset in de vorige aflevering is geen keuze voor uit');
    });

    test('audio: aflevering N viel terug op de standaardtrack, N+1 heeft de gewenste taal weer', () {
      final fallbackThatPlayed = _audio('2', lang: 'jpn');
      final service = _svc(
        metadata: _episode('ep4'),
        sticky: _choice(audio: 'eng'),
      );

      final result = service.selectAudioTrack([_audio('1', lang: 'eng'), _audio('2', lang: 'jpn')], fallbackThatPlayed);

      expect(result?.track.language, 'eng');
      expect(result?.priority, isNot(TrackSelectionPriority.navigation));
    });

    test('een terugval wordt niet als serievoorkeur weggeschreven', () async {
      // De opslag mag na een terugval nog steeds de oorspronkelijke intentie
      // dragen. Vandaag schrijft prioriteit `navigation` de spelende track weg
      // via onAudioTrackChanged, en dat maakt de terugval permanent.
      await TrackPreferenceStore.saveSubtitle(_episode('ep3'), language: 'eng');

      final service = _svc(
        metadata: _episode('ep4'),
        sticky: _choice(subtitle: 'eng'),
      );
      final result = service.selectSubtitleTrack([_sub('2', lang: 'nld')], _sub('2', lang: 'nld'), null);

      expect(
        result.priority,
        isNot(TrackSelectionPriority.navigation),
        reason: 'alleen prioriteit navigation schrijft terug naar de opslag; een terugval mag dat pad niet raken',
      );
      expect((await TrackPreferenceStore.read(_episode('ep4')))?.subtitleLanguage, 'eng');
    });
  });

  // ────────────────────────────────────────────────────────────────
  // CONTROL B — de serievoorkeur werkt over aflevering en seizoen heen
  // ────────────────────────────────────────────────────────────────
  group('CONTROL B — de serievoorkeur geldt over afleveringen en seizoenen', () {
    test('elke aflevering van dezelfde serie resolveert dezelfde intentie', () async {
      await TrackPreferenceStore.saveSubtitle(_episode('s2e4'), language: 'eng');
      await TrackPreferenceStore.saveAudio(_episode('s2e4'), language: 'eng');

      for (final id in ['s2e5', 's2e6', 's3e1']) {
        final stored = await TrackPreferenceStore.read(_episode(id));
        expect(stored?.subtitleLanguage, 'eng', reason: 'aflevering $id');
        expect(stored?.audioLanguage, 'eng', reason: 'aflevering $id');

        final service = _svc(metadata: _episode(id), sticky: stored);
        final subs = service.selectSubtitleTrack([_sub('1', lang: 'eng'), _sub('2', lang: 'nld')], null, null);
        expect(subs.track.language, 'eng', reason: 'aflevering $id');
        expect(subs.priority, TrackSelectionPriority.sticky);
      }
    });
  });

  // ────────────────────────────────────────────────────────────────
  // CONTROL D — gewenst, terugval, gewenst weer beschikbaar
  // ────────────────────────────────────────────────────────────────
  group('CONTROL D — de gewenste taal komt vanzelf terug', () {
    test('aflevering 3 kiest de gewenste taal weer, na een terugval in 2', () {
      final sticky = _choice(subtitle: 'eng');

      // Aflevering 1: Engels aanwezig, Engels gekozen.
      final one = _svc(
        metadata: _episode('ep1'),
        sticky: sticky,
      ).selectSubtitleTrack([_sub('1', lang: 'eng'), _sub('2', lang: 'nld')], null, null);
      expect(one.track.language, 'eng');

      // Aflevering 2: geen Engels. Wat er ook uit de terugval komt, het is een
      // resolutie en geen intentie — dus geef het door zoals de speler dat nu
      // doet en kijk wat aflevering 3 ervan maakt.
      final two = _svc(
        metadata: _episode('ep2'),
        sticky: sticky,
      ).selectSubtitleTrack([_sub('2', lang: 'nld')], one.track, null);

      // Aflevering 3: Engels weer aanwezig, en de terugval uit 2 mag niet winnen.
      final three = _svc(
        metadata: _episode('ep3'),
        sticky: sticky,
      ).selectSubtitleTrack([_sub('1', lang: 'eng'), _sub('2', lang: 'nld')], two.track, null);
      expect(three.track.language, 'eng', reason: 'DEC-096 lid 1: elke aflevering resolveert de intentie opnieuw');
    });

    // Het terugvalcontract zelf (gewenste taal → terugvaltaal → uit) hangt aan
    // de profielvoorkeur en staat daarom in `lang1_controls_management_test.dart`.
  });

  // ────────────────────────────────────────────────────────────────
  // CONTROL E / F — rememberPerSeries aan en uit
  // ────────────────────────────────────────────────────────────────
  group('CONTROL E — handmatige wissel met onthouden aan schrijft de serie-override', () {
    test('een bewuste keuze landt in de serievoorkeur', () async {
      await PleyaProfileLanguagePreferenceStore.write(const PleyaProfileLanguagePreferences(rememberPerSeries: true));

      await TrackPreferenceStore.saveSubtitle(_episode('s1e1'), language: 'eng');

      expect((await TrackPreferenceStore.read(_episode('s1e2')))?.subtitleLanguage, 'eng');
    });
  });

  group('CONTROL F — handmatige wissel met onthouden uit schrijft geen override', () {
    test('met de schakelaar uit blijft de opslag leeg', () async {
      await PleyaProfileLanguagePreferenceStore.write(const PleyaProfileLanguagePreferences(rememberPerSeries: false));

      // De schakelaar hoort in de schrijflaag te zitten, niet alleen bij de
      // aanroepers: TrackPreferenceStore is de eigenaar van de serievoorkeur.
      await TrackPreferenceStore.saveSubtitle(_episode('s1e1'), language: 'eng');

      expect(
        await TrackPreferenceStore.read(_episode('s1e2')),
        isNull,
        reason: 'DEC-096 lid 3: staat onthouden uit, dan ontstaat er geen serie-override',
      );
    });
  });
}
