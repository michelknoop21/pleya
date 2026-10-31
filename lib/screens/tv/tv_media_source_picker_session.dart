part of 'tv_media_source_picker_route.dart';

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
    // A plain assignment: this runs from initState, before the first build.
    // The two setState calls below are a different case, they land after an
    // await and do need to schedule a frame.
    _isResolving = true;
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
