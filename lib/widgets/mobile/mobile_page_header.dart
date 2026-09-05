/// The mobile Home header: the Pleya lockup, an optional band of
/// caller-supplied actions, then search and the profile avatar. iOS Unified
/// 2026 fase 1, `docs/ios-unified-2026-fase1-plan.md` stap 5.
///
/// Deliberately never [PleyaLogo] or a typed "PLEYA" — the northstar's
/// header carries the two-layer lockup (rapport §3), and this is the one
/// place that draws it on mobile.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_avatar.dart';
import '../app_icon.dart';
import '../pleya_wordmark.dart';

class MobilePageHeader extends StatelessWidget {
  /// Extra actions between the lockup and search/avatar — the header stays
  /// wider than the comp in fase 1 for the three destinations that have not
  /// migrated yet (DEC-091), rather than dropping them silently.
  final List<Widget> actions;

  final VoidCallback onSearchTap;
  final Profile? activeProfile;
  final VoidCallback? onAvatarTap;

  /// Automation ids for this instance of the header, defaulting to Home's.
  ///
  /// The landings mount their own set rather than reusing Home's. Home, Series
  /// and Films are all children of the same `IndexedStack`, so all three
  /// headers are mounted at once, and the automation registry holds offstage
  /// nodes too: three headers claiming `home.header` would resolve as
  /// `home.header`, `home.header#2` and `home.header#3`, and a scenario would
  /// get whichever came first. That is the collision [AutomationIds.myPleyaSectionTile]
  /// documents, one surface further along.
  final String automationId;
  final String searchAutomationId;
  final String avatarAutomationId;

  /// Suffix distinguishing two headers that share an id set, i.e. the Series
  /// and Films landings.
  final String? automationInstance;

  const MobilePageHeader({
    super.key,
    this.actions = const [],
    required this.onSearchTap,
    required this.activeProfile,
    this.onAvatarTap,
    this.automationId = AutomationIds.homeHeader,
    this.searchAutomationId = AutomationIds.homeHeaderSearch,
    this.avatarAutomationId = AutomationIds.homeHeaderAvatar,
    this.automationInstance,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.viewPaddingOf(context).top;
    return AutomationNode(
      id: automationId,
      instance: automationInstance,
      role: 'region',
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: topInset + 12, bottom: 12),
        child: Row(
          children: [
            const PleyaWordmark(height: 28),
            const Spacer(),
            ...actions,
            AutomationNode(
              id: searchAutomationId,
              instance: automationInstance,
              role: 'button',
              child: IconButton(
                onPressed: onSearchTap,
                icon: const AppIcon(Symbols.search_rounded),
                tooltip: t.common.search,
              ),
            ),
            AutomationNode(
              id: avatarAutomationId,
              instance: automationInstance,
              role: 'button',
              child: GestureDetector(
                onTap: onAvatarTap,
                child: ProfileAvatar(profile: activeProfile, size: 32),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
