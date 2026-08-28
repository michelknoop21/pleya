import 'dart:io';

/// Desktop's `AppLifecycleState.resumed` fires on every window focus
/// (alt-tab), so an unthrottled resume probe would re-run its work on every
/// switch back to the app. Mobile backgrounding is a rarer event (an actual
/// app switch or lock), so it gets a much shorter cooldown.
///
/// Tracks its own "last allowed" timestamp; call [shouldProbe] once per
/// resume event and only act when it returns true.
class ResumeProbeCooldown {
  ResumeProbeCooldown({DateTime? initialLastProbe}) : _lastProbe = initialLastProbe ?? DateTime(0);

  DateTime _lastProbe;

  static const _mobileCooldown = Duration(seconds: 10);
  static const _desktopCooldown = Duration(minutes: 2);

  /// True at most once per cooldown window; a true return starts the next
  /// window over from [now].
  bool shouldProbe({DateTime? now}) {
    final at = now ?? DateTime.now();
    final cooldown = (Platform.isIOS || Platform.isAndroid) ? _mobileCooldown : _desktopCooldown;
    if (at.difference(_lastProbe) < cooldown) return false;
    _lastProbe = at;
    return true;
  }
}
