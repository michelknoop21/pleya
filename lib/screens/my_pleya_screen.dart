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
import '../providers/multi_server_provider.dart';
import '../providers/offline_mode_provider.dart';
import '../providers/seerr_provider.dart';
import '../providers/watchlist_provider.dart';
import '../theme/mono_tokens.dart';
import '../watch_together/screens/watch_together_screen.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/media_card_grid_layout.dart';
import '../widgets/settings_section.dart' show settingsOutlineColor;
import '../widgets/watchlist_card.dart';
import 'now_watching_screen.dart';
import 'servers_screen.dart';
import 'settings/about_screen.dart';
import 'tv/tv_my_pleya_screen.dart' show buildTvMyPleyaGroups, TvMyPleyaTile;
import 'tv/tv_my_pleya_sections.dart' show TvMyPleyaSection;

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
///
/// The tile taxonomy (which section exists, its icon, title, subtitle and
/// count) is [buildTvMyPleyaGroups], not reinvented here — TV's own doc
/// comment says a phone list is not a scaled-up 10-foot surface, and that is
/// about the *widget*, not the data behind it. Northstar 18 groups the same
/// tiles differently than TV does (Samen kijken is a list row here, a card on
/// TV), so this screen re-buckets them rather than rendering TV's groups.
class MyPleyaScreen extends StatelessWidget {
  const MyPleyaScreen({super.key, required this.onOpenTab, this.onOpenLibraryPicker});

  /// Jumps to another destination. The same `_selectTab` the bottom bar uses,
  /// so the screens list and the tab state stay in one place.
  final void Function(NavigationTabId tab) onOpenTab;

  /// Opens the library quick picker. On the phone this row is the only thing
  /// left that can: fase 2 took Bibliotheken out of the bottom bar, and the
  /// picker's single entry point was a long-press over that slot, so it left
  /// with it (DEC-104). Null where the bar still holds the slot, and the
  /// long-press is then simply not offered twice.
  ///
  /// Takes a [BuildContext] rather than closing over one, and it has to: the
  /// picker resolves `OverlaySheetController.of(context)`, and `MainScreen`'s
  /// own context sits *above* the `OverlaySheetHost` that provides it. This
  /// screen's context is below it.
  final void Function(BuildContext context)? onOpenLibraryPicker;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ActiveProfileProvider?>()?.active;
    final isOffline = context.watch<OfflineModeProvider?>()?.isOffline ?? false;
    final watchlist = context.watch<WatchlistProvider?>();
    final downloads = context.watch<DownloadProvider?>();
    final hasSeerr = context.watch<SeerrProvider?>()?.isConfigured ?? false;
    final servers = context.watch<MultiServerProvider?>();

    final groups = buildTvMyPleyaGroups(
      hasWatchlist: watchlist?.hasWatchlist ?? false,
      hasSeerr: hasSeerr && !isOffline,
      showDownloads: true,
      showActivity: servers?.hasOnlinePlexServers ?? false,
      watchlistCount: watchlist?.entriesByRecentlyAdded.length,
      downloadCount: downloads == null ? null : downloads.downloadedMovies.length + downloads.downloadedShows.length,
    );
    final tileFor = <TvMyPleyaSection, TvMyPleyaTile>{
      for (final group in groups)
        for (final tile in group.tiles)
          if (tile.section != null) tile.section!: tile,
    };

    return Scaffold(
      body: CustomScrollView(
        clipBehavior: Clip.none,
        slivers: [
          CustomAppBar(title: Text(t.myPleya.title), automaticallyImplyLeading: false),
          SliverToBoxAdapter(
            child: _ProfileHeader(
              profile: profile,
              onSwitchProfile: () => AccountUiActions.openProfiles(context),
              serversLine: (servers?.totalServerCount ?? 0) == 0
                  ? t.tvMyPleya.noServers
                  : t.tvMyPleya.serversOnline(
                      online: '${servers!.onlineServerCount}',
                      total: '${servers.totalServerCount}',
                    ),
            ),
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
          SliverToBoxAdapter(child: _MyPleyaGroupLabel(t.tvMyPleya.groupContent)),
          SliverToBoxAdapter(
            child: _MyPleyaCardRow(
              cards: [
                if (tileFor[TvMyPleyaSection.watchlist] case final tile?)
                  _MyPleyaCard(tile: tile, onTap: () => onOpenTab(NavigationTabId.watchlist)),
                if (tileFor[TvMyPleyaSection.requests] case final tile?)
                  _MyPleyaCard(tile: tile, onTap: () => onOpenTab(NavigationTabId.requests)),
                if (tileFor[TvMyPleyaSection.downloads] case final tile?)
                  _MyPleyaCard(tile: tile, onTap: () => onOpenTab(NavigationTabId.downloads)),
              ],
            ),
          ),
          SliverToBoxAdapter(child: _MyPleyaGroupLabel(t.tvMyPleya.groupSources)),
          SliverToBoxAdapter(
            child: _MyPleyaCardRow(
              cards: [
                if (tileFor[TvMyPleyaSection.libraries] case final tile?)
                  _MyPleyaCard(
                    tile: tile,
                    onTap: () => onOpenTab(NavigationTabId.libraries),
                    onLongPress: onOpenLibraryPicker == null ? null : () => onOpenLibraryPicker!(context),
                  ),
                if (tileFor[TvMyPleyaSection.servers] case final tile?)
                  _MyPleyaCard(
                    tile: tile,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ServersScreen())),
                  ),
                if (tileFor[TvMyPleyaSection.activity] case final tile?)
                  _MyPleyaCard(
                    tile: tile,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NowWatchingScreen())),
                  ),
              ],
            ),
          ),
          SliverToBoxAdapter(child: _MyPleyaGroupLabel(t.tvMyPleya.groupPleya)),
          if (tileFor[TvMyPleyaSection.watchTogether] case final tile?)
            SliverToBoxAdapter(
              child: _SectionRow(
                icon: tile.icon,
                label: tile.title,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WatchTogetherScreen())),
              ),
            ),
          if (tileFor[TvMyPleyaSection.settings] case final tile?)
            SliverToBoxAdapter(
              child: _SectionRow(icon: tile.icon, label: tile.title, onTap: () => onOpenTab(NavigationTabId.settings)),
            ),
          if (tileFor[TvMyPleyaSection.about] case final tile?)
            SliverToBoxAdapter(
              child: _SectionRow(
                icon: tile.icon,
                label: tile.title,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen())),
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
          const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
        ],
      ),
    );
  }
}

/// Avatar, name and the server-status line from northstar 18. Deliberately
/// compact so the kijklijst rail lands in the first screenful instead of
/// below the fold, and so the account actions at the bottom stay secondary to
/// the content between them.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.onSwitchProfile, required this.serversLine});

  final Profile? profile;
  final VoidCallback onSwitchProfile;
  final String serversLine;

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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(profile?.displayName ?? '', style: theme.textTheme.titleMedium),
                        Text(serversLine, style: theme.textTheme.bodySmall),
                      ],
                    ),
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

/// The small caps section heading above a card row or list group
/// ("MIJN CONTENT", "BIBLIOTHEKEN EN BRONNEN", "PLEYA" in northstar 18).
class _MyPleyaGroupLabel extends StatelessWidget {
  const _MyPleyaGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: tokens(context).textMuted, letterSpacing: 0.5),
      ),
    );
  }
}

/// Up to three [_MyPleyaCard]s side by side, evenly split. Fewer cards than
/// three still fill the row rather than leaving a gap on the right, which
/// only happens when a section (Aanvragen, Activiteit) is conditionally gone.
class _MyPleyaCardRow extends StatelessWidget {
  const _MyPleyaCardRow({required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      // IntrinsicHeight, not a bare stretch Row: this row sits in a sliver,
      // where the incoming height constraint is unbounded, and stretch alone
      // asks every card to fill that infinity.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: cards[i])],
          ],
        ),
      ),
    );
  }
}

/// One "Mijn content" / "Bibliotheken en bronnen" tile: icon, optional count
/// top-right, title, subtitle. `surfaceElevated` plus an outline, never a
/// Material container color — those collapse onto the page background in
/// this theme (see [[mono-theme-material-collisions]] in the tvOS gotchas).
class _MyPleyaCard extends StatelessWidget {
  const _MyPleyaCard({required this.tile, required this.onTap, this.onLongPress});

  final TvMyPleyaTile tile;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semanticsLabel = tile.count == null
        ? t.tvMyPleya.semantics.tile(title: tile.title, subtitle: tile.subtitle)
        : t.tvMyPleya.semantics.tileWithCount(title: tile.title, subtitle: tile.subtitle, count: '${tile.count}');

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens(context).surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: settingsOutlineColor(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(tile.icon, size: 22),
                  if (tile.count != null) Text('${tile.count}', style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                tile.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: .bold),
              ),
              const SizedBox(height: 2),
              Text(
                tile.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: tokens(context).textMuted),
              ),
            ],
          ),
        ),
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
