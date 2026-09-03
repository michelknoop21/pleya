/// Which logical titles the Home billboard may show (hoofdstuk 9.5 of
/// docs/tvos-unified-experience.md).
///
/// Data only. Fase 8 owns every bit of hero presentation — the rounded
/// billboard, the 8-second rotation of hoofdstuk 9.6, artwork warm-up, the
/// late-hero rules of 9.7 — and none of that is decided here. This file
/// answers one question: given candidate rows that have already been
/// projected, which distinct groups are eligible, and in what order.
///
/// It also never picks a *source*. Selection is presentation, and hoofdstuk
/// 4.6/13.6 keep every write brongebonden: handing back a chosen
/// [UnifiedMediaSource] would put a source that a viewer never picked one
/// step away from a play, a delete or a mark-watched. Callers get whole
/// [UnifiedMediaGroup]s and route them through the activation coordinator
/// and the picker like every other card (hoofdstuk 4.4).
library;

import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_hub.dart';

class FeaturedSelector {
  /// [maxCount] caps the carousel at hoofdstuk 9.5's upper bound. The lower
  /// bound of that band (five slides) is deliberately *not* enforced: a
  /// library that only yields three eligible titles yields three, and
  /// padding it out would mean inventing content semantics the catalogue
  /// does not have.
  const FeaturedSelector({this.maxCount = 8});

  final int maxCount;

  /// Picks up to [maxCount] distinct groups from [candidateHubs], in the
  /// order the caller supplied them.
  ///
  /// The candidate order *is* the priority order of hoofdstuk 9.5
  /// (recent uitgebrachte films eerst — the hero stays the shop window of
  /// what is newly out, exactly like the current Home hero's release-date
  /// ordered `DiscoverProvider.latestMovies` — then persoonlijke Top Picks,
  /// recent toegevoegde series, redactionele hubs, fallback) — expressed by
  /// which rows the caller passes and in what sequence, not re-derived here
  /// from a backend score. Plex, Jellyfin and the local recommendation
  /// engine do not produce comparable numbers (hoofdstuk 17.3), so
  /// re-ranking on one would be arbitrary dressed up as relevance.
  ///
  /// [candidateHubs] is expected to be the bounded set the caller already
  /// projected. This selector never loads anything, and in particular never
  /// walks the complete catalogue looking for a better hero.
  ///
  /// [now] decides what counts as unreleased; it is injected so a given
  /// input always produces the same list.
  List<UnifiedMediaGroup> select(List<UnifiedMediaHub> candidateHubs, {DateTime? now}) {
    final asOf = now ?? DateTime.now();
    final selected = <UnifiedMediaGroup>[];
    final seenGroupIds = <String>{};
    final seenSourceKeys = <String>{};
    final seenBucketKeys = <String>{};

    for (final hub in candidateHubs) {
      for (final group in hub.groups) {
        if (selected.length >= maxCount) return selected;
        if (!_isEligible(group, asOf)) continue;
        if (_isDuplicate(group, seenGroupIds, seenSourceKeys, seenBucketKeys)) continue;

        seenGroupIds.add(group.groupId);
        seenSourceKeys.addAll(group.sources.map((s) => s.sourceKey));
        final bucketKey = group.identity.bucketKey;
        if (bucketKey != null) seenBucketKeys.add(bucketKey);
        selected.add(group);
      }
    }
    return selected;
  }

  /// Hoofdstuk 9.5: films and series only — never a loose episode — with a
  /// usable title, and never a title the metadata claims is still unreleased.
  bool _isEligible(UnifiedMediaGroup group, DateTime asOf) {
    final item = group.representativeSource.item;
    if (item.kind != MediaKind.movie && item.kind != MediaKind.show) return false;
    if ((item.title ?? '').trim().isEmpty) return false;
    return !_isUnreleased(item, asOf);
  }

  /// A release date in the future, or a release *year* beyond the current
  /// one. Both are checked because the two arrive from different places and
  /// a wrong one is common: hoofdstuk 9.5 calls this out as "geen
  /// unreleased titel door foute toekomstige metadata", so the stricter of
  /// the two available signals wins.
  bool _isUnreleased(MediaItem item, DateTime asOf) {
    final available = DateTime.tryParse((item.originallyAvailableAt ?? '').trim());
    if (available != null && available.isAfter(asOf)) return true;
    final year = item.year;
    return year != null && year > asOf.year;
  }

  /// A title already on a slide never gets a second one — including when it
  /// reaches the selector from two rows, or as two groups that the identity
  /// pipeline could not prove equal but that share a concrete source or a
  /// hoofdstuk 11.2 bucket. Over-rejecting here only costs the carousel a
  /// candidate it has alternatives for; a repeated slide is visible.
  bool _isDuplicate(
    UnifiedMediaGroup group,
    Set<String> seenGroupIds,
    Set<String> seenSourceKeys,
    Set<String> seenBucketKeys,
  ) {
    if (seenGroupIds.contains(group.groupId)) return true;
    if (group.sources.any((source) => seenSourceKeys.contains(source.sourceKey))) return true;
    final bucketKey = group.identity.bucketKey;
    return bucketKey != null && seenBucketKeys.contains(bucketKey);
  }
}
