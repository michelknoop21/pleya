/// The tech table on the iPhone detail page shows the tracks playback will
/// start with: the player's own cascade over the same layers (DEC-140).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_file_info.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/media/pleya_profile_language_preferences.dart';
import 'package:pleya/media/track_language_choice.dart';
import 'package:pleya/services/pleya_profile_language_preference_store.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/services/track_preference_store.dart';
import 'package:pleya/screens/media_detail/detail_track_preview.dart';

import '../../test_helpers/prefs.dart';

final _film = MediaItem(id: 'film1', backend: MediaBackend.plex, kind: MediaKind.movie);

// Server default: English audio, no subtitles.
final _info = MediaFileInfo(
  audioTracks: [
    MediaAudioTrack(id: 1, languageCode: 'eng', selected: true),
    MediaAudioTrack(id: 2, languageCode: 'nld', selected: false),
  ],
  subtitleTracks: [
    MediaSubtitleTrack(id: 3, languageCode: 'eng', selected: false, forced: false),
    MediaSubtitleTrack(id: 4, languageCode: 'nld', selected: false, forced: false),
  ],
);

Future<void> _profile({String? audio, String? subtitle, bool remember = false}) =>
    PleyaProfileLanguagePreferenceStore.write(
      PleyaProfileLanguagePreferences(audioLanguage: audio, subtitleLanguage: subtitle, rememberPerSeries: remember),
    );

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

  test('no layers: the server default, subtitles off', () async {
    await _profile();
    final r = await resolveDetailTracks(_film, _info);
    expect((r.audioId, r.subtitleId), (1, null));
  });

  test('profile nld beats the server default eng, as in the player', () async {
    await _profile(audio: 'nld', subtitle: 'nld');
    final r = await resolveDetailTracks(_film, _info);
    expect((r.audioId, r.subtitleId), (2, 4));
  });

  test('remember off, profile eng: a pick of nld does not change what plays', () async {
    await _profile(audio: 'eng', subtitle: 'eng');
    final r = await resolveDetailTracks(
      _film,
      _info,
      audioPick: detailPlayerAudioTrack(_info.audioTracks[1]),
      subtitlePick: detailPlayerSubtitleTrack(_info.subtitleTracks[1]),
    );
    expect((r.audioId, r.subtitleId), (1, 3));
  });

  test('remember on: the stored pick is the series layer and wins', () async {
    await _profile(audio: 'eng', subtitle: 'eng', remember: true);
    await TrackPreferenceStore.saveAudio(_film, language: 'nld');
    await TrackPreferenceStore.saveSubtitle(_film, language: 'nld');
    final r = await resolveDetailTracks(_film, _info);
    expect((r.audioId, r.subtitleId), (2, 4));
  });

  test('no profile language: the pick plays', () async {
    await _profile();
    final r = await resolveDetailTracks(
      _film,
      _info,
      audioPick: detailPlayerAudioTrack(_info.audioTracks[1]),
      subtitlePick: detailPlayerSubtitleTrack(_info.subtitleTracks[1]),
    );
    expect((r.audioId, r.subtitleId), (2, 4));
  });

  test('profile subtitle deu missing from the file: off, whatever the pick', () async {
    await _profile(subtitle: 'deu');
    final r = await resolveDetailTracks(_film, _info, subtitlePick: detailPlayerSubtitleTrack(_info.subtitleTracks[1]));
    expect(r.subtitleId, isNull);
  });
}
