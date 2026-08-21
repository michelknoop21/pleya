import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../utils/layout_constants.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/bottom_sheet_header.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/focusable_tab_chip.dart';
import '../../widgets/overlay_sheet.dart';
import '../../widgets/overlay_sheet_geometry.dart';
import '../libraries/library_header.dart';

/// Discover/search type filter. `all` shows the mixed shelves; `movies` / `tv`
/// narrow the shelves (and enable the genre picker in discover, client-side type
/// filtering in search).
enum SeerrDiscoverType { all, movies, tv }

/// One genre entry. Structurally the same record as the client's `SeerrGenre`,
/// spelled out here so the bar carries no dependency on the seerr service layer
/// and can be built in a test from a literal.
typedef SeerrDiscoverGenre = ({int id, String name});

/// The control line above the discover shelves: type tabs on the left, the genre
/// picker on the right.
///
/// This is a [LibraryHeaderBar], not something that resembles one. A library page
/// puts Aanbevolen/Bladeren/Collecties on that line and hangs Groepering, Filters
/// and Sorteren off the right end, and Aanvragen now reads the same way: the same
/// 42px line, the same underline tabs, the same hairline, and a genre action that
/// opens the same centred panel Filters opens. What used to be here was a Wrap of
/// outlined pills over a 52px strip of more outlined pills — over a hundred pixels
/// and a border per option, which put more weight on the filter than on the
/// content it filters.
///
/// Knows nothing about the seerr client: the screen owns the state and hands down
/// the current selection plus two callbacks.
class SeerrDiscoverFilterBar extends StatefulWidget {
  const SeerrDiscoverFilterBar({
    super.key,
    required this.type,
    required this.genres,
    required this.genreId,
    required this.onTypeSelected,
    required this.onGenreSelected,
    this.firstTabFocusNode,
    this.onExitLeft,
    this.onExitUp,
    this.onExitDown,
  });

  /// The active type tab.
  final SeerrDiscoverType type;

  /// Genres for the active type. Empty hides the genre action entirely.
  final List<SeerrDiscoverGenre> genres;

  /// The active genre, or null when none is picked.
  final int? genreId;

  /// Fires with the tapped tab. A tab row reports what was chosen; whether that
  /// differs from the current value is the screen's business.
  final ValueChanged<SeerrDiscoverType> onTypeSelected;

  /// Fires with the picked genre, or null for "all genres".
  final ValueChanged<int?> onGenreSelected;

  /// The screen's handle on the first tab, so it can aim DOWN from the search
  /// field at this bar. Same split the grid slivers already use: the screen owns
  /// the node it needs to reach, the bar owns the rest of the row.
  final FocusNode? firstTabFocusNode;

  /// LEFT from the first tab. The sidebar, on TV.
  final VoidCallback? onExitLeft;

  /// UP from anywhere on the line. The search field above it.
  final VoidCallback? onExitUp;

  /// DOWN from anywhere on the line. The first item of the content below.
  final VoidCallback? onExitDown;

  @override
  State<SeerrDiscoverFilterBar> createState() => _SeerrDiscoverFilterBarState();
}

class _SeerrDiscoverFilterBarState extends State<SeerrDiscoverFilterBar> {
  /// [LibraryHeaderAction] owns no focus node of its own: whoever draws the
  /// header keeps them, so remote navigation can aim at a specific action.
  final _genreActionFocusNode = FocusNode(debugLabel: 'SeerrGenreAction');

  /// Every tab needs a node for the same reason. Without one a chip is still
  /// focusable, but nothing can *send* focus to it, and the remote is left to
  /// Flutter's default directional traversal through a horizontally scrolling
  /// row inside a sliver. That is what made this line so hard to work with.
  final _ownedFirstTabFocusNode = FocusNode(debugLabel: 'SeerrTypeTab0');
  final _laterTabFocusNodes = [FocusNode(debugLabel: 'SeerrTypeTab1'), FocusNode(debugLabel: 'SeerrTypeTab2')];

  FocusNode _tabFocusNode(int index) =>
      index == 0 ? (widget.firstTabFocusNode ?? _ownedFirstTabFocusNode) : _laterTabFocusNodes[index - 1];

  @override
  void didUpdateWidget(covariant SeerrDiscoverFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The genre action comes and goes with the type and with an active search.
    // Letting it disappear from under the focus leaves the whole screen with
    // nothing focused, which on a remote reads as the app having died.
    if (!_showGenreAction && _genreActionFocusNode.hasFocus) {
      _tabFocusNode(_lastTabIndex).requestFocus();
    }
  }

  @override
  void dispose() {
    _genreActionFocusNode.dispose();
    _ownedFirstTabFocusNode.dispose();
    for (final node in _laterTabFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  double get _inset => PlatformDetector.isTV() ? TvLayoutConstants.horizontalInset : 12.0;

  /// Genres belong to a narrowed view: with "All" selected there is no single
  /// genre list to show, and seerr's own discover behaves the same way.
  bool get _showGenreAction => widget.type != SeerrDiscoverType.all && widget.genres.isNotEmpty;

  String? get _selectedGenreName {
    final id = widget.genreId;
    if (id == null) return null;
    for (final genre in widget.genres) {
      if (genre.id == id) return genre.name;
    }
    return null;
  }

  static const _segmentTypes = [SeerrDiscoverType.all, SeerrDiscoverType.movies, SeerrDiscoverType.tv];

  int get _lastTabIndex => _segmentTypes.length - 1;

  @override
  Widget build(BuildContext context) {
    // "All" is a tab of its own now. It always was a state; you just had to find
    // it by tapping the active pill a second time.
    final labels = [t.seerr.filterAll, t.seerr.filterMovies, t.seerr.filterShows];
    final showGenre = _showGenreAction;

    return LibraryHeaderBar(
      padding: EdgeInsets.only(left: _inset, right: _inset),
      tabs: [
        for (var i = 0; i < _segmentTypes.length; i++)
          FocusableTabChip(
            key: ValueKey(_segmentTypes[i]),
            label: labels[i],
            isSelected: widget.type == _segmentTypes[i],
            focusNode: _tabFocusNode(i),
            onSelect: () => widget.onTypeSelected(_segmentTypes[i]),
            onNavigateLeft: i > 0 ? () => _tabFocusNode(i - 1).requestFocus() : widget.onExitLeft,
            onNavigateRight: i < _lastTabIndex
                ? () => _tabFocusNode(i + 1).requestFocus()
                : (showGenre ? _genreActionFocusNode.requestFocus : null),
            onNavigateUp: widget.onExitUp,
            onNavigateDown: widget.onExitDown,
          ),
      ],
      actions: [
        if (showGenre)
          LibraryHeaderAction(
            label: t.libraries.filterCategories.genre,
            value: _selectedGenreName,
            isActive: widget.genreId != null,
            focusNode: _genreActionFocusNode,
            onPressed: _openGenrePicker,
            onNavigateLeft: () => _tabFocusNode(_lastTabIndex).requestFocus(),
            onNavigateUp: widget.onExitUp,
            onNavigateDown: widget.onExitDown,
          ),
      ],
    );
  }

  void _openGenrePicker() {
    final controller = OverlaySheetController.maybeOf(context);
    if (controller == null) return;
    controller.show<Object?>(
      presentation: OverlaySheetPresentation.panel,
      builder: (sheetContext) => _GenrePicker(
        genres: widget.genres,
        selectedId: widget.genreId,
        onPicked: (id) {
          controller.close();
          widget.onGenreSelected(id);
        },
      ),
    );
  }
}

/// The genre list behind the header action. Same shape as the sort and grouping
/// panels: header with a close button, then a radio list that scrolls inside the
/// panel.
class _GenrePicker extends StatelessWidget {
  const _GenrePicker({required this.genres, required this.selectedId, required this.onPicked});

  final List<SeerrDiscoverGenre> genres;
  final int? selectedId;
  final ValueChanged<int?> onPicked;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BottomSheetHeader(title: t.libraries.filterCategories.genre),
        Flexible(
          child: ListView.builder(
            primary: false,
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: genres.length + 1,
            itemBuilder: (context, index) {
              // Index 0 is the way back to an unfiltered view. A picker needs a
              // visible "no genre" row: re-tapping the active one to clear it was
              // exactly the hidden affordance this bar is losing.
              final id = index == 0 ? null : genres[index - 1].id;
              final label = index == 0 ? t.libraries.all : genres[index - 1].name;
              final isSelected = selectedId == id;
              return FocusableListTile(
                key: ValueKey(id),
                dense: true,
                leading: AppIcon(
                  isSelected ? Symbols.radio_button_checked_rounded : Symbols.radio_button_unchecked_rounded,
                  fill: 1,
                ),
                title: Text(label),
                onTap: () => onPicked(id),
              );
            },
          ),
        ),
      ],
    );
  }
}
