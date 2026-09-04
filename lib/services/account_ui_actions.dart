import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connection/connection_registry.dart';
import '../i18n/strings.g.dart';
import '../profiles/plex_home_service.dart';
import '../profiles/profile_connection_registry.dart';
import '../profiles/profile_registry.dart';
import '../providers/companion_remote_provider.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/multi_server_provider.dart';
import '../providers/playback_state_provider.dart';
import '../providers/user_profile_provider.dart';
import '../screens/auth_screen.dart';
import '../screens/profile/profile_switch_screen.dart';
import '../utils/dialogs.dart';
import 'storage_service.dart';

/// The account actions that used to live only behind the avatar in the Home
/// header: switch or manage profiles, and sign out.
///
/// Extracted when My Pleya became the personal destination on mobile. Both
/// entry points now come through this one door, so signing out cannot drift
/// into two implementations that clear different things, and the list of
/// things it clears is long enough that a second copy would.
///
/// Same split as [WatchlistUiActions]: everything that needs a
/// [BuildContext] lives here, nothing else does.
class AccountUiActions {
  AccountUiActions._();

  /// Open the profile list: switch, manage, add, or sign a Plex account out.
  ///
  /// Deliberately not a "quick switch" of its own. [ProfileSwitchScreen]
  /// without `requireSelection` is the management variant, and it already
  /// carries switching, the PIN flow, per-profile manage/delete and adding a
  /// Pleya profile. A second, thinner switcher would be a second place to keep
  /// the PIN prompt correct.
  /// Returns when the picker is closed, so a caller that has to bracket the
  /// visit — the TV shell hands tvOS's Menu button back and forth around it —
  /// can await it instead of guessing.
  static Future<void> openProfiles(BuildContext context) {
    return Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (context) => const ProfileSwitchScreen()));
  }

  /// Confirm, then clear every trace of the session and return to sign-in.
  ///
  /// The order matters: the companion remote goes first because it holds a
  /// live socket, and the registries go before storage because clearing a
  /// registry writes to it. Plex is never asked to revoke the token, the same
  /// choice `_signOutPlexAccount` makes in [ProfileSwitchScreen].
  static Future<void> logout(BuildContext context) async {
    final confirm = await showConfirmDialog(
      context,
      title: t.common.logout,
      message: t.messages.logoutConfirm,
      confirmText: t.common.logout,
      isDestructive: true,
    );
    if (!confirm || !context.mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    final userProfileProvider = context.read<UserProfileProvider>();
    final multiServerProvider = context.read<MultiServerProvider>();
    final hiddenLibrariesProvider = context.read<HiddenLibrariesProvider>();
    final playbackStateProvider = context.read<PlaybackStateProvider>();
    final connectionRegistry = context.read<ConnectionRegistry>();
    final profileRegistry = context.read<ProfileRegistry>();
    final profileConnReg = context.read<ProfileConnectionRegistry>();
    final plexHome = context.read<PlexHomeService>();
    final companionRemote = context.read<CompanionRemoteProvider>();

    // Clear all user data and provider states
    await companionRemote.resetForLogout();
    await userProfileProvider.logout();
    multiServerProvider.clearAllConnections();
    // Drop the profile/connection rows so the next sign-in starts clean
    // and doesn't bind to stale tokens or orphaned profile rows.
    await profileConnReg.clear();
    await profileRegistry.clear();
    await connectionRegistry.clear();
    await plexHome.clearAll();
    final storage = await StorageService.getInstance();
    await storage.clearActiveProfileId();
    await storage.clearAllProfileLastUsed();
    await hiddenLibrariesProvider.refresh();
    playbackStateProvider.clearShuffle();

    if (navigator.mounted) {
      unawaited(
        navigator.pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const AuthScreen()), (route) => false),
      );
    }
  }
}
