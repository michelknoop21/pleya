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
import '../../services/account_ui_actions.dart';
import '../../theme/glass/glass_settings.dart';
import '../../theme/glass/glass_surface.dart';
import '../../theme/mono_tokens.dart';
import '../app_icon.dart';
import '../pleya_wordmark.dart';

class MobilePageHeader extends StatelessWidget {
  /// Extra actions between the lockup and search/avatar — the header stays
  /// wider than the comp in fase 1 for the three destinations that have not
  /// migrated yet (DEC-102), rather than dropping them silently.
  final List<Widget> actions;

  final VoidCallback onSearchTap;
  final Profile? activeProfile;

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
            // The header sits on the page ground, so the lettering takes the
            // theme ink; white lettering vanishes on the light palette (J18).
            PleyaWordmark(height: 28, letteringColor: tokens(context).text),
            const Spacer(),
            ...actions,
            AutomationNode(
              id: searchAutomationId,
              instance: automationInstance,
              role: 'button',
              // LG-01: a glass circle with Liquid Glass on, the plain button
              // otherwise (GlassSurface renders [child] as-is when off).
              child: GlassLayer(
                tokens: const GlassTokens.control(),
                child: GlassSurface(
                  shape: const CircleBorder(),
                  tokens: const GlassTokens.control(),
                  child: IconButton(
                    onPressed: onSearchTap,
                    icon: const AppIcon(Symbols.search_rounded),
                    tooltip: t.common.search,
                  ),
                ),
              ),
            ),
            // The avatar is the profile switcher, as in the northstar: it opens
            // the same list Mijn Pleya's "Profiel wisselen" does. It used to be
            // a bare image, so tapping it did nothing (Michel, 25 September).
            AutomationNode(
              id: avatarAutomationId,
              instance: automationInstance,
              role: 'button',
              child: IconButton(
                onPressed: () => AccountUiActions.openProfiles(context),
                tooltip: t.screens.switchProfile,
                icon: ProfileAvatar(profile: activeProfile, size: 32),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
