import '../../media/media_file_info.dart';
import '../../media/media_item.dart';
import '../../media/media_source_info.dart';
import '../../mpv/models.dart';
import '../../services/pleya_profile_language_preference_store.dart';
import '../../services/track_preference_store.dart';
import '../../services/track_selection_service.dart';

/// A detail-page audio track as the player's track type, so a pick can be
/// handed to the player and the table can run the player's own cascade.
AudioTrack detailPlayerAudioTrack(MediaAudioTrack track) => AudioTrack(
  id: track.id.toString(),
  title: track.title ?? track.displayTitle,
  language: track.languageCode ?? track.language,
  codec: track.codec,
  channels: track.channels,
  profile: track.profile,
  isDefault: track.selected,
);

SubtitleTrack detailPlayerSubtitleTrack(MediaSubtitleTrack track) => SubtitleTrack(
  id: track.id.toString(),
  title: track.title ?? track.displayTitle,
  language: track.languageCode ?? track.language,
  codec: track.codec,
  isDefault: track.selected,
  isForced: track.forced,
);

/// The audio and subtitle track ids playback of [item] starts with from the
/// detail page, "off" being a null subtitle id, and whether a pick there is
/// stored as the series preference ("per serie onthouden"): [TrackSelectionService]'s
/// cascade over the stored series choice, the profile language, the page's
/// pick and then the source, the same reads `TrackManager` does. The table
/// shows this, so it agrees with what Play does.
///
/// ponytail: the source layer is the server's `selected` flag as the file's
/// default track; the player also matches the live stream list and the
/// server profile, which can differ for files with external subtitles.
Future<({int? audioId, int? subtitleId, bool remembered})> resolveDetailTracks(
  MediaItem item,
  MediaFileInfo info, {
  AudioTrack? audioPick,
  SubtitleTrack? subtitlePick,
}) async {
  final profile = await PleyaProfileLanguagePreferenceStore.read();
  final service = TrackSelectionService.preview(
    metadata: item,
    stickyChoice: await TrackPreferenceStore.read(item),
    globalPreferences: profile,
  );
  final audio = service.selectAudioTrack([for (final t in info.audioTracks) detailPlayerAudioTrack(t)], audioPick);
  final subtitle = service.selectSubtitleTrack(
    [for (final t in info.subtitleTracks) detailPlayerSubtitleTrack(t)],
    subtitlePick,
    audio?.track,
  );
  return (
    audioId: int.tryParse(audio?.track.id ?? ''),
    subtitleId: int.tryParse(subtitle.track.id),
    remembered: profile.rememberPerSeries,
  );
}
