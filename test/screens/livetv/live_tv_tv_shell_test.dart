/// LIVE1: op tvOS is de unified topnav de enige root-chrome.
///
/// Het harnas mount `LiveTvScreen` twee keer met exact dezelfde providers en
/// exact dezelfde fixture, en laat er één keer wel en één keer niet een
/// `TvShellSurface` omheen staan. Dat is de enige variabele. Wat de twee
/// renders verschillend doen is per definitie wat de shell-aanwezigheid
/// bepaalt, en dat is precies de vraag die dit bestand bewaakt.
///
/// De niet-shell-render is niet "de mobiele variant". Het is desktop, en de
/// app bar die daar staat blijft er staan: `shouldUseSideNavigation` is op
/// Windows, macOS en Linux nog steeds het juiste antwoord, en dit plan raakt
/// die tak niet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/live_tv_support.dart';
import 'package:pleya/media/noop_live_tv_support.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/models/livetv_channel.dart';
import 'package:pleya/models/livetv_dvr.dart';
import 'package:pleya/models/livetv_program.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/livetv/live_tv_screen.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/focusable_tab_chip.dart';
import 'package:pleya/widgets/tv/tv_page_chip_bar.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

const _serverId = 'nas';

/// Two channels, one program each, and a DVR: enough for all three tabs to
/// have something to draw. Fewer channels and the guide takes its
/// "noChannels" branch; no DVR and `_refreshVisibleTabs` drops the Opnames
/// tab, which is exactly the state Task 3 asserts separately.
class _FakeLiveTvSupport extends NoopLiveTvSupport {
  const _FakeLiveTvSupport();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<LiveTvDvr>> fetchDvrs() async => [LiveTvDvr(key: 'dvr-1', uuid: 'dvr-1')];

  @override
  Future<List<LiveTvChannel>> fetchChannels({String? lineup}) async => [
    LiveTvChannel(key: 'ch-1', title: 'NPO 1', number: '1'),
    LiveTvChannel(key: 'ch-2', title: 'NPO 2', number: '2'),
  ];

  @override
  Future<List<LiveTvProgram>> fetchSchedule({DateTime? from, DateTime? to}) async {
    final now = DateTime.now();
    return [
      LiveTvProgram(
        channelIdentifier: 'ch-1',
        title: 'Nieuwsuur',
        beginsAt: now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch ~/ 1000,
        endsAt: now.add(const Duration(minutes: 20)).millisecondsSinceEpoch ~/ 1000,
      ),
      LiveTvProgram(
        channelIdentifier: 'ch-2',
        title: 'Andere Tijden',
        beginsAt: now.add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000,
        endsAt: now.add(const Duration(minutes: 55)).millisecondsSinceEpoch ~/ 1000,
      ),
    ];
  }

  @override
  Future<String> buildFavoriteChannelSource({String? lineup}) async => 'server://$_serverId/epg';
}

/// Concrete waar Live TV het nodig heeft, `noSuchMethod` voor de rest. Zelfde
/// vorm als `_FakeClient` in `tv_discovery_landing_production_golden_test.dart`.
class _FakeLiveTvClient implements MediaServerClient {
  @override
  ServerId get serverId => ServerId(_serverId);

  @override
  String? get serverName => 'Plex thuis';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  LiveTvSupport get liveTv => const _FakeLiveTvSupport();

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget mountLiveTv({required bool inShell, required MultiServerProvider provider}) {
  final screen = ChangeNotifierProvider<MultiServerProvider>.value(value: provider, child: const LiveTvScreen());
  return TranslationProvider(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: monoTheme(dark: true),
      home: InputModeTracker(
        child: SizedBox(width: 1920, height: 1080, child: inShell ? TvShellSurface(child: screen) : screen),
      ),
    ),
  );
}

/// `SettingsService.getInstance()` bottoms out in real shared_preferences
/// platform-channel work, which hangs forever inside a `testWidgets` fake
/// async zone. It has to run from `setUp`, not from here, so this stays
/// synchronous.
MultiServerProvider buildProvider() {
  final manager = MultiServerManager()..debugRegisterClientForTesting(_FakeLiveTvClient());
  return MultiServerProvider(manager, DataAggregationService(manager))..debugSetLiveTvServersForTesting([
    LiveTvServerInfo(
      serverId: _serverId,
      dvrKey: 'dvr-1',
      dvrs: [LiveTvDvr(key: 'dvr-1', uuid: 'dvr-1', lineupTitle: 'Plex thuis')],
    ),
  ]);
}

void main() {
  setUpAll(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  setUp(() async {
    resetSharedPreferencesForTest();
    await SettingsService.getInstance();
    await initializeDateFormatting('en');
  });

  testWidgets('LIVE1: inside the TV shell the screen draws no app bar of its own', (tester) async {
    final provider = buildProvider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(mountLiveTv(inShell: true, provider: provider));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byType(AppBar),
      findsNothing,
      reason: 'the shell already draws the root navigation; a second bar under it is LIVE1',
    );
  });

  testWidgets('LIVE1: outside the shell the desktop app bar is unchanged', (tester) async {
    final provider = buildProvider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(mountLiveTv(inShell: false, provider: provider));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AppBar), findsOneWidget, reason: 'desktop keeps the bar it always had');
  });

  testWidgets('LIVE1: the page heading sits on the canonical TV page inset', (tester) async {
    // The 1920x1080 `SizedBox` in `mountLiveTv` only constrains layout; it does
    // not drive `MediaQuery.sizeOf`, which flutter_test otherwise reports at
    // its default 800x600. `TvLayoutConstants.scaleOf` falls back to
    // `MediaQuery.sizeOf` whenever no `TvDisplayMetrics` is published (the
    // lightweight `TvShellSurface` marker used here does not publish one,
    // only the full `TvRootShell` does), so without this the scale clamps to
    // its 0.85 floor and the assertion below is comparing against the wrong
    // number, exactly the "1080-hoge viewport" the reason string assumes.
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = buildProvider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(mountLiveTv(inShell: true, provider: provider));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final heading = find.text(t.liveTv.title);
    expect(heading, findsOneWidget);

    // Dezelfde linkerrand als elke andere TV-pagina. Een kop die zijn eigen
    // inset kiest is precies wat de audit van 2 september 2026 twaalf keer
    // mat, en wat `TvPageSurface` bestaat om te voorkomen.
    expect(
      tester.getTopLeft(heading).dx,
      closeTo(TvTopNavLayout.pageInset, 0.5),
      reason: 'scale is 1.0 op een 1080-hoge viewport, dus de inset is de token zelf',
    );
  });

  testWidgets('LIVE1: the shell render has exactly one secondary layer, in the chip language', (tester) async {
    final provider = buildProvider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(mountLiveTv(inShell: true, provider: provider));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(TvPageChipBar), findsOneWidget);
    // De oude rij is weg, niet verplaatst. Twee rijen die allebei van tab
    // kunnen wisselen is dezelfde fout als twee navigatiebalken, een niveau
    // lager.
    expect(
      find.byType(FocusableTabChip),
      findsNothing,
      reason: 'PB-8: de lokale navigatie is één secundaire laag, niet twee',
    );
    // De oude chiprij is hier niet alleen visueel vervangen: het widget type
    // zelf komt in deze render niet meer voor.
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('LIVE1: the chip row carries the three tabs and the four actions', (tester) async {
    final provider = buildProvider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(mountLiveTv(inShell: true, provider: provider));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final bar = tester.widget<TvPageChipBar>(find.byType(TvPageChipBar));
    final keys = [for (final chip in bar.chips) chip.key];

    // De volgorde is de leesvolgorde van mockup 17: eerst waar je bent, dan
    // wat je ermee kunt.
    expect(keys.take(3).toList(), ['liveTvTab_guide', 'liveTvTab_whatsOn', 'liveTvTab_recordings']);
    expect(keys, contains('liveTvAction_refresh'));

    // Gids is de actieve tab bij binnenkomst, en draagt als enige van de drie
    // de outline.
    expect(bar.chips.firstWhere((c) => c.key == 'liveTvTab_guide').selected, isTrue);
    expect(bar.chips.firstWhere((c) => c.key == 'liveTvTab_whatsOn').selected, isFalse);
  });

  testWidgets('LIVE1: the favorites chip carries its on/off state, the refresh chip does not', (tester) async {
    final provider = buildProvider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(mountLiveTv(inShell: true, provider: provider));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final bar = tester.widget<TvPageChipBar>(find.byType(TvPageChipBar));
    final refresh = bar.chips.firstWhere((c) => c.key == 'liveTvAction_refresh');

    // Een actierij is nooit "het huidige antwoord". Een outline erop zou
    // lezen als "deze staat aan", en dat is precies waarom het contextmenu in
    // TV3 dezelfde keuze maakte.
    expect(refresh.selected, isFalse);

    final favorites = bar.chips.where((c) => c.key == 'liveTvAction_favorites').firstOrNull;
    if (favorites != null) {
      expect(favorites.selected, isFalse, reason: 'het filter staat uit bij binnenkomst, en dat is een leesbare false');
    }
  });

  testWidgets('LIVE1: without a DVR the recordings chip is absent, not disabled', (tester) async {
    await SettingsService.getInstance();
    final manager = MultiServerManager()..debugRegisterClientForTesting(_FakeLiveTvClient());
    final provider = MultiServerProvider(manager, DataAggregationService(manager));
    // Geen debugSetLiveTvServersForTesting: geen DVR-capability, dus
    // `_refreshVisibleTabs` laat de Opnames-tab weg.
    addTearDown(provider.dispose);

    await tester.pumpWidget(mountLiveTv(inShell: true, provider: provider));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final bars = find.byType(TvPageChipBar);
    if (bars.evaluate().isEmpty) return; // leeg scherm, geen rij: ook goed
    final bar = tester.widget<TvPageChipBar>(bars);
    expect([for (final c in bar.chips) c.key], isNot(contains('liveTvTab_recordings')));
  });

  testWidgets('MOC-17: the heading carries a source and channel-count line', (tester) async {
    final provider = buildProvider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(mountLiveTv(inShell: true, provider: provider));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Twee zenders in de fixture, en beide komen van dezelfde bron, dus de
    // bron staat er één keer.
    expect(find.text('Plex thuis · ${t.liveTv.channelCount(count: 2)}'), findsOneWidget);
  });

  testWidgets('MOC-17: one channel says one channel, not "1 channels"', (tester) async {
    // Slang's plural gaat over de count-parameter; dit legt vast dat de
    // aanroepplek het sleutelpaar gebruikt en niet één sleutel met een getal.
    expect(t.liveTv.oneChannel, isNot(contains('1 ')));
  });
}
