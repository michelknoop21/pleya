part of '../media_detail_screen.dart';

/// The phone-only series tab strip from mockup 07: Afleveringen / Vergelijkbaar
/// / Extra's / Details. A plain tap-switched row (not a swipeable
/// [TabBarView]) so it lives inside the page's single [CustomScrollView]
/// without a nested-scrolling widget — season state and episode data stay in
/// [_MediaDetailScreenState] exactly as they do for TV, so switching tabs and
/// back never loses the selected season.
extension _PhoneEpisodeTabs on _MediaDetailScreenState {
  Widget _buildPhoneSeriesTabs(BuildContext context, MediaItem metadata) {
    final theme = Theme.of(context);
    final labels = [t.libraries.groupings.episodes, t.discover.similarTitles, t.discover.extrasTab, t.common.details];

    return Column(
      crossAxisAlignment: .start,
      children: [
        Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: AutomationNode(
                  id: AutomationIds.mediaDetailPhoneTab,
                  instance: '$i',
                  role: 'tab',
                  child: InkWell(
                    onTap: () => _selectPhoneDetailTab(i),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            labels[i],
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: i == _selectedPhoneDetailTab ? .w700 : .w500,
                              color: i == _selectedPhoneDetailTab
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Container(
                          height: 2,
                          color: i == _selectedPhoneDetailTab ? theme.colorScheme.primary : Colors.transparent,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _buildPhoneSeriesTabContent(context, metadata, _selectedPhoneDetailTab),
      ],
    );
  }

  Widget _buildPhoneSeriesTabContent(BuildContext context, MediaItem metadata, int tabIndex) {
    switch (tabIndex) {
      case 0:
        return _buildPhoneEpisodesTab(context, metadata);
      case 1:
        return _relatedHubs.isEmpty
            ? _sectionEmpty(context, t.states.emptyTitle)
            : Column(
                crossAxisAlignment: .start,
                children: [
                  for (final hub in _relatedHubs) ...[
                    HubSection(hub: hub, icon: _getRelatedHubIcon(hub), inset: true),
                    const SizedBox(height: 12),
                  ],
                ],
              );
      case 2:
        return (!widget.isOffline && _extras != null && _extras!.isNotEmpty)
            ? _buildExtrasSectionContent()
            : _sectionEmpty(context, t.states.emptyTitle);
      default:
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: .start,
          children: [
            if (metadata.summary != null && metadata.summary!.isNotEmpty) ...[
              CollapsibleText(
                text: metadata.summary!,
                maxLines: 6,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
              ),
              const SizedBox(height: 16),
            ],
            _buildPhoneCreditsLine(metadata),
            const SizedBox(height: 12),
            ..._buildPhoneWatchersAndInfoRows(context, metadata),
          ],
        );
    }
  }

  Widget _buildPhoneEpisodesTab(BuildContext context, MediaItem metadata) {
    final hasMultipleSeasons = _seasons.length > 1;

    return Column(
      crossAxisAlignment: .start,
      children: [
        if (hasMultipleSeasons) ...[
          Row(
            mainAxisAlignment: .spaceBetween,
            children: [
              _buildPhoneSeasonDropdown(context),
              if (_selectedSeasonIndex < _seasons.length)
                _buildPhoneSeasonCountLine(context, _seasons[_selectedSeasonIndex]),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (_isLoadingSeasons || _isLoadingSeasonEpisodes)
          _MediaDetailScreenState._sectionLoading
        else if (_seasonsLoadFailed)
          _sectionError(t.messages.seasonsLoadFailed, () => unawaited(_loadSeasons()))
        else if (_seasonEpisodesFirstPageError && _episodes.isEmpty)
          _sectionError(t.messages.episodesLoadFailed, () => unawaited(_fetchSeasonEpisodes(_selectedSeasonIndex)))
        else if (_episodes.isEmpty)
          _sectionEmpty(context, t.messages.noEpisodesFoundGeneral)
        else
          _buildEpisodesList(),
      ],
    );
  }

  Widget _buildPhoneSeasonDropdown(BuildContext context) {
    final theme = Theme.of(context);
    final current = _selectedSeasonIndex < _seasons.length ? _seasons[_selectedSeasonIndex] : null;

    return AutomationNode(
      id: AutomationIds.mediaDetailPhoneSeasonDropdown,
      role: 'button',
      state: () => {'season_index': _selectedSeasonIndex, 'season_title': current?.title},
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => unawaited(_showPhoneSeasonPicker(context)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: .min,
            children: [
              Text(current?.title ?? '', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: .w600)),
              const SizedBox(width: 4),
              Icon(Symbols.expand_more_rounded, size: 20, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneSeasonCountLine(BuildContext context, MediaItem season) {
    final theme = Theme.of(context);
    final leafCount = season.leafCount;
    if (leafCount == null) return const SizedBox.shrink();
    final viewedCount = season.viewedLeafCount ?? 0;
    return Text(
      '${t.libraries.groupings.episodes} ($leafCount) · ${t.discover.watched} ($viewedCount)',
      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }

  Future<void> _showPhoneSeasonPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: AutomationNode(
            id: AutomationIds.sheetSeasonPicker,
            role: 'sheet',
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _seasons.length,
              itemBuilder: (context, index) {
                final season = _seasons[index];
                return AutomationNode(
                  id: AutomationIds.sheetSeasonPickerRow,
                  instance: '$index',
                  role: 'list.item',
                  child: ListTile(
                    title: Text(season.title ?? ''),
                    trailing: index == _selectedSeasonIndex ? const Icon(Symbols.check_rounded) : null,
                    onTap: () => Navigator.pop(sheetContext, index),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
    if (selected == null || selected == _selectedSeasonIndex || !mounted) return;
    _selectPhoneSeason(selected);
    unawaited(_fetchSeasonEpisodes(selected));
  }
}
