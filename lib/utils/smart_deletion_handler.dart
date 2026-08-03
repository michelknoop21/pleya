import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../i18n/strings.g.dart';
import '../providers/download_provider.dart';
import '../widgets/deletion_progress_dialog.dart';

class SmartDeletionHandler {
  /// Execute deletion with smart progress dialog
  /// Only shows dialog if deletion takes longer than delayMs
  static Future<void> deleteWithProgress({
    required BuildContext context,
    required DownloadProvider provider,
    required String globalKey,
    int delayMs = 500,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: false);
    DialogRoute<void>? progressRoute;
    var deletionComplete = false;

    // Removes exactly the progress route. The old code popped the *screen's*
    // nearest route behind a `Navigator.canPop` guard, which could take out the
    // wrong route entirely — or, when the delayed dialog lost the race with
    // `finally`, leave a dialog up that nothing would ever close again.
    void closeDialog() {
      final route = progressRoute;
      if (route == null) return;
      progressRoute = null;
      if (route.isActive) navigator.removeRoute(route);
    }

    final timer = Timer(Duration(milliseconds: delayMs), () {
      // The completion flag is the race guard: without it a deletion that
      // finished at delayMs-epsilon still opened a permanent dialog.
      if (deletionComplete || !context.mounted) return;
      progressRoute = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        themes: InheritedTheme.capture(from: context, to: navigator.context),
        builder: (_) => _DeletionProgressHost(globalKey: globalKey, onClose: closeDialog),
      );
      unawaited(navigator.push(progressRoute!));
    });

    try {
      await provider.deleteDownload(globalKey);
    } finally {
      deletionComplete = true;
      timer.cancel();
      closeDialog();
    }
  }
}

class _DeletionProgressHost extends StatelessWidget {
  const _DeletionProgressHost({required this.globalKey, required this.onClose});

  final String globalKey;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadProvider>(
      builder: (context, provider, child) {
        final progress = provider.getDeletionProgress(globalKey);
        if (progress == null) {
          return DeletionProgressDialog(progress: null, onClose: onClose, indeterminateLabel: t.downloads.deleting);
        }
        return DeletionProgressDialog(progress: progress, onClose: onClose);
      },
    );
  }
}
