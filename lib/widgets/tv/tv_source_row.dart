/// The source list and the source row of hoofdstuk 14.3, lifted out of
/// [TvMediaSourcePicker] so the action-scope picker of hoofdstuk 23 renders the
/// same rows rather than a second set that drifts from them.
///
/// The seam is [TvSourceRowDescriptor], not [UnifiedMediaSource]: the two
/// pickers agree on what a row *looks like* and disagree completely on what
/// choosing one *means*, so the shared half stops at the descriptor and the
/// callbacks speak in `sourceKey` strings. That is also what lets the
/// action-scope picker put an "Alle bronnen" row in the same list — it is a
/// descriptor like any other, and no widget here needs to know it is not a
/// server.
///
/// Nothing here decides anything. Which rows exist, in what order, and which
/// one starts focused are inputs; see [TvMediaSourcePicker] for the full
/// rationale, which applies unchanged.
library;

import 'package:flutter/material.dart';

import '../../focus/dpad_navigator.dart';
import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../media/unified/source_availability.dart';
import '../../theme/mono_tokens.dart';
import 'tv_source_row_descriptor.dart';
import 'tv_unified_layout.dart';

/// The list, with a fade at whichever edge still has rows behind it.
///
/// Ten sources scroll (F3), and on a 10-foot surface a row sliced flat by the
/// panel edge reads as a rendering fault rather than as "there is more". The
/// fade is drawn, not scrolled: it says *more*, and the D-pad does the moving.
class TvSourceRowList extends StatefulWidget {
  const TvSourceRowList({
    super.key,
    required this.scale,
    required this.descriptors,
    required this.focusedSourceKey,
    required this.initialFocusNode,
    required this.initialFocusSourceKey,
    required this.onSelectSource,
    required this.onFocusSource,
  });

  final double scale;

  /// Every row, in the order the caller decided. A descriptor whose
  /// [TvSourceRowDescriptor.sourceKey] names no real source is fine — see the
  /// library doc.
  final List<TvSourceRowDescriptor> descriptors;
  final String focusedSourceKey;
  final FocusNode? initialFocusNode;
  final String? initialFocusSourceKey;

  /// Fires with the chosen row's `sourceKey`. Never with an unusable row: the
  /// row itself refuses focus and Select.
  final ValueChanged<String> onSelectSource;
  final ValueChanged<String> onFocusSource;

  @override
  State<TvSourceRowList> createState() => TvSourceRowListState();
}

class TvSourceRowListState extends State<TvSourceRowList> {
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
            itemCount: widget.descriptors.length,
            separatorBuilder: (_, _) => SizedBox(height: TvSourcePickerLayout.rowGap * scale),
            itemBuilder: (context, index) {
              final descriptor = widget.descriptors[index];
              final key = descriptor.sourceKey;
              return TvSourceRow(
                key: ValueKey(key),
                externalFocusNode: key == widget.initialFocusSourceKey ? widget.initialFocusNode : null,
                scale: scale,
                descriptor: descriptor,
                index: index,
                total: widget.descriptors.length,
                shouldTakeFocus: key == widget.focusedSourceKey,
                idleColor: mono.text.withValues(alpha: TvSourcePickerLayout.idleRowFill),
                onSelect: descriptor.isUsable ? () => widget.onSelectSource(key) : null,
                onFocused: () => widget.onFocusSource(key),
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
class TvSourceRow extends StatefulWidget {
  const TvSourceRow({
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
  State<TvSourceRow> createState() => TvSourceRowState();
}

class TvSourceRowState extends State<TvSourceRow> {
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
  void didUpdateWidget(TvSourceRow oldWidget) {
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
                  _TvStatusLabel(scale: scale, descriptor: descriptor),
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
              _TvProgressBar(scale: scale, fraction: descriptor.progressFraction!, enabled: enabled),
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
class _TvStatusLabel extends StatelessWidget {
  const _TvStatusLabel({required this.scale, required this.descriptor});

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
class _TvProgressBar extends StatelessWidget {
  const _TvProgressBar({required this.scale, required this.fraction, required this.enabled});

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
