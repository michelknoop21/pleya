import 'package:flutter/material.dart';

import '../../../automation/automation_ids.dart';
import '../../../i18n/strings.g.dart';
import '../../../mpv/mpv.dart';
import '../../../utils/formatters.dart';
import 'tv_panel_widgets.dart';

/// Audio or subtitle sync as a panel sub-view: the offset as a large number,
/// one value row that LEFT/RIGHT step by 100 ms, and a reset row. No Material
/// slider: on a remote the slider had no focus and nothing to grab (AUD2).
class TvSyncSubView extends StatefulWidget {
  final Player player;

  /// 'audio-delay' or 'sub-delay'.
  final String propertyName;
  final int initialOffset;
  final String labelText;
  final FocusNode firstFocusNode;
  final Future<void> Function(int offset) onOffsetChanged;

  const TvSyncSubView({
    super.key,
    required this.player,
    required this.propertyName,
    required this.initialOffset,
    required this.labelText,
    required this.firstFocusNode,
    required this.onOffsetChanged,
  });

  /// One press.
  static const int stepMs = 100;
  static const int maxAbsMs = 60000;

  @override
  State<TvSyncSubView> createState() => _TvSyncSubViewState();
}

class _TvSyncSubViewState extends State<TvSyncSubView> {
  late int _offset = widget.initialOffset;

  Future<void> _apply(int offsetMs) async {
    final clamped = offsetMs.clamp(-TvSyncSubView.maxAbsMs, TvSyncSubView.maxAbsMs);
    setState(() => _offset = clamped);
    // mpv takes seconds; the same write SyncOffsetControl does.
    await widget.player.setProperty(widget.propertyName, (clamped / 1000.0).toString());
    await widget.onOffsetChanged(clamped);
  }

  String _description() {
    if (_offset > 0) return t.videoControls.playsLater(label: widget.labelText);
    if (_offset < 0) return t.videoControls.playsEarlier(label: widget.labelText);
    return t.videoControls.noOffset;
  }

  @override
  Widget build(BuildContext context) {
    final m = TvPanelMetrics.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(m.gap(4), m.gap(4), m.gap(4), m.gap(18)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  formatSyncOffset(_offset.toDouble()),
                  style: TextStyle(color: Colors.white, fontSize: m.gap(44), fontWeight: FontWeight.w700, height: 1),
                ),
                SizedBox(width: m.gap(18)),
                Flexible(
                  child: Text(
                    _description(),
                    style: TextStyle(color: TvPanelTheme.textMuted, fontSize: m.valueFontSize),
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: TvPanelGroup(
              children: [
                TvPanelRow.value(
                  focusNode: widget.firstFocusNode,
                  title: t.videoControls.tvPanel.offset,
                  subtitle: t.videoControls.tvPanel.syncStepHint,
                  value: formatSyncOffset(_offset.toDouble()),
                  highlighted: _offset != 0,
                  onStepLeft: _offset <= -TvSyncSubView.maxAbsMs ? null : () => _apply(_offset - TvSyncSubView.stepMs),
                  onStepRight: _offset >= TvSyncSubView.maxAbsMs ? null : () => _apply(_offset + TvSyncSubView.stepMs),
                  onSelect: () => _apply(_offset + TvSyncSubView.stepMs),
                  // One row on its own page: there is no column to leave, and
                  // `syncStepHint` promises a direct step (DEC-107).
                  entersOnSelect: false,
                  automationId: AutomationIds.playerPanelRow,
                  automationInstance: 'sync_offset',
                  automationState: () => {'offsetMs': _offset},
                ),
                TvPanelRow(
                  title: t.videoControls.resetToZero,
                  dimmed: _offset == 0,
                  onSelect: _offset == 0 ? null : () => _apply(0),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(m.gap(4), m.gap(14), m.gap(4), m.gap(4)),
            child: Text(
              t.videoControls.tvPanel.syncKeepsForAllTitles,
              style: TextStyle(color: TvPanelTheme.textFaint, fontSize: m.subtitleFontSize),
            ),
          ),
        ],
      ),
    );
  }
}
