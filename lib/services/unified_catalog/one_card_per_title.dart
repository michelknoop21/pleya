/// One card per proven title for the surfaces that still render plain
/// [MediaItem] lists instead of [UnifiedMediaGroup]s: Home rows, the hero and
/// search on iPad, desktop and Android tablet.
///
/// No dedup of its own: the items go through the same
/// [groupUnifiedMediaSources] every unified surface uses, on the evidence each
/// item already holds (its stable guid and the provider numbers its list
/// answer carried). Nothing is requested, so this can run inside a build.
/// What it cannot prove without a request stays two cards, exactly like the
/// grouped surfaces when a lookup fails.
library;

import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import '../../media/unified/canonical_media_identity.dart';
import '../../media/unified/carried_external_ids.dart';
import '../../media/unified/identity_evidence.dart';
import '../../media/unified/unified_media_source.dart';
import 'grouping_service.dart';

/// [items] with every film and series that is proven to be on more than one
/// server shown once, as its representative copy (hoofdstuk 4.7), at the
/// position of its first copy. Everything else passes through in place:
/// episodes and seasons (a row of those is deduplicated where it is built),
/// kinds without an identity rule, and an item without a server.
///
/// Returns [items] itself when nothing merged.
List<MediaItem> oneCardPerProvenTitle(
  List<MediaItem> items, {
  bool Function(MediaItem item) trustStoredIdentity = storedIdentityIsSafe,
}) {
  if (items.length < 2) return items;

  final candidates = <GroupingCandidate>[];
  final indexOfSource = <String, int>{};
  for (final (i, item) in items.indexed) {
    final identity = canonicalIdentityOf(item);
    final serverId = item.serverId;
    if (identity == null || serverId == null || serverId.isEmpty) continue;
    if (identity.granularity != CanonicalIdentityGranularity.movie &&
        identity.granularity != CanonicalIdentityGranularity.show) {
      continue;
    }
    final source = UnifiedMediaSource.fromItem(item);
    // The same concrete item twice is the row's business, not a second copy.
    if (indexOfSource.containsKey(source.sourceKey)) continue;
    indexOfSource[source.sourceKey] = i;
    final scope = identity.granularity.name;
    final carried = externalIdsCarriedBy(item, allowLegacyPleya: trustStoredIdentity(item));
    candidates.add(
      GroupingCandidate(
        source: source,
        evidence: IdentityEvidence(
          identity: identity,
          strongTokens: {
            ...guidTokens(scope: scope, guid: item.guid, kind: item.kind),
            if (carried != null) ...externalIdTokens(scope: scope, ids: carried),
          },
        ),
      ),
    );
  }
  if (candidates.length < 2) return items;

  final replacement = <int, MediaItem>{};
  final dropped = <int>{};
  for (final group in groupUnifiedMediaSources(candidates)) {
    if (group.sources.length < 2) continue;
    final indexes = [for (final source in group.sources) indexOfSource[source.sourceKey]!]..sort();
    replacement[indexes.first] = group.representativeSource.item;
    dropped.addAll(indexes.skip(1));
  }
  if (dropped.isEmpty) return items;
  return [
    for (final (i, item) in items.indexed)
      if (!dropped.contains(i)) replacement[i] ?? item,
  ];
}

final Expando<List<MediaItem>> _collapsedLists = Expando('oneCardPerProvenTitleList');

/// [oneCardPerProvenTitle], remembered per list instance for a getter that is
/// read many times per build.
List<MediaItem> oneCardPerProvenTitleCached(List<MediaItem> items) =>
    _collapsedLists[items] ??= oneCardPerProvenTitle(items);

final Expando<MediaHub> _collapsedHubs = Expando('oneCardPerProvenTitle');

/// [hub] with [oneCardPerProvenTitle] applied to its items. Remembered per hub
/// instance, so a getter that runs on every build does the work once; a hub is
/// replaced, never changed in place, when one of its items updates.
MediaHub hubWithOneCardPerProvenTitle(MediaHub hub) {
  final cached = _collapsedHubs[hub];
  if (cached != null) return cached;
  final items = oneCardPerProvenTitle(hub.items);
  final collapsed = identical(items, hub.items) ? hub : hub.copyWith(items: items);
  _collapsedHubs[hub] = collapsed;
  return collapsed;
}
