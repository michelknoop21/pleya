/// The live world a Films or Series card hands to activation: what is
/// reachable right now, what changes while a picker is open, and how to find
/// the sources the catalog page never saw.
///
/// Fase 4 built [UnifiedActivationEnvironment] as a hole with five sides and
/// filled none of them, because the first real caller could not exist until a
/// unified catalog surface did. This is that filling. Every field matters, and
/// leaving one null quietly deletes a behaviour hoofdstuk 14 already proved:
///
/// * without `availabilityFor`, every row is `unknown` and nothing is usable;
/// * without `availabilityRevision`, a server dropping out under the cursor
///   leaves a row that looks fine and cannot play (hoofdstuk 14.4);
/// * without `resolveMoreSources`, the picker only ever shows the sources this
///   *page* merged — so a duplicate on a library the catalog has not paged to
///   yet is invisible, "Meer bronnen controleren…" never appears, and coverage
///   is silently reported as complete (hoofdstuk 14.5, 14.2);
/// * without `onManageServers`, hoofdstuk 14.7's offline panel offers a user
///   with no reachable server nothing to do but close it.
///
/// ## Why the catalog cannot supply coverage on its own
///
/// A catalog page knows the sources its merge happened to produce. It does not
/// know whether some other library holds the same title, because finding that
/// out is a per-identity fan-out, not a paging concern (hoofdstuk 12.8). So the
/// group opens the picker with the coverage it can honestly claim — the servers
/// this catalog is actually paging — and `resolveMoreSources` replaces it with
/// the real answer as the fan-out lands. Claiming completeness up front would
/// be the one lie `SourceCoverageState` exists to prevent.
library;

import 'package:flutter/foundation.dart';

import '../../media/ids.dart';
import '../../media/media_identity.dart';
import '../../media/media_item.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/source_availability.dart';
import '../../media/unified/source_coverage_state.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_source.dart';
import '../../services/unified_catalog/source_resolver.dart';
import '../../utils/external_ids.dart';
import 'tv_media_source_picker_route.dart';

/// The searchable identity of [group], for the hoofdstuk 12.8 fan-out.
///
/// [CanonicalMediaIdentity] — what a group carries — is a *bucketing* key: it
/// answers "are these two rows the same title" and is deliberately normalised
/// past the point where a server could look it up. [MediaIdentity] is the
/// lookup shape, and building one means going back to the concrete sources.
///
/// External ids are unioned across every source, not read off the
/// representative one. They are collected per source during identity
/// resolution and a source that never entered a duplicate bucket carries none
/// (see [UnifiedMediaSource.externalIds]), so taking only the representative's
/// would routinely search on a title string while a TMDB id sat one source
/// over. Conflicts cannot arise: two sources carrying *different* ids for the
/// same field would not have been grouped in the first place (hoofdstuk 11.4),
/// so a union is exactly as strong as its strongest member.
MediaIdentity unifiedGroupIdentity(UnifiedMediaGroup group) {
  final representative = group.representativeSource.item;
  String? imdb;
  int? tmdb;
  int? tvdb;
  String? guid;
  for (final source in group.sources) {
    imdb ??= source.externalIds.imdb;
    tmdb ??= source.externalIds.tmdb;
    tvdb ??= source.externalIds.tvdb;
    final sourceGuid = source.item.guid;
    if (guid == null && sourceGuid != null && sourceGuid.isNotEmpty) guid = sourceGuid;
  }
  return MediaIdentity(
    guid: guid,
    externalIds: ExternalIds(imdb: imdb, tmdb: tmdb, tvdb: tvdb),
    title: representative.title,
    year: representative.year,
    kind: representative.kind,
  );
}

/// Live server state, as the two accessors a catalog surface can get to.
///
/// A record rather than a `MultiServerManager` so the environment can be built
/// and tested without one: every rule below is about the three states
/// [SourceAvailability] distinguishes, not about how the app happens to track
/// servers.
typedef UnifiedServerHealth = ({bool Function(ServerId serverId) isOnline, Set<String> authErrorServerIds});

/// Whether one source can be opened right now.
///
/// Auth is checked before online: a server that answered and rejected us is
/// *not* offline, and hoofdstuk 14.7 needs the difference because one of the
/// two the user can fix from the sofa. `MultiServerManager` reports an
/// auth-rejected server as not-online too, so testing online first would
/// collapse both into "offline" and lose the actionable half.
SourceAvailability unifiedSourceAvailability(UnifiedMediaSource source, UnifiedServerHealth health) {
  if (health.authErrorServerIds.contains(source.serverId.value)) return SourceAvailability.authError;
  return health.isOnline(source.serverId) ? SourceAvailability.online : SourceAvailability.offline;
}

/// The coverage a catalog page can honestly claim for [group] before any
/// fan-out has run.
///
/// Expected is every server the catalog is paging; checked is every server that
/// contributed a source to this group. The gap is real and is what the panel's
/// "N servers could not be checked" line reports: those servers are in the
/// catalog, they simply have not been asked about *this title* yet.
///
/// A reason is attached only where one is actually known — a server that is
/// offline, or that rejected us. An online server we have not asked gets none:
/// it is unchecked and counted as such, and the three
/// [UncheckedSourceReason]s all claim to know *why*, which here we do not.
/// `lookupFailed` in particular would assert a failure that has not happened.
///
/// **This value is final for the life of the picker.** Fase 4's
/// `resolveMoreSources` returns the sources a fan-out found but not the
/// coverage it achieved, so a resolution that reaches every server still leaves
/// this line reading conservatively. That is the safe direction to be wrong in
/// — under-claiming what was checked, never over-claiming — and closing it
/// properly means widening a fase-4 signature, which is not a fase-5 call.
SourceCoverageState unifiedCatalogCoverage({
  required UnifiedMediaGroup group,
  required Set<String> catalogServerIds,
  required UnifiedServerHealth health,
}) {
  final checked = {for (final source in group.sources) source.serverId.value};
  final unchecked = catalogServerIds.difference(checked);
  return SourceCoverageState(
    // Unioned rather than assigned: a source can come from a server the caller
    // did not list, and `checkedServerIds` must stay a subset of the expected
    // set or the constructor's own assert fires.
    expectedServerIds: catalogServerIds.union(checked),
    checkedServerIds: checked,
    uncheckedReasons: {
      for (final serverId in unchecked)
        if (health.authErrorServerIds.contains(serverId))
          serverId: UncheckedSourceReason.authError
        else if (!health.isOnline(ServerId(serverId)))
          serverId: UncheckedSourceReason.offline,
    },
  );
}

/// Builds the environment one activation runs in.
///
/// [resolver] is optional so a surface without a profile id — nothing is signed
/// in yet, which the catalog screens can briefly be during startup binding —
/// degrades to "only the sources this page merged" instead of crashing. That is
/// a worse picker, not a broken one, and it is the same distinction the
/// coverage state already carries.
UnifiedActivationEnvironment buildUnifiedActivationEnvironment({
  required UnifiedMediaGroup group,
  required UnifiedServerHealth health,
  required Set<String> catalogServerIds,
  required Listenable availabilityRevision,
  SourceAllResolver? resolver,
  void Function()? onManageServers,
}) {
  return UnifiedActivationEnvironment(
    availabilityFor: (source) => unifiedSourceAvailability(source, health),
    coverage: unifiedCatalogCoverage(group: group, catalogServerIds: catalogServerIds, health: health),
    availabilityRevision: availabilityRevision,
    resolveMoreSources: resolver == null
        ? null
        : (isCancelled) async {
            final resolution = await resolver.resolveAllSourcesForGroup(
              unifiedGroupIdentity(group),
              // Handed straight through: the picker's predicate turns true the
              // moment the user picks, and the resolver polls it between
              // batches, which is hoofdstuk 14.5's "kiezen annuleert resterende
              // niet-essentiële lookups".
              isCancelled: isCancelled,
            );
            return _sourcesFromResolution(resolution.items, health);
          },
    onManageServers: onManageServers,
  );
}

/// Turns fan-out results into rows the picker can merge in.
///
/// Availability is stamped here rather than left `unknown`: these arrive while
/// the modal is open, and an unstamped row would render as unusable next to
/// identical ones that work. Items without a server id are dropped — a source
/// with nowhere to play from cannot be offered — rather than throwing, because
/// this runs behind an already-open panel where an exception would take the
/// whole picker down over one malformed row.
List<UnifiedMediaSource> _sourcesFromResolution(List<MediaItem> items, UnifiedServerHealth health) {
  final sources = <UnifiedMediaSource>[];
  for (final item in items) {
    final serverId = item.serverId;
    if (serverId == null || serverId.isEmpty) continue;
    final source = UnifiedMediaSource.fromItem(item);
    sources.add(source.withAvailability(unifiedSourceAvailability(source, health)));
  }
  return sources;
}

/// The health accessors, read off a live [MediaServerClient] registry.
///
/// A tiny adapter kept next to the record it produces, so the call site in the
/// catalog screen stays one line and the shape of [UnifiedServerHealth] is
/// documented in exactly one place.
UnifiedServerHealth unifiedServerHealth({
  required bool Function(ServerId serverId) isOnline,
  required Set<String> authErrorServerIds,
}) => (isOnline: isOnline, authErrorServerIds: authErrorServerIds);
