import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../assistant/assistant_age_gate.dart';
import '../../../assistant/assistant_title_facts.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/formatters.dart';
import '../../../utils/tv_hig.dart';
import '../big_p_scale.dart';

/// What a title card shows of [TitleFacts]: the age rating for the device
/// region, runtime, two genres, the score and the region's services. Each
/// part only when known.
typedef BigPFactParts = ({String? age, List<String> meta, String? score, String? services});

BigPFactParts bigPFactParts(TitleFacts? facts, {String? region}) {
  if (facts == null || facts.isEmpty) return (age: null, meta: const [], score: null, services: null);
  final where = region ?? assistantRegion();
  final age = AgeGate.rating(facts, where)?.age;
  final services = facts.providers[where] ?? const [];
  return (
    age: age == null ? null : (age == 0 ? t.assistant.match.allAges : '$age'),
    meta: [if (facts.runtimeMin case final min?) formatDurationTextual(min * 60000), ...facts.genres.take(2)],
    score: facts.score == null ? null : formatRating((facts.score! * 10).round() / 10),
    services: services.isEmpty
        ? null
        : t.assistant.match.watchOn(
            services: [
              services.take(2).join(', '),
              if (services.length > 2) t.assistant.match.more(count: services.length - 2),
            ].join(' '),
          ),
  );
}

/// The facts lines under a card's second line: one with the age badge,
/// runtime, genres and score, one with "Te zien op". Nothing at all when
/// nothing is known; [services] false keeps the second line out (the dense
/// list form).
class BigPTitleFacts extends StatelessWidget {
  const BigPTitleFacts({super.key, required this.facts, this.services = true});

  final TitleFacts? facts;
  final bool services;

  /// How many lines [facts] takes, so a card can give its plot fewer.
  static int lineCount(TitleFacts? facts, {bool services = true}) {
    final p = bigPFactParts(facts);
    return (p.age != null || p.meta.isNotEmpty || p.score != null ? 1 : 0) + (services && p.services != null ? 1 : 0);
  }

  /// The facts as words, for the card's semantic label.
  static List<String> describe(TitleFacts? facts) {
    final p = bigPFactParts(facts);
    return [?p.age, ...p.meta, if (p.score case final s?) t.assistant.match.score(score: s), ?p.services];
  }

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    final tk = tokens(context);
    final p = bigPFactParts(facts);
    // A phone or tablet wraps a long facts line; on TV one line is the rule.
    final lines = BigPScale.minTouch(context) > 0 ? 2 : 1;
    final style = TextStyle(color: tk.text.withValues(alpha: 0.65), fontSize: TvHig.caption2 * pt, height: 1.2);
    final first = p.age != null || p.meta.isNotEmpty || p.score != null;
    final second = services && p.services != null;
    if (!first && !second) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (first) ...[
          SizedBox(height: 4 * pt),
          Row(
            children: [
              if (p.age case final age?) ...[_AgeBadge(label: age, style: style), SizedBox(width: 10 * pt)],
              Flexible(
                child: Text(p.meta.join(' · '), maxLines: lines, overflow: TextOverflow.ellipsis, style: style),
              ),
              if (p.score case final score?) ...[
                SizedBox(width: p.meta.isEmpty ? 0 : 12 * pt),
                Icon(Symbols.star_rounded, fill: 1, size: TvHig.caption2 * pt, color: tk.accentAlt),
                SizedBox(width: 4 * pt),
                Text(score, maxLines: 1, style: style),
              ],
            ],
          ),
        ],
        if (second) ...[
          SizedBox(height: 4 * pt),
          Text(p.services!, maxLines: lines, overflow: TextOverflow.ellipsis, style: style),
        ],
      ],
    );
  }
}

/// The age rating as a small outlined label, as on a cinema listing.
class _AgeBadge extends StatelessWidget {
  const _AgeBadge({required this.label, required this.style});

  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    final ink = tokens(context).text.withValues(alpha: 0.85);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7 * pt),
      decoration: BoxDecoration(
        border: Border.all(color: ink.withValues(alpha: 0.6), width: 1.5 * pt),
        borderRadius: BorderRadius.circular(6 * pt),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: style.copyWith(color: ink, fontWeight: FontWeight.w700),
      ),
    );
  }
}
