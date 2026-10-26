/// Mijn Pleya on TV as it ships (A-24c): the real [TvMyPleyaScreen] under the
/// real [TvRootShell] and [TvTopNavigation], on the 1038 x 584 logical canvas
/// an Apple TV renders, with each capability of `pariteit-v4.csv` switchable.
///
/// Shared by the page's behaviour test and its golden, so the two cannot
/// drift into testing different pages.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/tv/tv_content_focus_authority.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/now_watching_provider.dart';
import 'package:pleya/providers/personal_media_provider.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/providers/watchlist_provider.dart';
import 'package:pleya/screens/tv/tv_my_pleya_screen.dart';
import 'package:pleya/screens/tv/tv_my_pleya_sections.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/big_p/big_p_rig.dart' show bigPAsset;
import 'package:pleya/widgets/pleya_wordmark.dart';
import 'package:pleya/widgets/tv/tv_account_menu.dart';
import 'package:pleya/widgets/tv/tv_top_navigation.dart';
import 'package:provider/provider.dart';

import '../widgets/big_p/fake_assistant_controller.dart';
import 'golden.dart';
import 'tv_my_pleya_conditions.dart';

/// The three themes a viewer can pick (A10 dark, A11 light, A12 OLED).
enum TvMyPleyaTheme { dark, light, oled }

/// What the profile has, per row of `pariteit-v4.csv`. Everything on by
/// default: the A10 picture.
class TvMyPleyaPageConditions {
  const TvMyPleyaPageConditions({
    this.bigP = true,
    this.watchlist = true,
    this.watchlistCount = 6,
    this.seerr = true,
    this.activity = true,
    this.collections = true,
    this.playlists = true,
    this.appleTv = true,
    this.profileName = 'Michel',
  });

  /// A15: no Seerr and no Tautulli behind Aanvragen and Activiteit.
  const TvMyPleyaPageConditions.withoutSeerrAndActivity() : this(seerr: false, activity: false);

  final bool bigP;
  final bool watchlist;
  final int watchlistCount;
  final bool seerr;
  final bool activity;
  final bool collections;
  final bool playlists;
  final bool appleTv;
  final String? profileName;
}

/// The pumped page and the handles a test reaches for.
class TvMyPleyaPage {
  TvMyPleyaPage._(this.tester, this.coordinator, this.navNodes, this.opened, this.upCalls, this.menuChoices);

  final WidgetTester tester;
  final TvNavigationCoordinator coordinator;
  final FocusMemoryTracker navNodes;
  final List<TvMyPleyaSection> opened;
  final List<int> upCalls;

  /// What each account menu opened from the avatar completed with (null for
  /// Back), in order.
  final List<TvAccountAction?> menuChoices;

  TvMyPleyaScreenState get state => tester.state<TvMyPleyaScreenState>(find.byType(TvMyPleyaScreen));

  String? get focused => FocusManager.instance.primaryFocus?.debugLabel;
}

/// A profile with a name, nothing else.
class _NamedProfile extends ChangeNotifier implements ActiveProfileProvider {
  _NamedProfile(this.active);

  @override
  final Profile? active;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Collecties and Afspeellijsten per capability, without a server behind
/// them: the page only asks whether they are supported.
class _PersonalMediaDouble extends ChangeNotifier implements PersonalMediaProvider {
  _PersonalMediaDouble({required this.supportsCollections, required this.supportsPlaylists});

  @override
  final bool supportsCollections;

  @override
  final bool supportsPlaylists;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MonoTokens _tokens(TvMyPleyaTheme theme) => switch (theme) {
  TvMyPleyaTheme.dark => monoTheme(dark: true).extension<MonoTokens>()!,
  TvMyPleyaTheme.light => monoTheme(dark: false).extension<MonoTokens>()!,
  TvMyPleyaTheme.oled => monoTheme(dark: true, oled: true).extension<MonoTokens>()!,
};

ThemeData _theme(TvMyPleyaTheme theme) => switch (theme) {
  TvMyPleyaTheme.dark => monoTheme(dark: true),
  TvMyPleyaTheme.light => monoTheme(dark: false),
  TvMyPleyaTheme.oled => monoTheme(dark: true, oled: true),
};

/// Pumps Mijn Pleya, active in the bar, at the Apple TV canvas.
Future<TvMyPleyaPage> pumpTvMyPleyaPage(
  WidgetTester tester, {
  TvMyPleyaPageConditions conditions = const TvMyPleyaPageConditions(),
  TvMyPleyaTheme theme = TvMyPleyaTheme.dark,
  Size size = kTvGoldenSurfaceSize,
}) async {
  TvDetectionService.debugSetAppleTVOverride(conditions.appleTv);
  addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
  setGoldenSurfaceSize(tester, size: size);

  final coordinator = TvNavigationCoordinator(initial: TvDestinationId.myPleya)
    ..updateConditions(const TvNavConditions(hasLiveTv: true))
    ..activate(TvDestinationId.myPleya);
  final navNodes = FocusMemoryTracker(debugLabelPrefix: 'tvNav');
  final navScope = FocusScopeNode(debugLabel: 'nav');
  final contentScope = FocusScopeNode(debugLabel: 'content');
  final manager = MultiServerManager();
  final servers = MultiServerProvider(manager, DataAggregationService(manager));
  final assistant = FakeAssistantController()
    ..availability = conditions.bigP ? AssistantAvailability.ready : AssistantAvailability.hidden;
  final watchlist = conditions.watchlist
      ? StockedWatchlistDouble(
          railEntries: [
            for (var i = 0; i < conditions.watchlistCount; i++) watchlistEntryDouble('w$i', title: 'Title $i'),
          ],
        )
      : null;
  final seerr = conditions.seerr ? ConfiguredSeerrDouble() : null;
  final nowWatching = conditions.activity ? AvailableNowWatchingDouble() : null;
  final personal = _PersonalMediaDouble(
    supportsCollections: conditions.collections,
    supportsPlaylists: conditions.playlists,
  );
  final profile = conditions.profileName == null
      ? null
      : Profile.local(id: 'p1', displayName: conditions.profileName!, createdAt: DateTime.utc(2026, 10, 26));
  final activeProfile = _NamedProfile(profile);
  addTearDown(() {
    coordinator.dispose();
    navNodes.dispose();
    navScope.dispose();
    contentScope.dispose();
    servers.dispose();
    assistant.dispose();
    watchlist?.dispose();
    seerr?.dispose();
    nowWatching?.dispose();
    personal.dispose();
    activeProfile.dispose();
  });

  final opened = <TvMyPleyaSection>[];
  final upCalls = <int>[];
  final menuChoices = <TvAccountAction?>[];
  final navigatorKey = GlobalKey<NavigatorState>();
  // The avatar opens the account menu the way `MainScreen` does, and the
  // remote goes back to the avatar when it closes.
  Future<void> openAccountMenu() async {
    final choice = await showTvAccountMenu(navigatorKey.currentContext!, profileName: profile?.displayName);
    menuChoices.add(choice);
    navNodes.get(tvNavProfileFocusKey).requestFocus();
  }

  final tokens = _tokens(theme);

  await tester.pumpWidget(
    TranslationProvider(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
          ChangeNotifierProvider<AssistantController>.value(value: assistant),
          ChangeNotifierProvider<ActiveProfileProvider>.value(value: activeProfile),
          ChangeNotifierProvider<PersonalMediaProvider>.value(value: personal),
          if (watchlist != null) ChangeNotifierProvider<WatchlistProvider>.value(value: watchlist),
          if (seerr != null) ChangeNotifierProvider<SeerrProvider>.value(value: seerr),
          if (nowWatching != null) ChangeNotifierProvider<NowWatchingProvider>.value(value: nowWatching),
        ],
        // Above the app, as in `main.dart`, so a dialog route shows the ring
        // in remote mode as well.
        child: InputModeTracker(
          child: MaterialApp(
            navigatorKey: navigatorKey,
            debugShowCheckedModeBanner: false,
            theme: _theme(theme),
            home: Scaffold(
              backgroundColor: tokens.bg,
              body: TvRootShell(
                coordinator: coordinator,
                contentFocus: TvContentFocusAuthority(),
                navNodes: navNodes,
                navFocusScope: navScope,
                contentFocusScope: contentScope,
                isNavFocused: false,
                profile: profile,
                onSelectDestination: coordinator.activate,
                // What `MainScreen._focusTvDestination` does with the ring.
                onFocusDestination: (d) =>
                    d.switchesOnFocus ? coordinator.activate(d) : coordinator.focusDestination(d),
                onFocusContent: ({bool restorePreviousFocus = true}) {},
                onFocusNav: () {},
                onOpenProfiles: () => unawaited(openAccountMenu()),
                onOverlaySheetOpenChanged: (_) {},
                onKeyEvent: (_) => KeyEventResult.ignored,
                selectLibrary: null,
                openSettings: null,
                dismissNestedRoute: ([_]) {},
                child: TvMyPleyaScreen(onOpenSection: opened.add, onExitUp: () => upCalls.add(1)),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // The wordmark and Big P are asset images, decoded asynchronously.
  final element = tester.element(find.byType(TvTopNavigation));
  for (final asset in [...PleyaWordmark.assets, bigPAsset('still-zwaaien')]) {
    await tester.runAsync(() => precacheImage(AssetImage(asset), element));
  }
  await tester.pumpAndSettle();
  return TvMyPleyaPage._(tester, coordinator, navNodes, opened, upCalls, menuChoices);
}
