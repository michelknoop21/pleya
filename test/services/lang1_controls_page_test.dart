/// LANG1 / DEC-096, negatieve controles J tot en met N: het beheer op de
/// pagina Taal en ondertitels (31 A), de sheet (31 B) en de twee toasts
/// (31 C en 31 D).
///
/// Deze controles verwijzen naar `TrackChoiceProvenance`,
/// `TrackPreferenceStore.clearKey` en `TrackSelectionService.fallbackNotice`,
/// die vóór deze bouwronde niet bestaan: dit bestand compileert daarom niet op
/// de code van `eae19cb4`, en dat is de vastgelegde rode uitkomst.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/playback_language_notice.dart';
import 'package:pleya/media/pleya_profile_language_preferences.dart';
import 'package:pleya/media/track_language_choice.dart';
import 'package:pleya/mpv/mpv.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/services/track_preference_store.dart';
import 'package:pleya/services/track_selection_service.dart';

import '../test_helpers/prefs.dart';

MediaItem _episode({
  String id = 'ep1',
  String show = 'show7',
  String showTitle = 'Severance',
  int season = 2,
  int episode = 4,
}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.episode,
  grandparentId: show,
  grandparentTitle: showTitle,
  grandparentThumbPath: '/library/metadata/$show/thumb/1',
  serverId: 'nas',
  parentIndex: season,
  index: episode,
);

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
    TrackPreferenceStore.deviceNameProvider = () async => 'Apple TV';
  });

  // ────────────────────────────────────────────────────────────────
  // CONTROL J — een bewaarde keuze draagt de herkomst die 31 A toont
  // ────────────────────────────────────────────────────────────────
  group('CONTROL J — herkomst bij de keuze', () {
    test('een keuze bewaart serie, poster, bron, aflevering en toestel', () async {
      await TrackPreferenceStore.saveSubtitle(_episode(), language: 'en', title: 'English');

      final stored = await TrackPreferenceStore.read(_episode());
      final provenance = stored!.provenance!;
      expect(provenance.title, 'Severance');
      expect(provenance.posterPath, '/library/metadata/show7/thumb/1');
      expect(provenance.serverId, 'nas');
      expect(provenance.episodeLabel, 'S2E4');
      expect(provenance.deviceName, 'Apple TV');
    });

    test('een tweede keuze verderop in de serie schrijft de herkomst bij', () async {
      await TrackPreferenceStore.saveSubtitle(_episode(), language: 'en');
      await TrackPreferenceStore.saveAudio(_episode(id: 'ep9', season: 3, episode: 1), language: 'en');

      final stored = await TrackPreferenceStore.read(_episode());
      expect(stored!.provenance!.episodeLabel, 'S3E1');
    });

    test('een film draagt zijn eigen titel en geen afleveringnummer', () async {
      final movie = MediaItem(
        id: 'movie1',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'Arrival',
        thumbPath: '/library/metadata/movie1/thumb/1',
        serverId: 'nas',
      );
      await TrackPreferenceStore.saveAudio(movie, language: 'en');

      final stored = await TrackPreferenceStore.read(movie);
      expect(stored!.provenance!.title, 'Arrival');
      expect(stored.provenance!.episodeLabel, isNull);
    });

    test('de herkomst overleeft serialisatie', () {
      const choice = TrackLanguageChoice(
        subtitleLanguage: 'en',
        updatedAt: 1234,
        provenance: TrackChoiceProvenance(
          title: 'Severance',
          posterPath: '/p',
          serverId: 'nas',
          seasonNumber: 2,
          episodeNumber: 4,
          deviceName: 'Apple TV',
        ),
      );
      final round = TrackLanguageChoice.fromJson(choice.toJson().cast<String, dynamic>());
      expect(round.provenance!.title, 'Severance');
      expect(round.provenance!.episodeLabel, 'S2E4');
      expect(round.provenance!.deviceName, 'Apple TV');
    });
  });

  // ────────────────────────────────────────────────────────────────
  // CONTROL K — de pagina leest alle serievoorkeuren van dit profiel
  // ────────────────────────────────────────────────────────────────
  group('CONTROL K — de lijst van 31 A', () {
    test('nieuwste eerst, met de herkomst erbij', () async {
      await TrackPreferenceStore.saveSubtitle(
        _episode(show: 'show1', showTitle: 'Shogun'),
        language: 'nl',
      );
      // Both writes stamp `DateTime.now()`, and two of them inside the same
      // millisecond order arbitrarily. The page sorts on that stamp, so the
      // test has to give it something to sort.
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await TrackPreferenceStore.saveSubtitle(
        _episode(show: 'show2', showTitle: 'Severance'),
        language: 'en',
      );

      final entries = await TrackPreferenceStore.readAllForActiveScope();
      expect(entries.map((e) => e.choice.provenance?.title), ['Severance', 'Shogun']);
      expect(entries.first.key, 'show2');
    });
  });

  // ────────────────────────────────────────────────────────────────
  // CONTROL L — "Gebruik globale voorkeur" wist precies één regel
  // ────────────────────────────────────────────────────────────────
  group('CONTROL L — wissen op sleutel', () {
    test('clearKey verwijdert de regel die de pagina toont en laat de rest staan', () async {
      await TrackPreferenceStore.saveSubtitle(
        _episode(show: 'show1', showTitle: 'Shogun'),
        language: 'nl',
      );
      await TrackPreferenceStore.saveSubtitle(
        _episode(show: 'show2', showTitle: 'Severance'),
        language: 'en',
      );

      await TrackPreferenceStore.clearKey('show2');

      final entries = await TrackPreferenceStore.readAllForActiveScope();
      expect(entries.map((e) => e.key), ['show1']);
      expect(await TrackPreferenceStore.read(_episode(show: 'show2')), isNull);
    });

    test('wissen werkt ook met "Onthoud keuzes per serie" uit', () async {
      await TrackPreferenceStore.saveSubtitle(_episode(show: 'show2'), language: 'en');
      await PleyaProfileLanguagePreferenceStore_setRemember(false);

      await TrackPreferenceStore.clearKey('show2');

      expect(await TrackPreferenceStore.readAllForActiveScope(), isEmpty);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // CONTROL M — de terugval meldt zich (31 D) en laat de opslag staan
  // ────────────────────────────────────────────────────────────────
  group('CONTROL M — de terugvalmelding', () {
    test('een aflevering zonder de gewenste taal levert een melding met eigenaar en talen', () {
      final service = _svc(
        metadata: _episode(),
        sticky: const TrackLanguageChoice(subtitleLanguage: 'en', updatedAt: 1),
        global: const PleyaProfileLanguagePreferences(subtitleFallbackLanguage: 'nl'),
      );

      final result = service.selectSubtitleTrack([_sub('1', lang: 'nl')], null, null);
      final notice = service.fallbackNotice(
        isSubtitle: true,
        priority: result.priority,
        actualLanguage: result.track.language,
        isOff: result.track.id == 'no',
      );

      expect(notice, isA<LanguageFallbackApplied>());
      final fallback = notice! as LanguageFallbackApplied;
      expect(fallback.wantedLanguage, 'en');
      expect(fallback.actualLanguage, 'nl');
      expect(fallback.fromSeriesPreference, isTrue);
      expect(fallback.seriesTitle, 'Severance');
      expect(fallback.subtitlesOff, isFalse);
    });

    test('geen gewenste en geen terugvaltaal: ondertitels uit, en dat is de melding', () {
      final service = _svc(
        metadata: _episode(),
        sticky: const TrackLanguageChoice(subtitleLanguage: 'en', updatedAt: 1),
      );

      final result = service.selectSubtitleTrack([_sub('1', lang: 'hu')], null, null);
      final notice =
          service.fallbackNotice(
                isSubtitle: true,
                priority: result.priority,
                actualLanguage: result.track.language,
                isOff: result.track.id == 'no',
              )!
              as LanguageFallbackApplied;

      expect(result.track.id, 'no');
      expect(notice.subtitlesOff, isTrue);
      expect(notice.wantedLanguage, 'en');
    });

    test('een globale wens die niet gehaald wordt noemt de globale voorkeur, niet de serie', () {
      final service = _svc(
        metadata: _episode(),
        global: const PleyaProfileLanguagePreferences(audioLanguage: 'ja'),
      );

      final result = service.selectAudioTrack([_audio('1', lang: 'en')], null)!;
      final notice =
          service.fallbackNotice(
                isSubtitle: false,
                priority: result.priority,
                actualLanguage: result.track.language,
                isOff: false,
              )!
              as LanguageFallbackApplied;

      expect(notice.fromSeriesPreference, isFalse);
      expect(notice.wantedLanguage, 'ja');
      expect(notice.actualLanguage, 'en');
    });

    test('de gewenste taal is er wel: geen melding', () {
      final service = _svc(
        metadata: _episode(),
        sticky: const TrackLanguageChoice(subtitleLanguage: 'en', updatedAt: 1),
      );

      final result = service.selectSubtitleTrack([_sub('1', lang: 'en')], null, null);
      expect(
        service.fallbackNotice(
          isSubtitle: true,
          priority: result.priority,
          actualLanguage: result.track.language,
          isOff: false,
        ),
        isNull,
      );
    });

    test('niemand had een wens: geen melding, ook niet als de bron iets kiest', () {
      final service = _svc(metadata: _episode());

      final result = service.selectAudioTrack([_audio('1', lang: 'de')], null)!;
      expect(
        service.fallbackNotice(
          isSubtitle: false,
          priority: result.priority,
          actualLanguage: result.track.language,
          isOff: false,
        ),
        isNull,
      );
    });

    test('een terugval raakt de opgeslagen serievoorkeur niet', () async {
      await TrackPreferenceStore.saveSubtitle(_episode(), language: 'en');
      final service = _svc(
        metadata: _episode(),
        sticky: await TrackPreferenceStore.read(_episode()),
        global: const PleyaProfileLanguagePreferences(subtitleFallbackLanguage: 'nl'),
      );

      service.selectSubtitleTrack([_sub('1', lang: 'nl')], null, null);

      final stored = await TrackPreferenceStore.read(_episode());
      expect(stored!.subtitleLanguage, 'en');
    });
  });
}

/// Zet alleen de schakelaar om, zonder de rest van de voorkeur aan te raken.
Future<void> PleyaProfileLanguagePreferenceStore_setRemember(bool value) async {
  final settings = await SettingsService.getInstance();
  final storage = await StorageService.getInstance();
  final scope = storage.activeUserScope() ?? '';
  final stored = settings.read(SettingsService.pleyaProfileLanguagePreferences);
  final current = stored[scope] ?? const PleyaProfileLanguagePreferences();
  await settings.write(SettingsService.pleyaProfileLanguagePreferences, {
    ...stored,
    scope: current.copyWith(rememberPerSeries: value),
  });
}
