/// The header of the iPhone library look.
///
/// Back, the library with its server line, then search, watchlist and avatar
/// stay pinned under the status bar, translucent over the grid. The tab row
/// and the filter row leave with the first scroll and float back on the way up,
/// which is what the library header has always done.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/profile_avatar.dart';
import '../../providers/watchlist_provider.dart';
import '../../services/account_ui_actions.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/mobile/library_phone_look.dart';

class MobileLibraryHeader extends StatelessWidget {
  const MobileLibraryHeader({
    super.key,
    required this.title,
    required this.onBack,
    required this.actions,
    required this.filterRow,
    this.tabRow,
    required this.floating,
  });

  /// The library with its dropdown, or the page title while none is open.
  final Widget title;
  final VoidCallback onBack;
  final List<Widget> actions;
  final Widget filterRow;

  /// Null while no library is open: there are no tabs to show.
  final Widget? tabRow;

  /// False on the loading, empty and error states, which have nothing to
  /// scroll back with.
  final bool floating;

  double get _rowsHeight =>
      LibraryPhoneMetrics.filterRowHeight + (tabRow == null ? 0 : LibraryPhoneMetrics.tabRowHeight);

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      automaticallyImplyLeading: false,
      centerTitle: false,
      titleSpacing: 0,
      toolbarHeight: LibraryPhoneMetrics.titleRowHeight,
      collapsedHeight: LibraryPhoneMetrics.titleRowHeight,
      expandedHeight: LibraryPhoneMetrics.titleRowHeight + _rowsHeight,
      pinned: true,
      floating: floating,
      snap: floating,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      title: _TitleRow(title: title, onBack: onBack, actions: actions),
      flexibleSpace: _HeaderBackground(
        rowsHeight: _rowsHeight,
        rows: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tabRow != null) SizedBox(height: LibraryPhoneMetrics.tabRowHeight, child: tabRow),
            filterRow,
          ],
        ),
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.title, required this.onBack, required this.actions});

  final Widget title;
  final VoidCallback onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 8),
      child: Row(
        children: [
          AutomationNode(
            id: AutomationIds.navigationBack,
            role: 'button',
            child: IconButton(onPressed: onBack, icon: const AppIcon(Symbols.arrow_back_rounded, fill: 1)),
          ),
          Expanded(
            child: Align(alignment: AlignmentDirectional.centerStart, child: title),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Fills the whole bar, status bar included, with the blur and tint the library
/// header already used for its capsule, and cuts the rows off at the title row
/// so they slide away beneath it.
class _HeaderBackground extends StatelessWidget {
  const _HeaderBackground({required this.rowsHeight, required this.rows});

  final double rowsHeight;
  final Widget rows;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: LibraryPhoneMetrics.headerBlurSigma,
              sigmaY: LibraryPhoneMetrics.headerBlurSigma,
            ),
            child: ColoredBox(color: tokens(context).bg.withValues(alpha: LibraryPhoneMetrics.headerTintAlpha)),
          ),
        ),
        Positioned(
          top: top + LibraryPhoneMetrics.titleRowHeight,
          left: 0,
          right: 0,
          bottom: 0,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.bottomCenter,
              minHeight: rowsHeight,
              maxHeight: rowsHeight,
              child: rows,
            ),
          ),
        ),
      ],
    );
  }
}

/// Library name, server line and the dropdown chevron, the child of the
/// screen's existing library menu button.
class MobileLibraryTitle extends StatelessWidget {
  const MobileLibraryTitle({super.key, required this.title, this.serverName});

  final String title;
  final String? serverName;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final server = serverName;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tk.text,
                          fontSize: LibraryPhoneMetrics.headerTitleSize,
                          fontWeight: FontWeight.w700,
                          letterSpacing: LibraryPhoneMetrics.letterSpacing,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    AppIcon(Symbols.keyboard_arrow_down_rounded, size: 22, color: tk.textMuted),
                  ],
                ),
                if (server != null && server.isNotEmpty)
                  Text(
                    server,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tk.textMuted,
                      fontSize: LibraryPhoneMetrics.headerServerSize,
                      fontWeight: FontWeight.w400,
                      letterSpacing: LibraryPhoneMetrics.letterSpacing,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Search, watchlist and avatar. An action whose destination does not exist in
/// this session is left out instead of drawn dead: no search callback, or no
/// watchlist on the connected backends.
class MobileLibraryHeaderActions extends StatelessWidget {
  const MobileLibraryHeaderActions({super.key, this.onSearch, this.onWatchlist});

  final VoidCallback? onSearch;
  final VoidCallback? onWatchlist;

  @override
  Widget build(BuildContext context) {
    final hasWatchlist = context.watch<WatchlistProvider?>()?.hasWatchlist ?? false;
    final profile = context.watch<ActiveProfileProvider?>()?.active;
    final search = onSearch;
    final watchlist = onWatchlist;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (search != null)
          AutomationNode(
            id: AutomationIds.libraryHeaderSearch,
            role: 'button',
            child: IconButton(onPressed: search, tooltip: t.common.search, icon: const AppIcon(Symbols.search_rounded)),
          ),
        if (watchlist != null && hasWatchlist)
          AutomationNode(
            id: AutomationIds.libraryHeaderWatchlist,
            role: 'button',
            child: IconButton(
              onPressed: watchlist,
              tooltip: t.watchlist.title,
              icon: const AppIcon(Symbols.bookmarks_rounded, fill: 1),
            ),
          ),
        AutomationNode(
          id: AutomationIds.libraryHeaderAvatar,
          role: 'button',
          child: IconButton(
            onPressed: () => AccountUiActions.openProfiles(context),
            tooltip: t.screens.switchProfile,
            icon: ProfileAvatar(profile: profile, size: 32),
          ),
        ),
      ],
    );
  }
}
