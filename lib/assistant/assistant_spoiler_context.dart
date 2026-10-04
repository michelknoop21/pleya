import 'dart:convert';

import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import 'assistant_plot_index.dart';

/// A conservative content fence, established from the original question.
/// Routing text can request less access; it cannot remove this fence.
bool assistantNeedsSpoilerScope(String prompt) {
  final text = foldText(prompt);
  final explicit = RegExp(
    r'spoiler|spoilervrij|recap|summariz|summaris|summary|samenvat|personage|persoon|character|person\b|scene|who is|wie is|what happened|wat gebeurde|'
    r'gebleven|where was|wie was|who was|remind|herinner|verhaal|story|plot|'
    r'(welke|which|what).*(aflevering|episode)|(aflevering|episode).*(waarin|where)',
  ).hasMatch(text);
  if (explicit) return true;
  final explanation = RegExp(r'context|explain|explanation|uitleg|verklaar').hasMatch(text);
  // Exempt only a confidently technical-only explanation. A technical
  // clause elsewhere cannot remove the scope of a narrative/unknown clause.
  const technicalWords = {
    'explain',
    'explanation',
    'uitleg',
    'verklaar',
    'why',
    'is',
    'over',
    'waarom',
    'this',
    'the',
    'and',
    'de',
    'en',
    'my',
    'mijn',
    'playback',
    'transcode',
    'transcodes',
    'transcoding',
    'transcoderen',
    'afspelen',
    'afspeel',
    'buffer',
    'buffers',
    'buffering',
    'bufferen',
    'kwaliteit',
    'quality',
    'codec',
    'codecs',
    'subtitle',
    'subtitles',
    'ondertitel',
    'ondertitels',
    'audio',
    'video',
    'slow',
    'slower',
    'traag',
    'slowly',
    'langzaam',
    'fix',
    'repair',
    'herstel',
    'works',
    'work',
    'werkt',
    'niet',
    'not',
    'does',
  };
  const technicalSubjects = {
    'playback',
    'transcode',
    'transcodes',
    'transcoding',
    'transcoderen',
    'afspelen',
    'afspeel',
    'buffer',
    'buffers',
    'buffering',
    'bufferen',
    'kwaliteit',
    'quality',
    'codec',
    'codecs',
    'subtitle',
    'subtitles',
    'ondertitel',
    'ondertitels',
    'audio',
    'video',
  };
  // Search stopwords/single-letter filtering must not erase the subject of
  // an explanation. Preserve every folded word, including titles like X.
  final words = text.split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)).where((word) => word.isNotEmpty);
  final technicalOnly = words.any(technicalSubjects.contains) && words.every(technicalWords.contains);
  return explanation && !technicalOnly;
}

/// Only identity/order and live progress, never a title or plot from the player.
class AssistantWatchBoundary {
  const AssistantWatchBoundary({
    required this.profileId,
    required this.serverId,
    required this.libraryId,
    required this.showId,
    required this.episodeId,
    required this.season,
    required this.episode,
    required this.positionMs,
    required this.durationMs,
    required this.sessionId,
    required this.revision,
  });
  final String profileId, serverId, libraryId, showId, episodeId, sessionId, revision;
  final int season, episode, positionMs, durationMs;
  bool get known =>
      profileId.isNotEmpty &&
      serverId.isNotEmpty &&
      libraryId.isNotEmpty &&
      showId.isNotEmpty &&
      episodeId.isNotEmpty &&
      season > 0 &&
      episode > 0 &&
      positionMs >= 0 &&
      durationMs > 0 &&
      positionMs < durationMs;
}

/// Existing session providers supply the profile/visibility checks.
class AssistantSpoilerServices {
  const AssistantSpoilerServices({
    required this.profileId,
    required this.profileCurrent,
    required this.boundary,
    required this.boundaryCurrent,
    required this.libraryVisible,
    this.resume,
  });
  final String profileId;
  final bool Function() profileCurrent;
  final AssistantWatchBoundary? Function() boundary;
  final bool Function(AssistantWatchBoundary) boundaryCurrent;
  final bool Function(String serverId, String libraryId) libraryVisible;
  final Future<AssistantSpoilerResumeEvidence?> Function(bool Function() cancelled)? resume;
}

class AssistantSpoilerResumeEvidence {
  const AssistantSpoilerResumeEvidence({required this.boundary, required this.current, required this.refresh});
  final AssistantWatchBoundary boundary;
  final bool Function() current;
  final Future<bool> Function() refresh;
}

/// One bounded cache entry. Identity, profile, boundary and the exact allowed
/// content participate in the key; a cancelled build never reaches this cache.
class AssistantSpoilerIndexCache {
  static final shared = AssistantSpoilerIndexCache();
  Object? _key;
  AssistantPlotIndex? _index;
  void clear() {
    _key = null;
    _index = null;
  }

  AssistantPlotIndex indexFor(AssistantWatchBoundary boundary, MediaServerClient client, List<AssistantPlotDoc> docs) {
    final key = (
      client,
      boundary.profileId,
      boundary.sessionId,
      boundary.revision,
      boundary.serverId,
      boundary.libraryId,
      boundary.showId,
      boundary.episodeId,
      boundary.season,
      boundary.episode,
      boundary.positionMs,
      jsonEncode([
        for (final doc in docs) [doc.item.id, doc.item.title, doc.item.summary, doc.item.parentIndex, doc.item.index],
      ]),
    );
    if (_index != null && key == _key) return _index!;
    _key = key;
    return _index = AssistantPlotIndex(List.unmodifiable(docs));
  }
}

class AssistantSpoilerContext {
  const AssistantSpoilerContext({this.position, this.index, this.matches = const [], required this.current});
  final AssistantWatchBoundary? position;
  final AssistantPlotIndex? index;
  final List<AssistantPlotDoc> matches;
  final bool Function() current;

  String answer(String language) {
    final dutch = language == 'Dutch';
    final insufficient = dutch
        ? 'Onvoldoende veilige brongegevens voor personage- of scènedetails.'
        : 'Insufficient safe source data for character or scene details.';
    if (!current() || position == null) {
      return dutch
          ? 'Je huidige kijkpositie is niet betrouwbaar bekend. $insufficient'
          : 'Your current watch position is not reliably known. $insufficient';
    }
    final p = position!;
    final seconds = p.positionMs ~/ 1000;
    final at = '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    final label = dutch ? 'Kijkpositie' : 'Watch position';
    return [
      '$label: S${p.season} E${p.episode}, $at.',
      for (final doc in matches) 'S${doc.item.parentIndex} E${doc.item.index}: ${_snippet(doc.item.summary!)}',
      insufficient,
    ].join('\n');
  }
}

DateTime? _airDate(String? value) {
  if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
  final parsed = DateTime.tryParse(value);
  return parsed != null && parsed.toIso8601String().startsWith(value) ? parsed : null;
}

String _snippet(String text) => text.length <= 400 ? text : '${text.substring(0, 400)}…';

/// Filter before constructing documents/tokenizing/ranking. Never reuse the
/// unrestricted movies/shows index or any external source. Fetches are capped
/// and bounded; the caller rechecks [current] before publishing.
Future<AssistantSpoilerContext> buildAssistantSpoilerContext({
  required AssistantSpoilerServices? services,
  required MediaServerClient? Function(String) clientFor,
  required bool Function() cancelled,
  required String question,
  AssistantSpoilerIndexCache? cache,
}) async {
  cache ??= AssistantSpoilerIndexCache.shared;
  AssistantSpoilerContext unknown() {
    cache!.clear();
    return AssistantSpoilerContext(current: () => false);
  }

  if (services == null || cancelled() || !services.profileCurrent()) return unknown();
  AssistantSpoilerResumeEvidence? resume;
  var selectedBoundary = services.boundary();
  if (selectedBoundary == null && services.resume != null) {
    try {
      resume = await services.resume!(cancelled).timeout(const Duration(seconds: 8));
    } catch (_) {
      return unknown();
    }
    selectedBoundary = resume?.boundary;
  }
  final boundary = selectedBoundary;
  if (boundary == null || !boundary.known || boundary.profileId != services.profileId) return unknown();
  final client = clientFor(boundary.serverId);
  if (client == null) return unknown();
  bool current() =>
      !cancelled() &&
      services.profileCurrent() &&
      (resume?.current() ?? services.boundaryCurrent(boundary)) &&
      services.libraryVisible(boundary.serverId, boundary.libraryId) &&
      identical(clientFor(boundary.serverId), client);
  if (!current()) return unknown();
  bool attributed(MediaItem item) {
    if (item.libraryId == boundary.libraryId) return true;
    // The resume adapter already proved top-library membership through an
    // exact current-user recursive query. Its same-series descendants may
    // omit ParentLibraryId; ParentId is then a season/show, not the root.
    final raw = item.raw;
    return resume != null && raw != null && raw['Id'] == item.id && !raw.containsKey('ParentLibraryId');
  }

  final candidates = <MediaItem>[];
  DateTime? boundaryDate;
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  Duration remaining() => deadline.difference(DateTime.now());
  try {
    final seasons = await client.fetchChildren(boundary.showId).timeout(remaining());
    if (!current()) return unknown();
    // Only positively numbered regular seasons; specials/alternate unknown
    // ordering are excluded. No future seasons need to be fetched.
    final earlier = seasons.where(
      (s) => s.kind == MediaKind.season && s.index != null && s.index! > 0 && s.index! <= boundary.season,
    );
    if (earlier.length > 30 || earlier.map((s) => s.index).toSet().length != earlier.length) return unknown();
    final seenOrder = <(int, int)>{};
    var count = 0;
    var foundBoundary = false;
    for (final season in earlier) {
      if (!current()) return unknown();
      if (season.serverId != null && season.serverId != boundary.serverId) return unknown();
      if (season.parentId != boundary.showId || !attributed(season)) return unknown();
      final episodes = await client.fetchChildren(season.id).timeout(remaining());
      if (!current()) return unknown();
      count += episodes.length;
      if (count > 2000) return unknown();
      for (final item in episodes) {
        if (item.kind != MediaKind.episode ||
            item.parentId != season.id ||
            item.grandparentId != boundary.showId ||
            !attributed(item) ||
            (item.serverId != null && item.serverId != boundary.serverId) ||
            item.parentIndex != season.index ||
            item.index == null ||
            item.index! <= 0) {
          continue;
        }
        if (!seenOrder.add((item.parentIndex!, item.index!))) return unknown();
        // Jellyfin retains compound-episode numbering in its raw DTO. A
        // summary can cover the whole range; a current range has no proved
        // single-episode position. Exclude both before constructing documents.
        if (item is JellyfinMediaItem) {
          final end = item.raw?['IndexNumberEnd'];
          if (end != null && (end is! int || end != item.index)) {
            if (item.id == boundary.episodeId) return unknown();
            continue;
          }
        }
        if (item.id == boundary.episodeId && item.parentIndex == boundary.season && item.index == boundary.episode) {
          boundaryDate = _airDate(item.originallyAvailableAt);
          foundBoundary = true;
        }
        final before =
            item.parentIndex! < boundary.season ||
            (item.parentIndex == boundary.season && item.index! < boundary.episode);
        // A rewatch's watched flag never opens the current/future episode.
        if (!before ||
            item.id == boundary.episodeId ||
            item.viewCount == null ||
            item.viewCount! <= 0 ||
            (item.viewOffsetMs ?? 0) > 0 ||
            item.summary == null ||
            item.summary!.trim().isEmpty) {
          continue;
        }
        final safe = MediaItem(
          id: item.id,
          backend: item.backend,
          kind: MediaKind.episode,
          serverId: boundary.serverId,
          libraryId: boundary.libraryId,
          parentId: season.id,
          grandparentId: boundary.showId,
          parentIndex: item.parentIndex,
          index: item.index,
          title: item.title,
          summary: item.summary,
          originallyAvailableAt: item.originallyAvailableAt,
        );
        candidates.add(safe);
      }
    }
    if (!current() || !foundBoundary) return unknown();
    if (resume != null && !await resume.refresh().timeout(remaining())) return unknown();
    if (!current()) return unknown();
    // The existing watch-order rule uses air date, with regular numeric
    // order as fallback. Same-day releases retain their positive episode
    // order; a contradictory later air date cannot qualify as earlier.
    final docs = [
      for (final item in candidates)
        if (boundaryDate == null ||
            _airDate(item.originallyAvailableAt) == null ||
            !_airDate(item.originallyAvailableAt)!.isAfter(boundaryDate))
          AssistantPlotDoc(boundary.serverId, item),
    ];
    final index = cache.indexFor(boundary, client, docs);
    final matches = index.search([question], limit: 3, kind: MediaKind.episode).map((hit) => hit.doc).toList();
    return AssistantSpoilerContext(
      position: boundary,
      index: index,
      matches: List.unmodifiable(matches),
      current: current,
    );
  } catch (_) {
    return unknown();
  }
}
