/// Pure text derivations for a search result row — iOS Unified 2026 fase 4,
/// mockup `05-zoeken.png`.
///
/// Next to `hero_text.dart` and for the same reason: a widget-free derivation
/// is testable on its own, and the mobile row is not the only surface that
/// will want these strings.
///
/// The three kinds read differently on purpose, because the question a viewer
/// is answering differs. For a film it is "which release is this"
/// (`2024 · Sci-fi · 2h 46m`), for a series "how much is there"
/// (`2023 · 2 seasons`), and for an episode "which one, of what"
/// (`Driftwood · S1 E2`). A single template would have to leave two of those
/// three half-empty.
library;

import '../../i18n/strings.g.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/unified/unified_media_group.dart';
import '../../utils/formatters.dart';

/// The row's title: an episode is named by itself, not by its show — the show
/// is already in [searchMetaLineFor] and the sections are separate, so a
/// viewer scanning Afleveringen is looking for the episode.
String searchTitleFor(MediaItem item) => item.displayTitle;

/// The row's one grey line under the title.
///
/// A field the backend did not report contributes nothing. There is no
/// placeholder and no "Unknown": an empty meta line is honest, a fabricated
/// one is not.
String searchMetaLineFor(MediaItem item) {
  final parts = switch (item.kind) {
    MediaKind.show || MediaKind.season => <String?>[item.year?.toString(), _seasonCount(item)],
    MediaKind.episode => <String?>[item.grandparentTitle, _episodeLabel(item)],
    _ => <String?>[item.year?.toString(), item.genres?.firstOrNull, _runtime(item)],
  };
  return parts.nonNulls.where((part) => part.isNotEmpty).join(' · ');
}

String? _seasonCount(MediaItem item) {
  final count = item.childCount;
  if (count == null || count <= 0) return null;
  return count == 1 ? t.unifiedCatalog.oneSeason : t.unifiedCatalog.seasons(count: count);
}

String? _episodeLabel(MediaItem item) {
  final season = item.parentIndex;
  final episode = item.index;
  if (season == null || episode == null) return null;
  return t.unifiedCatalog.discovery.episodeLabel(season: season, episode: episode);
}

String? _runtime(MediaItem item) {
  final duration = item.durationMs;
  if (duration == null || duration <= 0) return null;
  return formatDurationTextual(duration);
}

/// The trailing source count, or null when there is nothing to say.
///
/// One source is not information — the same rule the poster capsule follows
/// (rapport §8), applied to the row's text label. Mockup 05 draws "1 bron" on
/// one film row and nothing at all on the series row below it; the two cannot
/// both be the rule, and "only when it is more than one" is the one the rest
/// of the interface already keeps.
String? searchSourceCountFor(UnifiedMediaGroup group) {
  if (!group.hasMultipleSources) return null;
  return t.unifiedCatalog.sources(count: group.sources.length);
}
