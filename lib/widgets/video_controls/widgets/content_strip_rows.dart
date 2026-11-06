part of 'content_strip.dart';

/// The chapter and queue rows of [ContentStrip], split off to keep the state
/// class readable. Behaviour is unchanged.
extension _ContentStripRows on ContentStripState {
  Widget _buildChapterStrip(bool isTablet) {
    final thumbWidth = isTablet ? 200.0 : 120.0;
    final thumbHeight = isTablet ? 112.0 : 68.0;

    return StreamBuilder<Duration>(
      stream: widget.player.streams.position,
      initialData: widget.player.state.position,
      builder: (context, positionSnapshot) {
        final currentPosition = positionSnapshot.data ?? Duration.zero;
        final currentChapterIndex = MediaChapter.indexAtPosition(currentPosition, widget.chapters);

        _trimItemKeys(_chapterItemKeys, widget.chapters.length);

        if (currentChapterIndex != null && _lastAutoScrolledChapterIndex != currentChapterIndex) {
          _lastAutoScrolledChapterIndex = currentChapterIndex;
          _autoScrollTo(
            _chapterScrollController,
            _chapterItemKeys,
            currentChapterIndex,
            isTablet: isTablet,
            isCurrent: () => _lastAutoScrolledChapterIndex == currentChapterIndex,
          );
        }

        if (widget.useFocusNavigation) {
          _ensureFocusNodes(_chapterFocusNodes, widget.chapters.length, 'ChapterFocus');
        }

        return ListView.builder(
          controller: _chapterScrollController,
          scrollDirection: Axis.horizontal,
          clipBehavior: widget.useFocusNavigation ? Clip.none : Clip.hardEdge,
          itemCount: widget.chapters.length,
          padding: .symmetric(horizontal: widget.useFocusNavigation ? 12 : 4),
          itemBuilder: (context, index) {
            final chapter = widget.chapters[index];
            final isCurrent = currentChapterIndex == index;

            final localThumbPath = widget.serverId != null && chapter.thumb != null
                ? DownloadStorageService.instance.getArtworkPathSync(ServerId(widget.serverId!), chapter.thumb!)
                : null;

            void onTap() => unawaited(_handleChapterTap(chapter.startTime));

            final itemKey = _itemKeyFor(_chapterItemKeys, index);
            final item = _buildStripItem(
              key: itemKey,
              isCurrent: isCurrent,
              isTablet: isTablet,
              thumbnail: chapter.thumb != null
                  ? OptimizedMediaImage.thumb(
                      client: _tryGetClient(context, serverIdOrNull(widget.serverId)),
                      imagePath: chapter.thumb,
                      localFilePath: localThumbPath,
                      width: thumbWidth,
                      height: thumbHeight,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) =>
                          const AppIcon(Symbols.image_rounded, fill: 1, color: Colors.white54, size: 34),
                    )
                  : null,
              title: chapter.label,
              subtitle: formatDurationTimestamp(chapter.startTime),
              onTap: onTap,
            );

            if (widget.useFocusNavigation) {
              return Align(
                alignment: .topCenter,
                child: FocusableWrapper(
                  focusNode: _chapterFocusNodes[index],
                  onSelect: onTap,
                  onKeyEvent: (_, event) =>
                      _handleFocusItemKeyEvent(event, index, widget.chapters.length, _StripTab.chapters),
                  onFocusChange: (hasFocus) {
                    if (hasFocus) widget.onFocusActivity?.call();
                  },
                  borderRadius: 6,
                  autoScroll: false,
                  mode: FocusIndicatorMode.fill,
                  child: item,
                ),
              );
            }

            return item;
          },
        );
      },
    );
  }

  Widget _buildQueueStrip(bool isTablet) {
    final thumbWidth = isTablet ? 200.0 : 120.0;
    final thumbHeight = isTablet ? 112.0 : 68.0;

    return SettingValueBuilder<bool>(
      pref: SettingsService.hideSpoilers,
      builder: (context, hideSpoilers, _) => Consumer<PlaybackStateProvider>(
        builder: (context, playbackState, _) {
          final items = playbackState.loadedItems;
          final currentItemID = playbackState.currentPlayQueueItemID;
          final currentIndex = currentItemID == null
              ? -1
              : items.indexWhere((item) => playbackState.playQueueItemIdFor(item) == currentItemID);

          _trimItemKeys(_queueItemKeys, items.length);

          if (currentIndex >= 0 &&
              (_lastAutoScrolledQueueItemID != currentItemID || _lastAutoScrolledQueueIndex != currentIndex)) {
            _lastAutoScrolledQueueItemID = currentItemID;
            _lastAutoScrolledQueueIndex = currentIndex;
            _autoScrollTo(
              _queueScrollController,
              _queueItemKeys,
              currentIndex,
              isTablet: isTablet,
              isCurrent: () =>
                  _lastAutoScrolledQueueItemID == currentItemID && _lastAutoScrolledQueueIndex == currentIndex,
            );
          }

          if (widget.useFocusNavigation) {
            _ensureFocusNodes(_queueFocusNodes, items.length, 'QueueFocus');
          }

          return ListView.builder(
            controller: _queueScrollController,
            scrollDirection: Axis.horizontal,
            clipBehavior: widget.useFocusNavigation ? Clip.none : Clip.hardEdge,
            itemCount: items.length,
            padding: .symmetric(horizontal: widget.useFocusNavigation ? 12 : 4),
            itemBuilder: (context, index) {
              final item = items[index];
              final isCurrent = playbackState.playQueueItemIdFor(item) == currentItemID;

              final client = item.serverId != null
                  ? context.tryGetMediaClientForServer(serverIdOrNull(item.serverId))
                  : null;

              void onTap() => widget.onQueueItemSelected?.call(item);

              final itemKey = _itemKeyFor(_queueItemKeys, index);
              final stripItem = _buildStripItem(
                key: itemKey,
                isCurrent: isCurrent,
                isTablet: isTablet,
                thumbnail: item.rowThumbPath != null
                    ? OptimizedMediaImage.thumb(
                        client: client,
                        imagePath: item.rowThumbPath,
                        width: thumbWidth,
                        height: thumbHeight,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) =>
                            const AppIcon(Symbols.image_rounded, fill: 1, color: Colors.white54, size: 34),
                      )
                    : null,
                blurThumbnail: hideSpoilers && item.shouldHideSpoiler,
                title: item.title ?? '',
                subtitle: _buildQueueSubtitle(item),
                onTap: onTap,
              );

              if (widget.useFocusNavigation) {
                return Align(
                  alignment: .topCenter,
                  child: FocusableWrapper(
                    focusNode: _queueFocusNodes[index],
                    onSelect: onTap,
                    onKeyEvent: (_, event) => _handleFocusItemKeyEvent(event, index, items.length, _StripTab.queue),
                    onFocusChange: (hasFocus) {
                      if (hasFocus) widget.onFocusActivity?.call();
                    },
                    borderRadius: 6,
                    autoScroll: false,
                    mode: FocusIndicatorMode.fill,
                    child: stripItem,
                  ),
                );
              }

              return stripItem;
            },
          );
        },
      ),
    );
  }

  String _buildQueueSubtitle(MediaItem item) {
    if (item.grandparentTitle != null && item.parentIndex != null && item.index != null) {
      return '${item.grandparentTitle} \u00b7 S${item.parentIndex}E${item.index}';
    }
    if (item.grandparentTitle != null) return item.grandparentTitle!;
    if (item.year != null) {
      final edition = item.editionTitle;
      return edition != null ? '${item.year} · $edition' : '${item.year}';
    }
    return item.kind.name;
  }

  Widget _buildStripItem({
    Key? key,
    required bool isCurrent,
    required Widget? thumbnail,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool blurThumbnail = false,
    bool isTablet = false,
  }) {
    final itemWidth = isTablet ? 200.0 : 120.0;
    final thumbHeight = isTablet ? 112.0 : 68.0;
    final titleFontSize = isTablet ? 13.0 : 11.0;
    final subtitleFontSize = isTablet ? 12.0 : 10.0;

    final verticalMargin = widget.useFocusNavigation ? 4.0 : 0.0;
    return ClickableCursor(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          key: key,
          width: itemWidth,
          margin: .symmetric(horizontal: 6, vertical: verticalMargin),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: [
              MediaSelectorThumbnail(
                width: itemWidth,
                height: thumbHeight,
                thumbnail: thumbnail,
                isCurrent: isCurrent,
                borderColor: Colors.white,
                radius: 6,
                blurThumbnail: blurThumbnail,
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: titleFontSize,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: .ellipsis,
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: isCurrent ? Colors.white70 : Colors.white60,
                  fontSize: subtitleFontSize,
                  fontWeight: isCurrent ? FontWeight.w500 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: .ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
