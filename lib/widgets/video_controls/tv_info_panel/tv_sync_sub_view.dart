import 'package:flutter/material.dart';

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
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  formatSyncOffset(_offset.toDouble()),
                  style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w700, height: 1),
                ),
                const SizedBox(width: 18),
                Flexible(
                  child: Text(_description(), style: const TextStyle(color: TvPanelTheme.textMuted, fontSize: 16)),
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
                  onStepLeft: () => _apply(_offset - TvSyncSubView.stepMs),
                  onStepRight: () => _apply(_offset + TvSyncSubView.stepMs),
                  onSelect: () => _apply(_offset + TvSyncSubView.stepMs),
                  automationId: null,
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
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
            child: Text(
              t.videoControls.tvPanel.syncKeepsForAllTitles,
              style: const TextStyle(color: TvPanelTheme.textFaint, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
