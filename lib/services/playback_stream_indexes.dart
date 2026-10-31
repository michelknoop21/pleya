/// Maps what the player has selected back to the backend's stream indexes, for
/// a progress report. Jellyfin needs them to keep a transcoded session on the
/// same streams.
library;

import '../media/media_backend.dart';
import '../media/media_item.dart';
import '../media/media_source_info.dart';
import '../mpv/mpv.dart';
import 'track_selection_service.dart';

int? currentAudioStreamIndex(Player player, MediaItem metadata, MediaSourceInfo info) {
  final playerAudioTracks = player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
  if (metadata.backend == MediaBackend.jellyfin &&
      (info.audioTracks.any((track) => track.isExternal) || playerAudioTracks.length <= 1)) {
    final selectedSourceTrack = _selectedSourceAudioTrack(info);
    if (selectedSourceTrack != null) return selectedSourceTrack.id;
  }

  final track = player.state.track.audio;
  if (track == null) return null;

  final ordinal = playerAudioTracks.indexOf(track);
  if (ordinal >= 0 && ordinal < info.audioTracks.length) return info.audioTracks[ordinal].id;

  final matched = findPlexTrackForMpvAudio(track, info.audioTracks, allMpvTracks: player.state.tracks.audio);
  if (matched != null) return matched.id;

  final parsedId = int.tryParse(track.id);
  if (parsedId != null && info.audioTracks.any((t) => t.id == parsedId)) return parsedId;

  return null;
}

MediaAudioTrack? _selectedSourceAudioTrack(MediaSourceInfo info) {
  for (final track in info.audioTracks) {
    if (track.selected) return track;
  }
  final defaultIndex = info.defaultAudioStreamIndex;
  if (defaultIndex == null) return null;
  for (final track in info.audioTracks) {
    if (track.id == defaultIndex) return track;
  }
  return null;
}

int? currentSubtitleStreamIndex(Player player, MediaSourceInfo info) {
  final track = player.state.track.subtitle;
  if (track == null || track.id == 'no') return -1;

  if (track.isExternal && track.uri != null) {
    for (final mediaTrack in info.subtitleTracks) {
      final key = mediaTrack.key;
      if (mediaTrack.isExternal && key != null && track.uri!.contains(key)) {
        return mediaTrack.id;
      }
    }
  }

  final ordinal = player.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList().indexOf(track);
  if (ordinal >= 0 && ordinal < info.subtitleTracks.length) return info.subtitleTracks[ordinal].id;

  final matched = findPlexTrackForMpvSubtitle(track, info.subtitleTracks, allMpvTracks: player.state.tracks.subtitle);
  if (matched != null) return matched.id;

  final parsedId = int.tryParse(track.id);
  if (parsedId != null && info.subtitleTracks.any((t) => t.id == parsedId)) return parsedId;

  return null;
}
