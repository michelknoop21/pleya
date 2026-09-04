/// LANG1 / DEC-096, negatieve controles H en I.
///
/// DEC-096 lid 7: de serievoorkeur hoort bij de logische serie zolang de
/// identiteit betrouwbaar is, en valt anders terug op de concrete
/// server-en-serie-sleutel. Een onterechte samenvoeging is erger dan een
/// gemiste, dus er komt geen samenvoeging op alleen titel en jaar bij.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/track_language_choice.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/services/track_preference_store.dart';

import '../test_helpers/prefs.dart';

/// Een aflevering op een concrete server. [showGuid] is de stabiele
/// catalogus-GUID van de *serie* — de enige betrouwbare cross-source identiteit
/// die een aflevering vandaag kan dragen.
MediaItem _episode({
  required String id,
  required String serverId,
  required String showRatingKey,
  String? showTitle,
  String? showGuid,
  MediaBackend backend = MediaBackend.plex,
}) => MediaItem(
  id: id,
  backend: backend,
  kind: MediaKind.episode,
  serverId: serverId,
  grandparentId: showRatingKey,
  grandparentTitle: showTitle,
  grandparentGuid: showGuid,
);

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    await (await StorageService.getInstance()).clearActiveProfileId();
    await (await SettingsService.getInstance()).write(
      SettingsService.trackLanguagePreferences,
      const <String, TrackLanguageChoice>{},
    );
  });

  // ────────────────────────────────────────────────────────────────
  // CONTROL H — dezelfde logische serie op een tweede betrouwbare bron
  // ────────────────────────────────────────────────────────────────
  group('CONTROL H — één logische serie deelt één voorkeur', () {
    const showGuid = 'plex://show/5d9c08254eefaa001f5daa1e';

    test('dezelfde serie op NAS en op Zolder leest dezelfde voorkeur terug', () async {
      final onNas = _episode(
        id: 'e1',
        serverId: 'nas',
        showRatingKey: '4021',
        showTitle: 'Severance',
        showGuid: showGuid,
      );
      final onAttic = _episode(
        id: 'e9',
        serverId: 'zolder',
        showRatingKey: '881',
        showTitle: 'Severance',
        showGuid: showGuid,
      );

      await TrackPreferenceStore.saveSubtitle(onNas, language: 'eng');

      expect(
        (await TrackPreferenceStore.read(onAttic))?.subtitleLanguage,
        'eng',
        reason: 'DEC-096 lid 7: dezelfde show-GUID is dezelfde logische serie, ook op een andere server',
      );
    });

    test('een tweede bron krijgt geen eigen regel omdat de ratingKey verschilt', () async {
      final onNas = _episode(id: 'e1', serverId: 'nas', showRatingKey: '4021', showGuid: showGuid);
      final onAttic = _episode(id: 'e9', serverId: 'zolder', showRatingKey: '881', showGuid: showGuid);

      await TrackPreferenceStore.saveSubtitle(onNas, language: 'eng');
      await TrackPreferenceStore.saveSubtitle(onAttic, language: 'nld');

      final settings = await SettingsService.getInstance();
      final entries = settings.read(SettingsService.trackLanguagePreferences);
      expect(entries.length, 1, reason: 'één logische serie is één regel, geen twee');
      expect((await TrackPreferenceStore.read(onNas))?.subtitleLanguage, 'nld');
    });
  });

  // ────────────────────────────────────────────────────────────────
  // CONTROL I — een onbetrouwbare identiteit wordt niet samengevoegd
  // ────────────────────────────────────────────────────────────────
  group('CONTROL I — zonder betrouwbare identiteit geen samenvoeging', () {
    test('twee series zonder show-GUID blijven gescheiden, ook bij dezelfde titel', () async {
      final first = _episode(id: 'e1', serverId: 'nas', showRatingKey: '4021', showTitle: 'The Office');
      final second = _episode(id: 'e2', serverId: 'zolder', showRatingKey: '881', showTitle: 'The Office');

      await TrackPreferenceStore.saveSubtitle(first, language: 'eng');

      expect(
        await TrackPreferenceStore.read(second),
        isNull,
        reason: 'een onterechte samenvoeging is erger dan een gemiste; titelgelijkheid is geen bewijs',
      );
    });

    test('een niet-bruikbare GUID telt niet als bewijs', () async {
      // `agents.none://` is Plex\'s markering voor "geen agent heeft dit
      // gematcht" en zegt dus niets over wat de serie is.
      const unmatched = 'com.plexapp.agents.none://4021?lang=en';
      final first = _episode(id: 'e1', serverId: 'nas', showRatingKey: '4021', showGuid: unmatched);
      final second = _episode(id: 'e2', serverId: 'zolder', showRatingKey: '881', showGuid: unmatched);

      await TrackPreferenceStore.saveSubtitle(first, language: 'eng');

      expect(await TrackPreferenceStore.read(second), isNull);
    });

    test('een serverlokale GUID zonder schema telt niet als bewijs', () async {
      final first = _episode(id: 'e1', serverId: 'nas', showRatingKey: '4021', showGuid: 'local-4021');
      final second = _episode(id: 'e2', serverId: 'zolder', showRatingKey: '881', showGuid: 'local-4021');

      await TrackPreferenceStore.saveSubtitle(first, language: 'eng');

      expect(await TrackPreferenceStore.read(second), isNull);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // Migratie van de bestaande serversleutel (17 augustus)
  // ────────────────────────────────────────────────────────────────
  group('legacy migratie — een bestaande voorkeur op de serversleutel gaat niet verloren', () {
    const showGuid = 'plex://show/5d9c08254eefaa001f5daa1e';

    test('een regel die op de serversleutel staat wordt nog gelezen', () async {
      // Zoals de opslag er vóór LANG1 uitzag: `{scope}|{grandparentId}`.
      final settings = await SettingsService.getInstance();
      await settings.write(SettingsService.trackLanguagePreferences, {
        '|4021': const TrackLanguageChoice(subtitleLanguage: 'eng', updatedAt: 1),
      });

      final item = _episode(id: 'e1', serverId: 'nas', showRatingKey: '4021', showGuid: showGuid);
      expect((await TrackPreferenceStore.read(item))?.subtitleLanguage, 'eng');
    });

    test('een schrijfactie promoveert de regel naar de logische sleutel', () async {
      final settings = await SettingsService.getInstance();
      await settings.write(SettingsService.trackLanguagePreferences, {
        '|4021': const TrackLanguageChoice(subtitleLanguage: 'eng', updatedAt: 1),
      });

      final onNas = _episode(id: 'e1', serverId: 'nas', showRatingKey: '4021', showGuid: showGuid);
      await TrackPreferenceStore.saveAudio(onNas, language: 'eng');

      final onAttic = _episode(id: 'e9', serverId: 'zolder', showRatingKey: '881', showGuid: showGuid);
      expect((await TrackPreferenceStore.read(onAttic))?.subtitleLanguage, 'eng');
      expect((await TrackPreferenceStore.read(onAttic))?.audioLanguage, 'eng');
    });
  });
}
