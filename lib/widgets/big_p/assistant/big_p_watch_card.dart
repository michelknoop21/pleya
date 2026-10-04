import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../assistant/assistant_tools.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/tv_hig.dart';
import '../big_p_scale.dart';
import 'big_p_assistant_widgets.dart';

// Five viewers side by side: the card stays one band, so the title cards,
// two follow-ups and the buttons fit under it in the panel.
const _viewers = 5;

/// watch_stats as one card: a headline with the period and the total, the
/// viewers as portraits with the leader ringed in the brand gradient, and
/// the streams of "now" as their own list. The watched titles follow as
/// ranked title cards (see the results view); servers without a source and
/// a partial read are footnotes.
class BigPWatchCard extends StatelessWidget {
  const BigPWatchCard({super.key, required this.stats});

  final AssistantWatchStats stats;

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    final tk = tokens(context);
    final s = stats;
    final d = t.assistant.displays;
    final muted = TextStyle(color: tk.text.withValues(alpha: 0.6), fontSize: TvHig.caption2 * pt);
    final viewers = s.users.take(_viewers).toList();
    final total = s.users.fold(0, (sum, u) => sum + u.plays);
    // No rows because no server could answer is not "nothing watched".
    final empty = s.days != null && viewers.isEmpty && s.titles.isEmpty && s.unavailable.isEmpty && !s.partial;
    final period = switch (s.days) {
      null => d.watchNow,
      final days => d.watchDays(n: days),
    };

    return BigPCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.watchTitle,
                      style: TextStyle(
                        color: tk.text,
                        fontSize: TvHig.headline * pt,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                    SizedBox(height: 4 * pt),
                    Text('${s.serverName} · $period', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                  ],
                ),
              ),
              if (s.days != null && total > 0) _Total(value: total, label: d.playsTotal),
            ],
          ),
          SizedBox(height: 24 * pt),
          if (s.days == null) ...[
            for (final session in s.sessions.take(8)) _Stream(user: session.userName, title: session.title),
            if (s.sessions.isEmpty && s.unavailable.isEmpty) Text(d.nobodyNow, style: muted),
          ] else if (empty)
            Text(d.nothingWatched, style: muted)
          else if (viewers.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, v) in viewers.indexed)
                  Expanded(
                    child: _Viewer(name: v.name, plays: v.plays, leader: i == 0),
                  ),
                // Fewer than five keep their size instead of stretching.
                for (var i = viewers.length; i < _viewers; i++) const Spacer(),
              ],
            ),
          for (final note in [if (s.partial) d.partialData, for (final name in s.unavailable) d.noSource(server: name)])
            Padding(
              padding: EdgeInsets.only(top: 14 * pt),
              child: Row(
                children: [
                  Icon(Symbols.info_rounded, color: tk.text.withValues(alpha: 0.55), size: 20 * pt),
                  SizedBox(width: 8 * pt),
                  Expanded(child: Text(note, style: muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The period's total, right-aligned against the headline, in the brand
/// gradient.
class _Total extends StatelessWidget {
  const _Total({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    final tk = tokens(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ShaderMask(
          shaderCallback: tk.accentGradient.createShader,
          child: Text(
            '$value',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'ArchivoBlack',
              fontSize: TvHig.title3 * pt,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Text(
          label,
          style: TextStyle(color: tk.text.withValues(alpha: 0.6), fontSize: TvHig.caption2 * pt),
        ),
      ],
    );
  }
}

/// One viewer: a monogram portrait, the name and the plays. The leader's
/// portrait is ringed in the brand gradient and its count is in the accent.
class _Viewer extends StatelessWidget {
  const _Viewer({required this.name, required this.plays, required this.leader});

  final String name;
  final int plays;
  final bool leader;

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    final tk = tokens(context);
    final size = 78 * pt;
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    // A steady tint per name, dark enough for white type on the glass.
    final hue = name.toLowerCase().codeUnits.fold(0, (h, c) => (h * 31 + c) % 360).toDouble();
    final tint = HSLColor.fromAHSL(1, hue, 0.32, 0.30).toColor();
    return Column(
      children: [
        Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(3 * pt),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: leader ? tk.accentGradient : null,
            color: leader ? null : tk.text.withValues(alpha: 0.14),
          ),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: tint),
            child: Text(
              initial,
              style: TextStyle(color: Colors.white, fontSize: TvHig.callout * pt, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        SizedBox(height: 10 * pt),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4 * pt),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: tk.text,
              fontSize: TvHig.caption1 * pt,
              fontWeight: leader ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        SizedBox(height: 2 * pt),
        Text(
          t.assistant.displays.playsShort(count: plays),
          style: TextStyle(
            color: leader ? tk.accent : tk.text.withValues(alpha: 0.6),
            fontSize: TvHig.caption2 * pt,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// One stream of "now": who and what, the name allowed to shrink first.
class _Stream extends StatelessWidget {
  const _Stream({required this.user, required this.title});

  final String user;
  final String title;

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    final tk = tokens(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 10 * pt),
      child: Row(
        children: [
          Icon(Symbols.play_circle_rounded, fill: 1, color: tk.accent, size: 26 * pt),
          SizedBox(width: 12 * pt),
          Flexible(
            child: Text(
              user,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tk.text, fontSize: TvHig.caption1 * pt, fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(width: 12 * pt),
          Expanded(
            flex: 2,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tk.text.withValues(alpha: 0.75), fontSize: TvHig.caption1 * pt),
            ),
          ),
        ],
      ),
    );
  }
}
