part of '../media_detail_screen.dart';

/// PB-4/DEC-109: horizontal seizoenchips met één actieve afleveringenrail,
/// replacing what used to be a vertical hub-per-season stack in
/// `TvBrowseRail`. The chips own which season is selected; `_tvDetailHubs`
/// (in `media_detail_screen.dart`) renders only that one season's rail.
///
/// State — `_selectedSeasonIndex`, `_seasonEpisodePager`, `_seasonTabFocusNodes`,
/// `_seasonTabsScrollController` — is the same state the pre-existing mobile
/// season tabs (`_buildSeasonTabsContent`) already own; this only adds a
/// TV-scaled row over the same fields and the same `_fetchSeasonEpisodes`
/// pager, so pagination, loading, retry and prefetch keep working unchanged.
extension _MediaDetailTvSeasonChips on _MediaDetailScreenState {
  bool _tvDetailShowsSeasonChips(MediaItem metadata) =>
      PlatformDetector.isTV() && metadata.isShow && !_showEpisodesDirectly && _seasons.length > 1;

  // DENS1: font and padding in HIG points (times `TvHig.of`), so a chip is
  // about 60 pt tall with Body text, level with the action row above it. On
  // `scaleOf` it was 76 pt around 27 pt text.
  static const double _tvSeasonChipFontSize = TvHig.body;
  static const double _tvSeasonChipPaddingHorizontal = 24;
  static const double _tvSeasonChipPaddingVertical = 6;
  // A pill: larger than half of any chip height this row renders.
  static const double _tvSeasonChipRadius = 40;
  static const double _tvSeasonChipGap = 12;
  static const double _tvSeasonChipHeadingGap = 20;
  static const double _tvSeasonChipTopGap = 20;

  /// De randen die per constructie altijd meetellen, gefocust of niet.
  ///
  /// De chip tekent zelf een `Border.all(width: 1)`, en `FocusableWrapper`
  /// legt er in `FocusIndicatorMode.ring` zonder `focusShapeBorder` een
  /// `FocusTheme.focusDecoration` omheen met `focusBorderWidth`. Allebei zijn
  /// het `BoxDecoration`-borders, en een `Container` legt de dimensies van
  /// zijn border als padding om het kind: transparant of niet, ze kosten
  /// hoogte. Ze schalen niet mee, want geen van beide breedtes doet dat.
  static const double _tvSeasonChipBorderInset = 2 * (1 + FocusTheme.focusBorderWidth);

  /// The chip row's own height, excluding the gap to whatever sits below it.
  /// Measured, not guessed, for the same reason `_unifiedSourceLineHeight`
  /// gives: a guessed line-height multiplier and the real render drift apart,
  /// and this number feeds a height *reservation* that must not undershoot.
  ///
  /// The style comes from `Theme.of(context).textTheme.bodyMedium`, not
  /// `DefaultTextStyle.of(context).style`: `context` here is
  /// `_MediaDetailScreenState`'s own `BuildContext`, which sits *above* the
  /// `Scaffold` this same State's `build` constructs a few calls down. That
  /// `Scaffold` is a descendant of this context, never an ancestor, so
  /// `DefaultTextStyle.of` here resolves Flutter's fallback debug style
  /// (48px monospace, no line-height multiplier) instead of the app's real
  /// themed text style the live chip's `Text` actually renders with several
  /// layers further down, where a `Material` (the same `Scaffold`) is an
  /// ancestor. `Theme.of` does not depend on that ancestry, and returns the
  /// same `bodyMedium` a `Material` descendant's `DefaultTextStyle` is built
  /// from, so a measurement taken from either context agrees.
  double _tvDetailSeasonChipContentHeight(double scale) {
    final style = Theme.of(context).textTheme.bodyMedium ?? DefaultTextStyle.of(context).style;
    final painter = TextPainter(
      text: TextSpan(
        text: 'Mg',
        style: style.copyWith(fontSize: _tvSeasonChipFontSize * TvHig.of(context), fontWeight: FontWeight.w600),
      ),
      textDirection: Directionality.of(context),
    )..layout();
    final textHeight = painter.height;
    painter.dispose();
    return textHeight + (2 * _tvSeasonChipPaddingVertical * TvHig.of(context)) + _tvSeasonChipBorderInset;
  }

  /// VIS2/37 C: the row takes the season rail's own header line, so
  /// "Afleveringen", the chips and the count read as one line. A chip is
  /// taller than that strip, so the row ends where the strip ends minus the
  /// room a focused card grows into; centered on the strip, the selected chip
  /// sat on the first episode's focus ring. This is where the row's top
  /// lands, measured from the rail's top.
  double _tvDetailSeasonChipRowTop(double scale) =>
      TvBrowseRailLayout.railTopPaddingForScale(scale) +
      TvBrowseRailLayout.hubStripHeightForScale(scale) -
      TvBrowseRailLayout.railInteractionExpansionForScale(scale) -
      _tvDetailSeasonChipContentHeight(scale);

  /// What the row needs reserved on top of the rail's own height: how far it
  /// sticks out above the rail, plus the gap 37 C keeps between the action
  /// row and this line. Without that gap the pills touched the action row.
  double _tvDetailSeasonChipOverhang(double scale) =>
      (-_tvDetailSeasonChipRowTop(scale)).clamp(0.0, double.infinity).toDouble() + _tvSeasonChipTopGap * scale;

  /// Switches to [seasonIndex] if it isn't already selected. Identical to
  /// what the mobile season tab's `onSelect`/`onNavigateLeft`/`onNavigateRight`
  /// already do — `_fetchSeasonEpisodes` owns the cache check, the fetch, and
  /// the adjacent-season prefetch, so there is nothing season-specific left
  /// for this method to duplicate.
  void _tvSelectSeason(int seasonIndex) {
    if (seasonIndex < 0 || seasonIndex >= _seasons.length || seasonIndex == _selectedSeasonIndex) return;
    setStateIfMounted(() => _selectedSeasonIndex = seasonIndex);
    unawaited(_fetchSeasonEpisodes(seasonIndex));
  }

  /// UP from the episode rail (PB-4): the active season chip when there is a
  /// chip row, otherwise the action row exactly as before chips existed.
  void _focusAboveTvDetailRail(MediaItem metadata) {
    if (_tvDetailShowsSeasonChips(metadata)) {
      _focusSelectedSeasonTab();
      return;
    }
    _focusTvDetailActionRow();
  }

  Widget _buildTvDetailSeasonChips(MediaItem metadata, double scale) {
    return AutomationNode(
      id: AutomationIds.mediaDetailSeasonChips,
      role: 'list',
      state: () => {'child_count': _seasons.length, 'selected_index': _selectedSeasonIndex},
      child: SizedBox(
        height: _tvDetailSeasonChipContentHeight(scale),
        child: Row(
          children: [
            // The rail's header strip draws nothing for this hub; this is its
            // title, in the rail's own active-header style.
            Text(
              t.libraries.groupings.episodes,
              maxLines: 1,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: TvHig.body * TvHig.of(context),
                height: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(width: _tvSeasonChipHeadingGap * scale),
            Flexible(child: _buildTvDetailSeasonChipScroller(scale)),
            if (_tvDetailSelectedSeasonCountLabel() case final count?) ...[
              SizedBox(width: _tvSeasonChipHeadingGap * scale),
              Text(
                count,
                maxLines: 1,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens(context).onArtworkInk(dark: 0.60, light: 0.85),
                  fontSize: TvHig.caption1 * TvHig.of(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "10 afleveringen · 6 bekeken" for the selected season, from the same
  /// season fields the phone's episode tab counts with.
  String? _tvDetailSelectedSeasonCountLabel() {
    if (_seasons.isEmpty) return null;
    final season = _seasons[_selectedSeasonIndex.clamp(0, _seasons.length - 1)];
    final total = season.leafCount ?? _episodes.length;
    if (total <= 0) return null;
    return t.discover.episodeCountWatched(count: total, watched: season.viewedLeafCount ?? 0);
  }

  Widget _buildTvDetailSeasonChipScroller(double scale) {
    return SingleChildScrollView(
      controller: _seasonTabsScrollController,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < _seasons.length; i++)
            Padding(
              padding: EdgeInsets.only(right: i == _seasons.length - 1 ? 0 : _tvSeasonChipGap * scale),
              child: AutomationNode(
                id: AutomationIds.mediaDetailSeasonChip,
                instance: '$i',
                role: 'chip',
                state: () => {'selected': i == _selectedSeasonIndex},
                focusNode: _seasonTabFocusNodes.length > i ? _seasonTabFocusNodes[i] : null,
                child: _TvSeasonChip(
                  label: _seasons[i].title?.isNotEmpty == true
                      ? _seasons[i].title!
                      : (_seasons[i].displaySubtitle ?? _seasons[i].displayTitle),
                  isSelected: i == _selectedSeasonIndex,
                  scale: scale,
                  focusNode: _seasonTabFocusNodes.length > i ? _seasonTabFocusNodes[i] : null,
                  onSelect: () => _tvSelectSeason(i),
                  onNavigateLeft: i > 0
                      ? () {
                          _tvSelectSeason(i - 1);
                          _seasonTabFocusNodes[i - 1].requestFocus();
                          _scrollSeasonTabIntoView(i - 1);
                        }
                      : null,
                  onNavigateRight: i < _seasons.length - 1
                      ? () {
                          _tvSelectSeason(i + 1);
                          _seasonTabFocusNodes[i + 1].requestFocus();
                          _scrollSeasonTabIntoView(i + 1);
                        }
                      : null,
                  onNavigateUp: _focusTvDetailActionRow,
                  onNavigateDown: () => _tvDetailRailKey.currentState?.requestFocus(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One season chip: label only, selected = filled, focused = a lighter sheen
/// and a visible outline — the same three-state contract
/// `FocusableTabChip.segmented` already draws for the mobile season tabs
/// (transparent idle, `surfaceElevated` selected, muted-to-full ink), redrawn
/// at TV geometry instead of the fixed Material text-theme sizes that widget
/// reads, which the 10-foot distance this row is read from does not forgive.
class _TvSeasonChip extends StatefulWidget {
  const _TvSeasonChip({
    required this.label,
    required this.isSelected,
    required this.scale,
    required this.onSelect,
    this.focusNode,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onNavigateUp,
    this.onNavigateDown,
  });

  final String label;
  final bool isSelected;
  final double scale;
  final VoidCallback onSelect;
  final FocusNode? focusNode;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;

  @override
  State<_TvSeasonChip> createState() => _TvSeasonChipState();
}

class _TvSeasonChipState extends State<_TvSeasonChip> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final scale = widget.scale;
    final isSelected = widget.isSelected;
    // 37 C: every chip is a filled pill, the selected one solid in text ink.
    // A transparent idle chip read as a gap, and the row as unevenly spaced
    // words. The focus ring is `FocusableWrapper`'s, on top of either state.
    final backgroundColor = isSelected ? mono.text : mono.text.withValues(alpha: _isFocused ? 0.22 : 0.10);
    final foregroundColor = isSelected ? mono.bg : mono.text.withValues(alpha: _isFocused ? 1 : 0.85);
    // Kept, transparent: its width is part of the height DET4 measures.
    const borderColor = Colors.transparent;

    return FocusableWrapper(
      focusNode: widget.focusNode,
      onSelect: widget.onSelect,
      onNavigateLeft: widget.onNavigateLeft,
      onNavigateRight: widget.onNavigateRight,
      onNavigateUp: widget.onNavigateUp,
      onNavigateDown: widget.onNavigateDown,
      onFocusChange: (focused) {
        if (mounted && focused != _isFocused) setState(() => _isFocused = focused);
      },
      borderRadius: _MediaDetailTvSeasonChips._tvSeasonChipRadius * scale,
      disableScale: true,
      semanticLabel: widget.label,
      child: AnimatedContainer(
        duration: mono.fast,
        padding: EdgeInsets.symmetric(
          horizontal: _MediaDetailTvSeasonChips._tvSeasonChipPaddingHorizontal * TvHig.of(context),
          vertical: _MediaDetailTvSeasonChips._tvSeasonChipPaddingVertical * TvHig.of(context),
        ),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(_MediaDetailTvSeasonChips._tvSeasonChipRadius * scale),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Text(
          widget.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: foregroundColor,
            fontSize: _MediaDetailTvSeasonChips._tvSeasonChipFontSize * TvHig.of(context),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
