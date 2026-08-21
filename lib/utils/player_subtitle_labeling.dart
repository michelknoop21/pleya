import 'package:flutter/foundation.dart';

import '../i18n/strings.g.dart';
import '../media/media_source_info.dart';
import '../mpv/mpv.dart';
import 'app_logger.dart';
import 'subtitle_track_resolver.dart';
import 'track_label_builder.dart';

/// Placeholder titles that carry no information — servers hand these out for
/// streams without a language, and letting them win the label would hide the
/// real language sitting further down the ladder.
const _placeholderTitles = {'unknown', 'onbekend', 'und', 'undetermined', 'undefined', 'no title'};

String? _dropPlaceholder(String? value) {
  if (value == null) return null;
  return _placeholderTitles.contains(value.trim().toLowerCase()) ? null : value;
}

/// Holds this file's mutable state: the one-entry resolution cache and the
/// diagnostics dedupe signature.
class SubtitleLabeling {
  SubtitleLabeling._();

  static List<SubtitleTrack>? _cachedPlayerTracks;
  static List<MediaSubtitleTrack>? _cachedServerTracks;
  static SubtitleTrackResolution? _cachedResolution;
  static String? _lastDiagnosticsSignature;

  /// Resolution for these exact list instances.
  ///
  /// Both call sites hand the same list objects to every row they build, and
  /// a track sheet rebuilds constantly, so an identity cache turns N resolves
  /// per frame into one. The resolver itself stays a pure function; the cache
  /// lives here.
  static SubtitleTrackResolution resolutionFor(
    List<SubtitleTrack> playerTracks,
    List<MediaSubtitleTrack> serverTracks,
  ) {
    final cached = _cachedResolution;
    if (cached != null &&
        identical(_cachedPlayerTracks, playerTracks) &&
        identical(_cachedServerTracks, serverTracks)) {
      return cached;
    }
    final resolution = SubtitleTrackResolver.resolve(playerTracks: playerTracks, serverTracks: serverTracks);
    _cachedPlayerTracks = playerTracks;
    _cachedServerTracks = serverTracks;
    return _cachedResolution = resolution;
  }

  /// Clears both statics. Without this the second test in a file gets a
  /// silently deduplicated diagnostics line and a stale resolution, so a
  /// "nothing leaks into the log" assertion would pass vacuously.
  @visibleForTesting
  static void resetCachesForTest() {
    _lastDiagnosticsSignature = null;
    _cachedPlayerTracks = null;
    _cachedServerTracks = null;
    _cachedResolution = null;
  }
}

/// Label for an mpv subtitle track, enriched with the server's stream metadata.
///
/// Direct play hands the UI only what the container tags carry, so an untagged
/// stream would fall all the way through to a numbered label. The server
/// usually does know the language, so its metadata fills the gaps — container
/// tags still win where they exist, and nothing is borrowed from a server
/// stream the resolver could not tie to this track.
TrackLabel labelForPlayerSubtitle({
  required SubtitleTrack track,
  required int visibleIndex,
  required List<SubtitleTrack> playerTracks,
  required List<MediaSubtitleTrack> serverTracks,
  SubtitleTrackResolution? resolution,
}) {
  final entry = (resolution ?? SubtitleLabeling.resolutionFor(playerTracks, serverTracks)).forTrack(track.id);
  final server = entry?.server;
  return TrackLabelBuilder.subtitleLabel(
    title: _dropPlaceholder(track.title) ?? _dropPlaceholder(server?.title),
    language: track.language,
    // Only offered when the container had nothing to say, and only as the
    // code the resolver stands behind rather than whatever the server called
    // it — that is what turns an untagged Dutch stream into "Nederlands"
    // instead of a number.
    languageCode: track.language == null ? entry?.resolvedLanguageCode : null,
    codec: track.codec ?? server?.codec,
    forced: track.isForced || (server?.forced ?? false),
    displayTitle: _dropPlaceholder(server?.displayTitle),
    index: visibleIndex,
    numberLabel: (number) => t.videoControls.subtitleTrackNumber(number: number),
  );
}

/// One-line report of what the labeling saw, emitted only when the picture
/// actually changes — the track menus rebuild constantly.
///
/// Logged at info level on purpose: debug-level lines are dropped unless the
/// user turns debug logging on, and this needs to be readable in Settings →
/// Logs straight away (the only practical way to inspect a TV build).
///
/// Nothing here can carry a path, a URL or a token. `uri` is never rendered,
/// `key` is reduced to a flag, and the per-track strategy is a closed
/// vocabulary, so the rule that reads a filename can only ever report `name`.
void logSubtitleLabelingDiagnostics({
  required String surface,
  required List<SubtitleTrack> playerTracks,
  required List<MediaSubtitleTrack> serverTracks,
  bool? canUseSourceSubtitles,
}) {
  final resolution = SubtitleLabeling.resolutionFor(playerTracks, serverTracks);
  final player = playerTracks.indexed
      .map((pair) {
        final (index, t) = pair;
        final entry = resolution.forTrack(t.id);
        final strategy = entry == null ? '' : '#${entry.diagnosticToken}:${entry.confidence.name}';
        // An external track's id is `external:{uri}`, so printing it verbatim
        // would put the delivery URL — token and all — straight in the log.
        // The list position identifies the row just as well.
        final id = t.isExternal ? 'ext$index' : t.id;
        return '$id/${t.language ?? '-'}/${t.title ?? '-'}${t.isExternal ? '/ext' : ''}$strategy';
      })
      .join(', ');
  final server = serverTracks
      .map(
        (t) =>
            '${t.id}/${t.languageCode ?? '-'}/${t.language ?? '-'}/${t.displayTitle ?? '-'}'
            '${(t.key?.isNotEmpty ?? false) ? '/key' : ''}${t.external ? '/ext' : ''}',
      )
      .join(', ');
  final strategies = resolution.strategyHistogram.entries.map((e) => '${e.key}:${e.value}').join(',');
  final message =
      'subtitle-labeling[$surface] outcome=${resolution.alignment.name} '
      'source=${canUseSourceSubtitles ?? '-'} '
      'player=${playerTracks.length}(${playerTracks.where((t) => !t.isExternal).length} embedded) '
      'server=${serverTracks.length}(${serverTracks.where((t) => !t.isExternal).length} embedded) '
      'resolved=${resolution.resolvedCount}/${playerTracks.length} enriched=${resolution.enrichedCount} '
      'strategies=$strategies '
      'playerTracks=[$player] serverTracks=[$server]';
  if (message == SubtitleLabeling._lastDiagnosticsSignature) return;
  SubtitleLabeling._lastDiagnosticsSignature = message;
  appLogger.i(message);
}
