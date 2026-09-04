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

  /// The left column, in the row shape mockup 31 A draws: title and note on
  /// the left, the current value on the right, SELECT opens the picker.
  ///
  /// A record per row rather than a widget list, so the column can wire up its
  /// own vertical traversal without the caller repeating six neighbours.
  List<({String key, String title, String value, String? note, bool? toggled, VoidCallback onSelect})> _tvLeftRows(
    PleyaProfileLanguagePreferences global,
  ) => [
    (
      key: _kTvAudio,
      title: t.languageSettings.audio,
      value: _audioValue(global),
      note: t.languageSettings.audioFallbackNote,
      toggled: null,
      onSelect: () => _editAudioLanguage(global),
    ),
    (
      key: _kTvSubtitles,
      title: t.languageSettings.subtitles,
      value: _subtitleValue(global),
      note: t.languageSettings.subtitlesNote,
      toggled: null,
      onSelect: () => _editSubtitleLanguage(global),
    ),
    (
      key: _kTvFallback,
      title: t.languageSettings.subtitleFallback,
      value: _fallbackValue(global),
      note: t.languageSettings.subtitleFallbackNote,
      toggled: null,
      onSelect: () => _editSubtitleFallback(global),
    ),
    (
      key: _kTvPolicy,
      title: t.languageSettings.subtitleDisplay,
      value: _policyValue(global),
      note: t.languageSettings.subtitleDisplayNote,
      toggled: null,
      onSelect: () => _editSubtitlePolicy(global),
    ),
    (
      key: _kTvRemember,
      title: t.settings.rememberTrackSelections,
      value: global.rememberPerSeries ? t.common.on : t.common.off,
      note: null,
      toggled: global.rememberPerSeries,
      onSelect: () => PleyaProfileLanguagePreferenceStore.update(
        (preferences) => preferences.copyWith(rememberPerSeries: !preferences.rememberPerSeries),
      ),
    ),
    (
      key: _kTvMirror,
      title: t.settings.writeSeriesLanguageToServer,
      value: global.mirrorToPlex ? t.common.on : t.common.off,
      note: null,
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
    final rows = _tvLeftRows(global);
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
        for (var index = 0; index < rows.length; index++) ...[
          // Tighter than the hub's tile gap: this column carries six rows and
          // two labels, and every point between them is one the last row does
          // not have above the fold.
          if (index > 0) SizedBox(height: TvMyPleyaLayout.tileTitleSubtitleGap * 2 * scale),
          // The label of the second group sits between the four preference rows
          // and the two switches, where 31 A puts "Onthouden".
          if (rows[index].key == _kTvRemember)
            Padding(
              padding: EdgeInsets.only(top: TvMyPleyaLayout.tileGap * scale),
              child: TvPageGroupLabel(t.languageSettings.rememberHeader),
            ),
          TvLanguageValueRow(
            rowKey: rows[index].key,
            title: rows[index].title,
            value: rows[index].value,
            note: rows[index].note,
            toggled: rows[index].toggled,
            node: _focusTracker.get(rows[index].key, debugLabel: rows[index].key),
            onSelect: rows[index].onSelect,
            onNavigateUp: index == 0 ? null : () => _focusKey(rows[index - 1].key),
            onNavigateDown: index == rows.length - 1 ? null : () => _focusKey(rows[index + 1].key),
            // RIGHT crosses to the series column, at its top row: the column
            // beside this one is a different list, so "the next item" is not
            // "the thing to my right".
            onNavigateRight: _series.isEmpty ? null : () => _focusKey(_seriesKeyFor(0)),
          ),
        ],
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
