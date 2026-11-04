/// The filter panel of hoofdstuk 10.6, as two zones: a rail of refinement
/// categories on the left, and the options of whichever one is active on the
/// right.
///
/// ## Why two zones rather than one stacked column
///
/// The first build stacked Status, Genre, Year, Servers and Libraries as five
/// headed sections in one scroller. It was functionally right and visually
/// wrong: a remote-driven modal that you scroll past four headings to reach the
/// fifth reads as a settings window, and on a 584-logical-high canvas the fifth
/// section was always below the fold. A rail costs one focus move and puts
/// every category one press away, with the options always at the top of their
/// own column. It is also what lets an unavailable category simply not be in
/// the list, instead of being a greyed heading with an apology under it.
///
/// ## Nothing is applied until Apply
///
/// Hoofdstuk 10.6 says why, and it is a remote-control reason rather than a
/// taste one: "Wijzigingen worden pas toegepast bij Toepassen, zodat de grid
/// niet na elke remote-klik herlaadt en focus steelt." Every tick here mutates
/// a draft; the grid behind the panel does not move until the user is done.
/// Menu, Back and Escape close without applying, which is why the draft is
/// discarded on close rather than written back.
///
/// ## Two header actions, one panel
///
/// `movies-reference.png` is binding on three header actions — Alle bronnen,
/// Filters, sort — while 10.6 is equally clear that Servers and Libraries are
/// *categories of the Filters panel*. Both hold: this is one panel, and "Alle
/// bronnen" opens it with the rail already on Servers. One piece of state, one
/// place to change it, two ways in.
///
/// ## An unavailable category is absent, not greyed
///
/// Genre, Year and Status are only offered when every participating backend
/// executes them (see `unifiedFilterCapabilitiesFor`). Such a category is left
/// out of the rail entirely and one quiet line under the zones says that
/// something was left out — the explanation the greyed version existed to give,
/// at a twentieth of the visual weight. The *stored* selection is never
/// discarded: it stays in the draft and in the saved preference, so excluding
/// the server that suppressed it brings both the category and the user's old
/// choice back.
library;

export 'tv_catalog_filter_model.dart' show TvCatalogFilterSection;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_server_client.dart';
import '../../services/unified_catalog/source_cursor.dart';
import '../../services/unified_catalog/unified_catalog_filters.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/focus_utils.dart';
import '../../utils/layout_constants.dart';
import '../overlay_sheet.dart';
import '../overlay_sheet_geometry.dart';
import 'tv_catalog_filter_model.dart';
import 'tv_catalog_sort_panel.dart';
import 'tv_panel_primitives.dart';
import 'tv_unified_layout.dart';

/// Opens the panel and returns the new selection, or null when the user backed
/// out without applying.
Future<UnifiedCatalogFilterSelection?> showTvCatalogFilterPanel(
  BuildContext context, {
  required UnifiedCatalogFilterSelection selection,
  required UnifiedFilterCapabilities capabilities,
  required List<CatalogLibrary> libraries,
  required TvCatalogFilterSection initialSection,
  required MediaServerClient? Function(String serverId) clientFor,
  bool asSubpage = false,
}) {
  final initialFocusNode = FocusNode(debugLabel: 'TvCatalogFilterInitialFocus');
  return OverlaySheetController.showAdaptive<UnifiedCatalogFilterSelection>(
    context,
    presentation: OverlaySheetPresentation.panel,
    initialFocusNode: initialFocusNode,
    restoreLauncherFocus: true,
    asSubpage: asSubpage,
    builder: (sheetContext) => TvCatalogFilterPanel(
      selection: selection,
      capabilities: capabilities,
      libraries: libraries,
      initialSection: initialSection,
      initialFocusNode: initialFocusNode,
      clientFor: clientFor,
      onApply: (next) => asSubpage
          ? OverlaySheetController.popAdaptive(sheetContext, next)
          : OverlaySheetController.closeAdaptive(sheetContext, next),
      onClose: () => asSubpage
          ? OverlaySheetController.popAdaptive(sheetContext, null)
          : OverlaySheetController.closeAdaptive(sheetContext, null),
    ),
  );
}

class TvCatalogFilterPanel extends StatefulWidget {
  const TvCatalogFilterPanel({
    super.key,
    required this.selection,
    required this.capabilities,
    required this.libraries,
    required this.initialSection,
    required this.onApply,
    required this.onClose,
    this.initialFocusNode,
    this.clientFor,
  });

  final UnifiedCatalogFilterSelection selection;
  final UnifiedFilterCapabilities capabilities;

  /// Every eligible library, restricted or not — a server the user has excluded
  /// still needs a row, or there is no way back to it.
  final List<CatalogLibrary> libraries;

  final TvCatalogFilterSection initialSection;
  final ValueChanged<UnifiedCatalogFilterSelection> onApply;
  final VoidCallback onClose;
  final FocusNode? initialFocusNode;

  /// Null in tests that only exercise the source categories, which need no
  /// network call at all.
  final MediaServerClient? Function(String serverId)? clientFor;

  @override
  State<TvCatalogFilterPanel> createState() => _TvCatalogFilterPanelState();
}

class _TvCatalogFilterPanelState extends State<TvCatalogFilterPanel> {
  late final TvCatalogFilterModel _model = TvCatalogFilterModel(
    selection: widget.selection,
    capabilities: widget.capabilities,
    libraries: widget.libraries,
    clientFor: widget.clientFor,
  );
  late TvCatalogFilterSection _active = _model.resolveInitialSection(widget.initialSection);

  /// One node per category, kept for the panel's lifetime: the rail's length
  /// only changes when capabilities do, and stable nodes are what let LEFT out
  /// of the options column land back on the category the user came from.
  final Map<TvCatalogFilterSection, FocusNode> _railNodes = {};

  /// Nodes for the options currently on the right. Rebuilt when the active
  /// category changes, because the list they address does.
  List<FocusNode> _optionNodes = const [];

  @override
  void initState() {
    super.initState();
    // The host's initial-focus node *is* the opening category's rail node,
    // rather than a node handed to whichever row happens to be active.
    //
    // That was the first build, and it was wrong twice over: the node migrated
    // from row to row as the active category followed the focus, and the rail
    // node the active row was no longer using had no context — so LEFT out of
    // the options column requested focus on a detached node and did nothing at
    // all. One node per category, owned for the panel's life, and the host
    // simply borrows one of them.
    final initial = widget.initialFocusNode;
    if (initial != null) _railNodes[_active] = initial;
    _model.addListener(_onModelChanged);
    if (widget.capabilities.supportsMetadataFilters) unawaited(_loadOptions());
  }

  void _onModelChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(TvCatalogFilterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _model
      ..capabilities = widget.capabilities
      ..libraries = widget.libraries;
  }

  @override
  void dispose() {
    // Includes the host's initial-focus node, which this panel owns: it is
    // created by `showTvCatalogFilterPanel` for exactly one panel.
    for (final node in _railNodes.values) {
      node.dispose();
    }
    for (final node in _optionNodes) {
      node.dispose();
    }
    _model.dispose();
    super.dispose();
  }

  /// Genre and year values, fetched behind an already-open panel. See
  /// [TvCatalogFilterModel.loadOptions].
  Future<void> _loadOptions() async {
    await _model.loadOptions();
    if (!mounted) return;
    final hadFocus = _railNodes[_active]?.hasFocus ?? false;
    setState(() => _active = _model.survivingSection(_active));
    // The row the focus was on may have gone with its placeholder; hand the
    // focus to the row that took its place instead of letting it die.
    if (hadFocus) FocusUtils.requestFocusAfterBuild(this, _railNodeFor(_active));
  }

  FocusNode _railNodeFor(TvCatalogFilterSection section) =>
      _railNodes.putIfAbsent(section, () => FocusNode(debugLabel: 'TvCatalogFilterRail.${section.name}'));

  /// Grows or shrinks [_optionNodes] to [count].
  ///
  /// Called from `build`, so it must not call `setState` and must not dispose a
  /// node that is still mounted in the tree being rebuilt — the surplus nodes
  /// are unfocused first and disposed after the frame for exactly that reason.
  void _syncOptionNodes(int count) {
    if (_optionNodes.length == count) return;
    final next = <FocusNode>[
      for (var i = 0; i < count; i++)
        i < _optionNodes.length ? _optionNodes[i] : FocusNode(debugLabel: 'TvCatalogFilterOption$i'),
    ];
    final surplus = _optionNodes.skip(count).toList();
    _optionNodes = next;
    if (surplus.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in surplus) {
          node.dispose();
        }
      });
    }
  }

  /// Moving through the rail swaps the options column under the focus.
  ///
  /// Focus-driven rather than press-driven on purpose: on a remote, walking a
  /// rail with a Select on every stop to see what is in it costs a press at
  /// every one of its six stops on top of walking it. Select and RIGHT then both mean the same
  /// thing — go into the list you are already looking at.
  void _showSection(TvCatalogFilterSection section) {
    if (_active == section) return;
    setState(() => _active = section);
  }

  /// RIGHT or Select on a category: hand the focus to the first option.
  ///
  /// Synchronous, and deliberately not deferred to a post-frame callback. The
  /// nodes for the active category are already built and attached by the time
  /// any key reaches the rail — moving *within* the rail and entering the
  /// options are always two separate presses with a frame between them — and
  /// `addPostFrameCallback` does not schedule a frame of its own, so a deferred
  /// request simply never ran when nothing else had dirtied the tree. That is
  /// not a test artefact: on a settled panel a remote's RIGHT is exactly that
  /// "nothing else changed" case, so the deferred version dropped the press on
  /// a real Apple TV too.
  void _enterOptions() {
    if (_optionNodes.isEmpty) return;
    _optionNodes.first.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final radius = tvPanelBorderRadius(MediaQuery.sizeOf(context));
    final sections = _model.availableSections;
    final rows = _model.rowsFor(_active);
    _syncOptionNodes(rows.length);

    return DecoratedBox(
      decoration: tvPanelDecoration(mono, radius),
      child: Padding(
        padding: EdgeInsets.all(TvSourcePickerLayout.panelPadding * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.unifiedCatalog.filters.title,
              style: TextStyle(
                fontSize: TvSourcePickerLayout.titleFontSize * scale,
                fontWeight: FontWeight.w700,
                color: mono.text,
                letterSpacing: -0.3,
              ),
            ),
            SizedBox(height: TvSourcePickerLayout.sectionGap * scale),
            Flexible(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final railWidth = (constraints.maxWidth * TvCatalogLayout.filterRailFraction)
                      .clamp(
                        math.min(TvCatalogLayout.filterRailMinWidth, constraints.maxWidth),
                        TvCatalogLayout.filterRailMaxWidth,
                      )
                      .toDouble();
                  // Only for categories the backends cannot execute. A category
                  // hidden for lack of values is not "unavailable for these
                  // sources", and saying so would send the user looking for a
                  // server to exclude.
                  final noteShown = _model.hasUnsupportedSections;
                  return SizedBox(
                    height: _zoneHeight(scale, constraints.maxHeight),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: railWidth, child: _buildRail(sections, scale)),
                        SizedBox(width: TvCatalogLayout.filterZoneGap * scale),
                        // The note lives *inside* the options column, under the
                        // list rather than under the whole zone. It belongs to
                        // the options either way — the categories it explains
                        // are the ones missing from the rail, so as a caption of
                        // the rail it would be about the wrong half — but with
                        // the zone now a fixed height, a note placed under the
                        // zone floats a hundred pixels below the last option in
                        // any category short enough not to fill it, and reads as
                        // unrelated to anything. Under a loose list it stays
                        // against the row it is talking about.
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Flexible(fit: FlexFit.loose, child: _buildOptions(rows, scale)),
                              if (noteShown)
                                Padding(
                                  padding: EdgeInsets.only(top: TvSourcePickerLayout.rowGap * scale),
                                  child: _PanelNote(text: t.unifiedCatalog.filters.someUnavailable, scale: scale),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: TvSourcePickerLayout.footerGap * scale),
            _buildFooter(scale),
          ],
        ),
      ),
    );
  }

  /// The height of the zone area, which is deliberately *not* the height of
  /// what is in it.
  ///
  /// See [TvCatalogLayout.filterZoneRows]: a panel sized to its active category
  /// jumps every time the focus moves down the rail. This makes the two zones
  /// one stable box, so the rail, the options and the footer all stay where the
  /// user left them and only the contents of the right-hand column change.
  ///
  /// The clamp is what keeps that promise honest on a surface too short to keep
  /// it: below the ideal height the zone takes what there is, and the fade over
  /// the options takes over from there.
  double _zoneHeight(double scale, double available) {
    const rows = TvCatalogLayout.filterZoneRows;
    final ideal = (TvCatalogLayout.optionRowMinHeight * rows + TvCatalogLayout.optionRowGap * (rows - 1)) * scale;
    if (!available.isFinite) return ideal;
    return math.max(0, math.min(ideal, available));
  }

  /// The left zone: one row per available category.
  ///
  /// [TvCatalogLayout.filterZoneRows] is sized so this never scrolls, which is
  /// the arrangement that matters: a hidden category takes its active-count
  /// chip with it, and the chip is the only thing on screen saying that filter
  /// is on. That promise is only as good as the room the panel is given,
  /// though. `_zoneHeight` clamps to what the surface has, so under roughly 555
  /// logical pixels of panel height the rail overflows again, and `setForceTv`
  /// puts the TV catalogue on windows that short. The fade is what covers that
  /// case, for the same reason the options column has one: cut flat, the last
  /// visible category reads as a rendering fault rather than as "there is more
  /// here".
  Widget _buildRail(List<TvCatalogFilterSection> sections, double scale) {
    return _FadingEdges(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < sections.length; i++) ...[
              if (i > 0) SizedBox(height: TvCatalogLayout.filterRailGap * scale),
              _CategoryRow(
                label: tvCatalogFilterSectionLabel(sections[i]),
                count: _model.activeCountFor(sections[i]),
                isActive: sections[i] == _active,
                scale: scale,
                // Stable per category for the panel's life. The opening category's
                // node is the one the host was handed, so "Alle bronnen" lands on
                // Servers and "Filters" on the first available category.
                focusNode: _railNodeFor(sections[i]),
                onFocused: () => _showSection(sections[i]),
                onEnter: _enterOptions,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The right zone: the active category's choices, or one quiet line saying
  /// why there are none.
  Widget _buildOptions(List<TvCatalogFilterRowSpec> rows, double scale) {
    if (rows.isEmpty) {
      return _PanelNote(
        text: _model.isLoadingOptions ? t.common.loading : t.unifiedCatalog.filters.noValues,
        scale: scale,
      );
    }
    // Centred when the list is shorter than the zone. The fixed zone height is
    // what stops the panel resizing as the focus walks the rail, but top-aligned
    // it left a two-option category — Status, which is the one the Filters
    // capsule opens on — as two rows clinging to the ceiling of a box two thirds
    // empty. Centring spends the same space as breathing room instead of as a
    // void.
    return _FadingEdges(
      // A category can hold far more rows than the panel is tall — ten genres
      // against a six-entry rail is the ordinary case, not the extreme one —
      // so the list is cut by the panel's bottom edge. Cut flat, the last
      // visible row is a half-height rectangle that reads as a rendering fault
      // rather than as "there is more below this". The fade is the affordance,
      // and it appears only on an edge that actually has something past it.
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: _zoneHeight(scale, double.infinity)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) SizedBox(height: TvCatalogLayout.optionRowGap * scale),
                TvCatalogOptionRow(
                  label: rows[i].label,
                  secondary: rows[i].secondary,
                  isSelected: rows[i].isSelected,
                  scale: scale,
                  focusNode: _optionNodes[i],
                  // LEFT is the only way out of this column on a remote, and it
                  // goes to the category the list belongs to rather than to
                  // wherever the traversal policy would land.
                  onNavigateLeft: () => _railNodeFor(_active).requestFocus(),
                  onPressed: rows[i].onPressed,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Hoofdstuk 10.6's sticky footer, as two actions rather than three.
  ///
  /// The first build had Wissen, Sluiten and Toepassen as three capsules of
  /// roughly equal weight, which left the one action that commits the user's
  /// work indistinguishable from the one that throws it away. Close is gone:
  /// Menu, Back and Escape already close the panel and are what a remote
  /// reaches for, so the capsule was a focus stop duplicating a gesture. What
  /// is left is a quiet reset on the left and one primary CTA on the right —
  /// far apart, and impossible to confuse.
  Widget _buildFooter(double scale) {
    return Row(
      children: [
        // Only offered when there is something to clear: a permanently present
        // "Clear all" on an untouched panel is a focus stop that does nothing.
        if (!_model.draft.isEmpty)
          TvPanelButton(
            scale: scale,
            label: t.unifiedCatalog.filters.clearAll,
            onPressed: _model.clearAll,
            primary: false,
          ),
        const Spacer(),
        TvPanelButton(
          scale: scale,
          label: t.unifiedCatalog.filters.apply,
          onPressed: () => widget.onApply(_model.draft),
          primary: true,
        ),
      ],
    );
  }
}

/// One category in the left rail.
///
/// Active and focused are two different states, for the same reason [DEC-053]
/// separates selected from focused on an option row: once the user moves RIGHT
/// the white ring is in the options column, and the rail still has to say which
/// list is on screen. Active is a fill; focus is the ring.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.label,
    required this.count,
    required this.isActive,
    required this.scale,
    required this.focusNode,
    required this.onFocused,
    required this.onEnter,
  });

  final String label;
  final int count;
  final bool isActive;
  final double scale;

  /// The panel's stable node for this category — the target LEFT out of the
  /// options column returns to, and, for the opening category, the node the
  /// overlay host focuses on open.
  final FocusNode focusNode;

  final VoidCallback onFocused;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);

    return FocusableWrapper(
      focusNode: focusNode,
      onSelect: onEnter,
      // RIGHT and Select mean the same thing here: the rail is navigation, not
      // a choice, and both gestures are "go into this list".
      onNavigateRight: onEnter,
      onFocusChange: (focused) {
        if (focused) onFocused();
      },
      borderRadius: TvSourcePickerLayout.rowRadius * scale,
      disableScale: true,
      semanticLabel: count > 0 ? '$label ($count)' : label,
      child: AnimatedContainer(
        duration: mono.fast,
        constraints: BoxConstraints(minHeight: TvCatalogLayout.optionRowMinHeight * scale),
        decoration: BoxDecoration(
          color: mono.text.withValues(alpha: isActive ? TvCatalogLayout.filterActiveCategoryFill : 0),
          borderRadius: BorderRadius.circular(TvSourcePickerLayout.rowRadius * scale),
          border: Border.all(
            color: mono.text.withValues(alpha: isActive ? TvCatalogLayout.filterActiveCategoryOutline : 0),
            width: 1,
          ),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: TvCatalogLayout.optionRowPaddingHorizontal * scale,
          vertical: TvCatalogLayout.optionRowPaddingVertical * scale,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: TvSourcePickerLayout.rowPrimaryFontSize * scale,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: mono.text.withValues(
                    alpha: isActive ? TvSourcePickerLayout.inkPrimary : TvCatalogLayout.filterIdleCategoryInk,
                  ),
                ),
              ),
            ),
            if (count > 0) ...[
              SizedBox(width: TvCatalogLayout.optionRowPaddingHorizontal * 0.4 * scale),
              _CountChip(count: count, scale: scale),
            ],
          ],
        ),
      ),
    );
  }
}

/// How many choices a category carries, as a compact chip.
///
/// White-on-translucent rather than brand red: the red badge on the *header's*
/// Filters action says "this page is narrowed", which is a page-level fact
/// worth a colour. Inside the panel every chip would be red at once, which
/// would read as five warnings.
class _CountChip extends StatelessWidget {
  const _CountChip({required this.count, required this.scale});

  final int count;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: mono.text.withValues(alpha: TvCatalogLayout.filterActiveCategoryOutline),
        borderRadius: BorderRadius.circular(TvCatalogLayout.badgeRadius * scale),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: TvCatalogLayout.filterCountPaddingHorizontal * scale,
          vertical: TvCatalogLayout.filterCountPaddingVertical * scale,
        ),
        child: Text(
          '$count',
          style: TextStyle(
            fontSize: TvCatalogLayout.filterCountFontSize * scale,
            fontWeight: FontWeight.w700,
            color: mono.text,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

/// Fades whichever end of a scrollable has content past it.
///
/// Deliberately state-driven rather than a permanent gradient at both ends: a
/// list that fits, or one scrolled to its end, has nothing below it, and fading
/// the last row there would dim a real choice for no reason. The mask is only a
/// hint that the list continues.
///
/// A [ShaderMask] costs a `saveLayer`, which is why this is not something to
/// scatter over a grid. Inside a modal that is already compositing its own
/// shadow, over a list of at most a few dozen rows, it is the cheapest honest
/// way to say "there is more".
class _FadingEdges extends StatefulWidget {
  const _FadingEdges({required this.child});

  final Widget child;

  @override
  State<_FadingEdges> createState() => _FadingEdgesState();
}

class _FadingEdgesState extends State<_FadingEdges> {
  bool _hasAbove = false;
  bool _hasBelow = false;

  /// How much of each end the fade covers, as a fraction of the column's
  /// height. Small: this is an edge treatment, and a fade deep enough to dim a
  /// whole row would be hiding the list rather than hinting at it.
  static const double _extent = 0.08;

  /// Applies [metrics], deferred to the end of the frame.
  ///
  /// Deferred because the notification that matters most arrives *during
  /// layout* — see [build] — and calling `setState` there is illegal. The
  /// post-frame callback is safe here, unlike in a focus handler, precisely
  /// because a frame is already running: it fires at the end of this one, and
  /// the `setState` inside it schedules the next.
  void _update(ScrollMetrics metrics) {
    final above = metrics.extentBefore > 1;
    final below = metrics.extentAfter > 1;
    if (above == _hasAbove && below == _hasBelow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || (above == _hasAbove && below == _hasBelow)) return;
      setState(() {
        _hasAbove = above;
        _hasBelow = below;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // Two listeners, because one of them does not fire on the case this widget
    // exists for. `ScrollNotification` is dispatched when the user scrolls; a
    // list that overflows the moment it is built has never scrolled, and the
    // first version listened only for that and so never faded anything. The
    // metrics of an untouched-but-overflowing list arrive as
    // `ScrollMetricsNotification`, which is not a `ScrollNotification` at all
    // and is dispatched during layout.
    final listener = NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        _update(notification.metrics);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          _update(notification.metrics);
          return false;
        },
        child: widget.child,
      ),
    );

    if (!_hasAbove && !_hasBelow) return listener;

    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          if (_hasAbove) const Color(0x00FFFFFF) else const Color(0xFFFFFFFF),
          const Color(0xFFFFFFFF),
          const Color(0xFFFFFFFF),
          if (_hasBelow) const Color(0x00FFFFFF) else const Color(0xFFFFFFFF),
        ],
        stops: const [0, _extent, 1 - _extent, 1],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: listener,
    );
  }
}

/// A line that explains rather than offers: nothing to choose from, still
/// loading, or something left out of the rail.
///
/// Not focusable, on purpose. Hoofdstuk 10.6 wants active choices focusable; an
/// explanation is not a choice, and a focus stop that cannot be pressed is how
/// a remote-driven panel starts feeling broken.
class _PanelNote extends StatelessWidget {
  const _PanelNote({required this.text, required this.scale});

  final String text;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: TvSourcePickerLayout.rowLineGap * scale),
      child: Text(
        text,
        style: TextStyle(
          fontSize: TvSourcePickerLayout.rowSecondaryFontSize * scale,
          color: mono.text.withValues(alpha: TvSourcePickerLayout.inkTertiary),
        ),
      ),
    );
  }
}
