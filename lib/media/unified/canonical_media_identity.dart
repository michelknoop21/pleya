/// The identity a source is bucketed and grouped on (hoofdstuk 11 of
/// docs/tvos-unified-experience.md). Pure value type: no I/O, no server
/// concepts. [canonicalIdentityOf] is the one place a [MediaItem] gets turned
/// into one, so every future caller (Home, Films, Series, Search, Verder
/// kijken, Watchlist) reads the same rules instead of re-deriving them.
library;

import '../media_item.dart';
import '../media_kind.dart';
import '../../utils/title_normalizer.dart';

/// The granularity a [CanonicalMediaIdentity] was built at. Kept distinct
/// from [MediaKind] because grouping sometimes needs an identity at a
/// granularity other than the source item's own kind — e.g. an episode's
/// *show* identity — without inventing a second enum for that.
enum CanonicalIdentityGranularity {
  movie,
  show,
  season,
  episode,

  /// No hoofdstuk 11.1 rule applies (collections, playlists, music, folders,
  /// ...). Never bucketable, so [CanonicalMediaIdentity.opaque] instances
  /// never auto-merge with anything — a source with no defined identity rule
  /// still needs a group of its own (grouping never drops a source), it just
  /// never grows one.
  other,
}

/// A content identity to bucket and group sources on. Two sources with an
/// identical [CanonicalMediaIdentity] (or overlapping strong tokens, see
/// `identity_evidence.dart`) describe the same logical title.
class CanonicalMediaIdentity {
  final CanonicalIdentityGranularity granularity;

  /// Normalized (lower-case, punctuation-stripped) title at this granularity.
  /// For [CanonicalIdentityGranularity.episode]/[season] this is the *show's*
  /// title, not the episode/season's own name.
  final String? normalizedTitle;

  /// Release year. Only meaningful for [CanonicalIdentityGranularity.movie]
  /// and [CanonicalIdentityGranularity.show].
  final int? year;

  /// 1-based season number. Set for [season] and [episode].
  final int? seasonIndex;

  /// 1-based episode number within [seasonIndex]. Set for [episode] only.
  final int? episodeIndex;

  const CanonicalMediaIdentity._({
    required this.granularity,
    this.normalizedTitle,
    this.year,
    this.seasonIndex,
    this.episodeIndex,
  });

  factory CanonicalMediaIdentity.movie({String? title, int? year}) => CanonicalMediaIdentity._(
    granularity: CanonicalIdentityGranularity.movie,
    normalizedTitle: _normalizedOrNull(title),
    year: year,
  );

  factory CanonicalMediaIdentity.show({String? title, int? year}) => CanonicalMediaIdentity._(
    granularity: CanonicalIdentityGranularity.show,
    normalizedTitle: _normalizedOrNull(title),
    year: year,
  );

  factory CanonicalMediaIdentity.season({String? showTitle, int? seasonIndex}) => CanonicalMediaIdentity._(
    granularity: CanonicalIdentityGranularity.season,
    normalizedTitle: _normalizedOrNull(showTitle),
    seasonIndex: seasonIndex,
  );

  factory CanonicalMediaIdentity.episode({String? showTitle, int? seasonIndex, int? episodeIndex}) =>
      CanonicalMediaIdentity._(
        granularity: CanonicalIdentityGranularity.episode,
        normalizedTitle: _normalizedOrNull(showTitle),
        seasonIndex: seasonIndex,
        episodeIndex: episodeIndex,
      );

  factory CanonicalMediaIdentity.opaque() =>
      const CanonicalMediaIdentity._(granularity: CanonicalIdentityGranularity.other);

  static String? _normalizedOrNull(String? title) {
    final normalized = normalizeTitleForMatching(title);
    return normalized.isEmpty ? null : normalized;
  }

  /// The cheap Phase-A bucket key (hoofdstuk 11.2): `kind + normalized title
  /// + year` for movies/shows, `episode + normalized show title + season
  /// index + episode index` for episodes. Two sources land in the same
  /// bucket only when this matches exactly — a bucket miss never costs an
  /// external-id lookup.
  ///
  /// Returns null when there isn't enough data to bucket at all (no title,
  /// or an episode missing its season/episode index): such an item never
  /// auto-merges with anything on weak evidence, but strong-token grouping
  /// (external ids, stable guid) still applies to it independently.
  String? get bucketKey {
    switch (granularity) {
      case CanonicalIdentityGranularity.movie:
      case CanonicalIdentityGranularity.show:
        final title = normalizedTitle;
        if (title == null) return null;
        return '${granularity.name}:$title:${year ?? ''}';
      case CanonicalIdentityGranularity.season:
        final title = normalizedTitle;
        if (title == null || seasonIndex == null) return null;
        return 'season:$title:$seasonIndex';
      case CanonicalIdentityGranularity.episode:
        final title = normalizedTitle;
        if (title == null || seasonIndex == null || episodeIndex == null) return null;
        return 'episode:$title:$seasonIndex:$episodeIndex';
      case CanonicalIdentityGranularity.other:
        return null;
    }
  }

  /// Whether [year] agrees for a weak title+year fallback merge (hoofdstuk
  /// 11.6): both known and equal. A missing year on either side never counts
  /// as agreement — omission is not equality.
  bool yearAgreesWith(CanonicalMediaIdentity other) => year != null && other.year != null && year == other.year;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanonicalMediaIdentity &&
          other.granularity == granularity &&
          other.normalizedTitle == normalizedTitle &&
          other.year == year &&
          other.seasonIndex == seasonIndex &&
          other.episodeIndex == episodeIndex;

  @override
  int get hashCode => Object.hash(granularity, normalizedTitle, year, seasonIndex, episodeIndex);

  @override
  String toString() => 'CanonicalMediaIdentity(${bucketKey ?? '$granularity:$normalizedTitle'})';
}

/// Builds the identity of [item] at its own kind: a movie's own identity, a
/// show's own identity, a season's (show + season number), an episode's
/// (show + season + episode number).
///
/// Returns null for kinds hoofdstuk 11.1 has no identity rule for
/// (collections, playlists, music, folders, ...) — those never participate
/// in unified grouping.
CanonicalMediaIdentity? canonicalIdentityOf(MediaItem item) {
  switch (item.kind) {
    case MediaKind.movie:
      return CanonicalMediaIdentity.movie(title: item.title, year: item.year);
    case MediaKind.show:
      return CanonicalMediaIdentity.show(title: item.title, year: item.year);
    case MediaKind.season:
      return CanonicalMediaIdentity.season(
        showTitle: item.grandparentTitle ?? item.parentTitle,
        seasonIndex: item.index,
      );
    case MediaKind.episode:
      return CanonicalMediaIdentity.episode(
        showTitle: item.grandparentTitle,
        seasonIndex: item.parentIndex,
        episodeIndex: item.index,
      );
    default:
      return null;
  }
}
