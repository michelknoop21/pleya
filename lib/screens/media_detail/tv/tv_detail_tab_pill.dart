import 'package:flutter/material.dart';

import '../../../focus/focusable_wrapper.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/tv_hig.dart';
import 'tv_detail_layout.dart';

/// One tab above a series page: Serie, Season 1, Season 2.
///
/// A white pill under the focus and an outlined one on the tab that is open
/// while the focus is elsewhere (03 and 01). Drawn here rather than by the
/// wrapper's ring: in this theme a selected Material state is invisible
/// ([DEC-053](../../../../docs/DECISIONS.md#dec-053)).
class TvDetailTabPill extends StatefulWidget {
  const TvDetailTabPill({
    super.key,
    required this.label,
    required this.active,
    required this.focusNode,
    required this.onSelect,
    required this.onNavigateUp,
    required this.onNavigateDown,
    required this.onNavigateLeft,
    required this.onNavigateRight,
  });

  final String label;
  final bool active;
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final VoidCallback onNavigateUp;
  final VoidCallback onNavigateDown;
  final VoidCallback onNavigateLeft;
  final VoidCallback onNavigateRight;

  @override
  State<TvDetailTabPill> createState() => _TvDetailTabPillState();
}

class _TvDetailTabPillState extends State<TvDetailTabPill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final pt = TvHig.of(context);
    final height = TvDetailLayout.tabHeight * pt;
    final focused = _focused;
    final Color ink = focused ? const Color(0xFF101010) : (widget.active ? tk.text : tk.textMuted);
    return FocusableWrapper(
      focusNode: widget.focusNode,
      onSelect: widget.onSelect,
      onNavigateUp: widget.onNavigateUp,
      onNavigateDown: widget.onNavigateDown,
      onNavigateLeft: widget.onNavigateLeft,
      onNavigateRight: widget.onNavigateRight,
      onFocusChange: (value) {
        if (mounted && value != _focused) setState(() => _focused = value);
      },
      borderRadius: height / 2,
      disableScale: true,
      autoScroll: false,
      mode: FocusIndicatorMode.delegated,
      semanticLabel: widget.label,
      child: AnimatedContainer(
        duration: tk.fast,
        height: height,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: TvDetailLayout.tabPadding * pt),
        decoration: BoxDecoration(
          color: focused ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(height / 2),
          border: Border.all(
            color: widget.active && !focused ? tk.text.withValues(alpha: 0.8) : Colors.transparent,
            width: 2 * pt,
          ),
        ),
        child: Text(
          widget.label,
          maxLines: 1,
          style: TextStyle(
            color: ink,
            fontSize: TvHig.caption1 * pt,
            fontWeight: focused || widget.active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
