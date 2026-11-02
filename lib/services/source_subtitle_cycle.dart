import '../media/media_source_info.dart';

/// The track after [currentId] in a server's source list, wrapping at the end.
/// Off (0) and an unknown id start at the first track. Null without tracks.
MediaSubtitleTrack? nextSourceSubtitleTrack(List<MediaSubtitleTrack> tracks, int? currentId) {
  if (tracks.isEmpty) return null;
  final at = tracks.indexWhere((track) => track.id == currentId);
  return tracks[(at + 1) % tracks.length];
}
