// Visual evidence: Big P's TV windows in every stand, at Apple TV scale
// (1038x584 logical, scaled 1.85 to 1920x1080 as `_AppleTvScale` does), with
// the app's fonts, over the Home reference. Skipped unless BIGP_SHOT_DIR is set:
//   BIGP_SHOT_DIR=/tmp/bigp flutter test test/screens/tv/assistant/tv_assistant_audit_shots_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_title_facts.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_screen.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_summon.dart';
import 'package:pleya/services/apple_tv_native_text_entry.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/speech_search_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/native_input_session.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/big_p/big_p_rig.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/pleya_wordmark.dart';
import 'package:provider/provider.dart';

import '../../../test_helpers/golden.dart';
import 'tv_assistant_test_support.dart';

final _dir = Platform.environment['BIGP_SHOT_DIR'];
const _channel = MethodChannel('test_assistant_audit_entry');

AssistantTitleTarget _target(MediaItem item) => (serverId: ServerId('zolder'), serverName: 'Zolder', item: item);

MediaItem _movie(String id, String title, int year) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title,
  year: year,
  serverId: 'zolder',
  serverName: 'Zolder',
);

final _matches = AssistantTitleMatches(AssistantToolContext(servers: MultiServerManager()), [
  AssistantTitleMatch(
    matchId: 'm1',
    title: 'The Martian',
    year: 2015,
    kind: 'movie',
    confidence: 'high',
    targets: [_target(_movie('42', 'The Martian', 2015))],
    snippet: 'Astronaut Mark Watney blijft achter op Mars en moet overleven tot er hulp komt.',
    facts: const TitleFacts(
      certifications: {'NL': '12'},
      genres: ['Sciencefiction', 'Drama', 'Avontuur'],
      runtimeMin: 144,
      score: 7.7,
      providers: {
        'NL': ['Disney Plus', 'Netflix', 'Videoland'],
      },
      sources: {'tmdb'},
    ),
  ),
  const AssistantTitleMatch(
    matchId: 'm2',
    title: 'Red Planet',
    year: 2000,
    kind: 'movie',
    confidence: 'low',
    targets: [],
    request: AssistantRequestOption(
      seerrId: 'movie:10',
      title: 'Red Planet',
      year: 2000,
      kind: 'movie',
      posterUrl: '',
      overview: 'Een bemanning strandt op Mars.',
      status: 'not_requested',
    ),
    snippet: 'Astronauts stranded on a dying Mars.',
    facts: const TitleFacts(certifications: {'US': 'R'}, runtimeMin: 106, score: 5.6, sources: {'tmdb'}),
  ),
  AssistantTitleMatch(
    matchId: 'm3',
    title: 'Interstellar',
    year: 2014,
    kind: 'movie',
    confidence: 'medium',
    targets: [_target(_movie('43', 'Interstellar', 2014))],
  ),
  AssistantTitleMatch(
    matchId: 'm4',
    title: 'Gravity',
    year: 2013,
    kind: 'movie',
    confidence: 'medium',
    targets: [_target(_movie('44', 'Gravity', 2013))],
  ),
]);

final _watch = AssistantWatchStats(
  serverName: 'Pleya',
  days: 7,
  users: const [
    (name: 'Gideuh', plays: 36, seconds: 0),
    (name: 'Jan', plays: 6, seconds: 0),
    (name: 'Michel', plays: 4, seconds: 0),
  ],
  titles: [
    (
      title: 'The Block',
      plays: 19,
      viewers: const ['Gideuh', 'Jan'],
      show: true,
      target: _target(MediaItem(id: 's1', backend: MediaBackend.plex, kind: MediaKind.show, title: 'The Block')),
    ),
    (title: 'House', plays: 7, viewers: const ['Jan'], show: true, target: null),
    (
      title: 'Interstellar',
      plays: 3,
      viewers: const ['Michel'],
      show: false,
      target: _target(_movie('43', 'Interstellar', 2014)),
    ),
  ],
);

final _grid = AssistantMediaGrid([
  for (var i = 1; i <= 8; i++) (item: _movie('g$i', 'Mission: Impossible $i', 1994 + i * 3), group: null),
]);

final _options = AssistantRequestOptions(AssistantToolContext(servers: MultiServerManager()), const [
  AssistantRequestOption(
    seerrId: 'movie:286217',
    title: 'The Martian',
    year: 2015,
    kind: 'movie',
    posterUrl: '',
    overview: 'Tijdens een bemande missie naar Mars wordt astronaut Mark Watney dood gewaand.',
    status: 'not_requested',
  ),
  AssistantRequestOption(
    seerrId: 'tv:1',
    title: 'The Expanse',
    year: 2015,
    kind: 'series',
    posterUrl: '',
    overview: 'Honderden jaren in de toekomst is het zonnestelsel gekoloniseerd.',
    status: 'partially_available',
  ),
]);

const _longAnswer =
    'Op Zolder staan 1.284 films en 212 series. Afgelopen week zijn er 37 titels bijgekomen, '
    'vooral films uit 2024. De grootste bibliotheek is Films met 1.104 titels; Kids heeft er 180. '
    'De laatste scan van Films was vanochtend om 06:12 en liep zonder fouten. Series is gisteren '
    'voor het laatst gescand. Wil je dat ik Series nu opnieuw scan, of zal ik eerst kijken welke '
    'titels geen poster hebben? Dat zijn er op dit moment 14, de meeste in Kids.';

typedef _Stand = void Function(FakeAssistantController c);

final Map<String, _Stand> _stands = {
  'idle': (c) => c.state = AssistantSurfaceState.idle,
  'listening': (c) => c.state = AssistantSurfaceState.listening,
  'working': (c) => c
    ..prompt = 'Scan Films op Zolder en kijk daarna welke titels geen poster hebben'
    ..state = AssistantSurfaceState.working
    ..steps = const [
      AssistantStep(index: 0, tool: 'list_libraries', serverName: 'Zolder', phase: AssistantStepPhase.done),
      AssistantStep(index: 1, tool: 'scan_library', serverName: 'Zolder', phase: AssistantStepPhase.done),
      AssistantStep(index: 2, tool: 'search_catalog', serverName: 'Zolder', phase: AssistantStepPhase.started),
    ],
  'working-streamed': (c) => c
    ..prompt = 'Een film over astronauten op Mars'
    ..state = AssistantSurfaceState.working
    ..displays = [_matches]
    ..stillChecking = true
    ..steps = const [
      AssistantStep(index: 0, tool: 'find_title', serverName: 'Zolder', phase: AssistantStepPhase.started),
    ],
  'result-short': (c) => c
    ..prompt = 'Hoeveel films staan er op Zolder?'
    ..state = AssistantSurfaceState.result
    ..answer = 'Op Zolder staan 1.284 films.',
  'result-long': (c) => c
    ..prompt = 'Hoe staat Zolder ervoor?'
    ..state = AssistantSurfaceState.result
    ..answer = _longAnswer,
  'result-matches': (c) => c
    ..prompt = 'Een film over astronauten die vastzitten in de ruimte'
    ..state = AssistantSurfaceState.result
    ..answer = 'Dit zijn de beste kandidaten: «The Martian», «Red Planet», «Interstellar» en «Gravity».'
    ..displays = [_matches],
  'kids-ages': (c) => c
    ..prompt = 'Is er een film voor de kinderen?'
    ..state = AssistantSurfaceState.result
    ..answer = 'Daarvoor moet Pleya eerst weten hoe oud de kinderen zijn.'
    ..displays = [const AssistantKidsAgesPrompt('Is er een film voor de kinderen?')],
  'result-watch': (c) => c
    ..prompt = 'Wat is er deze week het meest bekeken?'
    ..state = AssistantSurfaceState.result
    ..answer = 'Deze week is The Block het populairst, vooral bij Gideuh.'
    ..displays = [_watch],
  'result-grid': (c) => c
    ..prompt = 'Welke Mission: Impossible-films hebben we?'
    ..state = AssistantSurfaceState.result
    ..answer = 'Ik vond acht Mission: Impossible-films.'
    ..displays = [_grid],
  'result-options': (c) => c
    ..prompt = 'Vraag The Martian aan'
    ..state = AssistantSurfaceState.result
    ..answer = 'Ik vond twee titels. Welke bedoel je?'
    ..displays = [_options],
  'result-action': (c) => c
    ..prompt = 'Scan Films'
    ..state = AssistantSurfaceState.result
    ..answer = 'Ik heb de scan van Films op Zolder gestart.'
    ..actions = const [
      AssistantActionRecord(kind: AssistantActionKind.scanLibrary, serverName: 'Zolder', subject: 'Films'),
    ],
  'result-error': (c) => c
    ..prompt = 'Scan alles op alle servers en maak een rij van alles wat nieuw is'
    ..state = AssistantSurfaceState.result
    ..resultIsError = true
    ..lastEnd = AssistantRunEnd.stepLimit,
  'confirm': (c) => c
    ..prompt = 'Maak Sam aan met toegang tot Kids'
    ..state = AssistantSurfaceState.working
    ..pending = AssistantPendingAction(
      kind: AssistantActionKind.createUser,
      serverId: ServerId('zolder'),
      serverName: 'Zolder',
      subject: 'Sam',
      libraryNames: const ['Kids'],
      password: AssistantPasswordMode.required,
      execute: ({password}) async => const {},
    ),
};

/// `_AppleTvScale` from main.dart: lay out at 1/1.85 and scale the paint up.
Widget _appleTvScale(Widget child) => LayoutBuilder(
  builder: (context, box) {
    const scale = 1.85;
    final size = Size(box.maxWidth / scale, box.maxHeight / scale);
    final q = MediaQuery.of(context);
    return Transform.scale(
      scale: scale,
      alignment: Alignment.topLeft,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(
          size: size,
          child: MediaQuery(
            data: q.copyWith(size: size, devicePixelRatio: q.devicePixelRatio * scale),
            child: child,
          ),
        ),
      ),
    );
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ui.Image background;

  setUpAll(() async {
    await loadAppFontsForGoldens();
    await LocaleSettings.setLocale(AppLocale.nl);
    final bytes = File('docs/assets/tvos-unified/home-reference.png').readAsBytesSync();
    background = (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
  });

  setUp(() {
    // A Dutch Apple TV: the Kijkwijzer rating and the NL services (T8).
    TestWidgetsFlutterBinding.instance.platformDispatcher.localeTestValue = const Locale('nl', 'NL');
    TvDetectionService.debugSetAppleTVOverride(true);
    messenger.setMockMethodCallHandler(_channel, (call) async => <String, dynamic>{'text': 'Vraag', 'submitted': true});
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.clearLocaleTestValue();
    TvDetectionService.debugSetAppleTVOverride(null);
    messenger.setMockMethodCallHandler(_channel, null);
    NativeInputSession.debugReset();
  });

  Future<void> shoot(
    WidgetTester tester,
    String name,
    FakeAssistantController c,
    Widget surface, {
    Future<void> Function()? before,
  }) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: TranslationProvider(
          child: ChangeNotifierProvider<AssistantController>.value(
            value: c,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: monoTheme(dark: true),
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(disableAnimations: true),
                  child: _appleTvScale(
                    InputModeTracker(
                      child: OverlaySheetHost(
                        child: Scaffold(
                          backgroundColor: Colors.black,
                          body: Stack(
                            fit: StackFit.expand,
                            children: [
                              RawImage(image: background, fit: BoxFit.cover),
                              surface,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final ctx = tester.element(find.byKey(boundary));
      for (final a in [
        for (final p in kBigPPoses) bigPPoseAsset(p),
        for (final m in kBigPMouths) bigPAsset('mouth-$m'),
        bigPAsset('brow-l'),
        bigPAsset('brow-r'),
        bigPAsset('aim-arm'),
        bigPAsset('wave-arm'),
        PleyaWordmark.markAsset,
      ]) {
        await precacheImage(AssetImage(a), ctx);
      }
    });
    await settle(tester);
    await before?.call();

    await tester.pump(const Duration(milliseconds: 1200));
    await tester.runAsync(() async {
      final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await ro.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$_dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox());
  }

  for (final MapEntry(key: name, value: stand) in _stands.entries) {
    testWidgets('summoned $name', skip: _dir == null, (tester) async {
      final c = FakeAssistantController();
      addTearDown(c.dispose);
      final presses = StreamController<void>.broadcast();
      addTearDown(presses.close);
      final entry = AppleTvNativeTextEntry(channel: _channel);
      final host = TvAssistantSummonHost(
        longPresses: presses.stream,
        speech: SpeechSearchService(textEntry: entry),
        textEntry: entry,
        screenContext: () => null,
        child: const SizedBox.expand(),
      );
      await shoot(
        tester,
        'summon-$name',
        c,
        host,
        before: () async {
          presses.add(null);
          await settle(tester);
          stand(c);
          c.emit();
          await settle(tester);
        },
      );
    });
  }

  for (final name in ['idle', 'result-long', 'result-matches', 'result-watch', 'confirm', 'kids-ages']) {
    testWidgets('surface $name', skip: _dir == null, (tester) async {
      final c = FakeAssistantController();
      addTearDown(c.dispose);
      _stands[name]!(c);
      final entry = AppleTvNativeTextEntry(channel: _channel);
      await shoot(
        tester,
        'surface-$name',
        c,
        TvAssistantScreen(
          speech: SpeechSearchService(textEntry: entry),
          textEntry: entry,
        ),
        // The ages card rises on a controller change, as after a real run.
        before: () async {
          c.emit();
          await settle(tester);
        },
      );
    });
  }

  for (final (name, availability) in [
    ('gate-setup', AssistantAvailability.needsSetup),
    ('gate-locked', AssistantAvailability.locked),
  ]) {
    testWidgets('surface $name', skip: _dir == null, (tester) async {
      final c = FakeAssistantController()..availability = availability;
      addTearDown(c.dispose);
      final entry = AppleTvNativeTextEntry(channel: _channel);
      await shoot(
        tester,
        'surface-$name',
        c,
        TvAssistantScreen(
          speech: SpeechSearchService(textEntry: entry),
          textEntry: entry,
        ),
      );
    });
  }
}
