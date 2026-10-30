part of '../../media_detail_screen.dart';

/// The order of 12, for the entries of the media menu. An entry that is not
/// listed goes after these, so nothing the menu offers can fall off the panel.
const List<String> _tvDetailPanelOrder = [
  'watchlist_toggle',
  'add_to',
  'play_trailer',
  'watch',
  'unwatch',
  'rate',
  'shuffle_play',
  'request',
  'play_from_beginning',
  'play_version',
  'fileinfo',
];

/// What Beheren holds: everything that changes the server's copy of a title,
/// and that the menu only lists for someone with the rights to do it.
const Set<String> _tvDetailManageActions = {
  'edit_metadata',
  'match',
  'unmatch',
  'remove_from_collection',
  'delete_media',
};

/// Meer acties (12). Its rows are the media menu's entries with the two things
/// only this page knows on top, the file's tracks and the unified sources, so
/// the menu stays the one definition of what a title offers.
extension _MediaDetailTvMoreActions on _MediaDetailScreenState {
  void _tvDetailOpenMoreActions() {
    final menu = _contextMenuKey.currentState;
    final menuContext = _contextMenuKey.currentContext;
    if (menu == null || menuContext == null) return;
    SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
    unawaited(_runTvDetailMoreActions(menu, menuContext));
  }

  Future<void> _runTvDetailMoreActions(MediaContextMenuState menu, BuildContext menuContext) async {
    // The context under the page's own sheet host, which the State's is not when
    // this page stands on its own.
    final chosen = await OverlaySheetController.showAdaptive<Future<void> Function()>(
      menuContext,
      presentation: OverlaySheetPresentation.tvSidePanel,
      alignment: Alignment.centerRight,
      restoreLauncherFocus: true,
      builder: (sheetContext) => ValueListenableBuilder<int>(
        valueListenable: _tvDetailPanelRevision,
        builder: (context, _, _) => TvDetailActionPanel(
          title: t.discover.moreActions,
          rows: _tvDetailPanelRows(sheetContext, menu, menuContext),
        ),
      ),
    );
    if (chosen == null) return;
    // After the frame that hands the focus back to ⋮: an action that opens
    // something of its own takes the focus from there, and gives it back there.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) await chosen();
  }

  /// A row that runs its action with the panel gone.
  TvDetailActionRow _tvDetailMenuRow(
    BuildContext sheetContext,
    MediaContextMenuState menu,
    BuildContext menuContext,
    MediaMenuAction action,
  ) => TvDetailActionRow(
    id: action.value,
    icon: action.icon,
    label: action.label,
    value: action.subtitle,
    onSelect: () {
      SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
      OverlaySheetController.closeAdaptive(sheetContext, () async {
        if (menuContext.mounted) await menu.runMenuAction(menuContext, action.value);
      });
    },
  );

  List<TvDetailActionRow> _tvDetailPanelRows(
    BuildContext sheetContext,
    MediaContextMenuState menu,
    BuildContext menuContext,
  ) {
    final actions = menu.menuActions(menuContext);
    final manage = actions.where((action) => _tvDetailManageActions.contains(action.value)).toList();
    final general = actions.where((action) => !_tvDetailManageActions.contains(action.value)).toList();
    int rank(MediaMenuAction action) {
      final index = _tvDetailPanelOrder.indexOf(action.value);
      return index < 0 ? _tvDetailPanelOrder.length : index;
    }

    final ordered = [...general]..sort((a, b) => rank(a).compareTo(rank(b)));
    final audio = _detailAudioTracks.where((track) => track.id == _selectedDetailAudioTrackId).firstOrNull;
    final subtitle = _detailSubtitleTracks.where((track) => track.id == _selectedDetailSubtitleTrackId).firstOrNull;
    final hasTracks = _detailAudioTarget != null;
    return [
      if (hasTracks && _detailAudioTracks.isNotEmpty)
        TvDetailActionRow(
          id: 'audio',
          icon: Symbols.volume_up_rounded,
          iconFilled: true,
          label: t.discover.audioStream,
          value: audio == null ? null : detailAudioLabel(audio),
          onSelect: () => unawaited(_tvDetailChooseAudio(sheetContext)),
        ),
      if (hasTracks && _detailSubtitleTracks.isNotEmpty)
        TvDetailActionRow(
          id: 'subtitles',
          icon: Symbols.subtitles_rounded,
          label: t.discover.subtitlesRow,
          value: subtitle?.label.primary ?? t.common.off,
          onSelect: () => unawaited(_tvDetailChooseSubtitle(sheetContext)),
        ),
      for (final action in ordered) _tvDetailMenuRow(sheetContext, menu, menuContext, action),
      if (_tvDetailSourceRow(sheetContext) case final source?) source,
      if (manage.isNotEmpty)
        TvDetailActionRow(
          id: 'manage',
          icon: Symbols.edit_rounded,
          label: t.discover.manageTitle,
          onSelect: () {
            SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
            unawaited(
              OverlaySheetController.of(sheetContext).push<void>(
                keepPreviousAlive: true,
                builder: (_) => TvDetailActionPanel(
                  title: t.discover.manageTitle,
                  rows: [for (final action in manage) _tvDetailMenuRow(sheetContext, menu, menuContext, action)],
                ),
              ),
            );
          },
        ),
    ];
  }

  /// Bronnen on a unified title: the picker the source line under the actions
  /// opens. A pick replaces this route, so the label is the new page's.
  TvDetailActionRow? _tvDetailSourceRow(BuildContext sheetContext) {
    final routeContext = widget.unifiedRouteContext;
    final onChangeSource = widget.onChangeSource;
    if (routeContext == null || !routeContext.hasAlternativeSources || onChangeSource == null) return null;
    return TvDetailActionRow(
      id: 'source',
      icon: Symbols.dns_rounded,
      label: t.sourcePicker.source,
      value: _unifiedSourceParts(routeContext).join(' • '),
      onSelect: () {
        SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
        OverlaySheetController.closeAdaptive(sheetContext, () async {
          final pageContext = _contextMenuKey.currentContext ?? context;
          await onChangeSource(pageContext);
        });
      },
    );
  }

  /// Tracks open as a page in this panel, so a pick lands back on its row with
  /// the new value. The row the panel opens on is the track in use.
  Future<T?> _tvDetailPushChoice<T>(
    BuildContext sheetContext, {
    required String title,
    required MediaItem target,
    required List<TvDetailActionRow> Function(FocusNode selected, void Function(T) choose) rows,
  }) async {
    SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
    final selected = FocusNode(debugLabel: 'detail_track_selected');
    final controller = OverlaySheetController.of(sheetContext);
    final chosen = await controller.push<T>(
      keepPreviousAlive: true,
      initialFocusNode: selected,
      builder: (_) => TvDetailActionPanel(
        title: title,
        subtitle: _trackScopeLabel(target),
        note: _detailPickRemembered ? t.discover.trackChoiceNote : t.discover.trackChoiceNoteOnce,
        rows: rows(selected, (value) {
          SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
          controller.pop(value);
        }),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => selected.dispose());
    return chosen;
  }

  Future<void> _tvDetailChooseAudio(BuildContext sheetContext) async {
    final target = _detailAudioTarget;
    if (target == null) return;
    final track = await _tvDetailPushChoice<MediaAudioTrack>(
      sheetContext,
      title: t.discover.audioStream,
      target: target,
      rows: (selected, choose) => [
        for (final track in _detailAudioTracks)
          TvDetailActionRow(
            id: 'track_${track.id}',
            icon: track.id == _selectedDetailAudioTrackId ? Symbols.check_rounded : Symbols.volume_up_rounded,
            label: detailAudioLabel(track),
            focusNode: track.id == _selectedDetailAudioTrackId ? selected : null,
            onSelect: () => choose(track),
          ),
      ],
    );
    if (track != null && mounted) await _applyDetailAudioTrack(target, track);
  }

  Future<void> _tvDetailChooseSubtitle(BuildContext sheetContext) async {
    final target = _detailAudioTarget;
    if (target == null) return;
    final current = _selectedDetailSubtitleTrackId;
    final choice = await _tvDetailPushChoice<MobileSubtitleChoice>(
      sheetContext,
      title: t.discover.subtitlesRow,
      target: target,
      rows: (selected, choose) => [
        TvDetailActionRow(
          id: 'track_off',
          icon: current == null ? Symbols.check_rounded : Symbols.subtitles_off_rounded,
          label: t.common.off,
          focusNode: current == null ? selected : null,
          onSelect: () => choose((track: null)),
        ),
        for (final track in _detailSubtitleTracks)
          TvDetailActionRow(
            id: 'track_${track.id}',
            icon: track.id == current ? Symbols.check_rounded : Symbols.subtitles_rounded,
            label: track.label.primary,
            focusNode: track.id == current ? selected : null,
            onSelect: () => choose((track: track)),
          ),
      ],
    );
    if (choice != null && mounted) await _applyDetailSubtitleTrack(target, choice.track);
  }
}
