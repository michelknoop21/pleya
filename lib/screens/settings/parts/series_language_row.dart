/// One stored series preference, as mockup 31 A lists it: poster, title, the
/// choice on one line, and where it came from on the next.
///
/// Two rows, one set of strings. The phone and the desktop get a settings list
/// row; a television gets the tile language of `TvMenuTile` at ten-foot type.
/// Everything either of them says comes from the functions at the top of this
/// file, so the two surfaces cannot describe the same preference differently.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../automation/automation_ids.dart';
import '../../../focus/focusable_wrapper.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/ids.dart';
import '../../../media/track_language_choice.dart';
import '../../../providers/multi_server_provider.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/layout_constants.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/optimized_media_image.dart';
import '../../../widgets/settings_section.dart';
import '../../../widgets/tv/tv_unified_layout.dart';
import '../../../utils/language_codes.dart';

/// "Audio: English · Subtitles: English".
///
/// A field the viewer never chose reads as "global": the entry only overrides
/// what it holds, and saying "Nederlands" for an audio language that is really
/// coming from the profile would misname where the value lives.
String seriesLanguageSummary(TrackLanguageChoice choice) {
  final audio = choice.hasAudio
      ? (languageDisplayName(choice.audioLanguage) ?? t.languageSettings.global)
      : t.languageSettings.global;
  final subtitles = choice.subtitlesOff
      ? t.languageSettings.off
      : (choice.hasSubtitle
            ? '${languageDisplayName(choice.subtitleLanguage) ?? t.languageSettings.global}'
                  '${choice.subtitleForced ? ' (${t.languageSettings.forced})' : ''}'
            : t.languageSettings.global);
  return t.languageSettings.rowLanguages(audio: audio, subtitles: subtitles);
}

/// "Chosen on 2 Sep at S2E4 · Apple TV", with the parts that are missing left
/// out rather than filled with a placeholder.
///
/// Null when the entry predates provenance entirely — an entry written before
/// this page existed has a date and nothing else, and a line reading "Chosen
/// on 2 Sep" alone is worth more than no line at all, so the date carries it.
String? seriesOriginLine(TrackLanguageChoice choice) {
  final date = formatChoiceDate(choice.updatedAt);
  if (date == null) return null;
  final provenance = choice.provenance;
  final episode = provenance?.episodeLabel;
  final device = provenance?.deviceName;
  if (episode != null && device != null) {
    return t.languageSettings.rowOrigin(date: date, episode: episode, device: device);
  }
  if (device != null) return t.languageSettings.rowOriginNoEpisode(date: date, device: device);
  return t.languageSettings.rowOriginNoDevice(date: date);
}

/// The title to show for an entry, falling back to its key.
///
/// The key is not pretty, and it is also never nothing: an entry stored before
/// provenance existed would otherwise be a blank row the viewer cannot act on,
/// while "Gebruik globale voorkeur" works on it perfectly well.
String seriesDisplayTitle(({String key, TrackLanguageChoice choice}) entry) =>
    entry.choice.provenance?.title ?? entry.key;

/// Day and month for this year, the year added once it is not.
///
/// Falls back to the locale-independent numeric form when `intl` has no data
/// for the current language. `main.dart` loads it for the saved locale at
/// startup, so that is normally never; a settings page is not the place to
/// throw when it is, and a date the viewer can still read beats an error
/// widget where a row should be.
String? formatChoiceDate(int updatedAt) {
  if (updatedAt <= 0) return null;
  final date = DateTime.fromMillisecondsSinceEpoch(updatedAt);
  final locale = LocaleSettings.currentLocale.languageCode;
  try {
    final formatter = date.year == DateTime.now().year ? DateFormat.MMMd(locale) : DateFormat.yMMMd(locale);
    return formatter.format(date);
  } on Exception {
    return '${date.day}-${date.month}-${date.year}';
  }
}

/// The show's poster, drawn from the server the choice was made on.
///
/// Degrades to a glyph rather than to an empty box: that server may have been
/// removed since, may be offline, or may be a backend that reports no poster
/// path on an episode at all, and none of those is a reason for the row to
/// lose its shape.
class SeriesPoster extends StatelessWidget {
  const SeriesPoster({super.key, required this.provenance, required this.width, required this.height});

  final TrackChoiceProvenance? provenance;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final path = provenance?.posterPath;
    final serverId = provenance?.serverId;
    final client = (path == null || serverId == null || serverId.isEmpty)
        ? null
        : context.read<MultiServerProvider?>()?.getClientForServer(ServerId(serverId));
    final radius = BorderRadius.circular(6);

    if (client == null || path == null) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: tokens(context).surfaceElevated, borderRadius: radius),
        child: Center(
          child: AppIcon(Symbols.tv_rounded, fill: 1, size: width * 0.45, color: tokens(context).textMuted),
        ),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: OptimizedMediaImage(
        client: client,
        imagePath: path,
        width: width,
        height: height,
        fit: BoxFit.cover,
        fallbackIcon: Symbols.tv_rounded,
      ),
    );
  }
}

/// The settings-list shape, for everything that is not a television.
class SeriesLanguageRow extends StatelessWidget {
  const SeriesLanguageRow({super.key, required this.entry, required this.onSelect});

  final ({String key, TrackLanguageChoice choice}) entry;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final origin = seriesOriginLine(entry.choice);
    return SettingRowFocus(
      onSelect: onSelect,
      child: ListTile(
        contentPadding: kSettingRowPadding,
        leading: SeriesPoster(provenance: entry.choice.provenance, width: 40, height: 60),
        title: Text(seriesDisplayTitle(entry)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(seriesLanguageSummary(entry.choice)),
            if (origin != null) Text(origin, style: TextStyle(fontSize: 12, color: tokens(context).textMuted)),
          ],
        ),
        trailing: AppIcon(Symbols.chevron_right_rounded, fill: 1, size: 20, color: tokens(context).textMuted),
        onTap: onSelect,
      ),
    );
  }
}

/// The ten-foot shape: the tile language of the rest of Mijn Pleya, with the
/// poster mockup 31 A puts in front of the three lines.
class TvSeriesLanguageRow extends StatelessWidget {
  const TvSeriesLanguageRow({
    super.key,
    required this.entry,
    required this.node,
    required this.onSelect,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
  });

  final ({String key, TrackLanguageChoice choice}) entry;
  final FocusNode node;
  final VoidCallback onSelect;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final tk = tokens(context);
    final origin = seriesOriginLine(entry.choice);

    return FocusableWrapper(
      focusNode: node,
      onSelect: onSelect,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      onNavigateLeft: onNavigateLeft,
      borderRadius: TvMyPleyaLayout.tileRadius * scale,
      automationId: AutomationIds.myPleyaSectionTile,
      automationInstance: 'language.series.${entry.key}',
      automationRole: 'grid.item',
      automationState: () => <String, Object?>{
        'title': seriesDisplayTitle(entry),
        'value': seriesLanguageSummary(entry.choice),
      },
      // Hoofdstuk 33.8, the same rule the menu tile follows: a settings row
      // does not scale on focus. The ring and the lighter fill say where the
      // remote is, and a poster that grows would push the column around.
      disableScale: true,
      semanticLabel: '${seriesDisplayTitle(entry)}. ${seriesLanguageSummary(entry.choice)}',
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.all(TvMyPleyaLayout.tileFocusRingGap * scale),
          child: Builder(
            builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return AnimatedContainer(
                duration: TvTopNavLayout.focusDuration,
                curve: Curves.easeOut,
                padding: EdgeInsets.all(TvMyPleyaLayout.tilePadding * scale),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(TvMyPleyaLayout.tileRadius * scale),
                  color: tk.text.withValues(
                    alpha: focused ? TvMyPleyaLayout.tileFocusedFillAlpha : TvMyPleyaLayout.tileFillAlpha,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SeriesPoster(provenance: entry.choice.provenance, width: 56 * scale, height: 84 * scale),
                    SizedBox(width: TvMyPleyaLayout.tilePadding * scale),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            seriesDisplayTitle(entry),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: TvMyPleyaLayout.tileTitleFontSize * scale,
                              fontWeight: FontWeight.w600,
                              color: tk.text,
                            ),
                          ),
                          SizedBox(height: TvMyPleyaLayout.tileTitleSubtitleGap * scale),
                          Text(
                            seriesLanguageSummary(entry.choice),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: TvMyPleyaLayout.tileSubtitleFontSize * scale,
                              color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
                            ),
                          ),
                          if (origin != null) ...[
                            SizedBox(height: TvMyPleyaLayout.tileTitleSubtitleGap * scale),
                            Text(
                              origin,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: TvMyPleyaLayout.tileSubtitleFontSize * scale,
                                color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    AppIcon(
                      Symbols.chevron_right_rounded,
                      fill: 1,
                      size: TvMyPleyaLayout.tileIconSize * scale,
                      color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A left-column row of mockup 31 A: title and note on the left, the current
/// value and a chevron on the right, or a toggle glyph where the row is a
/// switch.
///
/// Not `TvMenuTile`, and the simulator is what settled that. A hub tile is
/// ~180 points tall on an Apple TV once `TvLayoutConstants` has scaled it, and
/// six of them stacked put the last two below the 1080-point viewport: the
/// Pleya Verify run of 5 September failed on exactly that
/// (`insideViewport(language.language_remember)` overflowing on the bottom).
/// The tile idiom belongs to an index of destinations two columns wide; this
/// column is six settings on one screen, which is what 31 A draws and what this
/// row is measured for.
///
/// Same automation id as a menu tile on purpose (`my_pleya.section.tile`): a
/// scenario addresses the row by what it *is* for the viewer, and the shape it
/// is drawn in is not part of that contract.
class TvLanguageValueRow extends StatelessWidget {
  const TvLanguageValueRow({
    super.key,
    required this.rowKey,
    required this.title,
    required this.value,
    required this.node,
    required this.onSelect,
    this.note,
    this.toggled,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateRight,
  });

  /// Stable within the page, and the focus key the page restores to.
  final String rowKey;
  final String title;

  /// The current answer, on the right where 31 A puts it.
  final String value;

  /// The line under the title that says what the value means. Optional: the
  /// two switches carry their state on the value line instead.
  final String? note;

  /// A switch's state, when this row is one. Null on a row that opens a picker,
  /// which then draws a chevron.
  final bool? toggled;

  final FocusNode node;
  final VoidCallback onSelect;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateRight;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final tk = tokens(context);
    final radius = TvMyPleyaLayout.tileRadius * scale;
    final noteLine = note;

    return FocusableWrapper(
      focusNode: node,
      onSelect: onSelect,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      onNavigateRight: onNavigateRight,
      borderRadius: radius,
      automationId: AutomationIds.myPleyaSectionTile,
      automationInstance: 'language.$rowKey',
      automationRole: 'grid.item',
      automationState: () => <String, Object?>{'title': title, 'value': value, if (toggled != null) 'toggled': toggled},
      // Hoofdstuk 33.8: a settings row does not scale on focus. The ring and
      // the lighter fill say where the remote is.
      disableScale: true,
      semanticLabel: '$title. $value',
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.all(TvMyPleyaLayout.tileFocusRingGap * scale),
          child: Builder(
            builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return AnimatedContainer(
                duration: TvTopNavLayout.focusDuration,
                curve: Curves.easeOut,
                // Vertically tighter than a hub tile, and measured rather than
                // chosen: six of these plus two group labels have to fit above
                // the 1080-point fold on an Apple TV, which is what mockup 31 A
                // draws and what the Pleya Verify assertions check.
                padding: EdgeInsets.symmetric(
                  horizontal: TvMyPleyaLayout.tilePadding * scale,
                  vertical: TvMyPleyaLayout.tileTitleSubtitleGap * 2 * scale,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  color: tk.text.withValues(
                    alpha: focused ? TvMyPleyaLayout.tileFocusedFillAlpha : TvMyPleyaLayout.tileFillAlpha,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: TvMyPleyaLayout.tileTitleFontSize * scale,
                              fontWeight: FontWeight.w600,
                              color: tk.text,
                            ),
                          ),
                          if (noteLine != null) ...[
                            SizedBox(height: TvMyPleyaLayout.tileTitleSubtitleGap * scale),
                            Text(
                              noteLine,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: TvMyPleyaLayout.tileSubtitleFontSize * scale,
                                color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(width: TvMyPleyaLayout.tilePadding * scale),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: TvMyPleyaLayout.tileTitleFontSize * scale,
                        color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
                      ),
                    ),
                    SizedBox(width: TvMyPleyaLayout.tileTitleSubtitleGap * 2 * scale),
                    if (toggled != null)
                      Icon(
                        toggled! ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                        size: TvMyPleyaLayout.tileIconSize * scale,
                        color: tk.text.withValues(
                          alpha: toggled! ? TvMyPleyaLayout.inkPrimary : TvMyPleyaLayout.inkTertiary,
                        ),
                      )
                    else
                      AppIcon(
                        Symbols.chevron_right_rounded,
                        fill: 1,
                        size: TvMyPleyaLayout.tileIconSize * scale,
                        color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
