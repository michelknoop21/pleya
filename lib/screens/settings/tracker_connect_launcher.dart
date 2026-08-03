import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../focus/input_mode_tracker.dart';
import '../../i18n/strings.g.dart';
import '../../utils/app_logger.dart';
import '../../utils/snackbar_helper.dart';

/// Shared "connect this tracker" launcher.
///
/// Handles the busy/already-connected guard, shows the service's code dialog
/// once `connect` hands us a payload, auto-launches the browser on pointer
/// platforms, closes the dialog when the flow resolves, and surfaces a failure
/// snack. Service-specific pieces are supplied via [connect], [buildDialog],
/// and [urlFor] so both `TrackersProvider`-backed and `TraktAccountProvider`-
/// backed flows share one code path.
Future<void> launchTrackerConnect<T>(
  BuildContext context, {
  required bool isBusyOrConnected,
  required String serviceName,
  required Future<bool> Function(void Function(T)) connect,
  required VoidCallback onCancel,
  required Widget Function(T payload, VoidCallback onCancel) buildDialog,
  required String Function(T payload) urlFor,
}) async {
  if (isBusyOrConnected) return;

  final autoLaunchBrowser = !InputModeTracker.isKeyboardMode(context);
  final navigator = Navigator.of(context, rootNavigator: false);
  DialogRoute<void>? codeRoute;

  // Removes exactly the code dialog, never "whatever is on top". The previous
  // `Navigator.pop(context)` used the *screen's* context, so a snackbar-less
  // race could pop the settings screen out from under the user instead.
  void closeCodeDialog() {
    final route = codeRoute;
    if (route == null) return;
    codeRoute = null;
    if (route.isActive) navigator.removeRoute(route);
  }

  final ok = await connect((payload) {
    if (!context.mounted) return;
    codeRoute = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: (_) => buildDialog(payload, () {
        closeCodeDialog();
        onCancel();
      }),
    );
    unawaited(navigator.push(codeRoute!));
    if (autoLaunchBrowser) {
      unawaited(
        launchUrl(Uri.parse(urlFor(payload)), mode: LaunchMode.externalApplication).catchError((Object e) {
          appLogger.d('$serviceName: failed to auto-launch browser', error: e);
          return false;
        }),
      );
    }
  });

  // Always tear the dialog down, mounted or not: the route reference stays
  // valid even when the originating screen is gone.
  closeCodeDialog();
  if (!context.mounted) return;
  if (!ok) {
    showAppSnackBar(context, t.trackers.connectFailed(service: serviceName));
  }
}
