import 'package:flutter/material.dart';

import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../focus/focusable_wrapper.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/tv_hig.dart';
import '../../../widgets/app_icon.dart';
import 'tv_detail_layout.dart';

/// One line of a [TvDetailActionPanel].
class TvDetailActionRow {
  const TvDetailActionRow({
    required this.id,
    required this.icon,
    required this.label,
    required this.onSelect,
    this.value,
    this.iconFilled = false,
    this.focusNode,
  });

  /// The automation instance, and what keeps a row's focus through a rebuild.
  final String id;
  final IconData icon;
  final String label;

  /// What is set now, right of the label: the audio track, Off, a source.
  final String? value;
  final bool iconFilled;
  final VoidCallback onSelect;

  /// For the page that opens on another row than its first.
  final FocusNode? focusNode;
}

/// The panel of 12: a heading and a column of rows, a white pill under the
/// focus. The sheet's scope keeps the focus in; the rows stop it at both ends.
class TvDetailActionPanel extends StatelessWidget {
  const TvDetailActionPanel({super.key, required this.title, required this.rows, this.subtitle, this.note});

  final String title;

  /// Under the heading: what a choice on this page applies to.
  final String? subtitle;

  /// Under the rows: what a choice on this page does.
  final String? note;
  final List<TvDetailActionRow> rows;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final pt = TvHig.of(context);
    final padding = EdgeInsets.fromLTRB(
      TvDetailLayout.panelPadding * pt,
      TvDetailLayout.panelTitleTop * pt,
      TvDetailLayout.panelPadding * pt,
      TvDetailLayout.panelPadding * pt,
    );
    return AutomationNode(
      id: AutomationIds.mediaDetailActionPanel,
      role: 'region',
      state: () => {'title': title, 'child_count': rows.length},
      // The theme tracks its body text out; 12 is set solid, as the page is.
      child: DefaultTextStyle.merge(
        style: const TextStyle(letterSpacing: 0),
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: TvDetailLayout.panelTitleHeight * pt,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tk.text, fontSize: TvHig.body * pt, fontWeight: FontWeight.w700),
                ),
              ),
              if (subtitle case final subtitle?) ...[
                SizedBox(height: 8 * pt),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tk.textMuted, fontSize: TvHig.caption2 * pt),
                ),
              ],
              SizedBox(height: (subtitle == null ? TvDetailLayout.panelRowsTop : 32) * pt),
              Expanded(
                child: SingleChildScrollView(
                  clipBehavior: Clip.none,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (index, row) in rows.indexed)
                        Padding(
                          key: ValueKey(row.id),
                          padding: EdgeInsets.only(top: index == 0 ? 0 : TvDetailLayout.panelRowGap * pt),
                          child: _Row(row: row, first: index == 0, last: index == rows.length - 1),
                        ),
                    ],
                  ),
                ),
              ),
              if (note case final note?) ...[
                SizedBox(height: 24 * pt),
                Text(
                  note,
                  style: TextStyle(color: tk.textMuted, fontSize: TvHig.caption2 * pt),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({required this.row, required this.first, required this.last});

  final TvDetailActionRow row;

  /// At an end of the list the press stops: left to the traversal, the last
  /// row's DOWN would wrap round to the first.
  final bool first;
  final bool last;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _focused = false;
  FocusNode? _ownNode;

  FocusNode get _node => widget.row.focusNode ?? (_ownNode ??= FocusNode(debugLabel: 'action_row_${widget.row.id}'));

  @override
  void dispose() {
    _ownNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final pt = TvHig.of(context);
    final row = widget.row;
    final height = TvDetailLayout.panelRowHeight * pt;
    final Color ink = _focused ? const Color(0xFF101010) : tk.text;
    final Color muted = _focused ? const Color(0xFF101010) : tk.textMuted;
    final value = row.value;
    final label = Text(
      row.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: ink, fontSize: TvHig.caption1 * pt),
    );
    return AutomationNode(
      id: AutomationIds.mediaDetailActionPanelRow,
      instance: row.id,
      role: 'list.item',
      label: row.label,
      focusNode: _node,
      state: () => {'value': value},
      child: FocusableWrapper(
        focusNode: _node,
        onSelect: row.onSelect,
        onNavigateUp: () {
          if (!widget.first) _node.previousFocus();
        },
        onNavigateDown: () {
          if (!widget.last) _node.nextFocus();
        },
        onFocusChange: (focused) {
          if (mounted && focused != _focused) setState(() => _focused = focused);
        },
        borderRadius: height / 2,
        disableScale: true,
        autoScroll: true,
        scrollOnlyWhenHidden: true,
        mode: FocusIndicatorMode.delegated,
        semanticLabel: [row.label, ?value].join(', '),
        child: AnimatedContainer(
          duration: tk.fast,
          height: height,
          decoration: BoxDecoration(
            color: _focused ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(height / 2),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Positioned(
                left: (TvDetailLayout.panelIconCentre - TvHig.body / 2) * pt,
                child: AppIcon(row.icon, fill: row.iconFilled ? 1 : 0, size: TvHig.body * pt, color: ink),
              ),
              Padding(
                padding: EdgeInsets.only(
                  left: TvDetailLayout.panelLabelInset * pt,
                  right: TvDetailLayout.panelValueInset * pt,
                ),
                child: Row(
                  children: [
                    if (value == null)
                      Expanded(child: label)
                    else ...[
                      // As wide as it reads: what is left is the value's, and a
                      // track's name is the longer of the two.
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 200 * pt),
                        child: label,
                      ),
                      SizedBox(width: 16 * pt),
                      Expanded(
                        child: Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(color: muted, fontSize: TvHig.caption2 * pt, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
