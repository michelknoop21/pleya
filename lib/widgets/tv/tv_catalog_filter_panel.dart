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

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_server_client.dart';
import '../../services/unified_catalog/source_cursor.dart';
import '../../services/unified_catalog/unified_catalog_filters.dart';
import '../../services/unified_catalog/unified_filter_options.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/global_key_utils.dart';
import '../../utils/layout_constants.dart';
import '../overlay_sheet.dart';
import '../overlay_sheet_geometry.dart';
import 'tv_catalog_sort_panel.dart';
import 'tv_panel_primitives.dart';
import 'tv_unified_layout.dart';

/// Which category the panel opens on, and — since every category is one of
/// these — what the rail is a list of.
enum TvCatalogFilterSection { status, genre, year, servers, libraries }

/// Rail order (hoofdstuk 10.6's own listing): the two source categories first,
/// because they are the only ones no backend can take away, then the metadata
/// refinements, then watch status. Anything that can be omitted is therefore
/// omitted from the bottom, and the top of the rail never moves.
const List<TvCatalogFilterSection> _railOrder = [
  TvCatalogFilterSection.servers,
  TvCatalogFilterSection.libraries,
  TvCatalogFilterSection.genre,
  TvCatalogFilterSection.year,
  TvCatalogFilterSection.status,
];

/// Opens the panel and returns the new selection, or null when the user backed
/// out without applying.
Future<UnifiedCatalogFilterSelection?> showTvCatalogFilterPanel(
  BuildContext context, {
  required UnifiedCatalogFilterSelection selection,
  required UnifiedFilterCapabilities capabilities,
  required List<CatalogLibrary> libraries,
  required TvCatalogFilterSection initialSection,
  required MediaServerClient? Function(String serverId) clientFor,
}) {
  final initialFocusNode = FocusNode(debugLabel: 'TvCatalogFilterInitialFocus');
  return OverlaySheetController.showAdaptive<UnifiedCatalogFilterSelection>(
    context,
    presentation: OverlaySheetPresentation.panel,
    initialFocusNode: initialFocusNode,
    restoreLauncherFocus: true,
    builder: (sheetContext) => TvCatalogFilterPanel(
      selection: selection,
      capabilities: capabilities,
      libraries: libraries,
      initialSection: initialSection,
      initialFocusNode: initialFocusNode,
      clientFor: clientFor,
      onApply: (next) => OverlaySheetController.closeAdaptive(sheetContext, next),
      onClose: () => OverlaySheetController.closeAdaptive(sheetContext, null),
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
  late UnifiedCatalogFilterSelection _draft = widget.selection;
  late TvCatalogFilterSection _active = _resolveInitialSection();
  UnifiedFilterOptions _options = UnifiedFilterOptions.empty;
  bool _isLoadingOptions = false;

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
    if (widget.capabilities.supportsMetadataFilters) unawaited(_loadOptions());
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
    super.dispose();
  }

  /// The category the panel opens on, or the first available one when the
  /// caller asked for a category this source set cannot execute.
  ///
  /// Falling back rather than honouring the request is the whole point of
  /// omitting unavailable categories: opening on a category that is not in the
  /// rail would put the initial focus on nothing.
  TvCatalogFilterSection _resolveInitialSection() {
    final available = _availableSections;
    return available.contains(widget.initialSection) ? widget.initialSection : available.first;
  }

  /// Which categories this source set can actually execute.
  ///
  /// Servers and Libraries are unconditional — they are executed by leaving a
  /// cursor out of the merge, not by asking a backend to filter — so the rail
  /// is never empty and [_resolveInitialSection] always has something to fall
  /// back to.
  List<TvCatalogFilterSection> get _availableSections => [
    for (final section in _railOrder)
      if (_supports(section)) section,
  ];

  bool _supports(TvCatalogFilterSection section) => switch (section) {
    TvCatalogFilterSection.status => widget.capabilities.supportsWatchFilter,
    TvCatalogFilterSection.genre || TvCatalogFilterSection.year => widget.capabilities.supportsMetadataFilters,
    TvCatalogFilterSection.servers || TvCatalogFilterSection.libraries => true,
  };

  /// Genre and year values, fetched behind an already-open panel.
  ///
  /// The panel does not wait for them: Status, Servers and Libraries need
  /// nothing from a server, and blocking the whole modal on a fan-out would put
  /// a spinner in front of three categories that were ready immediately.
  Future<void> _loadOptions() async {
    final clientFor = widget.clientFor;
    if (clientFor == null) return;
    setState(() => _isLoadingOptions = true);
    final options = await loadUnifiedFilterOptions(
      libraries: widget.libraries,
      clientFor: (serverId) => clientFor(serverId.value),
    );
    if (!mounted) return;
    setState(() {
      _options = options;
      _isLoadingOptions = false;
    });
  }

  void _toggleGenre(String genre) => setState(() => _draft = _draft.copyWith(genres: _toggled(_draft.genres, genre)));

  void _toggleYear(int year) => setState(() => _draft = _draft.copyWith(years: _toggled(_draft.years, year)));

  void _toggleServer(String serverId) =>
      setState(() => _draft = _draft.copyWith(serverIds: _toggled(_draft.serverIds, serverId)));

  void _toggleLibrary(String key) =>
      setState(() => _draft = _draft.copyWith(libraryKeys: _toggled(_draft.libraryKeys, key)));

  void _setWatchState(UnifiedWatchFilter value) => setState(() => _draft = _draft.copyWith(watchState: value));

  static Set<T> _toggled<T>(Set<T> current, T value) =>
      current.contains(value) ? ({...current}..remove(value)) : {...current, value};

  /// Distinct servers behind the eligible libraries, in a stable order.
  ///
  /// Ordered by name, then by id: server names are user-editable and can
  /// collide (edge case A7), so a name-only sort would let two servers swap
  /// rows between openings.
  List<({String id, String name})> get _servers {
    final byId = <String, String>{};
    for (final library in widget.libraries) {
      byId.putIfAbsent(library.serverId.value, () => library.serverName);
    }
    final servers = [for (final entry in byId.entries) (id: entry.key, name: entry.value)];
    servers.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
    return servers;
  }

  /// The rows of one category, as data.
  List<_RowSpec> _rowsFor(TvCatalogFilterSection section) => switch (section) {
    TvCatalogFilterSection.status => [
      _RowSpec(
        label: t.unifiedCatalog.filters.all,
        isSelected: _draft.watchState == UnifiedWatchFilter.all,
        onPressed: () => _setWatchState(UnifiedWatchFilter.all),
      ),
      _RowSpec(
        label: t.unifiedCatalog.filters.unwatched,
        isSelected: _draft.watchState == UnifiedWatchFilter.unwatched,
        onPressed: () => _setWatchState(UnifiedWatchFilter.unwatched),
      ),
    ],
    TvCatalogFilterSection.genre => [
      for (final genre in _options.genres)
        _RowSpec(label: genre, isSelected: _draft.genres.contains(genre), onPressed: () => _toggleGenre(genre)),
    ],
    TvCatalogFilterSection.year => [
      for (final year in _options.years)
        _RowSpec(label: '$year', isSelected: _draft.years.contains(year), onPressed: () => _toggleYear(year)),
    ],
    TvCatalogFilterSection.servers => [
      for (final server in _servers)
        _RowSpec(
          label: server.name,
          isSelected: _draft.serverIds.contains(server.id),
          onPressed: () => _toggleServer(server.id),
        ),
    ],
    TvCatalogFilterSection.libraries => [
      for (final library in widget.libraries)
        _RowSpec(
          label: library.libraryTitle,
          // The server, because two libraries called "Movies" on two servers
          // are otherwise the same row twice.
          secondary: library.serverName,
          isSelected: _draft.libraryKeys.contains(buildGlobalKey(library.serverId, library.libraryId)),
          onPressed: () => _toggleLibrary(buildGlobalKey(library.serverId, library.libraryId)),
        ),
    ],
  };

  /// How many choices a category currently carries, for its count chip.
  ///
  /// Status counts as one when it is narrowing and zero when it is not — "All"
  /// is the absence of a filter, and a chip reading 1 on an unfiltered category
  /// is the kind of detail that makes a panel feel like a form.
  int _activeCountFor(TvCatalogFilterSection section) => switch (section) {
    TvCatalogFilterSection.status => _draft.watchState == UnifiedWatchFilter.all ? 0 : 1,
    TvCatalogFilterSection.genre => _draft.genres.length,
    TvCatalogFilterSection.year => _draft.years.length,
    TvCatalogFilterSection.servers => _draft.serverIds.length,
    TvCatalogFilterSection.libraries => _draft.libraryKeys.length,
  };

  String _labelFor(TvCatalogFilterSection section) => switch (section) {
    TvCatalogFilterSection.status => t.unifiedCatalog.filters.status,
    TvCatalogFilterSection.genre => t.unifiedCatalog.filters.genre,
    TvCatalogFilterSection.year => t.unifiedCatalog.filters.year,
    TvCatalogFilterSection.servers => t.unifiedCatalog.filters.servers,
    TvCatalogFilterSection.libraries => t.unifiedCatalog.filters.libraries,
  };

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
  /// five-item rail with a Select on every stop to see what is in it is four
  /// presses more than walking it. Select and RIGHT then both mean the same
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
    final sections = _availableSections;
    final rows = _rowsFor(_active);
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
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: railWidth, child: _buildRail(sections, scale)),
                            SizedBox(width: TvCatalogLayout.filterZoneGap * scale),
                            Expanded(child: _buildOptions(rows, scale)),
                          ],
                        ),
                      ),
                      // Indented to the options column rather than to the panel
                      // edge. Flush left it starts under the rail and reads as
                      // a caption *of the rail*, which is the one thing it is
                      // not about — the categories it explains are the ones not
                      // in the rail.
                      if (sections.length != _railOrder.length)
                        Padding(
                          padding: EdgeInsets.only(
                            left: railWidth + TvCatalogLayout.filterZoneGap * scale,
                            top: TvSourcePickerLayout.rowGap * scale,
                          ),
                          child: _PanelNote(text: t.unifiedCatalog.filters.someUnavailable, scale: scale),
                        ),
                    ],
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

  /// The left zone: one row per available category.
  Widget _buildRail(List<TvCatalogFilterSection> sections, double scale) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) SizedBox(height: TvCatalogLayout.optionRowGap * scale),
            _CategoryRow(
              label: _labelFor(sections[i]),
              count: _activeCountFor(sections[i]),
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
    );
  }

  /// The right zone: the active category's choices, or one quiet line saying
  /// why there are none.
  Widget _buildOptions(List<_RowSpec> rows, double scale) {
    if (rows.isEmpty) {
      return _PanelNote(text: _isLoadingOptions ? t.common.loading : t.unifiedCatalog.filters.noValues, scale: scale);
    }
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
        if (!_draft.isEmpty)
          TvPanelButton(
            scale: scale,
            label: t.unifiedCatalog.filters.clearAll,
            onPressed: () => setState(() => _draft = UnifiedCatalogFilterSelection.empty),
            primary: false,
          ),
        const Spacer(),
        TvPanelButton(
          scale: scale,
          label: t.unifiedCatalog.filters.apply,
          onPressed: () => widget.onApply(_draft),
          primary: true,
        ),
      ],
    );
  }
}

/// One row's data, so a category's rows are described once and rendered once.
class _RowSpec {
  const _RowSpec({required this.label, required this.isSelected, required this.onPressed, this.secondary});

  final String label;
  final String? secondary;
  final bool isSelected;
  final VoidCallback onPressed;
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
