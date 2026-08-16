import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../navigation/navigation_tabs.dart';
import '../profiles/active_profile_provider.dart';
import '../profiles/profile.dart';
import '../profiles/profile_avatar.dart';
import 'profile/profile_switch_screen.dart';
import '../providers/download_provider.dart';
import '../providers/offline_mode_provider.dart';
import '../providers/seerr_provider.dart';
import '../providers/watchlist_provider.dart';
import '../widgets/desktop_app_bar.dart';

/// The personal corner of the mobile app.
///
/// A phone bottom bar holds five destinations before it needs an overflow
/// menu, and Home, Libraries, Live TV and Search already claim four of them.
/// Rather than hiding a feature behind a menu, the personal destinations move
/// together into one place: the profile, the kijklijst, downloads and requests.
///
/// It exists on every mobile session, with or without a watchlist, because it
/// is also the only route to Downloads, Requests and Settings there. Only its
/// sections come and go.
///
/// Desktop and TV do not get this screen. Their sidebar has room for all of it
/// as first-class destinations, and duplicating the structure would be a second
/// information architecture for no gain.
class MyPleyaScreen extends StatelessWidget {
  const MyPleyaScreen({super.key, required this.onOpenTab});

  /// Jumps to another destination. The same `_selectTab` the bottom bar uses,
  /// so the screens list and the tab state stay in one place.
  final void Function(NavigationTabId tab) onOpenTab;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ActiveProfileProvider?>()?.active;
    final isOffline = context.watch<OfflineModeProvider?>()?.isOffline ?? false;
    final watchlist = context.watch<WatchlistProvider?>();
    final downloads = context.watch<DownloadProvider?>();
    final hasSeerr = context.watch<SeerrProvider?>()?.isConfigured ?? false;

    return Scaffold(
      body: CustomScrollView(
        clipBehavior: Clip.none,
        slivers: [
          CustomAppBar(title: Text(t.myPleya.title), automaticallyImplyLeading: false),
          SliverToBoxAdapter(
            child: _ProfileHeader(
              profile: profile,
              onOpenSettings: () => onOpenTab(NavigationTabId.settings),
              onSwitchProfile: () => Navigator.of(
                context,
                rootNavigator: true,
              ).push(MaterialPageRoute(builder: (_) => const ProfileSwitchScreen())),
            ),
          ),
          if (watchlist?.hasWatchlist ?? false)
            SliverToBoxAdapter(
              child: _SectionRow(
                icon: Symbols.bookmark_add_rounded,
                label: t.watchlist.title,
                trailing: t.watchlist.seeAll,
                onTap: () => onOpenTab(NavigationTabId.watchlist),
              ),
            ),
          SliverToBoxAdapter(
            child: _SectionRow(
              icon: Symbols.download_rounded,
              label: t.navigation.downloads,
              trailing: _downloadsSubtitle(downloads),
              onTap: () => onOpenTab(NavigationTabId.downloads),
            ),
          ),
          // Requests needs a live Seerr session, so it is the one section that
          // disappears offline rather than degrading.
          if (hasSeerr && !isOffline)
            SliverToBoxAdapter(
              child: _SectionRow(
                icon: Symbols.playlist_add_rounded,
                label: t.seerr.title,
                onTap: () => onOpenTab(NavigationTabId.requests),
              ),
            ),
        ],
      ),
    );
  }

  static String? _downloadsSubtitle(DownloadProvider? downloads) {
    if (downloads == null) return null;
    final count = downloads.downloadedMovies.length + downloads.downloadedShows.length;
    return count == 0 ? null : t.myPleya.downloadsCount(n: count);
  }
}

/// Avatar, name and a gear. Deliberately compact so the kijklijst rail lands
/// in the first screenful instead of below the fold.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.onOpenSettings, required this.onSwitchProfile});

  final Profile? profile;
  final VoidCallback onOpenSettings;
  final VoidCallback onSwitchProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
      child: Row(
        children: [
          InkWell(
            onTap: onSwitchProfile,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  ProfileAvatar(profile: profile, size: 40),
                  const SizedBox(width: 12),
                  Text(profile?.displayName ?? '', style: theme.textTheme.titleMedium),
                ],
              ),
            ),
          ),
          const Spacer(),
          IconButton(onPressed: onOpenSettings, icon: const Icon(Symbols.settings_rounded), tooltip: t.common.settings),
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.icon, required this.label, required this.onTap, this.trailing});

  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: trailing == null
          ? const Icon(Symbols.chevron_right_rounded)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(trailing!, style: Theme.of(context).textTheme.bodySmall),
                const Icon(Symbols.chevron_right_rounded),
              ],
            ),
      onTap: onTap,
    );
  }
}
