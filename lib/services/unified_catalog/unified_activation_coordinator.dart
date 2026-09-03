/// Source choice, decided *before* the existing route runs (hoofdstuk 4.4 and
/// 14 of docs/tvos-unified-experience.md).
///
/// ```
/// UnifiedMediaGroup ─▶ coordinator ─┬─ one usable source ────────────┐
///                                   └─ several ─▶ source picker ─────┤
///                                                                    ▼
///                                                              MediaItem
///                                                                    │
///                                                       existing Pleya flow
/// ```
///
/// Everything here is pure and synchronous. That is the point: the player and
/// the detail route stay free of unified-catalogue logic (hoofdstuk 4.4), and
/// the rules that decide *which* concrete source they receive — the
/// deterministic ranking of hoofdstuk 4.7, the skip-the-picker rule of 14.6,
/// the focus rules of 14.4, the failure contract of hoofdstuk 15 — are all
/// checkable without a widget tree, a navigator or a server. The UI half owns
/// presentation, focus traversal and remote input; it owns none of these
/// decisions.
///
/// Two things this file deliberately cannot do, because hoofdstuk 4.4/15
/// forbid them anywhere:
///
/// * fail over to another source after a playback error — the alternative is
///   offered, never taken ([evaluatePlaybackFailure]);
/// * treat a *remembered per-title source* as a choice — it sets focus and
///   nothing else (hoofdstuk 14.8).
///
/// ## The preferred server supersedes one rule, and only one
///
/// The profile's **preferred server** (`PreferredServerStore`) may select a
/// source without asking. That is a deliberate change to the earlier fase-4
/// rule that *every* source preference could only set picker focus, and it
/// applies to that preference alone. The two are not the same signal:
/// "the server I run" is a standing answer, while "the source I last picked for
/// this one film" is not strong enough to skip a question with.
///
/// The resulting order in [UnifiedActivationCoordinator.decide]:
///
/// ```
/// 1. explicit source already chosen in this flow → keep it   (owned by the caller:
///                                                             a detail route is
///                                                             source-bound already)
/// 2. preferred server has a usable source        → best source on that server, direct
/// 3. exactly one usable source                   → direct    (hoofdstuk 14.6)
/// 4. several usable, preference not applicable   → picker
/// ```
///
/// An explicit source-selection intent — "Wijzigen" on a detail page,
/// "Andere bron kiezen" after a failed start — never reaches [decide] at all.
/// Those callers open the picker directly, precisely so a standing default
/// cannot answer a question the user just asked.
library;

import '../../media/media_item.dart';
import '../../media/unified/source_availability.dart';
import '../../media/unified/source_coverage_state.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_source.dart';
import '../../media/unified/unified_route_context.dart';

/// Why no source could be offered at all (hoofdstuk 14.7, which requires
/// different copy for the two: an auth error says "Opnieuw aanmelden
/// vereist", a network outage does not).
enum NoUsableSourceReason {
  /// At least one source' server rejected us. Takes precedence over
  /// [allOffline]: a user who can re-authenticate has something to do, and
  /// telling them "nothing is reachable" would hide it.
  authRequired,

  /// Every source's server is unreachable or unchecked.
  allOffline,
}

/// What activation should do next. Exactly one of three things happens, and
/// the caller cannot invent a fourth.
sealed class UnifiedActivationDecision {
  const UnifiedActivationDecision();
}

/// One usable source: skip the picker and use the existing route (hoofdstuk
/// 14.6 — "geen nutteloze modal met één bruikbare optie").
class ActivateSourceDirectly extends UnifiedActivationDecision {
  final UnifiedMediaSource source;
  final UnifiedMediaRouteContext routeContext;

  const ActivateSourceDirectly({required this.source, required this.routeContext});

  /// The concrete item the existing route receives. Hoofdstuk 4.1: still one
  /// concrete source, never a group.
  MediaItem get item => source.item;

  @override
  String toString() => 'ActivateSourceDirectly(${source.sourceKey})';
}

/// Several usable sources: the user chooses (hoofdstuk 14).
class ShowSourcePicker extends UnifiedActivationDecision {
  /// Every source in the group, usable or not, in hoofdstuk 4.7 order.
  /// Unusable ones are included on purpose — hoofdstuk 14.4 renders them as
  /// disabled rows rather than hiding them, so a user can see that the server
  /// they expected is simply down.
  final List<UnifiedMediaSource> sources;

  /// Which row starts focused (hoofdstuk 14.4). Always names a usable source
  /// when the group has one.
  final String initialFocusSourceKey;

  /// The remembered choice for this title, if any and if it still names a
  /// source in [sources]. Drives the "Laatst gebruikt" marking; it has
  /// already been folded into [initialFocusSourceKey] where it was valid.
  final String? preferredSourceKey;

  /// The profile's default server, when it exists. Marked in the picker so the
  /// user can see why some titles never asked — and, when it is in this list
  /// but unusable, why this one did.
  final String? preferredServerId;

  final SourceCoverageState coverage;
  final UnifiedActivationIntent intent;

  ShowSourcePicker({
    required List<UnifiedMediaSource> sources,
    required this.initialFocusSourceKey,
    required this.coverage,
    required this.intent,
    this.preferredSourceKey,
    this.preferredServerId,
  }) : sources = List.unmodifiable(sources) {
    assert(
      this.sources.any((s) => s.sourceKey == initialFocusSourceKey),
      'initialFocusSourceKey must name one of sources',
    );
  }

  @override
  String toString() => 'ShowSourcePicker(${sources.length} sources, focus: $initialFocusSourceKey)';
}

/// Nothing can be opened right now (hoofdstuk 14.7).
class NoUsableSource extends UnifiedActivationDecision {
  final NoUsableSourceReason reason;

  /// Every source, still in hoofdstuk 4.7 order, so the UI can name the
  /// servers it could not reach instead of a bare error.
  final List<UnifiedMediaSource> sources;

  final SourceCoverageState coverage;

  NoUsableSource({required this.reason, required List<UnifiedMediaSource> sources, required this.coverage})
    : sources = List.unmodifiable(sources);

  @override
  String toString() => 'NoUsableSource(${reason.name}, ${sources.length} sources)';
}

/// What is on offer after playback initialisation failed (hoofdstuk 15).
///
/// A value, not an action: "geen stille fallback, omdat een andere bron een
/// andere edition, trackset of progress kan hebben". The coordinator says
/// whether an alternative exists; only the user takes it.
class PlaybackFailureOptions {
  /// The source whose playback failed.
  final String failedSourceKey;

  /// Usable sources other than [failedSourceKey], in hoofdstuk 4.7 order.
  final List<UnifiedMediaSource> alternatives;

  PlaybackFailureOptions({required this.failedSourceKey, required List<UnifiedMediaSource> alternatives})
    : alternatives = List.unmodifiable(alternatives);

  /// Whether to offer "[ Andere bron kiezen ]" at all. When false the failure
  /// is an ordinary playback error and the existing player error state is the
  /// whole story.
  bool get hasAlternatives => alternatives.isNotEmpty;

  @override
  String toString() => 'PlaybackFailureOptions($failedSourceKey, ${alternatives.length} alternatives)';
}

/// Decides which concrete source an activation routes to.
///
/// Stateless. Every method takes the sources it should reason about, so a
/// caller holding a group across a server going down re-asks rather than
/// trusting a cached answer — which is what makes "de gefocuste bron gaat
/// offline terwijl de modal openstaat" (hoofdstuk 14.4) expressible at all.
class UnifiedActivationCoordinator {
  const UnifiedActivationCoordinator();

  /// The whole decision, from a group plus current server state.
  ///
  /// [availabilityFor] answers "is this server usable right now" and is read
  /// once per source here rather than trusted off [UnifiedMediaSource], whose
  /// stamped value may predate the last server health change.
  /// [preferredSourceKey] is the remembered choice from
  /// `SourcePreferenceStore` — focus only, never selection.
  /// [preferredServerId] is the profile's default server from
  /// `PreferredServerStore` — the one preference that *does* select; see the
  /// library doc for why the two differ.
  UnifiedActivationDecision decide({
    required UnifiedMediaGroup group,
    required UnifiedActivationIntent intent,
    required SourceAvailability Function(UnifiedMediaSource source) availabilityFor,
    SourceCoverageState? coverage,
    String? preferredSourceKey,
    String? preferredServerId,
  }) {
    final effectiveCoverage = coverage ?? SourceCoverageState.none;
    final ordered = rankSources(
      group.sources.map((s) => s.withAvailability(availabilityFor(s))).toList(),
      preferredSourceKey: preferredSourceKey,
    );
    final usable = ordered.where((s) => s.availability.isUsable).toList();

    if (usable.isEmpty) {
      return NoUsableSource(
        reason: ordered.any((s) => s.availability == SourceAvailability.authError)
            ? NoUsableSourceReason.authRequired
            : NoUsableSourceReason.allOffline,
        sources: ordered,
        coverage: effectiveCoverage,
      );
    }

    // The profile's standing answer. Taken before the count is even looked at:
    // with three usable sources and a preferred server among them there is
    // still nothing to ask. `usable` is already in hoofdstuk 4.7 order, so the
    // first match is the best source *on that server* rather than whichever
    // library answered first.
    //
    // A preferred server that is offline, rejecting us, hidden from the profile
    // or simply absent from this group has no entry in `usable` and therefore
    // cannot be picked — the fall-through below is the whole of that rule.
    final onPreferredServer = preferredServerId == null
        ? null
        : usable.where((s) => s.serverId.value == preferredServerId).firstOrNull;
    if (onPreferredServer != null) {
      return ActivateSourceDirectly(
        source: onPreferredServer,
        routeContext: buildRouteContext(
          group: group,
          orderedSources: ordered,
          sourceKey: onPreferredServer.sourceKey,
          coverage: effectiveCoverage,
          intent: intent,
        ),
      );
    }

    // Hoofdstuk 14.6: exactly one usable source skips the picker, and it does
    // so whether or not other expected servers went unchecked — a modal with a
    // single choosable row asks the user a question with one answer. This is
    // also what keeps "preferred server offline, one alternative left" fast:
    // there is no choice to present.
    if (usable.length == 1) {
      return ActivateSourceDirectly(
        source: usable.single,
        routeContext: buildRouteContext(
          group: group,
          orderedSources: ordered,
          sourceKey: usable.single.sourceKey,
          coverage: effectiveCoverage,
          intent: intent,
        ),
      );
    }

    return ShowSourcePicker(
      sources: ordered,
      initialFocusSourceKey: selectInitialFocus(ordered, preferredSourceKey: preferredSourceKey)!,
      preferredSourceKey: ordered.any((s) => s.sourceKey == preferredSourceKey) ? preferredSourceKey : null,
      preferredServerId: preferredServerId,
      coverage: effectiveCoverage,
      intent: intent,
    );
  }

  /// The route context for a source the user has landed on, whether it was
  /// chosen in the picker or reached directly.
  UnifiedMediaRouteContext buildRouteContext({
    required UnifiedMediaGroup group,
    required List<UnifiedMediaSource> orderedSources,
    required String sourceKey,
    required SourceCoverageState coverage,
    required UnifiedActivationIntent intent,
  }) => UnifiedMediaRouteContext(
    groupId: group.groupId,
    identity: group.identity,
    sourceKey: sourceKey,
    availableSourceKeys: orderedSources.map((s) => s.sourceKey).toList(),
    coverage: coverage,
    intent: intent,
  );

  /// Whether to offer another source after playback initialisation failed
  /// (hoofdstuk 15). Never switches; only reports what a switch could reach.
  PlaybackFailureOptions evaluatePlaybackFailure({
    required List<UnifiedMediaSource> sources,
    required String failedSourceKey,
    required SourceAvailability Function(UnifiedMediaSource source) availabilityFor,
    String? preferredSourceKey,
  }) {
    final ordered = rankSources(
      sources.map((s) => s.withAvailability(availabilityFor(s))).toList(),
      preferredSourceKey: preferredSourceKey,
    );
    return PlaybackFailureOptions(
      failedSourceKey: failedSourceKey,
      // The source that just failed is excluded even if its server still
      // reports online: the server being up is precisely what did not help.
      alternatives: ordered.where((s) => s.sourceKey != failedSourceKey && s.availability.isUsable).toList(),
    );
  }
}

/// Hoofdstuk 4.7's deterministic order, applied as a total sort.
///
/// ```
/// preferred source → online state → metadata completeness
/// → artwork completeness → quality information → server name → server id
/// → item id
/// ```
///
/// Total by construction: `sourceKey` is `serverId:itemId` and unique within a
/// group, so the last two tiers can never both tie. That totality is the whole
/// contract of 4.7 — "de eerste server die antwoordt" must never be able to
/// influence the outcome, and a comparator with a residual tie would leave the
/// input order (i.e. response order) deciding it.
List<UnifiedMediaSource> rankSources(List<UnifiedMediaSource> sources, {String? preferredSourceKey}) {
  final ranked = List<UnifiedMediaSource>.from(sources);
  ranked.sort((a, b) => compareSourcesForActivation(a, b, preferredSourceKey: preferredSourceKey));
  return ranked;
}

/// Negative when [a] ranks before [b]. See [rankSources].
int compareSourcesForActivation(UnifiedMediaSource a, UnifiedMediaSource b, {String? preferredSourceKey}) {
  if (preferredSourceKey != null && a.sourceKey != b.sourceKey) {
    if (a.sourceKey == preferredSourceKey) return -1;
    if (b.sourceKey == preferredSourceKey) return 1;
  }

  final availability = a.availability.rank.compareTo(b.availability.rank);
  if (availability != 0) return availability;

  // Higher completeness first, hence the reversed comparison.
  final metadata = metadataCompleteness(b.item).compareTo(metadataCompleteness(a.item));
  if (metadata != 0) return metadata;

  final artwork = artworkCompleteness(b.item).compareTo(artworkCompleteness(a.item));
  if (artwork != 0) return artwork;

  final quality = qualityCompleteness(b.item).compareTo(qualityCompleteness(a.item));
  if (quality != 0) return quality;

  final serverName = a.serverName.toLowerCase().compareTo(b.serverName.toLowerCase());
  if (serverName != 0) return serverName;

  final serverId = a.serverId.value.compareTo(b.serverId.value);
  if (serverId != 0) return serverId;

  return a.item.id.compareTo(b.item.id);
}

/// How much descriptive metadata a source carries, as a count of present
/// fields. Hoofdstuk 4.7 ranks on *completeness*, so this counts presence and
/// deliberately does not score one field above another — a weighting would be
/// a product decision the contract does not make.
int metadataCompleteness(MediaItem item) {
  var score = 0;
  if ((item.summary ?? '').trim().isNotEmpty) score++;
  if (item.year != null) score++;
  if (item.durationMs != null) score++;
  if ((item.genres ?? const []).isNotEmpty) score++;
  if ((item.directors ?? const []).isNotEmpty) score++;
  if ((item.roles ?? const []).isNotEmpty) score++;
  if (item.rating != null) score++;
  if ((item.contentRating ?? '').trim().isNotEmpty) score++;
  return score;
}

/// How much artwork a source carries, as a count of present images.
int artworkCompleteness(MediaItem item) {
  var score = 0;
  if ((item.thumbPath ?? '').trim().isNotEmpty) score++;
  if ((item.artPath ?? '').trim().isNotEmpty) score++;
  if ((item.grandparentThumbPath ?? '').trim().isNotEmpty) score++;
  if ((item.grandparentArtPath ?? '').trim().isNotEmpty) score++;
  return score;
}

/// How much of the quality picture a source can describe.
///
/// Read as completeness, matching the two tiers it sits with in hoofdstuk
/// 4.7 — "does this source tell us about its quality at all", not "is this
/// source higher quality". Preferring the 4K source over the 1080p one is a
/// product rule the contract does not state, and inventing it here would make
/// the default source depend on a rule nobody agreed to.
int qualityCompleteness(MediaItem item) {
  final versions = item.mediaVersions ?? const [];
  if (versions.isEmpty) return 0;
  var score = 1;
  final first = versions.first;
  if ((first.videoResolution ?? '').trim().isNotEmpty) score++;
  if ((first.videoCodec ?? '').trim().isNotEmpty) score++;
  if (first.height != null) score++;
  if (first.bitrate != null) score++;
  return score;
}

/// Which row starts focused (hoofdstuk 14.4).
///
/// 1. the remembered source, when it still exists and is online;
/// 2. otherwise the online source with the most recent progress;
/// 3. otherwise the best online source by hoofdstuk 4.7;
/// 4. otherwise — nothing is online — the best source overall, so the modal
///    still has a focused row to render its disabled state around.
///
/// Returns null only for an empty list.
String? selectInitialFocus(List<UnifiedMediaSource> ordered, {String? preferredSourceKey}) {
  if (ordered.isEmpty) return null;
  final online = ordered.where((s) => s.availability.isUsable).toList();
  if (online.isEmpty) return ordered.first.sourceKey;

  if (preferredSourceKey != null) {
    for (final source in online) {
      if (source.sourceKey == preferredSourceKey) return source.sourceKey;
    }
  }

  UnifiedMediaSource? mostRecent;
  for (final source in online) {
    final lastViewed = source.item.lastViewedAt;
    if (lastViewed == null) continue;
    // Strictly greater, so a tie leaves the hoofdstuk 4.7 winner in place
    // rather than letting list order decide.
    if (mostRecent == null || lastViewed > mostRecent.item.lastViewedAt!) mostRecent = source;
  }
  if (mostRecent != null) return mostRecent.sourceKey;

  return online.first.sourceKey;
}

/// Where focus goes when the focused row stops being usable while the modal is
/// open (hoofdstuk 14.4: "rij wordt disabled; focus gaat naar dichtstbijzijnde
/// online rij").
///
/// Returns the focused key unchanged when it is still usable, the nearest
/// usable row by list distance otherwise, and null when nothing is usable —
/// at which point 14.4 sends focus to "Servers beheren" or "Sluiten", which
/// are the UI's own controls and not sources.
///
/// A tie in distance resolves downward (the row after), because the rows below
/// are the ones a user has not passed yet.
String? nextFocusAfterAvailabilityChange({
  required List<UnifiedMediaSource> ordered,
  required String focusedSourceKey,
}) {
  final index = ordered.indexWhere((s) => s.sourceKey == focusedSourceKey);
  if (index >= 0 && ordered[index].availability.isUsable) return focusedSourceKey;

  // A focused row that vanished entirely (hoofdstuk 14.4's "source verdwijnt")
  // has no position to measure from; the best usable row is the honest answer.
  if (index < 0) {
    for (final source in ordered) {
      if (source.availability.isUsable) return source.sourceKey;
    }
    return null;
  }

  for (var distance = 1; distance < ordered.length; distance++) {
    final after = index + distance;
    if (after < ordered.length && ordered[after].availability.isUsable) return ordered[after].sourceKey;
    final before = index - distance;
    if (before >= 0 && ordered[before].availability.isUsable) return ordered[before].sourceKey;
  }
  return null;
}

/// Folds sources discovered while the modal is open into the list it is
/// already showing (hoofdstuk 14.4: "wordt onderaan toegevoegd zonder de
/// huidige focus te verplaatsen").
///
/// [current]'s order is preserved exactly — re-sorting the visible list under
/// a user who is reading it would move the row beneath their thumb. New
/// sources are appended, ranked among themselves so the tail is deterministic
/// too. 14.4 puts the tidy re-sort at the *next* opening, not this one.
///
/// A source already in [current] is refreshed in place rather than duplicated:
/// the same server answering the background resolution with a newer copy of a
/// row is an update, not an arrival.
List<UnifiedMediaSource> mergeLateSources(
  List<UnifiedMediaSource> current,
  List<UnifiedMediaSource> incoming, {
  String? preferredSourceKey,
}) {
  final byKey = {for (final source in incoming) source.sourceKey: source};
  final merged = [for (final source in current) byKey[source.sourceKey] ?? source];
  final knownKeys = current.map((s) => s.sourceKey).toSet();
  final arrivals = incoming.where((s) => !knownKeys.contains(s.sourceKey)).toList();
  return [...merged, ...rankSources(arrivals, preferredSourceKey: preferredSourceKey)];
}
