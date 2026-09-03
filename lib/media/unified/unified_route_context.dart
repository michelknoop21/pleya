/// What a details or playback route needs to know about the *group* it was
/// reached through (hoofdstuk 15 of docs/tvos-unified-experience.md).
///
/// Strictly additive. Hoofdstuk 4.1 keeps `MediaItem` one concrete source and
/// hoofdstuk 4.4 keeps source choice *before* the route, so this object never
/// replaces the concrete `MediaItem` a route already receives and never
/// carries a second candidate the route could switch to on its own. It exists
/// so a detail page can render "Bron: NAS • Films 4K [Wijzigen]" and re-open
/// the same picker — a route that ignores it behaves exactly as it does today.
library;

import 'canonical_media_identity.dart';
import 'source_coverage_state.dart';

/// Why activation reached a route: what the user asked for, before any
/// per-kind setting (`episodeAction`, `continueWatchingAction`) turns a play
/// into a details or the other way round.
///
/// Hoofdstuk 14.2 gives the two intents different picker copy, and hoofdstuk
/// 15 reopens the picker in details mode from a detail page, so the intent has
/// to survive as a value rather than staying an implicit `playDirectly` bool.
enum UnifiedActivationIntent {
  /// The user wants to watch. Picker copy: "Kies waar je wilt afspelen".
  play,

  /// The user wants the detail page. Picker copy: "Kies een bron voor de
  /// details".
  details,
}

/// The group behind a concrete route target.
class UnifiedMediaRouteContext {
  /// The group this route was reached through. Session-scoped (hoofdstuk
  /// 11.9) — good for refocusing a still-live list, never for persistence.
  final String groupId;

  /// The group's canonical identity. Unlike [groupId] this is content-derived
  /// and stable across sessions, which is what makes it the key a remembered
  /// source preference is stored under.
  final CanonicalMediaIdentity identity;

  /// `UnifiedMediaSource.sourceKey` of the source this route actually got.
  /// Always names one of [availableSourceKeys].
  final String sourceKey;

  /// Every source the group had when the route opened, in the deterministic
  /// order of hoofdstuk 4.7. Keys only: a route must not be able to reach a
  /// second `MediaItem` and quietly render it (hoofdstuk 15's "geen half
  /// gemergede detailpagina"). Re-opening the picker re-reads the live group.
  final List<String> availableSourceKeys;

  /// Whether every server that could hold this title was actually asked.
  /// Drives the "1 server kon niet worden gecontroleerd" header of hoofdstuk
  /// 14.2 — a detail page showing one source out of a partially-checked set
  /// should be able to say so.
  final SourceCoverageState coverage;

  /// What the user originally asked for, carried through so a picker reopened
  /// from a detail page keeps the right copy.
  final UnifiedActivationIntent intent;

  UnifiedMediaRouteContext({
    required this.groupId,
    required this.identity,
    required this.sourceKey,
    required List<String> availableSourceKeys,
    required this.coverage,
    required this.intent,
  }) : availableSourceKeys = List.unmodifiable(availableSourceKeys) {
    assert(
      this.availableSourceKeys.contains(sourceKey),
      'UnifiedMediaRouteContext.sourceKey must name one of availableSourceKeys',
    );
  }

  /// Whether a "Wijzigen" affordance is worth rendering at all (hoofdstuk 15
  /// only shows the source line when more than one source exists).
  bool get hasAlternativeSources => availableSourceKeys.length > 1;

  /// This context with a different chosen source, after a switch on the
  /// detail page. Hoofdstuk 15 replaces the route rather than stacking one, so
  /// the new route gets a context that differs only in [sourceKey].
  UnifiedMediaRouteContext withSourceKey(String sourceKey) => UnifiedMediaRouteContext(
    groupId: groupId,
    identity: identity,
    sourceKey: sourceKey,
    availableSourceKeys: availableSourceKeys,
    coverage: coverage,
    intent: intent,
  );

  @override
  String toString() =>
      'UnifiedMediaRouteContext($groupId, source: $sourceKey of ${availableSourceKeys.length}, ${intent.name})';
}
