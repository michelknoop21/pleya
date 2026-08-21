import 'package:path/path.dart' as p;

import '../media/media_source_info.dart';
import '../mpv/models.dart';
import 'language_codes.dart';
import 'track_metadata_normalizer.dart';

/// How a player track was tied to a server stream. Ordered strongest first;
/// the order is also the order the passes run in.
enum SubtitleMatchStrategy {
  /// The external URI carries the server's own stream key or delivery path.
  externalUri,

  /// A sidecar our downloader wrote, whose filename *is* the server track id.
  sidecarFileId,

  /// mpv's container stream index equals a unique server stream index.
  serverStreamIndex,

  /// One server stream, and only one, shares this track's language, codec,
  /// forced flag and title.
  uniqueAttributes,

  /// Position, either through a wholly aligned list or between two anchors
  /// that a stronger strategy already pinned.
  positional,

  /// A language code recognised in a local sidecar's filename. Never a match
  /// to a server stream, only a language hint.
  filenameToken,

  /// Nothing could be proven.
  none,
}

/// How much a match is worth. Only [exact] and [strong] may reach persisted
/// preferences; [inferred] is good enough to put on screen and no further.
enum SubtitleMatchConfidence { exact, strong, inferred, none }

class ResolvedSubtitleTrack {
  final SubtitleTrack track;
  final MediaSubtitleTrack? server;
  final SubtitleMatchStrategy strategy;
  final SubtitleMatchConfidence confidence;

  /// Normalised ISO 639-1 code the resolver stands behind. Null whenever the
  /// evidence is ambiguous — never a guess.
  final String? resolvedLanguageCode;

  /// Whether [resolvedLanguageCode] came from somewhere other than the mpv
  /// track's own tag.
  final bool languageFromServer;

  const ResolvedSubtitleTrack({
    required this.track,
    required this.server,
    required this.strategy,
    required this.confidence,
    required this.resolvedLanguageCode,
    required this.languageFromServer,
  });

  bool get isStorable => confidence == SubtitleMatchConfidence.exact || confidence == SubtitleMatchConfidence.strong;

  /// Short token for the diagnostics line. Deliberately a closed vocabulary:
  /// it can never leak a path, a URL or a matched filename token.
  String get diagnosticToken => switch (strategy) {
    SubtitleMatchStrategy.externalUri => 'uri',
    SubtitleMatchStrategy.sidecarFileId => 'file',
    SubtitleMatchStrategy.serverStreamIndex => 'idx',
    SubtitleMatchStrategy.uniqueAttributes => 'attr',
    SubtitleMatchStrategy.positional => 'pos',
    SubtitleMatchStrategy.filenameToken => 'name',
    SubtitleMatchStrategy.none => 'none',
  };
}

class SubtitleTrackResolution {
  final List<ResolvedSubtitleTrack> entries;

  /// Whether the embedded lists could be coupled by position wholesale. Kept
  /// for the diagnostics and as the predicate for the positional pass; it is
  /// no longer a gate on everything else.
  final SubtitleAlignmentOutcome alignment;

  const SubtitleTrackResolution({required this.entries, required this.alignment});

  ResolvedSubtitleTrack? forTrack(String mpvTrackId) => entries.where((e) => e.track.id == mpvTrackId).firstOrNull;

  int get resolvedCount => entries.where((e) => e.server != null).length;

  int get enrichedCount => entries.where((e) => e.languageFromServer).length;

  Map<String, int> get strategyHistogram {
    final counts = <String, int>{};
    for (final entry in entries) {
      counts[entry.diagnosticToken] = (counts[entry.diagnosticToken] ?? 0) + 1;
    }
    return counts;
  }
}

/// Whether the embedded player and server subtitle lists line up by position.
enum SubtitleAlignmentOutcome { aligned, noServerData, countMismatch, contradiction }

/// Ties mpv subtitle tracks to the server's stream metadata.
///
/// Resolves the whole list at once rather than one track at a time, because
/// three of the rules are claims about both lists together: uniqueness of an
/// attribute signature, uniqueness of a stream index, and positional
/// interpolation between already-claimed neighbours. Resolving per track would
/// also let two player tracks claim the same server stream.
///
/// Every strategy is conservative in the same way: it assigns only when
/// exactly one candidate qualifies, and every assignment is vetoed when both
/// sides name a language and the two disagree. Where nothing can be proven the
/// entry stays [SubtitleMatchStrategy.none] and the caller falls back to a
/// numbered label — a wrong language reads worse than no language.
class SubtitleTrackResolver {
  SubtitleTrackResolver._();

  static SubtitleTrackResolution resolve({
    required List<SubtitleTrack> playerTracks,
    required List<MediaSubtitleTrack> serverTracks,
  }) {
    final alignment = diagnoseSubtitleAlignment(playerTracks, serverTracks);
    final matches = <String, MediaSubtitleTrack>{};
    final strategies = <String, SubtitleMatchStrategy>{};
    final claimed = <MediaSubtitleTrack>{};

    void assign(SubtitleTrack track, MediaSubtitleTrack server, SubtitleMatchStrategy strategy) {
      matches[track.id] = server;
      strategies[track.id] = strategy;
      claimed.add(server);
    }

    List<SubtitleTrack> unresolved() => playerTracks.where((t) => !matches.containsKey(t.id)).toList();
    List<MediaSubtitleTrack> unclaimed() => serverTracks.where((t) => !claimed.contains(t)).toList();

    // 1 + 2 — identifiers both sides genuinely share.
    for (final track in unresolved()) {
      final uri = track.uri;
      if (uri == null) continue;
      final byUri = _singleWhere(unclaimed(), (server) => _uriNamesServerStream(uri, server));
      if (byUri != null && !_contradicts(track, byUri)) {
        assign(track, byUri, SubtitleMatchStrategy.externalUri);
        continue;
      }
      final byFile = _sidecarTrackId(uri);
      if (byFile == null) continue;
      final server = _singleWhere(unclaimed(), (server) => server.id == byFile);
      if (server != null && !_contradicts(track, server)) {
        assign(track, server, SubtitleMatchStrategy.sidecarFileId);
      }
    }

    // 3 — container stream index. Only reachable when mpv reported ff-index,
    // which is what keeps Plex out: its stream id is a database key, not a
    // position, and comparing the two would match by coincidence.
    for (final track in unresolved()) {
      final ffIndex = track.ffIndex;
      if (ffIndex == null) continue;
      final server = _singleWhere(unclaimed(), (server) => (server.index ?? server.id) == ffIndex);
      if (server != null && !_contradicts(track, server)) {
        assign(track, server, SubtitleMatchStrategy.serverStreamIndex);
      }
    }

    // 4 — a signature that is unique on both sides. Three passes, dropping the
    // weakest component each time, so an untagged codec doesn't sink an
    // otherwise obvious one-Dutch-one-English case.
    for (final relaxation in [0, 1, 2]) {
      for (final track in unresolved()) {
        final candidates = unclaimed().where((s) => _signatureMatches(track, s, relaxation)).toList();
        if (candidates.length != 1) continue;
        final server = candidates.single;
        // Mutual: that server stream must have no other suitor either.
        final rivals = unresolved().where((t) => _signatureMatches(t, server, relaxation)).toList();
        if (rivals.length != 1) continue;
        assign(track, server, SubtitleMatchStrategy.uniqueAttributes);
      }
    }

    // 5a — the whole embedded list lines up.
    if (alignment == SubtitleAlignmentOutcome.aligned) {
      final embeddedPlayer = playerTracks.where((t) => !t.isExternal).toList();
      final embeddedServer = serverTracks.where((t) => !t.isExternal).toList();
      for (var i = 0; i < embeddedPlayer.length; i++) {
        final track = embeddedPlayer[i];
        if (matches.containsKey(track.id)) continue;
        final server = embeddedServer[i];
        if (claimed.contains(server) || _contradicts(track, server)) continue;
        assign(track, server, SubtitleMatchStrategy.positional);
      }
    } else {
      // 5b — interpolate between anchors a stronger strategy already pinned.
      final embeddedPlayer = playerTracks.where((t) => !t.isExternal).toList();
      final embeddedServer = serverTracks.where((t) => !t.isExternal).toList();
      for (var i = 1; i < embeddedPlayer.length - 1; i++) {
        final track = embeddedPlayer[i];
        if (matches.containsKey(track.id)) continue;
        final before = matches[embeddedPlayer[i - 1].id];
        final after = matches[embeddedPlayer[i + 1].id];
        if (before == null || after == null) continue;
        final lower = embeddedServer.indexOf(before);
        final upper = embeddedServer.indexOf(after);
        if (lower < 0 || upper < 0 || upper - lower != 2) continue;
        final server = embeddedServer[lower + 1];
        if (claimed.contains(server) || _contradicts(track, server)) continue;
        assign(track, server, SubtitleMatchStrategy.positional);
      }
    }

    final entries = <ResolvedSubtitleTrack>[];
    for (final track in playerTracks) {
      final server = matches[track.id];
      final ownLanguage = normalizeLanguageCode(track.language);
      final serverLanguage = server == null
          ? null
          : normalizeLanguageCode(server.languageCode) ?? normalizeLanguageCode(server.language);

      var strategy = strategies[track.id] ?? SubtitleMatchStrategy.none;
      var confidence = switch (strategy) {
        SubtitleMatchStrategy.externalUri ||
        SubtitleMatchStrategy.sidecarFileId ||
        SubtitleMatchStrategy.serverStreamIndex => SubtitleMatchConfidence.exact,
        SubtitleMatchStrategy.uniqueAttributes || SubtitleMatchStrategy.positional => SubtitleMatchConfidence.strong,
        _ => SubtitleMatchConfidence.none,
      };

      var language = ownLanguage ?? serverLanguage;
      // 6 — last resort, and only where there is nothing at all to override:
      // no container tag, and no server stream to borrow from.
      if (language == null && server == null) {
        final hint = _sidecarNameLanguageHint(track);
        if (hint != null) {
          language = hint;
          strategy = SubtitleMatchStrategy.filenameToken;
          confidence = SubtitleMatchConfidence.inferred;
        }
      }

      entries.add(
        ResolvedSubtitleTrack(
          track: track,
          server: server,
          strategy: strategy,
          confidence: confidence,
          resolvedLanguageCode: language,
          languageFromServer: ownLanguage == null && language != null,
        ),
      );
    }

    return SubtitleTrackResolution(entries: entries, alignment: alignment);
  }

  static T? _singleWhere<T>(List<T> items, bool Function(T) test) {
    final matches = items.where(test).toList();
    return matches.length == 1 ? matches.single : null;
  }

  /// True when both sides name a language and they are different languages.
  static bool _contradicts(SubtitleTrack track, MediaSubtitleTrack server) {
    final own = normalizeLanguageCode(track.language);
    if (own == null) return false;
    final theirs = normalizeLanguageCode(server.languageCode) ?? normalizeLanguageCode(server.language);
    if (theirs == null) return false;
    return own != theirs;
  }

  /// Whether [uri] is the delivery address of [server]'s stream.
  ///
  /// Plex builds `{base}{key}.{ext}?…`, Jellyfin either its `DeliveryUrl` or
  /// `/Videos/{item}/{source}/Subtitles/{index}/Stream.{codec}`. The key match
  /// requires a delimiter after it, or `/library/streams/20` would match
  /// inside `/library/streams/200`.
  static bool _uriNamesServerStream(String uri, MediaSubtitleTrack server) {
    final key = server.key;
    if (key != null && key.isNotEmpty) {
      final at = uri.indexOf(key);
      if (at >= 0) {
        final after = at + key.length;
        if (after >= uri.length || '.?/&#'.contains(uri[after])) return true;
      }
    }
    return _jellyfinStreamIndexFromUri(uri) == (server.index ?? server.id);
  }

  static int? _jellyfinStreamIndexFromUri(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return null;
    final segments = parsed.pathSegments;
    for (var i = 0; i + 2 < segments.length; i++) {
      if (segments[i] != 'Subtitles') continue;
      if (!segments[i + 2].startsWith('Stream.')) continue;
      return int.tryParse(segments[i + 1]);
    }
    return null;
  }

  /// The server track id encoded in a sidecar filename our own downloader
  /// wrote (`{video}_subs/{trackId}.{ext}`). Parses the whole basename, never
  /// a substring, so `Show.S01E02.720p.srt` cannot land on stream id 2.
  static int? _sidecarTrackId(String uri) {
    final path = _localPath(uri);
    if (path == null) return null;
    final id = int.tryParse(p.basenameWithoutExtension(path));
    return (id != null && id > 0) ? id : null;
  }

  /// Local filesystem path behind [uri], or null when it addresses a server.
  static String? _localPath(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return uri;
    if (parsed.scheme.isEmpty) return uri;
    if (parsed.scheme == 'file') return Uri.decodeComponent(parsed.path);
    if (parsed.scheme == 'content') return Uri.decodeComponent(parsed.path);
    return null;
  }

  /// A language code spelled out in a local sidecar's own filename.
  ///
  /// Bounded hard, because "a token that looks like a language" is the one
  /// heuristic here. Local files only, never a delivery URL, whose path holds
  /// the library and the title. Basename only, never the directory, for the
  /// same reason. Codes only, never names, so a film called *Dutch* is not a
  /// Dutch subtitle. And a two-letter token only immediately before the
  /// extension, because `hi`, `it`, `no`, `id` and `pt` are all real ISO codes
  /// and all common release-name noise.
  static String? _sidecarNameLanguageHint(SubtitleTrack track) {
    final uri = track.uri;
    if (uri == null) return null;
    final path = _localPath(uri);
    if (path == null) return null;

    final tokens = p.basenameWithoutExtension(path).split(RegExp(r'[._\-\s]+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return null;

    for (var i = tokens.length - 1; i >= 0; i--) {
      final token = tokens[i].toLowerCase();
      if (token == 'forced') continue;
      if (token.length == 2 && i != tokens.length - 1) continue;
      if (token.length != 2 && token.length != 3) continue;
      if (!RegExp(r'^[a-z]+$').hasMatch(token)) continue;
      final code = LanguageCodes.getIso6391Code(token);
      if (code != null) return code;
    }
    return null;
  }

  static bool _signatureMatches(SubtitleTrack track, MediaSubtitleTrack server, int relaxation) {
    final own = normalizeLanguageCode(track.language);
    final theirs = normalizeLanguageCode(server.languageCode) ?? normalizeLanguageCode(server.language);
    // A signature without a language on either side proves nothing; that gap
    // is what the positional pass is for.
    if (own == null || theirs == null || own != theirs) return false;
    if (track.isForced != server.forced) return false;

    if (relaxation < 2) {
      final ownCodec = normalizeSubtitleCodec(track.codec);
      final theirCodec = normalizeSubtitleCodec(server.codec);
      if (ownCodec != null && theirCodec != null && ownCodec != theirCodec) return false;
    }
    if (relaxation < 1) {
      final ownTitle = normalizeTrackTitle(track.title, codec: track.codec, languageCode: own);
      final theirTitle = normalizeTrackTitle(
        server.title ?? server.displayTitle,
        codec: server.codec,
        languageCode: theirs,
      );
      if (ownTitle != null && theirTitle != null && ownTitle != theirTitle) return false;
    }
    return true;
  }
}

/// Whether the embedded player and server lists can be coupled by position
/// wholesale. No longer a gate on individual matches — the resolver's stronger
/// strategies run regardless — but still the predicate for the positional pass
/// and a useful line in the diagnostics.
SubtitleAlignmentOutcome diagnoseSubtitleAlignment(
  List<SubtitleTrack> playerTracks,
  List<MediaSubtitleTrack> serverTracks,
) {
  final embeddedPlayer = playerTracks.where((t) => !t.isExternal).toList();
  final embeddedServer = serverTracks.where((t) => !t.isExternal).toList();
  if (embeddedServer.isEmpty) return SubtitleAlignmentOutcome.noServerData;
  if (embeddedServer.length != embeddedPlayer.length) return SubtitleAlignmentOutcome.countMismatch;
  for (var i = 0; i < embeddedPlayer.length; i++) {
    if (SubtitleTrackResolver._contradicts(embeddedPlayer[i], embeddedServer[i])) {
      return SubtitleAlignmentOutcome.contradiction;
    }
  }
  return SubtitleAlignmentOutcome.aligned;
}
