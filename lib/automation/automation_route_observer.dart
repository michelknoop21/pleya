import 'package:flutter/widgets.dart';

import 'automation_event_log.dart';
import 'pleya_verify.dart';

/// Emits `screen.changed` on every push/pop/replace.
///
/// Most routes in this app are unnamed (see CLAUDE.md's note that only
/// `kVideoPlayerRouteName` exists), so `to`/`from` are frequently null —
/// still a real, useful signal: the small number of named routes resolve
/// directly, and an unnamed transition still proves *that* navigation
/// happened, which `media-detail.episode-refresh`'s "no screen.changed to
/// screen.libraries happened" assertion depends on.
class AutomationRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  void _emit(String reason, Route<dynamic>? route, Route<dynamic>? previousRoute) {
    if (!kPleyaVerify) return;
    AutomationEventLog.instance.emit('screen.changed', {
      'reason': reason,
      'to': ?route?.settings.name,
      'from': ?previousRoute?.settings.name,
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _emit('push', route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _emit('pop', route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _emit('replace', newRoute, oldRoute);
  }
}
