/// Activation for a [UnifiedMediaGroup]: the one place that turns "the user
/// pressed Select on a title" into "one concrete `serverId:itemId` reaches the
/// existing Pleya route" (hoofdstuk 4.4, 14 and 15 of
/// docs/tvos-unified-experience.md).
///
/// ```
/// group ─▶ preferences ─▶ coordinator.decide ─┬─ preferred server ─▶ route
///                                              ├─ one source ───────▶ route
///                                              ├─ several ─▶ picker ─▶ remember ─▶ route
///                                              └─ none ────▶ picker (unreachable state)
/// ```
///
/// Everything decided here is decided by `UnifiedActivationCoordinator`; this
/// file owns the *sequence*, not the rules. It is deliberately the only caller
/// of that contract, which is why late arrivals ([mergeLateSources]), a server
/// dropping out under the cursor ([nextFocusAfterAvailabilityChange]) and a
/// failed playback start ([UnifiedActivationCoordinator.evaluatePlaybackFailure])
/// all pass through here rather than being re-derived by a widget.
///
/// Four rules this file exists to keep:
///
/// * **Two preferences, two amounts of authority.** The profile's *preferred
///   server* (`PreferredServerStore`) may select without asking — that is the
///   whole point of it, and it is what stops a duplicated library from asking
///   the same question at every title. The *last-used source for this title*
///   (`SourcePreferenceStore`) may only set the picker's focus. An explicit
///   source-selection intent — "Wijzigen", "Andere bron kiezen" — bypasses the
///   first entirely: those two paths call [showUnifiedSourcePicker] directly
///   rather than [activateUnifiedMediaGroup], so a standing default can never
///   answer a question the user has just asked.
/// * **No silent failover, anywhere.** A failed playback start only *offers* an
///   alternative (hoofdstuk 15); nothing here takes one.
/// * **No root `OverlayEntry`.** The picker goes through
///   `OverlaySheetController.showAdaptive`, whose host is mounted by
///   `MainScreen` *inside* `ProfileNavigationScope`. A hand-rolled root overlay
///   would navigate outside that scope and throw
///   `StateError: ProfileNavigationScope is required for profile routes` —
///   a black screen in release. See CLAUDE.md.
/// * **The user's choice is remembered, then routed** — in that order, and with
///   `SelectTraceRecorder.noteSourceSelection` recorded *before* the route
///   links its target, or every deliberate source switch would read as the
///   swap-under-the-cursor defect the trace exists to catch.
/// * **A route replacement, not a route stack.** Hoofdstuk 15: "Back na
///   bronwijziging keert niet door alle eerder gekozen bronnen heen."
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../diagnostics/select_trace_recorder.dart';
import '../../media/media_item.dart';
import '../../media/unified/source_availability.dart';
import '../../media/unified/source_coverage_state.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_source.dart';
import '../../media/unified/unified_route_context.dart';
import '../../navigation/tv/tv_nested_surface.dart';
import '../../services/unified_catalog/preferred_server_store.dart';
import '../../services/unified_catalog/source_preference_store.dart';
import '../../services/unified_catalog/unified_activation_coordinator.dart';
import '../../utils/media_navigation_helper.dart';
import '../../widgets/overlay_sheet.dart';
import '../../widgets/overlay_sheet_geometry.dart';
import '../../widgets/tv/tv_media_source_picker.dart';

/// What an activation ended up doing. Returned so a caller can tell "the user
/// cancelled" from "nothing was reachable" without inspecting the navigator.
enum UnifiedActivationOutcome {
  /// A concrete source was routed to (directly, or after the user chose).
  routed,

  /// The picker opened and the user backed out (hoofdstuk 14.4's "Menu
  /// annuleert"). Focus restoration is the caller's, and happens by itself:
  /// the overlay sheet never took the route's focus scope away.
  cancelled,

  /// Nothing was reachable (hoofdstuk 14.7).
  noUsableSource,
}

/// Live server state, plus the hooks hoofdstuk 14.5 and 14.4 need while the
/// modal is open. Grouped into one object because they are one concern —
/// "what does the world look like right now" — and because a nine-parameter
/// activation call is unreadable at the call site.
class UnifiedActivationEnvironment {
  /// "Is this source usable right now." Read per source, per decision, rather
  /// than trusted off [UnifiedMediaSource.availability], whose stamped value
  /// may predate the last server health change.
  final SourceAvailability Function(UnifiedMediaSource source) availabilityFor;

  /// Coverage from the resolution that produced the group, when there was one.
  final SourceCoverageState? coverage;

  /// Fires when server health changed. The open picker then re-reads
  /// [availabilityFor] for every row and moves focus with
  /// [nextFocusAfterAvailabilityChange] (hoofdstuk 14.4).
  final Listenable? availabilityRevision;

  /// Background source resolution (hoofdstuk 14.5). The picker opens on the
  /// sources already known and folds whatever this returns in underneath,
  /// without moving focus. The predicate it is handed turns true the moment
  /// the user picks, so "kiezen annuleert resterende niet-essentiële lookups"
  /// is honoured by the resolver itself — see
  /// `SourceAllResolver.resolveAllSourcesForGroup`'s `isCancelled`.
  final Future<List<UnifiedMediaSource>> Function(bool Function() isCancelled)? resolveMoreSources;

  /// Hoofdstuk 14.7's "Servers beheren". Omitted when the surface has nowhere
  /// to send the user, in which case only Close is offered.
  final VoidCallback? onManageServers;

  const UnifiedActivationEnvironment({
    required this.availabilityFor,
    this.coverage,
    this.availabilityRevision,
    this.resolveMoreSources,
    this.onManageServers,
  });
}

/// Opens [group] — picker first when the choice is the user's, straight through
/// when it is not.
Future<UnifiedActivationOutcome> activateUnifiedMediaGroup(
  BuildContext context, {
  required UnifiedMediaGroup group,
  required UnifiedActivationIntent intent,
  required UnifiedActivationEnvironment environment,
  Widget? artwork,
  bool playDirectly = false,
  bool isOffline = false,
  void Function(String)? onRefresh,
  ValueChanged<MediaItem>? onPlaybackReturned,
  String? traceId,
}) async {
  const coordinator = UnifiedActivationCoordinator();
  final preferredSourceKey = await SourcePreferenceStore.read(group.identity);
  final preferredServerId = await PreferredServerStore.read();
  if (!context.mounted) return UnifiedActivationOutcome.cancelled;

  final decision = coordinator.decide(
    group: group,
    intent: intent,
    availabilityFor: environment.availabilityFor,
    coverage: environment.coverage,
    preferredSourceKey: preferredSourceKey,
    preferredServerId: preferredServerId,
  );

  switch (decision) {
    // Hoofdstuk 14.6: one usable source is not a question, so it is not asked.
    // Nothing is remembered either — the user chose nothing.
    case ActivateSourceDirectly(:final source, :final routeContext):
      return _routeToSource(
        context,
        group: group,
        source: source,
        routeContext: routeContext,
        environment: environment,
        artwork: artwork,
        playDirectly: playDirectly,
        isOffline: isOffline,
        onRefresh: onRefresh,
        onPlaybackReturned: onPlaybackReturned,
        traceId: traceId,
      );

    case ShowSourcePicker(
      :final sources,
      :final initialFocusSourceKey,
      :final coverage,
      preferredSourceKey: final marked,
    ):
      final chosen = await showUnifiedSourcePicker(
        context,
        group: group,
        sources: sources,
        initialFocusSourceKey: initialFocusSourceKey,
        preferredSourceKey: marked,
        preferredServerId: preferredServerId,
        coverage: coverage,
        intent: intent,
        environment: environment,
        artwork: artwork,
      );
      if (chosen == null || !context.mounted) return UnifiedActivationOutcome.cancelled;
      return _acceptChoice(
        context,
        group: group,
        chosen: chosen,
        coverage: coverage,
        intent: intent,
        environment: environment,
        artwork: artwork,
        playDirectly: playDirectly,
        isOffline: isOffline,
        onRefresh: onRefresh,
        onPlaybackReturned: onPlaybackReturned,
        traceId: traceId,
      );

    // Hoofdstuk 14.7. The rows are still shown — "which server is down" is
    // exactly what the user came to find out — but the two things they can do
    // about it carry the focus.
    case NoUsableSource(:final sources, :final coverage):
      await showUnifiedSourcePicker(
        context,
        group: group,
        sources: sources,
        initialFocusSourceKey: sources.first.sourceKey,
        preferredServerId: preferredServerId,
        coverage: coverage,
        intent: intent,
        environment: environment,
        artwork: artwork,
      );
      return UnifiedActivationOutcome.noUsableSource;
  }
}

/// Records, remembers and routes a source the user picked.
///
/// The trace note comes first on purpose: from here on `selectedTarget` and
/// `activatedTarget` legitimately differ, and without the marker that reads as
/// precisely the swap-under-the-cursor defect the trace was built to catch.
Future<UnifiedActivationOutcome> _acceptChoice(
  BuildContext context, {
  required UnifiedMediaGroup group,
  required UnifiedMediaSource chosen,
  required SourceCoverageState coverage,
  required UnifiedActivationIntent intent,
  required UnifiedActivationEnvironment environment,
  required Widget? artwork,
  required bool playDirectly,
  required bool isOffline,
  required void Function(String)? onRefresh,
  required ValueChanged<MediaItem>? onPlaybackReturned,
  required String? traceId,
}) async {
  const coordinator = UnifiedActivationCoordinator();
  SelectTraceRecorder.instance.noteSourceSelection(traceId, detail: 'user picked ${chosen.sourceKey}');
  // Fire-and-forget: a preference is a convenience, and blocking the route on
  // a settings write would put a disk round-trip between Select and the player.
  unawaited(SourcePreferenceStore.remember(group.identity, chosen.sourceKey));

  return _routeToSource(
    context,
    group: group,
    source: chosen,
    routeContext: coordinator.buildRouteContext(
      group: group,
      orderedSources: group.sources,
      sourceKey: chosen.sourceKey,
      coverage: coverage,
      intent: intent,
    ),
    environment: environment,
    artwork: artwork,
    playDirectly: playDirectly,
    isOffline: isOffline,
    onRefresh: onRefresh,
    onPlaybackReturned: onPlaybackReturned,
    traceId: traceId,
  );
}

/// Hands one concrete source to the existing navigation helper, and stays
/// around for the two things hoofdstuk 15 can ask for afterwards: a source
/// switch from the detail page, and an alternative after a failed player start.
Future<UnifiedActivationOutcome> _routeToSource(
  BuildContext context, {
  required UnifiedMediaGroup group,
  required UnifiedMediaSource source,
  required UnifiedMediaRouteContext routeContext,
  required UnifiedActivationEnvironment environment,
  required Widget? artwork,
  required bool playDirectly,
  required bool isOffline,
  required void Function(String)? onRefresh,
  required ValueChanged<MediaItem>? onPlaybackReturned,
  required String? traceId,
}) async {
  var playbackInitFailed = false;

  await navigateToMediaItem(
    context,
    source.item,
    onRefresh: onRefresh,
    isOffline: isOffline,
    playDirectly: playDirectly,
    traceId: traceId,
    onPlaybackReturned: onPlaybackReturned,
    unifiedRouteContext: routeContext,
    onPlaybackInitFailed: () => playbackInitFailed = true,
    onChangeSource: routeContext.hasAlternativeSources
        ? (detailContext) => _changeSourceFromDetail(
            detailContext,
            group: group,
            routeContext: routeContext,
            environment: environment,
            artwork: artwork,
            isOffline: isOffline,
            onRefresh: onRefresh,
            onPlaybackReturned: onPlaybackReturned,
          )
        : null,
  );

  if (playbackInitFailed && context.mounted) {
    await _offerAlternativeAfterPlaybackFailure(
      context,
      group: group,
      failedSourceKey: source.sourceKey,
      routeContext: routeContext,
      environment: environment,
      artwork: artwork,
      isOffline: isOffline,
      onRefresh: onRefresh,
      onPlaybackReturned: onPlaybackReturned,
      traceId: traceId,
    );
  }

  return UnifiedActivationOutcome.routed;
}

/// Hoofdstuk 15's "[ Wijzigen ]" on the detail page.
///
/// The current detail route is popped before the new one is pushed, so Back
/// does not walk the user backwards through every source they looked at.
Future<void> _changeSourceFromDetail(
  BuildContext context, {
  required UnifiedMediaGroup group,
  required UnifiedMediaRouteContext routeContext,
  required UnifiedActivationEnvironment environment,
  required Widget? artwork,
  required bool isOffline,
  required void Function(String)? onRefresh,
  required ValueChanged<MediaItem>? onPlaybackReturned,
}) async {
  const coordinator = UnifiedActivationCoordinator();
  // Explicit source-selection intent: the picker opens whatever the profile's
  // preferred server says. Reading it here is for the *marking* only — a
  // standing default must not answer a question the user just asked.
  final preferredServerId = await PreferredServerStore.read();
  if (!context.mounted) return;
  final ordered = rankSources(
    group.sources.map((s) => s.withAvailability(environment.availabilityFor(s))).toList(),
    preferredSourceKey: routeContext.sourceKey,
  );
  final chosen = await showUnifiedSourcePicker(
    context,
    group: group,
    sources: ordered,
    initialFocusSourceKey: selectInitialFocus(ordered, preferredSourceKey: routeContext.sourceKey)!,
    currentSourceKey: routeContext.sourceKey,
    preferredServerId: preferredServerId,
    coverage: routeContext.coverage,
    intent: UnifiedActivationIntent.details,
    environment: environment,
    artwork: artwork,
  );
  if (chosen == null || chosen.sourceKey == routeContext.sourceKey || !context.mounted) return;

  // The detail page this was invoked from closes before the replacement opens,
  // so Back does not walk the viewer backwards through every source they
  // looked at. Which mechanism closes it depends on how it was opened: since
  // PB-1/SYS-1b a TV detail page is a nested route inside the shell, and
  // `Navigator.of` there resolves to the profile navigator that owns the shell
  // itself — `canPop()` is false on it, so this used to silently leave the old
  // page open and stack the new one on top of it.
  final nested = TvNestedRouteScope.of(context);
  if (nested != null) {
    nested.dismiss(null);
  } else {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }
  if (!context.mounted) return;

  unawaited(SourcePreferenceStore.remember(group.identity, chosen.sourceKey));
  await _routeToSource(
    context,
    group: group,
    source: chosen,
    routeContext: coordinator.buildRouteContext(
      group: group,
      orderedSources: ordered,
      sourceKey: chosen.sourceKey,
      coverage: routeContext.coverage,
      intent: UnifiedActivationIntent.details,
    ),
    environment: environment,
    artwork: artwork,
    playDirectly: false,
    isOffline: isOffline,
    onRefresh: onRefresh,
    onPlaybackReturned: onPlaybackReturned,
    traceId: null,
  );
}

/// Hoofdstuk 15's offer after a failed playback start.
///
/// The coordinator says whether an alternative exists; the user decides whether
/// to take it. When there is none, nothing is shown at all: the player has
/// already reported the failure through the ordinary notice path, and a second
/// dialog offering nothing would just be a dialog.
Future<void> _offerAlternativeAfterPlaybackFailure(
  BuildContext context, {
  required UnifiedMediaGroup group,
  required String failedSourceKey,
  required UnifiedMediaRouteContext routeContext,
  required UnifiedActivationEnvironment environment,
  required Widget? artwork,
  required bool isOffline,
  required void Function(String)? onRefresh,
  required ValueChanged<MediaItem>? onPlaybackReturned,
  required String? traceId,
}) async {
  const coordinator = UnifiedActivationCoordinator();
  final options = coordinator.evaluatePlaybackFailure(
    sources: group.sources,
    failedSourceKey: failedSourceKey,
    availabilityFor: environment.availabilityFor,
  );
  if (!options.hasAlternatives) return;

  final wantsAnother = await OverlaySheetController.showAdaptive<bool>(
    context,
    presentation: OverlaySheetPresentation.panel,
    builder: (sheetContext) => TvPlaybackFailureAlternative(
      onChooseAnother: () => OverlaySheetController.closeAdaptive(sheetContext, true),
      onClose: () => OverlaySheetController.closeAdaptive(sheetContext, false),
    ),
  );
  if (wantsAnother != true || !context.mounted) return;

  // Also an explicit source-selection intent: "Andere bron kiezen" opens the
  // picker even when a preferred server exists, and especially when the source
  // that just failed *was* the preferred one.
  final preferredServerId = await PreferredServerStore.read();
  if (!context.mounted) return;
  final chosen = await showUnifiedSourcePicker(
    context,
    group: group,
    sources: options.alternatives,
    initialFocusSourceKey: options.alternatives.first.sourceKey,
    preferredServerId: preferredServerId,
    coverage: routeContext.coverage,
    intent: UnifiedActivationIntent.play,
    environment: environment,
    artwork: artwork,
  );
  if (chosen == null || !context.mounted) return;

  await _acceptChoice(
    context,
    group: group,
    chosen: chosen,
    coverage: routeContext.coverage,
    intent: UnifiedActivationIntent.play,
    environment: environment,
    artwork: artwork,
    playDirectly: true,
    isOffline: isOffline,
    onRefresh: onRefresh,
    onPlaybackReturned: onPlaybackReturned,
    traceId: traceId,
  );
}

/// Shows the picker and returns the source the user chose, or null for a
/// cancel (Menu/Back/Close, hoofdstuk 14.4).
///
/// Public because both activation and the two hoofdstuk-15 re-entries above
/// open the same modal, and because the widget tests drive it directly.
Future<UnifiedMediaSource?> showUnifiedSourcePicker(
  BuildContext context, {
  required UnifiedMediaGroup group,
  required List<UnifiedMediaSource> sources,
  required String initialFocusSourceKey,
  required SourceCoverageState coverage,
  required UnifiedActivationIntent intent,
  required UnifiedActivationEnvironment environment,
  String? preferredSourceKey,
  String? currentSourceKey,
  String? preferredServerId,
  Widget? artwork,
}) {
  final representative = group.representativeSource.item;
  // Created here, handed to the host *and* to the row that should carry it.
  // The host focuses `initialFocusNode` when it has one and the first traversal
  // descendant otherwise, and that fallback runs a frame after a row could ask
  // for focus itself — which is how the footer button, not the source, ended up
  // focused. `_PickerSessionState` disposes it.
  final initialFocusNode = FocusNode(debugLabel: 'TvSourcePickerInitialFocus');
  return OverlaySheetController.showAdaptive<UnifiedMediaSource>(
    context,
    initialFocusNode: initialFocusNode,
    // Hoofdstuk 14.4: "annuleren herstelt exacte kaart of CTA". The overlay
    // sheet is not a route, so nothing pops focus back for us; the shared
    // launcher restore hands it to exactly the node that opened this — and to
    // nothing at all when that node has since left the tree, which is what a
    // picker ending in a route replacement leaves behind. Fase 5A generalised
    // it out of this file so the filter and sort panels use one system rather
    // than a third copy.
    restoreLauncherFocus: true,
    // The centred 10-foot modal of hoofdstuk 14.1. On TV,
    // `resolveOverlaySheetGeometry` turns this into the proportional panel;
    // off TV it is the existing centred/bottom behaviour, unchanged.
    presentation: OverlaySheetPresentation.panel,
    builder: (sheetContext) => _PickerSession(
      sources: sources,
      initialFocusSourceKey: initialFocusSourceKey,
      initialFocusNode: initialFocusNode,
      preferredSourceKey: preferredSourceKey,
      currentSourceKey: currentSourceKey,
      preferredServerId: preferredServerId,
      title: representative.displayTitle,
      year: representative.year,
      intent: intent,
      coverage: coverage,
      environment: environment,
      artwork: artwork,
      onChosen: (source) => OverlaySheetController.closeAdaptive(sheetContext, source),
      onClose: () => OverlaySheetController.closeAdaptive(sheetContext, null),
    ),
  );
}

/// The stateful half of one open picker: the three things hoofdstuk 14 allows
/// to change *while* the modal is up.
///
/// It owns them rather than the presentation widget so each one stays a single
/// call into the coordinator contract, applied to a list, instead of a rule
/// re-implemented in a build method.
class _PickerSession extends StatefulWidget {
  const _PickerSession({
    required this.sources,
    required this.initialFocusSourceKey,
    required this.initialFocusNode,
    required this.preferredSourceKey,
    required this.currentSourceKey,
    required this.preferredServerId,
    required this.title,
    required this.year,
    required this.intent,
    required this.coverage,
    required this.environment,
    required this.artwork,
    required this.onChosen,
    required this.onClose,
  });

  final List<UnifiedMediaSource> sources;
  final String initialFocusSourceKey;

  /// Owned by this session for its whole life; see [showUnifiedSourcePicker].
  final FocusNode initialFocusNode;
  final String? preferredSourceKey;
  final String? currentSourceKey;
  final String? preferredServerId;
  final String title;
  final int? year;
  final UnifiedActivationIntent intent;
  final SourceCoverageState coverage;
  final UnifiedActivationEnvironment environment;
  final Widget? artwork;
  final ValueChanged<UnifiedMediaSource> onChosen;
  final VoidCallback onClose;

  @override
  State<_PickerSession> createState() => _PickerSessionState();
}

class _PickerSessionState extends State<_PickerSession> {
  late List<UnifiedMediaSource> _sources;
  late String _focusedSourceKey;
  String? _preferredServerId;
  bool _isResolving = false;
  bool _chosen = false;

  @override
  void initState() {
    super.initState();
    _sources = widget.sources;
    _focusedSourceKey = widget.initialFocusSourceKey;
    _preferredServerId = widget.preferredServerId;
    widget.environment.availabilityRevision?.addListener(_onAvailabilityChanged);
    _startBackgroundResolution();
  }

  @override
  void dispose() {
    widget.environment.availabilityRevision?.removeListener(_onAvailabilityChanged);
    widget.initialFocusNode.dispose();
    super.dispose();
  }

  /// Hoofdstuk 14.5. The picker is already on screen by the time this runs;
  /// nothing here can block it, and the predicate handed to the resolver turns
  /// true the moment the user picks.
  void _startBackgroundResolution() {
    final resolve = widget.environment.resolveMoreSources;
    if (resolve == null) return;
    setState(() => _isResolving = true);
    unawaited(
      resolve(() => _chosen || !mounted).then(
        (incoming) {
          if (!mounted) return;
          setState(() {
            _isResolving = false;
            // Order is preserved and focus does not move: re-sorting the list a
            // user is reading would slide the row out from under their thumb.
            // Hoofdstuk 14.4 puts the tidy re-sort at the *next* opening.
            _sources = mergeLateSources(_sources, incoming, preferredSourceKey: widget.preferredSourceKey);
          });
        },
        onError: (_) {
          if (mounted) setState(() => _isResolving = false);
        },
      ),
    );
  }

  /// Hoofdstuk 14.4: "rij wordt disabled; focus gaat naar dichtstbijzijnde
  /// online rij".
  void _onAvailabilityChanged() {
    if (!mounted) return;
    final restamped = [
      for (final source in _sources) source.withAvailability(widget.environment.availabilityFor(source)),
    ];
    final nextFocus = nextFocusAfterAvailabilityChange(ordered: restamped, focusedSourceKey: _focusedSourceKey);
    setState(() {
      _sources = restamped;
      // Null means nothing is usable any more; 14.4 sends focus to the panel's
      // own controls then, and those are not sources — leaving the key alone
      // keeps the disabled row marked while the footer takes over.
      if (nextFocus != null) _focusedSourceKey = nextFocus;
    });
  }

  /// Sets the profile's default server from inside the picker.
  ///
  /// It does not also select the row: the user said "from now on", not "and now
  /// too", and turning a preference into an activation would be the silent
  /// choice the whole contract forbids. The mark moves; the picker stays open.
  void _setPreferredServer(UnifiedMediaSource source) {
    unawaited(PreferredServerStore.remember(source.serverId.value));
    setState(() => _preferredServerId = source.serverId.value);
  }

  @override
  Widget build(BuildContext context) {
    return TvMediaSourcePicker(
      sources: _sources,
      focusedSourceKey: _focusedSourceKey,
      preferredSourceKey: widget.preferredSourceKey,
      currentSourceKey: widget.currentSourceKey,
      preferredServerId: _preferredServerId,
      initialFocusNode: widget.initialFocusNode,
      initialFocusSourceKey: widget.initialFocusSourceKey,
      title: widget.title,
      year: widget.year,
      intent: widget.intent,
      coverage: widget.coverage,
      isResolving: _isResolving,
      artwork: widget.artwork,
      onSelectSource: (source) {
        _chosen = true;
        widget.onChosen(source);
      },
      onFocusSource: (key) => _focusedSourceKey = key,
      onClose: widget.onClose,
      onManageServers: widget.environment.onManageServers,
      onSetPreferredServer: _setPreferredServer,
    );
  }
}
