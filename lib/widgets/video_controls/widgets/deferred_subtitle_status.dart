import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../automation/automation_ids.dart';
import '../../../i18n/strings.g.dart';
import '../../../services/deferred_subtitle_loader.dart';
import '../tv_info_panel/tv_panel_widgets.dart';

/// What the subtitle button says while a track is not there, or null when it just opens the tracks.
String? deferredSubtitleNote(DeferredSubtitleStatus? status) => switch (status) {
  DeferredSubtitleStatus.preparing => t.videoControls.subtitlesPreparing,
  DeferredSubtitleStatus.failed => t.videoControls.subtitlesPrepareFailed,
  _ => null,
};

/// Stands in for the subtitle icon on the button while the server prepares the track.
class DeferredSubtitleIcon extends StatelessWidget {
  const DeferredSubtitleIcon({super.key});

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));
}

/// The state line above the tracks in the sheet, with "Opnieuw" after a failure.
class DeferredSubtitleNote extends StatelessWidget {
  const DeferredSubtitleNote({super.key, required this.loader});

  final DeferredSubtitleLoader loader;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: loader,
      builder: (context, _) {
        final note = deferredSubtitleNote(loader.status);
        if (note == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Expanded(child: Text(note, style: Theme.of(context).textTheme.bodyMedium)),
              if (loader.status == DeferredSubtitleStatus.failed)
                TextButton(onPressed: loader.retry, child: Text(t.videoControls.subtitlesPrepareRetry)),
            ],
          ),
        );
      },
    );
  }
}

/// The same line as a panel row. It sits below the tracks, so the focus order
/// of the tracks does not depend on whether a retry is on offer.
class TvDeferredSubtitleRow extends StatelessWidget {
  const TvDeferredSubtitleRow({super.key, required this.loader});

  final DeferredSubtitleLoader loader;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: loader,
      builder: (context, _) {
        final note = deferredSubtitleNote(loader.status);
        if (note == null) return const SizedBox.shrink();
        if (loader.status == DeferredSubtitleStatus.preparing) {
          return TvPanelRow(title: note, dimmed: true, canRequestFocus: false);
        }
        return TvPanelRow(
          icon: Symbols.refresh_rounded,
          title: note,
          value: t.videoControls.subtitlesPrepareRetry,
          onSelect: loader.retry,
          automationId: AutomationIds.playerPanelRow,
          automationInstance: 'subtitle.prepare_retry',
        );
      },
    );
  }
}
