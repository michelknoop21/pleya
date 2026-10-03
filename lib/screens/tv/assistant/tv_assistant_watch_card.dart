import 'dart:math';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../assistant/assistant_tools.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/tv_hig.dart';
import 'tv_assistant_widgets.dart';

// Five viewers: the card, the title cards, two follow-ups and the buttons
// stay one scroll.
const _rows = 5;

/// watch_stats as one card: who watched, ranked, with a bar against the
/// leader (the watched titles follow as title cards, see the results view); streams of "now" as their own
/// list; servers without a source as a footnote.
class TvAssistantWatchCard extends StatelessWidget {
  const TvAssistantWatchCard({super.key, required this.stats});

  final AssistantWatchStats stats;

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final tk = tokens(context);
    final s = stats;
    final d = t.assistant.displays;
    final muted = TextStyle(color: tk.text.withValues(alpha: 0.6), fontSize: TvHig.caption2 * pt);
    final users = [for (final u in s.users.take(_rows)) (label: u.name, plays: u.plays)];
    final columns = [if (users.isNotEmpty) _Ranking(heading: d.viewers, rows: users)];
    // No rows because no server could answer is not "nothing watched".
    final empty = s.days != null && columns.isEmpty && s.titles.isEmpty && s.unavailable.isEmpty;

    return TvAssistantCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.monitoring_rounded, color: tk.text, size: 30 * pt),
              SizedBox(width: 12 * pt),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.watchStats(server: s.serverName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tk.text, fontSize: TvHig.callout * pt, fontWeight: FontWeight.w700),
                    ),
                    Text(switch (s.days) {
                      null => d.watchNow,
                      final days => d.watchDays(n: days),
                    }, style: muted),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 18 * pt),
          if (s.days == null) ...[
            for (final session in s.sessions.take(8))
              Padding(
                padding: EdgeInsets.only(bottom: 8 * pt),
                child: Row(
                  children: [
                    Icon(Symbols.play_circle_rounded, fill: 1, color: tk.text.withValues(alpha: 0.8), size: 24 * pt),
                    SizedBox(width: 10 * pt),
                    Flexible(
                      child: Text(
                        session.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: tk.text, fontSize: TvHig.caption1 * pt, fontWeight: FontWeight.w600),
                      ),
                    ),
                    SizedBox(width: 10 * pt),
                    Expanded(
                      child: Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: tk.text.withValues(alpha: 0.75), fontSize: TvHig.caption1 * pt),
                      ),
                    ),
                  ],
                ),
              ),
            if (s.sessions.isEmpty && s.unavailable.isEmpty) Text(d.nobodyNow, style: muted),
          ] else if (empty)
            Text(d.nothingWatched, style: muted)
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < columns.length; i++) ...[
                  if (i > 0) SizedBox(width: 32 * pt),
                  Expanded(child: columns[i]),
                ],
              ],
            ),
          for (final name in s.unavailable)
            Padding(
              padding: EdgeInsets.only(top: 12 * pt),
              child: Row(
                children: [
                  Icon(Symbols.info_rounded, color: tk.text.withValues(alpha: 0.6), size: 20 * pt),
                  SizedBox(width: 8 * pt),
                  Expanded(
                    child: Text(d.noSource(server: name), style: muted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Ranking extends StatelessWidget {
  const _Ranking({required this.heading, required this.rows});

  final String heading;
  final List<({String label, int plays})> rows;

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final tk = tokens(context);
    final top = rows.map((r) => r.plays).fold(1, max);
    final small = TextStyle(color: tk.text.withValues(alpha: 0.6), fontSize: TvHig.caption2 * pt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading.toUpperCase(), style: small.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        SizedBox(height: 10 * pt),
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: 12 * pt),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 30 * pt,
                  child: Text('${i + 1}', style: small.copyWith(fontSize: TvHig.caption1 * pt)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              rows[i].label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tk.text,
                                fontSize: TvHig.caption1 * pt,
                                fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ),
                          SizedBox(width: 10 * pt),
                          Text(
                            t.assistant.displays.playsShort(count: rows[i].plays),
                            style: TextStyle(
                              color: tk.text,
                              fontSize: TvHig.caption1 * pt,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 6 * pt),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3 * pt),
                        child: LinearProgressIndicator(
                          value: rows[i].plays / top,
                          minHeight: 5 * pt,
                          backgroundColor: tk.text.withValues(alpha: 0.1),
                          color: tk.text.withValues(alpha: i == 0 ? 0.9 : 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
