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

  static const double _tvSeasonChipFontSize = 17;
  static const double _tvSeasonChipPaddingHorizontal = 22;
  static const double _tvSeasonChipPaddingVertical = 11;
  static const double _tvSeasonChipRadius = 10;
  static const double _tvSeasonChipGap = 10;
  static const double _tvSeasonChipRowBottomGap = 14;

  /// The chip row's own height, excluding the gap to whatever sits below it.
  /// Measured, not guessed, for the same reason `_unifiedSourceLineHeight`
  /// gives: a guessed line-height multiplier and the real render drift apart,
  /// and this number feeds a height *reservation* that must not undershoot.
  double _tvDetailSeasonChipContentHeight(double scale) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'Mg',
        style: DefaultTextStyle.of(
          context,
        ).style.copyWith(fontSize: _tvSeasonChipFontSize * scale, fontWeight: FontWeight.w600),
      ),
      textDirection: Directionality.of(context),
    )..layout();
    final textHeight = painter.height;
    painter.dispose();
    return textHeight + (2 * _tvSeasonChipPaddingVertical * scale);
  }

  /// The full band this row occupies above the rail, gap included — what a
  /// caller reserving vertical space for it needs.
  double _tvDetailSeasonChipRowHeight(double scale) =>
      _tvDetailSeasonChipContentHeight(scale) + (_tvSeasonChipRowBottomGap * scale);

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
        child: SingleChildScrollView(
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
        ),
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
    final backgroundColor = isSelected
        ? mono.surfaceElevated
        : (_isFocused ? mono.surfaceElevated.withValues(alpha: 0.6) : Colors.transparent);
    final foregroundColor = isSelected || _isFocused ? mono.text : mono.textMuted;
    final borderColor = _isFocused
        ? mono.text.withValues(alpha: 0.75)
        : (isSelected ? mono.outline.withValues(alpha: 0.9) : Colors.transparent);

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
          horizontal: _MediaDetailTvSeasonChips._tvSeasonChipPaddingHorizontal * scale,
          vertical: _MediaDetailTvSeasonChips._tvSeasonChipPaddingVertical * scale,
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
            fontSize: _MediaDetailTvSeasonChips._tvSeasonChipFontSize * scale,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
