/// Mijn Pleya on TV, the personal viewing space of A-24c (northstar
/// `docs/assets/a24c-northstars/02-Mijn-Pleya-v4/images/A10-mijn-pleya-dark.png`).
///
/// The mobile [MyPleyaScreen] is a phone list; this is the ten-foot page. Both
/// read the same kijklijst and Big P rules (`my_pleya_shared.dart`) and the
/// same [TvMyPleyaSection] routes, so the two platforms open the same screens
/// under the same names.
///
/// Composition, top to bottom: the heading (`Jouw wereld, <naam>.` with its
/// line underneath), then Big P large on the left as one focus object and the
/// kijklijst once on the right as a poster rail with `Bekijk alles`, then one
/// fixed row `Snel naar` with the daily destinations. There is no Beheer column
/// and no profile block: Instellingen is a destination in the top navigation,
/// and switching profile or signing out lives behind the avatar there
/// (`showTvAccountMenu`).
///
/// **Every tile opens something that already exists** (`pariteit-v4.csv`).
/// Conditional tiles close up rather than render disabled, so a profile
/// without Seerr or Tautulli gets a shorter row and no empty places (`A15`).
///
/// **Type.** Measured in HIG points ([TvHig.of]), which land 1:1 on the
/// 1920 x 1080 canvas the northstar is drawn on, and never under the 23 pt
/// tvOS minimum: the northstar's small capitals are drawn at about 17, and
/// the layout makes room for them at 23 instead.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../assistant/assistant_controller.dart';
import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../automation/automation_screen.dart';
import '../../focus/focus_memory_tracker.dart';
import '../../focus/focus_theme.dart';
import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../media/watchlist_entry.dart';
import '../../mixins/refreshable.dart';
import '../../profiles/active_profile_provider.dart';
import '../../providers/now_watching_provider.dart';
import '../../providers/personal_media_provider.dart';
import '../../providers/seerr_provider.dart';
import '../../providers/watchlist_provider.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../utils/media_navigation_helper.dart';
import '../../utils/platform_detector.dart';
import '../../utils/tv_hig.dart';
import '../../widgets/big_p/big_p_rig.dart' show bigPAsset;
import '../../widgets/tv/tv_catalog_card.dart' show TvCatalogWatchedBadge;
import '../../widgets/tv/tv_unified_layout.dart';
import '../../widgets/tv/tv_watchlist_card.dart' show tvWatchlistSemanticLabel;
import '../my_pleya_shared.dart';
import 'tv_my_pleya_dock.dart';
import 'tv_my_pleya_groups.dart';
import 'tv_my_pleya_sections.dart';

export 'tv_my_pleya_dock.dart';
export 'tv_my_pleya_groups.dart';

part 'tv_my_pleya_big_p.dart';
part 'tv_my_pleya_focus.dart';
part 'tv_my_pleya_header.dart';
part 'tv_my_pleya_tiles.dart';
part 'tv_my_pleya_watchlist.dart';

class TvMyPleyaScreen extends StatefulWidget {
  const TvMyPleyaScreen({super.key, required this.onOpenSection, required this.onExitUp});

  final ValueChanged<TvMyPleyaSection> onOpenSection;

  /// UP out of the top row, back to the top navigation (hoofdstuk 7.5 step 4).
  final VoidCallback onExitUp;

  @override
  State<TvMyPleyaScreen> createState() => TvMyPleyaScreenState();
}

class TvMyPleyaScreenState extends State<TvMyPleyaScreen> implements FocusableTab {
  /// The sections that have a way in as of the last build. OFF6: the shell
  /// asks this after a rebind, to close a section that no longer exists.
  /// Kijklijst counts while the page offers it, as the rail's `Bekijk alles`.
  Set<TvMyPleyaSection> get availableSections => _availableSections;
  Set<TvMyPleyaSection> _availableSections = const {};

  /// Owned by the state, not rebuilt per frame: a watchlist count arriving or a
  /// server going offline must not dispose the node the remote is standing on.
  final FocusMemoryTracker nodes = FocusMemoryTracker(debugLabelPrefix: 'tvMyPleya');
  final Map<String, String> _cameFrom = {};

  /// The first content action of the last build: Big P when he is offered,
  /// otherwise the first poster, `Bekijk alles` or the first tile.
  String? _firstKey;

  @override
  void initState() {
    super.initState();
    // Big P's card depends on entitlement, servers and the provider config;
    // the controller computes that only when an entry point asks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(context.read<AssistantController?>()?.refreshAvailability());
    });
  }

  @override
  void dispose() {
    nodes.dispose();
    super.dispose();
  }

  /// DOWN out of the top navigation. Restores the last position on this page
  /// where there is one, so leaving Mijn Pleya and coming back does not reset
  /// the remote (hoofdstuk 7.6); the first visit lands on Big P.
  @override
  void focusActiveTabIfReady() {
    final last = nodes.lastFocusedKey;
    if (last != null && nodes.nodeFor(last)?.context != null) {
      focusKey(last);
    } else {
      focusKey(_firstKey);
    }
  }

  /// Puts the focus on [key] if it can take it. Public so the shell can restore
  /// the tile a nested section was opened from.
  void focusKey(String? key) {
    if (key == null) return;
    final node = nodes.get(key);
    if (node.canRequestFocus) node.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final pt = TvHig.of(context);
    final profile = context.watch<ActiveProfileProvider?>()?.active;
    final watchlist = context.watch<WatchlistProvider?>();
    final personalMedia = context.watch<PersonalMediaProvider?>();
    final showBigP =
        (context.watch<AssistantController?>()?.availability ?? AssistantAvailability.hidden) !=
        AssistantAvailability.hidden;

    final dock = buildTvMyPleyaDock(
      hasSeerr: context.watch<SeerrProvider?>()?.isConfigured ?? false,
      // Hoofdstuk 18.3: Downloads never appears on Apple TV. The same predicate
      // `NavigationTab.getVisibleTabs` uses, so the tile and the tab cannot
      // disagree about whether the feature exists on this device.
      showDownloads: !PlatformDetector.isAppleTV(),
      // PB-7: Tautulli Now Watching is the one supported source today.
      showActivity: context.watch<NowWatchingProvider?>()?.isAvailable ?? false,
      showCollections: personalMedia?.supportsCollections ?? false,
      showPlaylists: personalMedia?.supportsPlaylists ?? false,
    );
    final entries = watchlist != null && watchlist.hasWatchlist ? myPleyaWatchlistEntries(watchlist) : null;

    _availableSections = {
      if (showBigP) TvMyPleyaSection.assistant,
      if (entries != null) TvMyPleyaSection.watchlist,
      for (final tile in dock) ?tile.section,
    };

    final map = _PageFocusMap(
      nodes: nodes,
      bigPKey: showBigP ? _bigPKey : null,
      posterKeys: [
        if (entries != null)
          for (final entry in entries) _posterKey(entry),
      ],
      seeAllKey: entries != null ? _seeAllKey : null,
      dockKeys: [for (final tile in dock) tile.focusKey],
      cameFrom: _cameFrom,
      onExitUp: widget.onExitUp,
    );
    _firstKey = map.firstKey;

    // The page is inset by the ring gap less, and everything that carries no
    // focus ring of its own adds it back, so every card edge and every line of
    // text starts on the same line.
    final ringGap = TvMyPleyaLayout.tileFocusRingGap * scale;
    final textInset = EdgeInsets.symmetric(horizontal: ringGap);

    final bigP = showBigP ? _BigPCard(map: map, onOpen: () => widget.onOpenSection(TvMyPleyaSection.assistant)) : null;
    final watchlistPanel = entries != null && watchlist != null
        ? _WatchlistPanel(
            entries: entries,
            provider: watchlist,
            map: map,
            onOpenAll: () => widget.onOpenSection(TvMyPleyaSection.watchlist),
          )
        : null;

    // Its own screen id: `screen.main` is mounted for the entire session and
    // says nothing about which destination is showing.
    return AutomationScreen(
      id: AutomationIds.screenMyPleya,
      readiness: () => const AutomationReadiness.ready(),
      // A safety net, not the layout: the page is measured to fit the
      // 1038 x 584 canvas without scrolling (A-24c). A locale with longer
      // words or a larger system text size can still reach the dock.
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          TvTopNavLayout.pageInset * scale - ringGap,
          _Pt.pageTop * pt,
          TvTopNavLayout.pageInset * scale - ringGap,
          _Pt.pageBottom * pt,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: textInset,
              child: _PageHeading(name: profile?.displayName),
            ),
            if (bigP != null || watchlistPanel != null) ...[
              SizedBox(height: _Pt.headingToCards * pt),
              SizedBox(
                height: _Pt.cardHeight * pt + 2 * ringGap,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (bigP != null) Expanded(flex: _Pt.bigPFlex, child: bigP),
                    if (bigP != null && watchlistPanel != null)
                      SizedBox(width: (_Pt.cardGap * pt - 2 * ringGap).clamp(0.0, double.infinity)),
                    if (watchlistPanel != null) Expanded(flex: _Pt.watchlistFlex, child: watchlistPanel),
                  ],
                ),
              ),
            ],
            SizedBox(height: _Pt.cardsToDock * pt),
            Padding(padding: textInset, child: _SectionLabel(t.tvMyPleya.quickLinks)),
            SizedBox(height: (_Pt.labelGap * pt - ringGap).clamp(0.0, double.infinity)),
            _Dock(tiles: dock, map: map, onOpen: (tile) => widget.onOpenSection(tile.section!)),
          ],
        ),
      ),
    );
  }
}

/// Big P carries the assistant section's own focus key, so the pop back from
/// his screen lands on the card (hoofdstuk 7.6).
final String _bigPKey = TvMyPleyaSection.assistant.tileFocusKey;

/// `Bekijk alles` carries the kijklijst section's own focus key, so the pop
/// back from the kijklijst lands on it.
final String _seeAllKey = TvMyPleyaSection.watchlist.tileFocusKey;

String _posterKey(WatchlistEntry entry) => 'tvMyPleya_poster_${entry.key}';

/// Northstar A10, in HIG points on the 1920 x 1080 canvas. Text sizes are
/// [TvHig] tokens and never under [TvHig.caption2].
abstract final class _Pt {
  static const double pageTop = 22;
  static const double pageBottom = 40;

  static const double eyebrowGap = 14;
  static const double headingGap = 6;

  /// The line under the heading and the Big P card's sentence (A10: 26).
  static const double subline = 26;
  static const double headingToCards = 36;

  /// The Big P card and the kijklijst panel share one height (A10: 290).
  static const double cardHeight = 290;
  static const double cardGap = 25;
  static const double cardRadius = 24;

  /// A10 draws the two cards 883 and 828 wide.
  static const int bigPFlex = 883;
  static const int watchlistFlex = 828;

  static const double cardsToDock = 30;
  static const double labelGap = 14;

  static const double tileHeight = 148;
  static const double tileGap = 24;
  static const double tileRadius = 18;
  static const double tilePadding = 22;

  /// Room for the icon and a label on two lines inside [tileHeight].
  static const double tilePaddingVertical = 18;
  static const double tileIcon = 36;

  /// The dock's labels, a little over [TvHig.caption1] as A10 draws them.
  static const double tileTitle = 26;

  /// Letter spacing of the small capitals, per point of type.
  static const double capsTracking = 0.12;
}
