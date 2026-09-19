/// Mockup 17's band onder de gids: wat er onder de ring staat, uitgeschreven.
///
/// **Waarom hij niets kan.** PB-8: "Een gefocust programma mag een blijvend
/// detailgebied voeden zonder de focus te stelen ... De detailbalk is context,
/// geen tweede verplichte activatiestap." De parity-audit noemt een balk met
/// een Kijken-knop erin als ARCHITECTURAL CONFLICT, en terecht: SELECT op een
/// lopend programma speelt al direct af, en een knop die hetzelfde doet zou
/// twee paden naar afspelen maken en het D-pad-contract van de gids raken.
///
/// De twee labels rechts zeggen daarom wat de remote al kan, in plaats van het
/// nog een keer aan te bieden. Ze zijn `ExcludeSemantics`: een schermlezer die
/// ze als knop aankondigt zou dezelfde belofte doen.
///
/// **Waarom hij zijn hoogte houdt.** Een band die verschijnt bij focus en
/// verdwijnt bij geen focus duwt het raster erboven op en neer bij elke
/// focuswissel, en dan verspringt de rij onder de remote terwijl je erdoorheen
/// loopt. Leeg is hij leeg, niet weg.
library;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import '../../../i18n/strings.g.dart';
import '../../../models/livetv_channel.dart';
import '../../../models/livetv_program.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/formatters.dart';
import '../../../utils/layout_constants.dart';
import '../../../widgets/tv/tv_unified_layout.dart';

class GuideDetailBand extends StatelessWidget {
  const GuideDetailBand({super.key, required this.channel, required this.program, required this.isRecordingScheduled});

  final LiveTvChannel? channel;
  final LiveTvProgram? program;
  final bool isRecordingScheduled;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final tk = tokens(context);
    final p = program;

    return Container(
      height: TvMyPleyaLayout.tilePadding * 2 * scale + 120 * scale,
      margin: EdgeInsets.symmetric(horizontal: TvTopNavLayout.pageInset * scale),
      padding: EdgeInsets.all(TvMyPleyaLayout.tilePadding * scale),
      decoration: BoxDecoration(
        color: tk.text.withValues(alpha: TvMyPleyaLayout.tileFillAlpha),
        borderRadius: BorderRadius.circular(TvMyPleyaLayout.tileRadius * scale),
      ),
      child: p == null
          ? const SizedBox.shrink()
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _body(context, p, scale, tk)),
                SizedBox(width: TvMyPleyaLayout.tilePadding * scale),
                ExcludeSemantics(child: _hints(context, p, scale, tk)),
              ],
            ),
    );
  }

  Widget _body(BuildContext context, LiveTvProgram p, double scale, MonoTokens tk) {
    final is24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final meta = <String>[
      if (channel?.displayName != null) channel!.displayName,
      if (p.startTime != null && p.endTime != null)
        '${formatClockTime(p.startTime!, is24Hour: is24Hour)} - '
            '${formatClockTime(p.endTime!, is24Hour: is24Hour)}',
      if (isRecordingScheduled) t.liveTv.recordingScheduled,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          p.grandparentTitle ?? p.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tk.text,
            fontSize: TvMyPleyaLayout.tileTitleFontSize * scale,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (meta.isNotEmpty) ...[
          SizedBox(height: TvMyPleyaLayout.tileTitleSubtitleGap * scale),
          Text(
            toBulletedString(meta),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
              fontSize: TvMyPleyaLayout.tileSubtitleFontSize * scale,
            ),
          ),
        ],
        if (p.summary != null && p.summary!.isNotEmpty) ...[
          SizedBox(height: TvMyPleyaLayout.tileTitleSubtitleGap * 2 * scale),
          Text(
            p.summary!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
              fontSize: TvMyPleyaLayout.tileSubtitleFontSize * scale,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  /// Wat de remote hier kan, als tekst. Geen knoppen: zie de klassedoc.
  Widget _hints(BuildContext context, LiveTvProgram p, double scale, MonoTokens tk) {
    final labels = <String>[
      if (p.isCurrentlyAiring) t.liveTv.watchChannel,
      if (isRecordingScheduled) t.liveTv.manageRecording else t.liveTv.record,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final label in labels)
          Padding(
            padding: EdgeInsets.only(bottom: TvMyPleyaLayout.tileTitleSubtitleGap * scale),
            child: Text(
              label,
              style: TextStyle(
                color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
                fontSize: TvMyPleyaLayout.tileSubtitleFontSize * scale,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}
