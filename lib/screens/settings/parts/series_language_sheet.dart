/// The series-preference sheet of mockup 31 B.
///
/// One action, deliberately: "Gebruik globale voorkeur". A different language
/// is chosen while watching, in the info panel, because that is the only place
/// the tracks an episode actually has are on screen — the footer says so.
///
/// Reads the series value and the profile value side by side, so the sentence
/// the page makes ("this series overrides that preference") is visible rather
/// than implied.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/pleya_profile_language_preferences.dart';
import '../../../media/track_language_choice.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/layout_constants.dart';
import '../../../widgets/overlay_sheet.dart';
import '../../../widgets/overlay_sheet_geometry.dart';
import '../../../widgets/tv/tv_catalog_sort_panel.dart';
import '../../../widgets/tv/tv_panel_primitives.dart';
import '../../../widgets/tv/tv_unified_layout.dart';
import 'series_language_row.dart';
import '../../../utils/language_codes.dart';

/// Opens the sheet. Answers true when the viewer asked to drop this series
/// preference, and null or false in every other case.
Future<bool?> showSeriesLanguageSheet(
  BuildContext context, {
  required ({String key, TrackLanguageChoice choice}) entry,
  required PleyaProfileLanguagePreferences global,
}) {
  return OverlaySheetController.showAdaptive<bool>(
    context,
    presentation: OverlaySheetPresentation.panel,
    restoreLauncherFocus: true,
    builder: (sheetContext) => SeriesLanguagePanel(
      entry: entry,
      global: global,
      onUseGlobal: () => OverlaySheetController.closeAdaptive(sheetContext, true),
      onClose: () => OverlaySheetController.closeAdaptive(sheetContext, false),
    ),
  );
}

class SeriesLanguagePanel extends StatelessWidget {
  const SeriesLanguagePanel({
    super.key,
    required this.entry,
    required this.global,
    required this.onUseGlobal,
    required this.onClose,
  });

  final ({String key, TrackLanguageChoice choice}) entry;
  final PleyaProfileLanguagePreferences global;
  final VoidCallback onUseGlobal;
  final VoidCallback onClose;

  /// "Serievoorkeur, gekozen op 2 september bij S2E4 op de Apple TV.", with
  /// the parts the entry does not carry left out.
  String _originSentence() {
    final date = formatChoiceDate(entry.choice.updatedAt);
    if (date == null) return '';
    final provenance = entry.choice.provenance;
    final episode = provenance?.episodeLabel;
    final device = provenance?.deviceName;
    if (episode != null && device != null) {
      return t.languageSettings.sheetOriginEpisode(date: date, episode: episode, device: device);
    }
    return t.languageSettings.sheetOrigin(date: date);
  }

  String _seriesAudio() =>
      entry.choice.hasAudio ? (languageDisplayName(entry.choice.audioLanguage) ?? '') : t.languageSettings.global;

  String _seriesSubtitles() {
    if (entry.choice.subtitlesOff) return t.languageSettings.off;
    if (!entry.choice.hasSubtitle) return t.languageSettings.global;
    return languageDisplayName(entry.choice.subtitleLanguage) ?? '';
  }

  String _globalAudio() => global.useOriginalAudio
      ? t.languageSettings.originalLanguage
      : (languageDisplayName(global.audioLanguage) ?? t.languageSettings.noPreference);

  String _globalSubtitles() => languageDisplayName(global.subtitleLanguage) ?? t.languageSettings.noPreference;

  /// Whether this entry is keyed on the logical series rather than on one
  /// server, which is exactly what decides how far it reaches (DEC-096 lid 7).
  bool get _isLogical => entry.key.startsWith('show:');

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final mono = tokens(context);
    final radius = tvPanelBorderRadius(MediaQuery.sizeOf(context));

    return DecoratedBox(
      decoration: tvPanelDecoration(mono, radius),
      child: Padding(
        padding: EdgeInsets.all(TvSourcePickerLayout.panelPadding * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SeriesPoster(provenance: entry.choice.provenance, width: 72 * scale, height: 108 * scale),
                SizedBox(width: TvSourcePickerLayout.sectionGap * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        seriesDisplayTitle(entry),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: TvSourcePickerLayout.titleFontSize * scale,
                          fontWeight: FontWeight.w600,
                          color: mono.text.withValues(alpha: TvSourcePickerLayout.inkPrimary),
                        ),
                      ),
                      SizedBox(height: 6 * scale),
                      Text(
                        [
                          _originSentence(),
                          _isLogical ? t.languageSettings.sheetScopeLogical : t.languageSettings.sheetScopeServer,
                        ].where((line) => line.isNotEmpty).join(' '),
                        style: TextStyle(
                          fontSize: TvSourcePickerLayout.subtitleFontSize * scale,
                          color: mono.text.withValues(alpha: TvSourcePickerLayout.inkSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: TvSourcePickerLayout.sectionGap * scale),
            _ReadRow(
              icon: Symbols.volume_up_rounded,
              label: t.languageSettings.audio,
              value: _seriesAudio(),
              globalValue: t.languageSettings.sheetProfileValue(value: _globalAudio()),
              scale: scale,
            ),
            SizedBox(height: TvSourcePickerLayout.rowGap * scale),
            _ReadRow(
              icon: Symbols.closed_caption_rounded,
              label: t.languageSettings.subtitles,
              value: _seriesSubtitles(),
              globalValue: t.languageSettings.sheetProfileValue(value: _globalSubtitles()),
              scale: scale,
            ),
            SizedBox(height: TvSourcePickerLayout.sectionGap * scale),
            TvCatalogOptionRow(
              label: t.languageSettings.useGlobal,
              secondary: t.languageSettings.useGlobalNote,
              // Not a setting, so nothing here is "the current answer": a
              // selected tint would read as "already applied".
              isSelected: false,
              scale: scale,
              onPressed: onUseGlobal,
            ),
            SizedBox(height: TvSourcePickerLayout.footerGap * scale),
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.languageSettings.sheetFooter,
                    style: TextStyle(
                      fontSize: TvSourcePickerLayout.subtitleFontSize * scale,
                      color: mono.text.withValues(alpha: TvSourcePickerLayout.inkSecondary),
                    ),
                  ),
                ),
                SizedBox(width: TvSourcePickerLayout.sectionGap * scale),
                TvPanelButton(scale: scale, label: t.common.close, onPressed: onClose, primary: false),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A line the viewer reads but cannot change here: the series value on the
/// left, the profile's value next to it.
class _ReadRow extends StatelessWidget {
  const _ReadRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.globalValue,
    required this.scale,
  });

  final IconData icon;
  final String label;
  final String value;
  final String globalValue;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    return Row(
      children: [
        Icon(
          icon,
          size: 20 * scale,
          color: mono.text.withValues(alpha: TvSourcePickerLayout.inkSecondary),
        ),
        SizedBox(width: 12 * scale),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: TvSourcePickerLayout.subtitleFontSize * scale,
              color: mono.text.withValues(alpha: TvSourcePickerLayout.inkPrimary),
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: TvSourcePickerLayout.subtitleFontSize * scale,
            fontWeight: FontWeight.w600,
            color: mono.text.withValues(alpha: TvSourcePickerLayout.inkPrimary),
          ),
        ),
        SizedBox(width: 12 * scale),
        Text(
          globalValue,
          style: TextStyle(
            fontSize: TvSourcePickerLayout.subtitleFontSize * scale,
            color: mono.text.withValues(alpha: TvSourcePickerLayout.inkTertiary),
          ),
        ),
      ],
    );
  }
}
