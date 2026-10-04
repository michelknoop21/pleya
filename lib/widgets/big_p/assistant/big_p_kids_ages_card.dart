import 'package:flutter/material.dart';

import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../focus/dpad_navigator.dart';
import '../../../focus/focusable_wrapper.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/tv_hig.dart';
import '../../../widgets/pleya_wordmark.dart';
import '../big_p_scale.dart';
import 'big_p_assistant_widgets.dart';

/// The Pleya card that asks for the children's ages (39 G's card, not a
/// message from Big P): a chip per age, several at once for several
/// children. Bewaar hands the ages to [onSave]; Zonder filter runs the
/// question once without the age gate. Focus opens on the first chip.
class BigPKidsAgesCard extends StatefulWidget {
  const BigPKidsAgesCard({
    super.key,
    required this.onSave,
    required this.onSkip,
    this.firstNode,
    this.embedded = false,
  });

  final ValueChanged<List<int>> onSave;
  final VoidCallback onSkip;

  /// Gets the first chip, for the surface's initial focus.
  final FocusNode? firstNode;

  /// Inside Big P's balloon (39 G): the balloon is the card.
  final bool embedded;

  @override
  State<BigPKidsAgesCard> createState() => _BigPKidsAgesCardState();
}

class _BigPKidsAgesCardState extends State<BigPKidsAgesCard> {
  final _ages = <int>{};

  void _toggle(int age) => setState(() => _ages.contains(age) ? _ages.remove(age) : _ages.add(age));

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    final tk = tokens(context);
    final k = t.assistant.kids;
    final muted = TextStyle(color: tk.text.withValues(alpha: 0.6), fontSize: TvHig.caption1 * pt);
    final skip = BigPButton(
      label: k.skip,
      automationId: AutomationIds.assistantKidsAgesButton,
      automationInstance: 'skip',
      onPressed: widget.onSkip,
    );
    final save = BigPButton(
      label: k.save,
      primary: true,
      enabled: _ages.isNotEmpty,
      automationId: AutomationIds.assistantKidsAgesButton,
      automationInstance: 'save',
      onPressed: () => widget.onSave((_ages.toList()..sort())),
    );
    return AutomationNode(
      id: AutomationIds.assistantKidsAges,
      role: 'sheet',
      state: () => {'ages': (_ages.toList()..sort())},
      child: Container(
        padding: widget.embedded ? null : EdgeInsets.all(48 * pt),
        decoration: widget.embedded
            ? null
            : BoxDecoration(color: tk.surface, borderRadius: BorderRadius.circular(28 * pt)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Image.asset(PleyaWordmark.markAsset, height: TvHig.caption1 * pt, filterQuality: FilterQuality.medium),
                SizedBox(width: 12 * pt),
                Expanded(child: Text(k.header, style: muted)),
              ],
            ),
            SizedBox(height: 10 * pt),
            Text(
              k.title,
              style: TextStyle(color: tk.text, fontSize: TvHig.title3 * pt * 0.8, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8 * pt),
            Text(k.body, style: muted.copyWith(height: 1.3)),
            SizedBox(height: 24 * pt),
            Wrap(
              spacing: 10 * pt,
              runSpacing: 10 * pt,
              children: [
                for (var age = 0; age <= 17; age++)
                  _AgeChip(
                    age: age,
                    selected: _ages.contains(age),
                    focusNode: age == 0 ? widget.firstNode : null,
                    onSelect: () => _toggle(age),
                  ),
              ],
            ),
            SizedBox(height: 32 * pt),
            // Right-aligned on TV, wrapping when the labels need it. In Big
            // P's balloon one above the other: these labels are too long for
            // 39 G's two halves on an iPhone SE.
            if (widget.embedded)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  save,
                  SizedBox(height: 4 * pt),
                  skip,
                ],
              )
            else
              Wrap(alignment: WrapAlignment.end, spacing: 12 * pt, runSpacing: 12 * pt, children: [skip, save]),
          ],
        ),
      ),
    );
  }
}

/// One age: a round toggle, filled in the accent when chosen.
class _AgeChip extends StatefulWidget {
  const _AgeChip({required this.age, required this.selected, required this.onSelect, this.focusNode});

  final int age;
  final bool selected;
  final VoidCallback onSelect;
  final FocusNode? focusNode;

  @override
  State<_AgeChip> createState() => _AgeChipState();
}

class _AgeChipState extends State<_AgeChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    final tk = tokens(context);
    final colors = Theme.of(context).colorScheme;
    final fill = widget.selected
        ? tk.accent
        : _focused
        ? colors.inverseSurface
        : const Color(0x1FFFFFFF);
    final ink = widget.selected
        ? Colors.white
        : _focused
        ? colors.onInverseSurface
        : tk.text;
    final size = 64 * pt;
    return GestureDetector(
      // FocusableWrapper only answers keys; on a touch screen a tap is Select.
      onTap: widget.onSelect,
      behavior: HitTestBehavior.opaque,
      child: FocusableWrapper(
        focusNode: widget.focusNode,
        borderRadius: size / 2,
        disableScale: true,
        semanticLabel: t.assistant.kids.age(age: widget.age),
        automationId: AutomationIds.assistantKidsAgesButton,
        automationInstance: 'age${widget.age}',
        automationRole: 'button',
        automationState: () => {'selected': widget.selected},
        onFocusChange: (focused) => setState(() => _focused = focused),
        onSelect: () {
          SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
          widget.onSelect();
        },
        child: Semantics(
          selected: widget.selected,
          child: AnimatedContainer(
            duration: tk.fast,
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
            child: Text(
              '${widget.age}',
              style: TextStyle(color: ink, fontSize: TvHig.callout * pt, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}
