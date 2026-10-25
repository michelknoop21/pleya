import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../automation/automation_ids.dart';
import '../automation/automation_node.dart';
import '../automation/automation_screen.dart';
import '../i18n/strings.g.dart';
import '../media/ids.dart';
import '../media/watchlist_entry.dart';
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
import '../utils/media_image_helper.dart';
import '../utils/media_navigation_helper.dart';
import '../utils/provider_extensions.dart';
import '../watch_together/screens/watch_together_screen.dart';
import '../widgets/big_p/big_p_rig.dart' show bigPAsset;
import '../widgets/optimized_media_image.dart';
import '../widgets/pleya_logo.dart';
import '../widgets/watched_indicator.dart';
import 'big_p/big_p_ask_row.dart' show summonableBigP;
import 'big_p/big_p_mobile_session.dart';
import 'now_watching_screen.dart';
import 'servers_screen.dart';
import 'settings/about_screen.dart';
import 'tv/tv_my_pleya_screen.dart' show buildTvMyPleyaGroups, TvMyPleyaTile;
import 'tv/tv_my_pleya_sections.dart' show TvMyPleyaSection;
import '../widgets/scroll_crown/scroll_crown.dart';

part 'my_pleya_cards.dart';
part 'my_pleya_watchlist_rail.dart';

/// The personal corner of the mobile app, in the Editorial layout of A-24b
/// (northstar `02-Mijn-Pleya/images/00-ios-geselecteerd.png`).
///
/// A phone bottom bar holds five destinations before it needs an overflow
/// menu, so the personal destinations live together here: the profile, the
/// kijklijst, downloads, requests, Big P and the account actions.
///
/// It exists on every mobile session, with or without a watchlist, because it
/// is also the only route to Downloads, Requests and Settings there. Only its
/// sections come and go.
///
/// Desktop and TV do not get this screen. Their sidebar has room for all of it
/// as first-class destinations.
///
/// Which section exists (and its icon and count) is [buildTvMyPleyaGroups];
/// this screen only decides where it shows. The layout is the northstar's:
/// title with the Pleya mark, a profile line, the kijklijst as posters, Jouw
/// content as quiet rows, the Big P card, and the Pleya group as rows.
class MyPleyaScreen extends StatefulWidget {
  const MyPleyaScreen({super.key, required this.onOpenTab, this.onOpenLibraryPicker});

  /// Jumps to another destination. The same `_selectTab` the bottom bar uses,
  /// so the screens list and the tab state stay in one place.
  final void Function(NavigationTabId tab) onOpenTab;

  /// Opens the library quick picker from a long press on Bibliotheken. Null
  /// where the bar still holds the libraries slot (DEC-104).
  ///
  /// Takes a [BuildContext]: the picker resolves `OverlaySheetController.of`,
  /// which sits below `MainScreen`'s own context.
  final void Function(BuildContext context)? onOpenLibraryPicker;

  @override
  State<MyPleyaScreen> createState() => _MyPleyaScreenState();
}

class _MyPleyaScreenState extends State<MyPleyaScreen> {
  @override
  void initState() {
    super.initState();
    // Big P's card depends on entitlement, servers and the model config,
    // which the controller works out only when asked.
    unawaited(context.read<BigPMobileSession?>()?.controller.refreshAvailability());
  }

  void _push(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ActiveProfileProvider?>()?.active;
    final isOffline = context.watch<OfflineModeProvider?>()?.isOffline ?? false;
    final watchlist = context.watch<WatchlistProvider?>();
    final downloads = context.watch<DownloadProvider?>();
    final hasSeerr = context.watch<SeerrProvider?>()?.isConfigured ?? false;
    final servers = context.watch<MultiServerProvider?>();
    final bigP = summonableBigP(context);

    final groups = buildTvMyPleyaGroups(
      hasWatchlist: watchlist?.hasWatchlist ?? false,
      hasSeerr: hasSeerr && !isOffline,
      showDownloads: true,
      showActivity: servers?.hasOnlinePlexServers ?? false,
      showCollections: false,
      showPlaylists: false,
      showAssistant: bigP != null,
      watchlistCount: watchlist?.entriesByRecentlyAdded.length,
      downloadCount: downloads == null ? null : downloads.downloadedMovies.length + downloads.downloadedShows.length,
    );
    final tileFor = <TvMyPleyaSection, TvMyPleyaTile>{
      for (final group in groups)
        for (final tile in group.tiles)
          if (tile.section != null) tile.section!: tile,
    };
    final online = servers?.onlineServerCount ?? 0;
    final total = servers?.totalServerCount ?? 0;

    Widget? row(
      TvMyPleyaSection section, {
      required String subtitle,
      required VoidCallback onTap,
      String? title,
      VoidCallback? onLongPress,
    }) {
      final tile = tileFor[section];
      if (tile == null) return null;
      return _MyPleyaRow(
        instance: section.name,
        icon: tile.icon,
        title: title ?? tile.title,
        subtitle: subtitle,
        count: tile.count,
        onTap: onTap,
        onLongPress: onLongPress,
      );
    }

    final contentRows = [
      row(
        TvMyPleyaSection.libraries,
        subtitle: t.myPleya.librariesSubtitle,
        onTap: () => widget.onOpenTab(NavigationTabId.libraries),
        onLongPress: widget.onOpenLibraryPicker == null ? null : () => widget.onOpenLibraryPicker!(context),
      ),
      row(
        TvMyPleyaSection.downloads,
        subtitle: t.myPleya.downloadsSubtitle,
        onTap: () => widget.onOpenTab(NavigationTabId.downloads),
      ),
      row(
        TvMyPleyaSection.requests,
        subtitle: t.myPleya.requestsSubtitle,
        onTap: () => widget.onOpenTab(NavigationTabId.requests),
      ),
    ].nonNulls.toList();

    final pleyaRows = [
      row(
        TvMyPleyaSection.servers,
        subtitle: total == 0 ? t.tvMyPleya.noServers : t.myPleya.serversOnline(count: '$online'),
        onTap: () => _push(const ServersScreen()),
      ),
      row(
        TvMyPleyaSection.activity,
        subtitle: t.myPleya.activitySubtitle,
        onTap: () => _push(const NowWatchingScreen()),
      ),
      row(
        TvMyPleyaSection.watchTogether,
        title: t.myPleya.watchTogether,
        subtitle: t.myPleya.watchTogetherSubtitle,
        onTap: () => _push(const WatchTogetherScreen()),
      ),
      row(
        TvMyPleyaSection.settings,
        subtitle: t.myPleya.settingsSubtitle,
        // A tab switch, not a push: the bar keeps My Pleya lit under Settings.
        onTap: () => widget.onOpenTab(NavigationTabId.settings),
      ),
      row(
        TvMyPleyaSection.about,
        title: t.settings.about,
        subtitle: t.myPleya.aboutSubtitle,
        onTap: () => _push(const AboutScreen()),
      ),
      _MyPleyaRow(
        instance: 'logout',
        icon: Symbols.logout_rounded,
        title: t.common.logout,
        subtitle: t.tvMyPleya.logoutSubtitle,
        destructive: true,
        onTap: () => unawaited(AccountUiActions.logout(context)),
      ),
    ].nonNulls.toList();

    // Same screen id TV's hub uses: the two never mount together.
    return AutomationScreen(
      id: AutomationIds.screenMyPleya,
      readiness: () => const AutomationReadiness.ready(),
      child: Scaffold(
        body: ScrollCrown(
          child: CustomScrollView(
            clipBehavior: Clip.none,
            slivers: [
              const SliverToBoxAdapter(child: _MyPleyaTitle()),
              SliverToBoxAdapter(
                child: _ProfileHeader(
                  profile: profile,
                  onSwitchProfile: () => AccountUiActions.openProfiles(context),
                  serversLine: total == 0
                      ? t.tvMyPleya.noServers
                      : t.tvMyPleya.serversOnline(online: '$online', total: '$total'),
                ),
              ),
              if (watchlist != null && watchlist.hasWatchlist) ...[
                SliverToBoxAdapter(
                  child: _MyPleyaGroupLabel(
                    t.settingsStudio.yourWatchlist,
                    action: _SeeAllLink(onTap: () => widget.onOpenTab(NavigationTabId.watchlist)),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _WatchlistRail(
                    provider: watchlist,
                    onOpenAll: () => widget.onOpenTab(NavigationTabId.watchlist),
                  ),
                ),
              ],
              SliverToBoxAdapter(child: _MyPleyaGroupLabel(t.settingsStudio.yourContent)),
              SliverToBoxAdapter(child: _MyPleyaRowList(rows: contentRows)),
              if ((tileFor[TvMyPleyaSection.assistant], bigP) case (final _?, final session?))
                SliverToBoxAdapter(child: _BigPCard(onTap: () => session.summon())),
              SliverToBoxAdapter(child: _MyPleyaGroupLabel(t.tvMyPleya.groupPleya)),
              SliverToBoxAdapter(child: _MyPleyaRowList(rows: pleyaRows)),
              // Clears the floating glass tab bar: with glass on the main Scaffold
              // extends the body under it and reports its height as bottom padding.
              SliverPadding(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 16)),
            ],
          ),
        ),
      ),
    );
  }
}
