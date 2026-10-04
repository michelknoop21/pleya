/// Where a track picked on the iPhone detail page lands in the DEC-109
/// cascade (DEC-140 follow-up).
///
/// The detail page does two things with a pick: it writes it to
/// [TrackPreferenceStore] (a no-op when "remember per series" is off) and it
/// passes it to the player as `preferredAudioTrack` / `preferredSubtitleTrack`.
/// The player's [TrackManager.applyTrackSelection] then reads the series
/// layer and the profile layer and runs [TrackSelectionService]. This test
/// replays that exact sequence, so it pins the order the viewer gets.
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

class _StubPlayer implements Player {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _film = MediaItem(id: 'film1', backend: MediaBackend.plex, kind: MediaKind.movie);

const _audioTracks = [
  AudioTrack(id: '1', language: 'eng', title: 'English'),
  AudioTrack(id: '2', language: 'nld', title: 'Nederlands'),
];
const _subtitleTracks = [
  SubtitleTrack(id: '1', language: 'eng', title: 'English'),
  SubtitleTrack(id: '2', language: 'nld', title: 'Nederlands'),
];

/// The detail page's pick followed by the player's selection, as in
/// `audio_selector.dart` and `TrackManager.applyTrackSelection`.
Future<({TrackSelectionResult<AudioTrack> audio, TrackSelectionResult<SubtitleTrack> subtitle})> _pickDutchThenPlay({
  required bool remember,
  String? profileAudio = 'eng',
  String? profileSubtitle = 'eng',
  String? profileSubtitleFallback,
}) async {
  await PleyaProfileLanguagePreferenceStore.write(
    PleyaProfileLanguagePreferences(
      audioLanguage: profileAudio,
      subtitleLanguage: profileSubtitle,
      subtitleFallbackLanguage: profileSubtitleFallback,
      rememberPerSeries: remember,
    ),
  );
  // Detail page: store write, gated by rememberPerSeries inside the store.
  await TrackPreferenceStore.saveAudio(_film, language: 'nld', title: 'Nederlands');
  await TrackPreferenceStore.saveSubtitle(_film, language: 'nld', title: 'Nederlands');

  // Player: the same reads TrackManager does per item.
  final service = TrackSelectionService(
    player: _StubPlayer(),
    metadata: _film,
    stickyChoice: await TrackPreferenceStore.read(_film),
    globalPreferences: await PleyaProfileLanguagePreferenceStore.read(),
  );
  final audio = service.selectAudioTrack(_audioTracks, _audioTracks[1])!;
  final subtitle = service.selectSubtitleTrack(_subtitleTracks, _subtitleTracks[1], audio.track);
  return (audio: audio, subtitle: subtitle);
}

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

  test('remember off, profile eng: the profile language beats the detail pick', () async {
    final r = await _pickDutchThenPlay(remember: false);
    expect(await TrackPreferenceStore.read(_film), isNull, reason: 'nothing is stored with remembering off');
    expect(r.audio.track.language, 'eng');
    expect(r.audio.priority, TrackSelectionPriority.globalProfile);
    expect(r.subtitle.track.language, 'eng');
    expect(r.subtitle.priority, TrackSelectionPriority.globalProfile);
  });

  test('remember on, profile eng: the stored pick (series layer) beats the profile', () async {
    final r = await _pickDutchThenPlay(remember: true);
    expect(r.audio.track.language, 'nld');
    expect(r.audio.priority, TrackSelectionPriority.sticky);
    expect(r.subtitle.track.language, 'nld');
    expect(r.subtitle.priority, TrackSelectionPriority.sticky);
  });

  test('remember off, profile without a language: the detail pick wins via navigation', () async {
    final r = await _pickDutchThenPlay(remember: false, profileAudio: null, profileSubtitle: null);
    expect(r.audio.track.language, 'nld');
    expect(r.audio.priority, TrackSelectionPriority.navigation);
    expect(r.subtitle.track.language, 'nld');
    expect(r.subtitle.priority, TrackSelectionPriority.navigation);
  });

  // Subtitles have a rule of their own: a wanted language the file lacks
  // ends the search before the navigation layer, so the detail pick is not
  // reached. Audio has no such rule and falls through to the pick.
  test('remember off, profile subtitle deu missing from the file: subtitles off, the pick is skipped', () async {
    final r = await _pickDutchThenPlay(remember: false, profileAudio: null, profileSubtitle: 'deu');
    expect(r.audio.track.language, 'nld');
    expect(r.audio.priority, TrackSelectionPriority.navigation);
    expect(r.subtitle.track, SubtitleTrack.off);
    expect(r.subtitle.priority, TrackSelectionPriority.off);
  });

  test('remember off, profile subtitle deu missing, fallback eng: the fallback beats the pick', () async {
    final r = await _pickDutchThenPlay(
      remember: false,
      profileAudio: null,
      profileSubtitle: 'deu',
      profileSubtitleFallback: 'eng',
    );
    expect(r.subtitle.track.language, 'eng');
    expect(r.subtitle.priority, TrackSelectionPriority.fallbackLanguage);
  });

  test('remember on, profile subtitle deu missing: the stored pick (series layer) still wins', () async {
    final r = await _pickDutchThenPlay(remember: true, profileAudio: null, profileSubtitle: 'deu');
    expect(r.subtitle.track.language, 'nld');
    expect(r.subtitle.priority, TrackSelectionPriority.sticky);
  });
}
