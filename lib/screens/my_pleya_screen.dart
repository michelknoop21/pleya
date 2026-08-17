import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../navigation/navigation_tabs.dart';
import '../profiles/active_profile_provider.dart';
import '../profiles/profile.dart';
import '../profiles/profile_avatar.dart';
import '../services/account_ui_actions.dart';
import '../providers/download_provider.dart';
import '../providers/offline_mode_provider.dart';
import '../providers/seerr_provider.dart';
import '../providers/watchlist_provider.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/media_card_grid_layout.dart';
import '../widgets/watchlist_card.dart';

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
            child: _ProfileHeader(profile: profile, onSwitchProfile: () => AccountUiActions.openProfiles(context)),
          ),
          if (watchlist?.hasWatchlist ?? false) ...[
            SliverToBoxAdapter(
              child: _SectionRow(
                icon: Symbols.bookmark_add_rounded,
                label: t.watchlist.title,
                trailing: t.watchlist.seeAll,
                onTap: () => onOpenTab(NavigationTabId.watchlist),
              ),
            ),
            SliverToBoxAdapter(
              child: _WatchlistRail(provider: watchlist!, onOpenAll: () => onOpenTab(NavigationTabId.watchlist)),
            ),
          ],
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
          // The three actions that used to hang off the avatar in the Home
          // header. They come last and behind a rule: this screen is a content
          // hub first, and account management is what you come here for least
          // often. Each one calls the action that already existed; the mobile
          // entry point moved, the behaviour did not.
          const SliverToBoxAdapter(child: Divider(height: 32, indent: 16, endIndent: 16)),
          SliverToBoxAdapter(
            child: _SectionRow(
              icon: Symbols.group_rounded,
              label: t.profiles.sectionTitle,
              onTap: () => AccountUiActions.openProfiles(context),
            ),
          ),
          SliverToBoxAdapter(
            child: _SectionRow(
              icon: Symbols.settings_rounded,
              label: t.common.settings,
              onTap: () => onOpenTab(NavigationTabId.settings),
            ),
          ),
          SliverToBoxAdapter(
            child: _SectionRow(
              icon: Symbols.logout_rounded,
              label: t.common.logout,
              showChevron: false,
              onTap: () => unawaited(AccountUiActions.logout(context)),
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

/// Avatar and name. Deliberately compact so the kijklijst rail lands in the
/// first screenful instead of below the fold, and so the account actions at the
/// bottom stay secondary to the content between them.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.onSwitchProfile});

  final Profile? profile;
  final VoidCallback onSwitchProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
      child: Row(
        children: [
          // The avatar and the name read as an identity, not as a control, so
          // what it does is said out loud for anyone who cannot see that
          // tapping it leads to the profile picker.
          Semantics(
            button: true,
            label: t.screens.switchProfile,
            child: InkWell(
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
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback onTap;

  /// Off for a row that acts instead of navigating, so a chevron cannot
  /// promise a screen that never opens. Sign out is the only such row.
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    if (!showChevron) {
      return ListTile(leading: Icon(icon), title: Text(label), onTap: onTap);
    }
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

/// A short horizontal preview of the kijklijst, with the full screen one tap
/// away.
///
/// The rail deliberately does not resolve availability. That work belongs to
/// the full screen, where the user is actually looking at the list; doing it
/// here would fan out lookups every time someone opens My Pleya to reach their
/// downloads.
class _WatchlistRail extends StatelessWidget {
  const _WatchlistRail({required this.provider, required this.onOpenAll});

  final WatchlistProvider provider;
  final VoidCallback onOpenAll;

  /// How many posters the rail shows before "See all" takes over.
  static const int maxItems = 12;

  static const double _posterWidth = 104;

  @override
  Widget build(BuildContext context) {
    final entries = provider.entriesByRecentlyAdded.take(maxItems).toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    // Same contract the kijklijst grid uses: a 2:3 poster plus the caption
    // MediaCard draws underneath it.
    final height = MediaCardGridLayout.cardHeightFor(context, _posterWidth);
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: entries.length,
        separatorBuilder: (context, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) => WatchlistCard(
          entry: entries[index],
          isPlayable: provider.isPlayable(entries[index]),
          onTap: onOpenAll,
          width: _posterWidth,
        ),
      ),
    );
  }
}
