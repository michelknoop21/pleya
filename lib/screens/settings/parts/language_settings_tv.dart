/// Taal en ondertitels on TV, per the approved mockup 31 A: the global
/// preference and the two switches on the left, the series preferences on the
/// right.
///
/// A `part` rather than a widget of its own for the reason `settings_tv_page`
/// gives: this is the same screen. Every value the left column writes and
/// every sheet the right column opens is the method the list row already
/// calls, so the product cannot end up with two definitions of "use the global
/// preference".
///
/// **Two columns, and the traversal that goes with them.** The left column is
/// the tile language of Mijn Pleya; the right is a list of preference rows. The
/// horizontal step between them is explicit — RIGHT off any left tile lands on
/// the series row nearest the top, LEFT off any series row returns to the tile
/// the remote came from — because directional traversal across two lists of
/// different heights otherwise picks whichever row happens to be geometrically
/// nearest, which from the last switch is not the first series.
part of '../language_settings_screen.dart';

/// Left-column keys. Stable, because they are also the focus keys the page
/// restores the remote to.
const String _kTvAudio = 'language_audio';
const String _kTvSubtitles = 'language_subtitles';
const String _kTvFallback = 'language_fallback';
const String _kTvPolicy = 'language_policy';
const String _kTvRemember = 'language_remember';
const String _kTvMirror = 'language_mirror';

extension _LanguageSettingsTvPage on _LanguageSettingsScreenState {
  String _seriesKeyFor(int index) => 'language_series_$index';

  void _focusKey(String key) {
    final node = _focusTracker.get(key);
    if (node.canRequestFocus) node.requestFocus();
  }

  /// The left column as tiles: title, the current value on the value line, and
  /// SELECT opens the picker. A switch says its state in the glyph, the way
  /// every other TV settings row does.
  List<TvMenuItem> _tvGlobalItems(PleyaProfileLanguagePreferences global) => [
    TvMenuItem(
      key: _kTvAudio,
      icon: Symbols.volume_up_rounded,
      title: t.languageSettings.audio,
      value: _audioValue(global),
      onSelect: () => _editAudioLanguage(global),
    ),
    TvMenuItem(
      key: _kTvSubtitles,
      icon: Symbols.subtitles_rounded,
      title: t.languageSettings.subtitles,
      value: _subtitleValue(global),
      onSelect: () => _editSubtitleLanguage(global),
    ),
    TvMenuItem(
      key: _kTvFallback,
      icon: Symbols.subtitles_off_rounded,
      title: t.languageSettings.subtitleFallback,
      value: _fallbackValue(global),
      onSelect: () => _editSubtitleFallback(global),
    ),
    TvMenuItem(
      key: _kTvPolicy,
      icon: Symbols.closed_caption_rounded,
      title: t.languageSettings.subtitleDisplay,
      value: _policyValue(global),
      onSelect: () => _editSubtitlePolicy(global),
    ),
  ];

  List<TvMenuItem> _tvRememberItems(PleyaProfileLanguagePreferences global) => [
    TvMenuItem(
      key: _kTvRemember,
      icon: Symbols.bookmark_rounded,
      title: t.settings.rememberTrackSelections,
      value: global.rememberPerSeries ? t.common.on : t.common.off,
      toggled: global.rememberPerSeries,
      onSelect: () => PleyaProfileLanguagePreferenceStore.update(
        (preferences) => preferences.copyWith(rememberPerSeries: !preferences.rememberPerSeries),
      ),
    ),
    TvMenuItem(
      key: _kTvMirror,
      icon: Symbols.cloud_upload_rounded,
      title: t.settings.writeSeriesLanguageToServer,
      value: global.mirrorToPlex ? t.common.on : t.common.off,
      toggled: global.mirrorToPlex,
      onSelect: () => PleyaProfileLanguagePreferenceStore.update(
        (preferences) => preferences.copyWith(mirrorToPlex: !preferences.mirrorToPlex),
      ),
    ),
  ];

  Widget _buildTv(BuildContext context, PleyaProfileLanguagePreferences global) {
    final scale = TvLayoutConstants.scaleOf(context);

    return TvPageSurface(
      title: t.languageSettings.title,
      automationInstance: 'language',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildTvGlobalColumn(context, global, scale)),
            SizedBox(width: TvMyPleyaLayout.tileGap * 2 * scale),
            Expanded(child: _buildTvSeriesColumn(context, global, scale)),
          ],
        ),
      ],
    );
  }

  Widget _buildTvGlobalColumn(BuildContext context, PleyaProfileLanguagePreferences global, double scale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TvPageGroupLabel(t.languageSettings.globalHeader),
        Padding(
          padding: EdgeInsets.only(bottom: TvMyPleyaLayout.tileGap * scale),
          child: Text(
            _ownerLine(context),
            style: TextStyle(
              fontSize: TvMyPleyaLayout.tileSubtitleFontSize * scale,
              color: tokens(context).text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
            ),
          ),
        ),
        TvMenuGrid(
          nodes: _focusTracker,
          columns: 1,
          automationInstance: 'language',
          // RIGHT off any tile lands on the series column, at its top row: the
          // column beside this one is a different list, and "the next item" in
          // a one-column grid is the tile below, not the thing to the right.
          onExitRight: _series.isEmpty ? null : () => _focusKey(_seriesKeyFor(0)),
          sections: [
            TvMenuSection(items: _tvGlobalItems(global)),
            TvMenuSection(label: t.languageSettings.rememberHeader, items: _tvRememberItems(global)),
          ],
        ),
      ],
    );
  }

  Widget _buildTvSeriesColumn(BuildContext context, PleyaProfileLanguagePreferences global, double scale) {
    final tk = tokens(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TvPageGroupLabel(t.languageSettings.seriesHeader),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_series.isEmpty)
          Text(
            t.languageSettings.seriesEmpty,
            style: TextStyle(
              fontSize: TvMyPleyaLayout.tileSubtitleFontSize * scale,
              color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
            ),
          )
        else ...[
          Padding(
            padding: EdgeInsets.only(bottom: TvMyPleyaLayout.tileGap * scale),
            child: Text(
              t.languageSettings.seriesCount(count: _series.length),
              style: TextStyle(
                fontSize: TvMyPleyaLayout.tileSubtitleFontSize * scale,
                color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
              ),
            ),
          ),
          for (var index = 0; index < _series.length; index++) ...[
            if (index > 0) SizedBox(height: TvMyPleyaLayout.tileGap * scale),
            TvSeriesLanguageRow(
              entry: _series[index],
              node: _focusTracker.get(_seriesKeyFor(index), debugLabel: _seriesKeyFor(index)),
              onSelect: () => _openSeries(_series[index], global),
              onNavigateUp: index == 0 ? null : () => _focusKey(_seriesKeyFor(index - 1)),
              onNavigateDown: index == _series.length - 1 ? null : () => _focusKey(_seriesKeyFor(index + 1)),
              // LEFT returns to the global column at the same height as the
              // remote left it, clipped to the tiles that exist. Without the
              // clip a viewer eleven series down would land on nothing.
              onNavigateLeft: () => _focusKey(_leftColumnKeyFor(index)),
            ),
          ],
          Padding(
            padding: EdgeInsets.only(top: TvMyPleyaLayout.tileGap * scale),
            child: Text(
              t.languageSettings.seriesFootnote,
              style: TextStyle(
                fontSize: TvMyPleyaLayout.tileSubtitleFontSize * scale,
                color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Which left-column tile a series row hands the focus back to.
  String _leftColumnKeyFor(int index) {
    const leftKeys = [_kTvAudio, _kTvSubtitles, _kTvFallback, _kTvPolicy, _kTvRemember, _kTvMirror];
    return leftKeys[index.clamp(0, leftKeys.length - 1)];
  }
}
