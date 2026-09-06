/// Pull-to-refresh, shared by Home, the fase-2 landings, Mijn lijst and
/// Downloads (iOS Unified 2026 fase 1, `docs/ios-unified-2026-fase1-plan.md`
/// stap 5). Same pattern as `base_library_tab.dart`'s existing
/// `RefreshIndicator`, factored out so every mobile surface gets the haptic
/// tick for free instead of re-deriving it.
library;

import 'package:flutter/material.dart';

import '../../utils/haptics.dart';

class MobileRefreshScope extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;

  const MobileRefreshScope({super.key, required this.onRefresh, required this.child});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () {
        Haptics.light();
        return onRefresh();
      },
      child: child,
    );
  }
}
