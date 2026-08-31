import 'package:flutter/material.dart';
import 'package:pleya/navigation/profile_navigation_scope.dart';

Widget withProfileNavigationScope({required Widget child, RouteObserver<PageRoute<dynamic>>? routeObserver}) {
  return ProfileNavigationScope(
    navigatorKey: GlobalKey<NavigatorState>(),
    routeObserver: routeObserver ?? RouteObserver<PageRoute<dynamic>>(),
    mainScaffoldMessengerKey: GlobalKey<ScaffoldMessengerState>(),
    child: child,
  );
}
