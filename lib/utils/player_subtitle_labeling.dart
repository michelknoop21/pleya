import '../media/media_source_info.dart';
import '../mpv/mpv.dart';
import 'track_label_builder.dart';

/// Placeholder titles that carry no information — servers hand these out for
/// streams without a language, and letting them win the label would hide the
/// real language sitting further down the ladder.
const _placeholderTitles = {'unknown', 'onbekend', 'und', 'undetermined', 'undefined', 'no title'};

String? _dropPlaceholder(String? value) {
  if (value == null) return null;
  return _placeholderTitles.contains(value.trim().toLowerCase()) ? null : value;
}

/// Server-side metadata for the embedded subtitle stream that [track] plays,
/// or null when the lists can't be lined up with confidence.
///
/// mpv numbers embedded subtitle tracks in container order and the server
/// reports its streams in that same order, so the two are matched by position
/// among the non-external entries. Differing counts mean the assumption broke
/// (mixed sidecars, a filtered version); a wrong language reads worse than no
/// language, so nothing is merged in that case.
MediaSubtitleTrack? matchServerSubtitle({
  required SubtitleTrack track,
  required List<SubtitleTrack> playerTracks,
  required List<MediaSubtitleTrack> serverTracks,
}) {
  if (track.isExternal) return null;
  final embeddedPlayer = playerTracks.where((t) => !t.isExternal).toList();
  final embeddedServer = serverTracks.where((t) => !t.isExternal).toList();
  if (embeddedServer.isEmpty || embeddedServer.length != embeddedPlayer.length) return null;
  final position = embeddedPlayer.indexWhere((t) => t.id == track.id);
  if (position < 0) return null;
  if (_alignmentContradicts(embeddedPlayer, embeddedServer)) return null;
  return embeddedServer[position];
}

/// Whether the positional alignment is provably wrong: any pair where both
/// sides name a language and the names disagree.
///
/// Equal counts alone don't prove the lists line up — a version whose streams
/// the server reports in another order would still match on length. Where both
/// sides did tag a language, agreement is the evidence that they do line up;
/// one disagreement discredits the whole alignment, not just that pair.
bool _alignmentContradicts(List<SubtitleTrack> playerTracks, List<MediaSubtitleTrack> serverTracks) {
  for (var i = 0; i < playerTracks.length; i++) {
    final player = _dropPlaceholder(playerTracks[i].language)?.trim().toLowerCase();
    if (player == null) continue;
    final server = serverTracks[i];
    // Only codes are comparable: mpv reports ISO 639 ('nl'/'nld') while the
    // server's `language` is an English display name ('Dutch'), which would
    // read as a mismatch against every code. `language` is only consulted when
    // it happens to hold a code itself.
    final candidates = [
      server.languageCode,
      server.language,
    ].map((v) => _dropPlaceholder(v)?.trim().toLowerCase()).whereType<String>().where((v) => v.length <= 3);
    if (candidates.isEmpty) continue;
    // 'nl' vs 'nld' is the same language in two ISO revisions, so either being
    // a prefix of the other counts as agreement.
    final agrees = candidates.any((c) => c.startsWith(player) || player.startsWith(c));
    if (!agrees) return true;
  }
  return false;
}

/// Label for an mpv subtitle track, enriched with the server's stream metadata.
///
/// Direct play hands the UI only what the container tags carry, so an untagged
/// stream would fall all the way through to "Track N". The server usually does
/// know the language, so its `languageCode` / `displayTitle` fill the gaps —
/// container tags still win where they exist.
TrackLabel labelForPlayerSubtitle({
  required SubtitleTrack track,
  required int visibleIndex,
  required List<SubtitleTrack> playerTracks,
  required List<MediaSubtitleTrack> serverTracks,
}) {
  final server = matchServerSubtitle(track: track, playerTracks: playerTracks, serverTracks: serverTracks);
  return TrackLabelBuilder.subtitleLabel(
    title: _dropPlaceholder(track.title) ?? _dropPlaceholder(server?.title),
    language: track.language ?? server?.language,
    // The resolver prefers languageCode, so only offer the server's when the
    // container had nothing to say.
    languageCode: track.language == null ? server?.languageCode : null,
    codec: track.codec ?? server?.codec,
    forced: track.isForced || (server?.forced ?? false),
    displayTitle: _dropPlaceholder(server?.displayTitle),
    index: visibleIndex,
  );
}
