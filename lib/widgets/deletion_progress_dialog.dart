import 'package:flutter/material.dart';
import '../focus/focusable_button.dart';
import '../models/download_models.dart';
import '../i18n/strings.g.dart';

class DeletionProgressDialog extends StatelessWidget {
  /// `null` while the provider has not reported per-item progress yet — the
  /// dialog then shows an indeterminate spinner with [indeterminateLabel].
  final DeletionProgress? progress;

  /// Dismisses the dialog. Always wired to a focusable button and to BACK, so
  /// a deletion that stalls on a hanging server is never a dead end.
  final VoidCallback? onClose;

  final String? indeterminateLabel;

  const DeletionProgressDialog({super.key, required this.progress, this.onClose, this.indeterminateLabel});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final progress = this.progress;

    return PopScope(
      // Still no bare system-back pop (that would leave the route bookkeeping
      // in the handler stale) — the callback routes BACK to the same close
      // path the button uses.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onClose?.call();
      },
      child: AlertDialog(
        content: Column(
          mainAxisSize: .min,
          children: [
            const SizedBox(width: 48, height: 48, child: CircularProgressIndicator()),

            const SizedBox(height: 24),

            if (progress == null)
              Text(
                indeterminateLabel ?? t.downloads.deleting,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              )
            else ...[
              Text(
                t.downloads.deletingWithProgress(
                  title: progress.itemTitle,
                  current: progress.currentItem,
                  total: progress.totalItems,
                ),
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              LinearProgressIndicator(value: progress.progressPercent),

              const SizedBox(height: 8),

              Text('${progress.progressPercentInt}%', style: Theme.of(context).textTheme.bodySmall),

              if (progress.currentOperation != null) ...[
                const SizedBox(height: 8),
                Text(
                  progress.currentOperation!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ],
        ),
        actions: onClose == null
            ? null
            : [
                FocusableButton(
                  autofocus: true,
                  onPressed: onClose,
                  child: TextButton(onPressed: onClose, child: Text(t.common.close)),
                ),
              ],
      ),
    );
  }
}
