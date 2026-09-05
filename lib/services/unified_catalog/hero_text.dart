/// Pure text derivations for a hero-style presentation of a
/// [UnifiedMediaGroup]: one metadata line and a display title.
///
/// Kept separate from any widget so a presentation layer can use it without
/// duplicating the derivation itself. Today's only caller is `MobileHeroCard`
/// (fase 1 van het iOS Unified 2026-plan, `docs/ios-unified-2026-fase1-plan.md`
/// stap 2); the tvOS billboard on `claude/netflix-redesign-b4x21v` builds its
/// own meta line over a different item shape (legacy `MediaItem`, a different
/// separator) and has not been moved onto this yet — that is TV-design work
/// outside this file's scope, not a promise this file is already keeping.
library;

import '../../i18n/strings.g.dart';
import '../../media/media_kind.dart';
import '../../media/unified/unified_media_group.dart';
import '../../utils/formatters.dart';

/// The hero's one metadata line: kind, genre, year, runtime, and — only when
/// there is more than one — the source count.
///
/// Pure and testable without a widget: a field that a group's representative
/// source did not report contributes nothing, never a placeholder.
String heroMetaLineFor(UnifiedMediaGroup group) {
  final item = group.representativeSource.item;
  final duration = item.durationMs;
  return [
    switch (item.kind) {
      MediaKind.movie => t.discover.movie,
      MediaKind.show || MediaKind.season || MediaKind.episode => t.discover.tvShow,
      _ => null,
    },
    if (item.genres != null && item.genres!.isNotEmpty) item.genres!.first,
    if (item.year != null) '${item.year}',
    if (duration != null && duration > 0) formatDurationTextual(duration),
    if (group.hasMultipleSources) t.unifiedCatalog.sources(count: group.sources.length),
  ].nonNulls.join(' · ');
}

/// The hero's display title: the group's representative item title, with an
/// episode falling back to its show's name.
String heroTitleFor(UnifiedMediaGroup group) {
  final item = group.representativeSource.item;
  return item.kind == MediaKind.episode ? (item.grandparentTitle ?? item.displayTitle) : item.displayTitle;
}
