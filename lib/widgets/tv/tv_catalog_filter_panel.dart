/// The filter panel of hoofdstuk 10.6: Status, Genre, Year, Servers and
/// Libraries, with a sticky footer that clears or applies.
///
/// ## Nothing is applied until Apply
///
/// Hoofdstuk 10.6 says why, and it is a remote-control reason rather than a
/// taste one: "Wijzigingen worden pas toegepast bij Toepassen, zodat de grid
/// niet na elke remote-klik herlaadt en focus steelt." Every tick here mutates
/// a draft; the grid behind the panel does not move until the user is done.
/// Menu closes without applying, which is why the draft is discarded on close
/// rather than written back.
///
/// ## Two header actions, one panel
///
/// `movies-reference.png` is binding on three header actions — Alle bronnen,
/// Filters, sort — while 10.6 is equally clear that Servers and Libraries are
/// *sections of the Filters panel*. Both hold: this is one panel with all five
/// sections, and "Alle bronnen" opens it with focus already on Servers. One
/// piece of state, one place to change it, two ways in.
///
/// ## A section can be unavailable
///
/// Genre, Year and Status are only offered when every participating backend
/// executes them (see `unifiedFilterCapabilitiesFor`). An unavailable section
/// is still drawn, greyed, with the reason under it — hiding it would leave a
/// user who filtered by genre yesterday with no explanation for where it went,
/// and no hint that excluding a server brings it back.
library;

import 'dart:async';

import 'package:flutter/material.dart';

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

/// Which section the panel opens on.
enum TvCatalogFilterSection { status, genre, year, servers, libraries }

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

  /// Null in tests that only exercise the source sections, which need no
  /// network call at all.
  final MediaServerClient? Function(String serverId)? clientFor;

  @override
  State<TvCatalogFilterPanel> createState() => _TvCatalogFilterPanelState();
}

class _TvCatalogFilterPanelState extends State<TvCatalogFilterPanel> {
  late UnifiedCatalogFilterSelection _draft = widget.selection;
  UnifiedFilterOptions _options = UnifiedFilterOptions.empty;
  bool _isLoadingOptions = false;

  @override
  void initState() {
    super.initState();
    if (widget.capabilities.supportsMetadataFilters) unawaited(_loadOptions());
  }

  @override
  void dispose() {
    widget.initialFocusNode?.dispose();
    super.dispose();
  }

  /// Genre and year values, fetched behind an already-open panel.
  ///
  /// The panel does not wait for them: Status, Servers and Libraries need
  /// nothing from a server, and blocking the whole modal on a fan-out would put
  /// a spinner in front of three sections that were ready immediately.
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

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final radius = tvPanelBorderRadius(MediaQuery.sizeOf(context));

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
            Flexible(child: SingleChildScrollView(child: _buildSections(scale))),
            SizedBox(height: TvSourcePickerLayout.footerGap * scale),
            _buildFooter(scale),
          ],
        ),
      ),
    );
  }

  Widget _buildSections(double scale) {
    final sections = <Widget>[
      _section(
        scale: scale,
        section: TvCatalogFilterSection.status,
        title: t.unifiedCatalog.filters.status,
        enabled: widget.capabilities.supportsWatchFilter,
        rows: [
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
      ),
      _section(
        scale: scale,
        section: TvCatalogFilterSection.genre,
        title: t.unifiedCatalog.filters.genre,
        enabled: widget.capabilities.supportsMetadataFilters,
        isLoading: _isLoadingOptions,
        rows: [
          for (final genre in _options.genres)
            _RowSpec(label: genre, isSelected: _draft.genres.contains(genre), onPressed: () => _toggleGenre(genre)),
        ],
      ),
      _section(
        scale: scale,
        section: TvCatalogFilterSection.year,
        title: t.unifiedCatalog.filters.year,
        enabled: widget.capabilities.supportsMetadataFilters,
        isLoading: _isLoadingOptions,
        rows: [
          for (final year in _options.years)
            _RowSpec(label: '$year', isSelected: _draft.years.contains(year), onPressed: () => _toggleYear(year)),
        ],
      ),
      _section(
        scale: scale,
        section: TvCatalogFilterSection.servers,
        title: t.unifiedCatalog.filters.servers,
        enabled: true,
        rows: [
          for (final server in _servers)
            _RowSpec(
              label: server.name,
              isSelected: _draft.serverIds.contains(server.id),
              onPressed: () => _toggleServer(server.id),
            ),
        ],
      ),
      _section(
        scale: scale,
        section: TvCatalogFilterSection.libraries,
        title: t.unifiedCatalog.filters.libraries,
        enabled: true,
        rows: [
          for (final library in widget.libraries)
            _RowSpec(
              label: library.libraryTitle,
              // The server, because two libraries called "Movies" on two
              // servers are otherwise the same row twice.
              secondary: library.serverName,
              isSelected: _draft.libraryKeys.contains(buildGlobalKey(library.serverId, library.libraryId)),
              onPressed: () => _toggleLibrary(buildGlobalKey(library.serverId, library.libraryId)),
            ),
        ],
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) SizedBox(height: TvSourcePickerLayout.sectionGap * scale),
          sections[i],
        ],
      ],
    );
  }

  Widget _section({
    required double scale,
    required TvCatalogFilterSection section,
    required String title,
    required bool enabled,
    required List<_RowSpec> rows,
    bool isLoading = false,
  }) {
    final mono = tokens(context);
    // The section the panel was opened on carries the host's initial focus, so
    // "Alle bronnen" lands on Servers and "Filters" lands on Status. Only the
    // first focusable row of that section takes it — a node handed to two
    // widgets focuses whichever built last.
    final wantsInitialFocus = section == widget.initialSection && enabled && rows.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: TvSourcePickerLayout.rowGap * scale),
          child: Text(
            title,
            style: TextStyle(
              fontSize: TvSourcePickerLayout.subtitleFontSize * scale,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: mono.text.withValues(
                alpha: enabled ? TvSourcePickerLayout.inkSecondary : TvSourcePickerLayout.inkDisabledSecondary,
              ),
            ),
          ),
        ),
        if (!enabled)
          _SectionNote(text: t.unifiedCatalog.filters.unsupported, scale: scale)
        else if (isLoading && rows.isEmpty)
          _SectionNote(text: t.common.loading, scale: scale)
        else if (rows.isEmpty)
          _SectionNote(text: t.unifiedCatalog.filters.noValues, scale: scale)
        else
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) SizedBox(height: TvCatalogLayout.optionRowGap * scale),
            TvCatalogOptionRow(
              label: rows[i].label,
              secondary: rows[i].secondary,
              isSelected: rows[i].isSelected,
              scale: scale,
              focusNode: wantsInitialFocus && i == 0 ? widget.initialFocusNode : null,
              onPressed: rows[i].onPressed,
            ),
          ],
      ],
    );
  }

  /// Hoofdstuk 10.6's sticky footer: Wissen and Toepassen, plus Close.
  ///
  /// A [Wrap] rather than a [Row]. Three capsules fit comfortably on the
  /// canonical canvas, and on a 720p output or a simulator window they do not —
  /// a Row simply overflows there, which is a striped banner across the one
  /// control that applies the user's work. Wrapping onto a second line is the
  /// only degradation that keeps every button reachable.
  Widget _buildFooter(double scale) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 12 * scale,
      runSpacing: 8 * scale,
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
        TvPanelButton(scale: scale, label: t.common.close, onPressed: widget.onClose, primary: false),
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

/// One row's data, so a section's rows are described once and rendered once.
class _RowSpec {
  const _RowSpec({required this.label, required this.isSelected, required this.onPressed, this.secondary});

  final String label;
  final String? secondary;
  final bool isSelected;
  final VoidCallback onPressed;
}

/// The line that stands in for a section's rows: unavailable, loading, or
/// nothing to choose from.
///
/// Not focusable, on purpose. Hoofdstuk 10.6 wants active choices focusable;
/// an explanation is not a choice, and a focus stop that cannot be pressed is
/// how a remote-driven panel starts feeling broken.
class _SectionNote extends StatelessWidget {
  const _SectionNote({required this.text, required this.scale});

  final String text;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    return Padding(
      padding: EdgeInsets.only(bottom: TvSourcePickerLayout.rowLineGap * scale),
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
