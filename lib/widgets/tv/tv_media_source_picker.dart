/// The source picker of hoofdstuk 14 (docs/tvos-unified-experience.md): a
/// centred 10-foot modal that asks which concrete source a title should open
/// from.
///
/// **This widget decides nothing.** Which sources exist, in what order, which
/// row starts focused, where focus goes when a server drops out, where a late
/// arrival is inserted — all of that is
/// `UnifiedActivationCoordinator`/`rankSources`/`selectInitialFocus`/
/// `nextFocusAfterAvailabilityChange`/`mergeLateSources`, and reaches this
/// widget as [TvMediaSourcePicker.sources] plus
/// [TvMediaSourcePicker.focusedSourceKey]. What lives here is presentation,
/// focus traversal and remote input: the half that hoofdstuk 14 describes in
/// pixels rather than in rules.
///
/// It is a controlled widget for that reason. The focused row is an input, not
/// internal state, so a test — and the route above it — can drive "the focused
/// source went offline" or "a late source arrived" as the state transitions
/// they are, instead of hoping the widget reproduces the rule a second time.
///
/// ## Depth, and which token owns which layer
///
/// Hoofdstuk 8.2 and 34 make `monoTheme` the authority, and DEC-053 is the
/// warning: this theme maps `secondaryContainer`, `primaryContainer`,
/// `surfaceContainerHighest` and `surfaceBright` all onto `surface`, so a state
/// painted with a Material container role is literally the same colour as the
/// card beneath it. Every surface here therefore comes from [MonoTokens], one
/// token per layer, and the ramp is deliberate:
///
/// ```
/// TV canvas          mono.bg              #141414
/// scrim + cast shadow                               the panel floats, not cut out
/// picker panel       mono.surface         #1F1F1F   + hairline + top sheen
/// source row (idle)  text @ 5%            ≈#2A2A2A  + faint hairline
/// source row (focus) mono.surfaceElevated #2F2F2F   + top sheen + WHITE ring
/// unusable row       no fill                        + hairline only
/// ```
///
/// Four layers is one more than the first render had, and the extra one is the
/// shadow: a panel whose only separation from the page is a 10-point luminance
/// step reads as a hole cut in the canvas, not as a surface in front of it.
/// `resolveOverlaySheetGeometry` owns it, in the same reference fractions as
/// the panel's own box, because the host clips the panel and a shadow drawn in
/// here would be clipped with it.
///
/// Focus is the white ring of `FocusTheme`, the lift to `surfaceElevated`, and
/// a sheen along the row's top edge — never a brighter grey alone, which from
/// three metres reads as "one row is a different shade" rather than "this is
/// where I am". Red and amber stay sparse: amber marks the remembered source,
/// the profile default and an expired session (all three actionable), red draws
/// resume progress and a playback failure, and nothing else on this surface is
/// branded.
///
/// Type carries the rest. The ink ladder is [TvSourcePickerLayout.inkPrimary]
/// and friends; there are no ad-hoc alphas below, because the reason the first
/// render read as a Material settings dialog was three text tiers sitting
/// within 25% of each other.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/dpad_navigator.dart';
import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../media/unified/source_availability.dart';
import '../../media/unified/source_coverage_state.dart';
import '../../media/unified/unified_media_source.dart';
import '../../media/unified/unified_route_context.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../overlay_sheet_geometry.dart';
import 'tv_panel_primitives.dart';
import 'tv_source_row_descriptor.dart';
import 'tv_unified_layout.dart';

/// The picker's content. The panel chrome (scrim, centring, corner radius,
/// enter animation) belongs to the overlay sheet host, which resolves it from
/// [OverlaySheetPresentation.panel]; this widget draws what is inside it, plus
/// the hairline that lands on the host's clipped edge.
class TvMediaSourcePicker extends StatelessWidget {
  /// Every source in hoofdstuk 4.7 order, usable or not. Unusable rows are
  /// rendered disabled rather than hidden (hoofdstuk 14.4) so a user can see
  /// that the server they expected is simply down.
  final List<UnifiedMediaSource> sources;

  /// The row that currently has focus. Owned by the caller — see the class doc.
  final String focusedSourceKey;

  /// The remembered choice (hoofdstuk 14.8). Marks "Laatst gebruikt"; it has
  /// already been folded into [focusedSourceKey] where it was valid.
  final String? preferredSourceKey;

  /// The source the surface behind the picker already shows, when the picker
  /// was reopened from a detail page to switch (hoofdstuk 15).
  final String? currentSourceKey;

  /// The profile's default server for duplicate content, when it has one.
  /// Marked on its row so the standing default is visible where it is being
  /// overruled, rather than being an invisible rule the user has to infer.
  final String? preferredServerId;

  final String title;
  final int? year;
  final UnifiedActivationIntent intent;
  final SourceCoverageState coverage;

  /// Whether background source resolution is still running (hoofdstuk 14.5).
  /// Draws the "Meer bronnen controleren…" line; never blocks the list.
  final bool isResolving;

  /// Artwork for the header. Null draws the poster-shaped stand-in of
  /// [_ArtworkFallback] rather than an empty well.
  final Widget? artwork;

  /// The node the overlay host was told to focus when the panel opened, and
  /// the row that should carry it.
  ///
  /// `OverlaySheetHost` focuses `initialFocusNode` if it has one and the first
  /// traversal descendant otherwise — and that fallback runs a frame *after*
  /// a row could request focus itself, so it silently overrode it and the
  /// footer button ended up focused. Handing the host the node up front is the
  /// supported way to say which row is the entry point.
  final FocusNode? initialFocusNode;
  final String? initialFocusSourceKey;

  final ValueChanged<UnifiedMediaSource> onSelectSource;
  final ValueChanged<String> onFocusSource;
  final VoidCallback onClose;

  /// Hoofdstuk 14.7's second button, offered only when nothing is reachable.
  final VoidCallback? onManageServers;

  /// Makes the focused row's server the profile's default. Offered only where
  /// the user is already looking at the choice — which is the one moment
  /// "always use this one" means something concrete. Null hides the action;
  /// the same setting gets a permanent home under Mijn Pleya later.
  final ValueChanged<UnifiedMediaSource>? onSetPreferredServer;

  const TvMediaSourcePicker({
    super.key,
    required this.sources,
    required this.focusedSourceKey,
    required this.title,
    required this.intent,
    required this.coverage,
    required this.onSelectSource,
    required this.onFocusSource,
    required this.onClose,
    this.preferredSourceKey,
    this.currentSourceKey,
    this.preferredServerId,
    this.year,
    this.isResolving = false,
    this.artwork,
    this.onManageServers,
    this.onSetPreferredServer,
    this.initialFocusNode,
    this.initialFocusSourceKey,
  });

  bool get _hasUsableSource => sources.any((s) => s.availability.isUsable);

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final mono = tokens(context);
    final descriptors = describeSources(
      sources,
      preferredSourceKey: preferredSourceKey,
      currentSourceKey: currentSourceKey,
      preferredServerId: preferredServerId,
    );
    final focused = sources.where((s) => s.sourceKey == focusedSourceKey).firstOrNull;
    // Hoofdstuk 14.4: "bij geen online bron naar 'Servers beheren' of
    // 'Sluiten'". A disabled row must never be the entry point — it cannot be
    // activated, so focus parked there leaves the remote with nothing to press.
    final entryRowKey = _hasUsableSource ? initialFocusSourceKey : null;
    final footerFocusNode = entryRowKey == null ? initialFocusNode : null;
    // Only worth offering on a row that is usable and is not already the
    // default: "always use the server you already always use" is not an action.
    final settable =
        onSetPreferredServer != null &&
            focused != null &&
            focused.availability.isUsable &&
            focused.serverId.value != preferredServerId
        ? focused
        : null;
    final radius = tvPanelBorderRadius(MediaQuery.sizeOf(context));

    return DecoratedBox(
      decoration: tvPanelDecoration(mono, radius),
      child: Padding(
        padding: EdgeInsets.all(TvSourcePickerLayout.panelPadding * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(scale: scale, title: title, year: year, intent: intent, coverage: coverage, artwork: artwork),
            SizedBox(height: TvSourcePickerLayout.sectionGap * scale),
            // Hoofdstuk 14.7: with nothing reachable the list of dead rows is
            // not the message — the two things the user can do about it are.
            if (!_hasUsableSource) ...[
              _UnreachableNotice(scale: scale, authRequired: _authRequired),
              SizedBox(height: TvSourcePickerLayout.rowGap * scale),
            ],
            Flexible(
              child: _SourceList(
                scale: scale,
                sources: sources,
                descriptors: descriptors,
                focusedSourceKey: focusedSourceKey,
                initialFocusNode: entryRowKey == null ? null : initialFocusNode,
                initialFocusSourceKey: entryRowKey,
                onSelectSource: onSelectSource,
                onFocusSource: onFocusSource,
              ),
            ),
            if (isResolving) ...[SizedBox(height: TvSourcePickerLayout.rowGap * scale), _ResolvingRow(scale: scale)],
            SizedBox(height: TvSourcePickerLayout.footerGap * scale),
            _Footer(
              scale: scale,
              onClose: onClose,
              onManageServers: _hasUsableSource ? null : onManageServers,
              settableServer: settable,
              onSetPreferredServer: onSetPreferredServer,
              focusNode: footerFocusNode,
            ),
          ],
        ),
      ),
    );
  }

  /// Hoofdstuk 14.7 keeps these two apart: an auth error is something the user
  /// can fix from the couch, an unreachable server is not, and one message for
  /// both would hide the actionable case behind the hopeless one.
  bool get _authRequired => sources.any((s) => s.availability == SourceAvailability.authError);
}

/// Hoofdstuk 14.7's headline, as part of the picker rather than as an alert
/// dropped into it.
///
/// The glyph is what makes the two cases tellable apart before the sentence is
/// read: amber for the session that has expired — actionable from the couch,
/// which is the one thing hoofdstuk 14.7 insists must not be hidden behind the
/// hopeless case — and quiet grey for a server that is simply out of reach.
/// Same left edge and same ink ladder as the rows below it: this is a state of
/// the picker, not a different kind of surface.
class _UnreachableNotice extends StatelessWidget {
  const _UnreachableNotice({required this.scale, required this.authRequired});

  final double scale;
  final bool authRequired;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final size = TvSourcePickerLayout.rowPrimaryFontSize * scale;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          authRequired ? Symbols.lock_person_rounded : Symbols.cloud_off_rounded,
          size: size,
          color: authRequired ? mono.accentAlt : mono.text.withValues(alpha: TvSourcePickerLayout.inkQuiet),
        ),
        SizedBox(width: 10 * scale),
        Expanded(
          child: Text(
            authRequired ? t.sourcePicker.reauthRequiredTitle : t.sourcePicker.noneReachableTitle,
            style: TextStyle(
              color: mono.text,
              fontSize: size,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.scale,
    required this.title,
    required this.year,
    required this.intent,
    required this.coverage,
    required this.artwork,
  });

  final double scale;
  final String title;
  final int? year;
  final UnifiedActivationIntent intent;
  final SourceCoverageState coverage;
  final Widget? artwork;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final posterWidth = TvSourcePickerLayout.posterWidth * scale;

    final radius = BorderRadius.circular(TvSourcePickerLayout.artworkRadius * scale);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The hairline is on the artwork, not just on its fallback: a poster
        // whose own darkest corner is near #1F1F1F otherwise bleeds into the
        // panel and stops reading as a picture of something.
        DecoratedBox(
          decoration: ShapeDecoration(
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: mono.outline, width: 1),
            ),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: SizedBox(
              width: posterWidth,
              height: posterWidth / TvSourcePickerLayout.posterAspectRatio,
              child: artwork ?? _ArtworkFallback(scale: scale, width: posterWidth),
            ),
          ),
        ),
        SizedBox(width: TvSourcePickerLayout.headerGap * scale),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                year == null ? title : '$title ($year)',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mono.text,
                  fontSize: TvSourcePickerLayout.titleFontSize * scale,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  height: 1.1,
                ),
              ),
              SizedBox(height: TvSourcePickerLayout.rowLineGap * scale * 1.5),
              // The question, not a field label. It carries the secondary tier
              // exactly — one step under the title and one step over the
              // coverage line, so the header reads title → intent → status
              // rather than as three stacked settings.
              Text(
                intent == UnifiedActivationIntent.play ? t.sourcePicker.playTitle : t.sourcePicker.detailsTitle,
                style: TextStyle(
                  color: mono.text.withValues(alpha: TvSourcePickerLayout.inkSecondary),
                  fontSize: TvSourcePickerLayout.subtitleFontSize * scale,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
              SizedBox(height: TvSourcePickerLayout.rowLineGap * scale * 1.5),
              _CoverageLine(scale: scale, coverage: coverage),
            ],
          ),
        ),
      ],
    );
  }
}

/// What "no artwork" looks like when it is deliberate.
///
/// Not a flat grey well with a small glyph in it — that is the shape of a
/// broken image, and it made the header read as an empty form field. This is a
/// poster-shaped tile with its own light: a top-lit wash over
/// `mono.surfaceElevated` and the same film glyph the watchlist and Seerr cards
/// use for a missing poster, at the size artwork would occupy rather than at
/// the size of an error icon. It stands *for* the artwork instead of marking
/// its absence.
class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({required this.scale, required this.width});

  final double scale;
  final double width;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.alphaBlend(mono.text.withValues(alpha: 0.06), mono.surfaceElevated), mono.bg],
        ),
      ),
      child: Center(
        child: Icon(Symbols.movie_rounded, fill: 1, color: mono.text.withValues(alpha: 0.2), size: width * 0.42),
      ),
    );
  }
}

/// "Beschikbaar op N servers", plus hoofdstuk 14.2's partial-coverage half when
/// a server could not be asked. Amber on that half only: an incomplete answer
/// is worth noticing, and hoofdstuk 8.2 allows amber for exactly that kind of
/// marker.
class _CoverageLine extends StatelessWidget {
  const _CoverageLine({required this.scale, required this.coverage});

  final double scale;
  final SourceCoverageState coverage;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final checked = coverage.checkedServerIds.length;
    final unchecked = coverage.uncheckedCount;
    final style = TextStyle(
      color: mono.text.withValues(alpha: TvSourcePickerLayout.inkTertiary),
      fontSize: TvSourcePickerLayout.statusFontSize * scale,
      fontWeight: FontWeight.w500,
      height: 1.2,
    );

    return Wrap(
      spacing: 8 * scale,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (checked > 0)
          Text(
            checked == 1 ? t.sourcePicker.availableOnOneServer : t.sourcePicker.availableOnManyServers(count: checked),
            style: style,
          ),
        // One tertiary line, not two competing ones. The middot ties the halves
        // together so partial coverage reads as a qualifier on the count it
        // qualifies, and the amber sits on that qualifier alone — at the same
        // size and one weight up, which is all hoofdstuk 8.2's "spaarzaam"
        // allows and all a status marker needs.
        if (checked > 0 && unchecked > 0) Text('·', style: style),
        if (unchecked > 0)
          Text(
            unchecked == 1 ? t.sourcePicker.oneServerUnchecked : t.sourcePicker.manyServersUnchecked(count: unchecked),
            style: style.copyWith(color: mono.accentAlt, fontWeight: FontWeight.w600),
          ),
      ],
    );
  }
}

/// The list, with a fade at whichever edge still has rows behind it.
///
/// Ten sources scroll (F3), and on a 10-foot surface a row sliced flat by the
/// panel edge reads as a rendering fault rather than as "there is more". The
/// fade is drawn, not scrolled: it says *more*, and the D-pad does the moving.
class _SourceList extends StatefulWidget {
  const _SourceList({
    required this.scale,
    required this.sources,
    required this.descriptors,
    required this.focusedSourceKey,
    required this.initialFocusNode,
    required this.initialFocusSourceKey,
    required this.onSelectSource,
    required this.onFocusSource,
  });

  final double scale;
  final List<UnifiedMediaSource> sources;
  final List<TvSourceRowDescriptor> descriptors;
  final String focusedSourceKey;
  final FocusNode? initialFocusNode;
  final String? initialFocusSourceKey;
  final ValueChanged<UnifiedMediaSource> onSelectSource;
  final ValueChanged<String> onFocusSource;

  @override
  State<_SourceList> createState() => _SourceListState();
}

class _SourceListState extends State<_SourceList> {
  final _controller = ScrollController();
  bool _hasMoreAbove = false;
  bool _hasMoreBelow = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncEdges(ScrollMetrics metrics) {
    final above = metrics.extentBefore > 1;
    final below = metrics.extentAfter > 1;
    if (above == _hasMoreAbove && below == _hasMoreBelow) return;
    // Post-frame: this runs from a notification during layout/paint, and
    // setState there would rebuild the tree that is currently being laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _hasMoreAbove = above;
        _hasMoreBelow = below;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final scale = widget.scale;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _syncEdges(notification.metrics);
        return false;
      },
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          _syncEdges(notification.metrics);
          return false;
        },
        child: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              if (_hasMoreAbove) Colors.transparent else Colors.black,
              Colors.black,
              Colors.black,
              if (_hasMoreBelow) Colors.transparent else Colors.black,
            ],
            stops: const [0, 0.06, 0.94, 1],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: ListView.separated(
            controller: _controller,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: widget.sources.length,
            separatorBuilder: (_, _) => SizedBox(height: TvSourcePickerLayout.rowGap * scale),
            itemBuilder: (context, index) {
              final source = widget.sources[index];
              final descriptor = widget.descriptors[index];
              return _SourceRow(
                key: ValueKey(source.sourceKey),
                externalFocusNode: source.sourceKey == widget.initialFocusSourceKey ? widget.initialFocusNode : null,
                scale: scale,
                descriptor: descriptor,
                index: index,
                total: widget.sources.length,
                shouldTakeFocus: source.sourceKey == widget.focusedSourceKey,
                idleColor: mono.text.withValues(alpha: TvSourcePickerLayout.idleRowFill),
                onSelect: descriptor.isUsable ? () => widget.onSelectSource(source) : null,
                onFocused: () => widget.onFocusSource(source.sourceKey),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One source row (hoofdstuk 14.3).
///
/// Focus is drawn twice on purpose: `FocusableWrapper` paints the theme's white
/// ring, and the row lifts from its idle fill to `surfaceElevated`. Both are
/// driven by the wrapper's *own* focus, never by the caller's requested key, so
/// the ring and the fill can never disagree about which row is live.
///
/// DEC-053 is why "Laatst gebruikt" and "Huidige bron" are words rather than
/// shades: a selection state painted as a container tint is invisible in this
/// theme, and selected is not the same state as focused.
class _SourceRow extends StatefulWidget {
  const _SourceRow({
    super.key,
    required this.externalFocusNode,
    required this.scale,
    required this.descriptor,
    required this.index,
    required this.total,
    required this.shouldTakeFocus,
    required this.idleColor,
    required this.onSelect,
    required this.onFocused,
  });

  /// Non-null only on the row the overlay host was told to focus at open time.
  final FocusNode? externalFocusNode;

  final double scale;
  final TvSourceRowDescriptor descriptor;
  final int index;
  final int total;
  final bool shouldTakeFocus;
  final Color idleColor;
  final VoidCallback? onSelect;
  final VoidCallback onFocused;

  @override
  State<_SourceRow> createState() => _SourceRowState();
}

class _SourceRowState extends State<_SourceRow> {
  FocusNode? _ownNode;
  bool _isFocused = false;

  /// The host owns the entry-point node's lifetime; every other row owns its
  /// own, created lazily so a list of ten rows does not allocate an unused one.
  FocusNode get _focusNode => widget.externalFocusNode ?? (_ownNode ??= FocusNode(debugLabel: 'TvSourcePickerRow'));

  @override
  void initState() {
    super.initState();
    // The entry-point row is focused by the host, which is the only way that
    // survives its own first-descendant fallback. Any *later* move — a server
    // dropping out under the cursor — is ours.
    if (widget.shouldTakeFocus && widget.externalFocusNode == null) _requestFocusAfterLayout();
  }

  @override
  void didUpdateWidget(_SourceRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The caller moved focus here — because a server dropped out under the
    // cursor (hoofdstuk 14.4), or because the list was rebuilt. Honour it.
    if (widget.shouldTakeFocus && !oldWidget.shouldTakeFocus) _requestFocusAfterLayout();
  }

  /// Post-frame, because a row that arrives with the list it is in has no
  /// attached node during the build that creates it.
  void _requestFocusAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.shouldTakeFocus && _focusNode.canRequestFocus) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _ownNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final descriptor = widget.descriptor;
    final mono = tokens(context);
    final enabled = descriptor.isUsable;

    // An unusable row still reads as a row — "which server is down" is the
    // answer the user came for — but it carries no fill, so the choosable rows
    // are the ones with weight.
    //
    // The fill is always a gradient, even when it is flat, so the focus
    // transition is a plain `Gradient.lerp` between two stops. The focused
    // row's top stop is a sheen: a surface catching light from above, which is
    // the depth cue a shadow would give if the list viewport did not clip it.
    final baseFill = !enabled ? Colors.transparent : (_isFocused ? mono.surfaceElevated : widget.idleColor);
    final topFill = _isFocused && enabled
        ? Color.alphaBlend(mono.text.withValues(alpha: TvSourcePickerLayout.focusedRowSheen), mono.surfaceElevated)
        : baseFill;

    final primaryColor = mono.text.withValues(
      alpha: enabled ? TvSourcePickerLayout.inkPrimary : TvSourcePickerLayout.inkDisabledPrimary,
    );
    final secondaryColor = mono.text.withValues(
      alpha: enabled ? TvSourcePickerLayout.inkSecondary : TvSourcePickerLayout.inkDisabledSecondary,
    );
    final tertiaryColor = mono.text.withValues(
      alpha: enabled ? TvSourcePickerLayout.inkTertiary : TvSourcePickerLayout.inkDisabledTertiary,
    );

    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(TvSourcePickerLayout.rowRadius * scale));

    return FocusableWrapper(
      focusNode: _focusNode,
      canRequestFocus: enabled,
      // `focusShapeBorder`, not `borderRadius`: the ring is then painted in
      // `foregroundDecoration`. A row has an opaque fill, and a ring drawn
      // behind it is a ring nobody sees — the exact failure that made the
      // focused source unidentifiable from the couch in the first render.
      focusShapeBorder: shape,
      // A row is a wide, dense band inside an already-small panel; scaling it
      // would push its neighbours around and clip against the panel edge. The
      // ring plus the fill lift carry the focus instead.
      disableScale: true,
      autoScroll: true,
      semanticLabel: t.sourcePicker.rowSemantics(
        index: widget.index + 1,
        count: widget.total,
        description: descriptor.accessibleDescription,
      ),
      onFocusChange: (focused) {
        setState(() => _isFocused = focused);
        if (focused) widget.onFocused();
      },
      onSelect: widget.onSelect == null
          ? null
          : () {
              // Select closes the picker and pushes a route, so the key-up of
              // this very press would otherwise land on whatever takes focus
              // next. Eleven other activation sites in this codebase arm this
              // for the same reason; see CLAUDE.md.
              SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
              widget.onSelect!();
            },
      child: AnimatedContainer(
        duration: mono.fast,
        constraints: BoxConstraints(minHeight: TvSourcePickerLayout.rowMinHeight * scale),
        padding: EdgeInsets.symmetric(
          horizontal: TvSourcePickerLayout.rowPaddingHorizontal * scale,
          vertical: TvSourcePickerLayout.rowPaddingVertical * scale,
        ),
        decoration: ShapeDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [topFill, baseFill],
          ),
          shape: shape.copyWith(
            // The hairline steps aside for the focus ring rather than doubling
            // it: two concentric borders read as a rendering artefact. On an
            // idle row it is deliberately fainter than `mono.outline`: at
            // `outline`'s 12% white every row wore a visible box, and a column
            // of boxed rows is a settings list. The fill does the separating;
            // the hairline only keeps the edge from dissolving.
            side: _isFocused
                ? BorderSide.none
                : BorderSide(
                    color: enabled ? mono.text.withValues(alpha: TvSourcePickerLayout.idleRowOutline) : mono.outline,
                    width: 1,
                  ),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    descriptor.serverName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: TvSourcePickerLayout.rowPrimaryFontSize * scale,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                      height: 1.1,
                    ),
                  ),
                ),
                if (descriptor.statusLabel != null) ...[
                  SizedBox(width: 12 * scale),
                  _StatusLabel(scale: scale, descriptor: descriptor),
                ],
              ],
            ),
            if (descriptor.contextParts.isNotEmpty) ...[
              SizedBox(height: TvSourcePickerLayout.rowLineGap * scale),
              Text(
                descriptor.contextParts.join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: secondaryColor,
                  fontSize: TvSourcePickerLayout.rowSecondaryFontSize * scale,
                  // Regular, not medium. Bold context under a bold server name
                  // is two headings on one row, and the eye then has to read
                  // both before it knows which server it is looking at.
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.1,
                  height: 1.15,
                ),
              ),
            ],
            if (descriptor.qualityParts.isNotEmpty || descriptor.progressLabel != null) ...[
              SizedBox(height: TvSourcePickerLayout.rowLineGap * scale * 0.75),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      descriptor.qualityParts.join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tertiaryColor,
                        fontSize: TvSourcePickerLayout.rowTertiaryFontSize * scale,
                        height: 1.15,
                      ),
                    ),
                  ),
                  if (descriptor.progressLabel != null) ...[
                    SizedBox(width: 12 * scale),
                    // A step brighter than the quality parts it shares the line
                    // with: "where was I" is the reason this row is the one to
                    // pick, and it is the half of the line worth reading.
                    Text(
                      descriptor.progressLabel!,
                      style: TextStyle(
                        color: secondaryColor,
                        fontSize: TvSourcePickerLayout.rowTertiaryFontSize * scale,
                        fontWeight: FontWeight.w500,
                        height: 1.15,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if (descriptor.progressFraction != null) ...[
              SizedBox(height: TvSourcePickerLayout.progressBarGap * scale),
              _ProgressBar(scale: scale, fraction: descriptor.progressFraction!, enabled: enabled),
            ],
          ],
        ),
      ),
    );
  }
}

/// The right-hand word on line one. Amber for the three states the user can act
/// on — the profile's standing default (hoofdstuk 14.8a), the remembered source
/// for this title, and a session that has expired and can be renewed from the
/// couch. A server that is simply out of reach gets quiet grey: it is
/// information, not a call to action, and amber on it would spend the accent
/// hoofdstuk 8.2 keeps sparse on the one row nobody can use.
///
/// Only one label ever renders (the descriptor ranks them), so the amber is one
/// short word on one row — which is what keeps "Voorkeursserver" a marker the
/// eye finds rather than a second thing competing with the server name.
class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.scale, required this.descriptor});

  final double scale;
  final TvSourceRowDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final actionable =
        descriptor.isPreferredServer ||
        descriptor.isPreferred ||
        descriptor.availability == SourceAvailability.authError;
    return Text(
      descriptor.statusLabel!,
      style: TextStyle(
        color: actionable ? mono.accentAlt : mono.text.withValues(alpha: TvSourcePickerLayout.inkQuiet),
        fontSize: TvSourcePickerLayout.statusFontSize * scale,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        height: 1.1,
      ),
    );
  }
}

/// Resume progress: a full-width track with the watched share filled in Pleya
/// red — hoofdstuk 8.2's one sanctioned use of the brand colour on this
/// surface, and the same "rode progressbalken" 33.1 makes binding for the home
/// cards.
///
/// The geometry is spelled out rather than left to the defaults, because the
/// defaults quietly produced the wrong picture: a `Stack` sizes to its largest
/// *non-positioned* child, so an unconstrained `FractionallySizedBox` made the
/// whole bar 26% wide, and a `ColoredBox` under loose vertical constraints
/// takes `constraints.smallest` — zero height — so the red never painted at
/// all. What rendered was the track, at the fill's width, in grey. Hence
/// `width: double.infinity` and an explicit `heightFactor`, and hence the
/// contract test in `tv_media_source_picker_test.dart` that measures both boxes
/// instead of trusting that they are there.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.scale, required this.fraction, required this.enabled});

  final double scale;
  final double fraction;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final height = TvSourcePickerLayout.progressBarHeight * scale;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The track has to read as a track. Without one the red fill is a
            // short line floating at the bottom of the row, which at three
            // metres looks like a rendering fault rather than like progress.
            ColoredBox(color: mono.text.withValues(alpha: TvSourcePickerLayout.progressTrack)),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: fraction,
                heightFactor: 1,
                child: ColoredBox(color: enabled ? mono.accent : mono.accent.withValues(alpha: 0.35)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hoofdstuk 14.5's spinner line. It sits *below* the list rather than in it,
/// so a late arrival lands under the rows a user is already reading instead of
/// under a placeholder that then disappears from under their thumb.
class _ResolvingRow extends StatelessWidget {
  const _ResolvingRow({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final size = TvSourcePickerLayout.statusFontSize * scale;
    return Row(
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: 1.6 * scale,
            color: mono.text.withValues(alpha: TvSourcePickerLayout.inkTertiary),
          ),
        ),
        SizedBox(width: 10 * scale),
        Text(
          t.sourcePicker.checkingMoreSources,
          style: TextStyle(
            color: mono.text.withValues(alpha: TvSourcePickerLayout.inkTertiary),
            fontSize: TvSourcePickerLayout.statusFontSize * scale,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.scale,
    required this.onClose,
    required this.onManageServers,
    required this.settableServer,
    required this.onSetPreferredServer,
    required this.focusNode,
  });

  final double scale;
  final VoidCallback onClose;
  final VoidCallback? onManageServers;
  final UnifiedMediaSource? settableServer;
  final ValueChanged<UnifiedMediaSource>? onSetPreferredServer;

  /// Set when no row can take focus, so the panel's own controls become the
  /// entry point. It goes to the most useful action available.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final settable = settableServer;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (settable != null)
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: TvPanelButton(
                scale: scale,
                // Named, not generic: from the couch "Altijd NAS gebruiken"
                // says what will happen, "Voorkeursserver instellen" asks the
                // user to remember which row they were on.
                label: t.sourcePicker.setPreferredServer(server: settable.serverName),
                icon: Symbols.star_rounded,
                onPressed: () => onSetPreferredServer!(settable),
                primary: false,
              ),
            ),
          ),
        if (onManageServers != null) ...[
          TvPanelButton(
            scale: scale,
            label: t.sourcePicker.manageServers,
            onPressed: onManageServers!,
            primary: true,
            focusNode: focusNode,
          ),
          SizedBox(width: 12 * scale),
        ],
        TvPanelButton(
          scale: scale,
          label: t.common.close,
          onPressed: onClose,
          primary: false,
          focusNode: onManageServers == null ? focusNode : null,
        ),
      ],
    );
  }
}

/// Hoofdstuk 15's offer after playback initialisation failed.
///
/// A *presentation* of `PlaybackFailureOptions`, which is itself only a report:
/// "geen stille fallback, omdat een andere bron een andere edition, trackset of
/// progress kan hebben". Nothing here switches source; [onChooseAnother] hands
/// the decision back to the user by reopening the picker.
class TvPlaybackFailureAlternative extends StatelessWidget {
  const TvPlaybackFailureAlternative({super.key, required this.onChooseAnother, required this.onClose});

  final VoidCallback onChooseAnother;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final mono = tokens(context);
    final radius = tvPanelBorderRadius(MediaQuery.sizeOf(context));

    return DecoratedBox(
      decoration: tvPanelDecoration(mono, radius),
      child: Padding(
        padding: EdgeInsets.all(TvSourcePickerLayout.panelPadding * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // The one place red is semantically earned on this surface: a
                // failure, not decoration. It sits in a small tinted well
                // rather than bare on the panel — the glyph then reads as a
                // status badge belonging to this surface instead of as a stray
                // Material alert icon, and the red stays a contained accent
                // rather than a loose mark (hoofdstuk 8.2's "spaarzaam").
                DecoratedBox(
                  decoration: ShapeDecoration(shape: const CircleBorder(), color: mono.accent.withValues(alpha: 0.14)),
                  child: Padding(
                    padding: EdgeInsets.all(9 * scale),
                    child: Icon(
                      Symbols.error_rounded,
                      color: mono.accent,
                      size: TvSourcePickerLayout.titleFontSize * scale,
                    ),
                  ),
                ),
                SizedBox(width: 14 * scale),
                Expanded(
                  child: Text(
                    t.sourcePicker.playbackFailedTitle,
                    style: TextStyle(
                      color: mono.text,
                      fontSize: TvSourcePickerLayout.titleFontSize * scale,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: TvSourcePickerLayout.sectionGap * scale * 1.5),
            // Wrap, not Row: hoofdstuk 25 promises the long translations still
            // fit, and two capsule buttons whose labels grow by half in German
            // overflow a panel sized as a fraction of the screen. Wrapping to a
            // second line is the graceful answer; a clipped button is not.
            Wrap(
              alignment: WrapAlignment.end,
              // The focused button grows by `FocusTheme.focusScale`, so a run
              // aligned at its start would step the unfocused one upwards.
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12 * scale,
              runSpacing: 10 * scale,
              children: [
                TvPanelButton(
                  scale: scale,
                  label: t.sourcePicker.chooseAnotherSource,
                  onPressed: onChooseAnother,
                  primary: true,
                ),
                TvPanelButton(scale: scale, label: t.common.close, onPressed: onClose, primary: false),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
