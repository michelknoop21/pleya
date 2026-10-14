import 'package:flutter/widgets.dart';

import '../../../widgets/big_p/assistant/big_p_match_card.dart';

/// Gives a long lead above cards a fourth reading line when the cards can
/// spare it: the panel keeps every card it showed before (five, when there
/// are that many) and only the room that is left over goes to the text.
///
/// It measures the laid-out list, so it follows the font, the scale and the
/// panel's width instead of guessing a card's height. One line is added only
/// when a whole line of slack is there, and taken back only if the cards are
/// cut after all, so it settles instead of flickering.
class TvAssistantLeadSlack extends StatefulWidget {
  const TvAssistantLeadSlack({super.key, required this.lineHeight, required this.builder});

  /// What one more reading line costs.
  final double lineHeight;

  /// Builds the panel with [readLines] lines for the lead; [cardsKey] goes on
  /// the column of cards and [viewportKey] on the box that holds the list.
  final Widget Function(int readLines, Key cardsKey, Key viewportKey) builder;

  static const base = 3;
  static const grown = 4;

  @override
  State<TvAssistantLeadSlack> createState() => _TvAssistantLeadSlackState();
}

class _TvAssistantLeadSlackState extends State<TvAssistantLeadSlack> {
  final _cardsKey = GlobalKey();
  final _viewportKey = GlobalKey();
  int _lines = TvAssistantLeadSlack.base;

  /// Room under the cards that must stay in view: five cards, or all of them
  /// when there are fewer. Null while nothing is laid out or no card is there.
  double? _slack() {
    final cards = _cardsKey.currentContext;
    final column = cards?.findRenderObject();
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (cards == null || column is! RenderBox || !column.hasSize || viewport is! RenderBox || !viewport.hasSize) {
      return null;
    }
    final boxes = <RenderBox>[];
    void visit(Element e) {
      if (boxes.length >= 5) return;
      if (e.widget is BigPMatchCard && e.renderObject is RenderBox) {
        boxes.add(e.renderObject! as RenderBox);
        return;
      }
      e.visitChildren(visit);
    }

    (cards as Element).visitChildren(visit);
    if (boxes.isEmpty || boxes.any((b) => !b.hasSize || !b.attached)) return null;
    // In the column's own coordinates, so a scrolled list measures the same
    // as one at rest; the column starts at the viewport's top edge.
    final bottom = boxes
        .map((b) => b.localToGlobal(Offset(0, b.size.height), ancestor: column).dy)
        .reduce((a, b) => a > b ? a : b);
    return viewport.size.height - bottom;
  }

  void _measure() {
    if (!mounted) return;
    final slack = _slack();
    if (slack == null) return;
    final grown = _lines == TvAssistantLeadSlack.grown;
    final want = (grown ? slack >= -0.5 : slack >= widget.lineHeight - 0.5)
        ? TvAssistantLeadSlack.grown
        : TvAssistantLeadSlack.base;
    if (want != _lines) setState(() => _lines = want);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return widget.builder(_lines, _cardsKey, _viewportKey);
  }
}
