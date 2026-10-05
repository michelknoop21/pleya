/// find_title's results on TV (38-motion-7): a found title in a library
/// opens its detail page, one only Seerr knows goes to the request card,
/// on the surface and in the summoned panel.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/navigation/tv/tv_content_route_registry.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_confirm_card.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_match_card.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_screen.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_summon.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_assistant_widgets.dart';
import 'package:pleya/services/apple_tv_native_text_entry.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/speech_search_service.dart';
import 'package:pleya/utils/native_input_session.dart';
import 'package:pleya/utils/global_key_utils.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/big_p/big_p_balloon.dart';

import 'tv_assistant_test_support.dart';

const _zolder = 'zolder';

AssistantTitleTarget _target(MediaItem item) => (serverId: ServerId(_zolder), serverName: 'Zolder', item: item);

final _martian = AssistantTitleMatch(
  matchId: 'm1',
  title: 'The Martian',
  year: 2015,
  kind: 'movie',
  confidence: 'high',
  targets: [
    _target(
      MediaItem(
        id: '42',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'The Martian',
        summary: 'Astronaut Mark Watney blijft achter op Mars.',
        serverId: _zolder,
      ),
    ),
  ],
);

const _request = AssistantRequestOption(
  seerrId: 'movie:10',
  title: 'Red Planet',
  year: 2000,
  kind: 'movie',
  posterUrl: '',
  overview: 'Een bemanning strandt op Mars.',
  status: 'not_requested',
);

const _redPlanet = AssistantTitleMatch(
  matchId: 'm2',
  title: 'Red Planet',
  year: 2000,
  kind: 'movie',
  confidence: 'low',
  targets: [],
  request: _request,
  snippet: 'Astronauts stranded on a dying Mars.',
);

final _episode = AssistantTitleMatch(
  matchId: 'm3',
  title: 'The Constant',
  kind: 'episode',
  confidence: 'medium',
  series: 'Lost',
  season: 4,
  episode: 5,
  targets: [
    _target(
      MediaItem(
        id: '405',
        backend: MediaBackend.plex,
        kind: MediaKind.episode,
        title: 'The Constant',
        grandparentId: '400',
        grandparentTitle: 'Lost',
        parentId: '404',
        parentIndex: 4,
        index: 5,
        serverId: _zolder,
      ),
    ),
  ],
);

final _extra = AssistantTitleMatch(
  matchId: 'm4',
  title: 'Mission to Mars',
  kind: 'movie',
  confidence: 'medium',
  targets: const [],
  request: const AssistantRequestOption(
    seerrId: 'movie:11',
    title: 'Mission to Mars',
    kind: 'movie',
    posterUrl: '',
    overview: '',
    status: 'available',
  ),
);

MediaItem _mission(String id, String server) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Mission: Impossible',
  year: 1996,
  serverId: server,
  serverName: server,
);

/// One film on two servers, as the unified catalog merges it: the
/// representative copy (nas) is not the first source.
final UnifiedMediaGroup _merged = () {
  final sources = [
    UnifiedMediaSource.fromItem(_mission('mi0', _zolder)),
    UnifiedMediaSource.fromItem(_mission('mi0', 'nas')),
  ];
  return UnifiedMediaGroup(
    groupId: 'mi0',
    identity: CanonicalMediaIdentity.movie(title: 'Mission: Impossible', year: 1996),
    sources: sources,
    representativeSourceKey: sources.last.sourceKey,
    watchState: UnifiedWatchState(representativeSourceKey: sources.last.sourceKey, isWatched: false),
  );
}();

/// What search_catalog hands over: fourteen films, two more than a grid
/// draws; the first one merged across servers.
final _grid = AssistantMediaGrid([
  (item: _merged.representativeSource.item, group: _merged),
  for (var i = 1; i <= 13; i++)
    (
      item: MediaItem(
        id: 'mi$i',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'Mission: Impossible $i',
        serverId: _zolder,
        serverName: 'Zolder',
      ),
      group: null,
    ),
]);

AssistantTitleMatches _fourMatches() => AssistantTitleMatches(AssistantToolContext(servers: MultiServerManager()), [
  _martian,
  _redPlanet,
  _episode,
  _extra,
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test_assistant_matches_entry');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FakeAssistantController c;
  late List<TvNestedRoute> routes;

  Future<Object?> push(TvNestedRoute route) {
    routes.add(route);
    return Completer<Object?>().future;
  }

  setUp(() {
    TvDetectionService.debugSetAppleTVOverride(true);
    c = FakeAssistantController();
    routes = [];
    tvContentRouteRegistry.attach(push);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => <String, dynamic>{'text': 'Die film over Mars', 'submitted': true},
    );
  });

  tearDown(() {
    tvContentRouteRegistry.detach(push);
    TvDetectionService.debugSetAppleTVOverride(null);
    messenger.setMockMethodCallHandler(channel, null);
    NativeInputSession.debugReset();
    c.dispose();
  });

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key, [int times = 1]) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(key);
      await settle(tester);
    }
  }

  String? focusedMatch() =>
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<BigPMatchCard>()?.match.matchId;

  /// What the panel shows: the surface's glass panel minus its 32 pt
  /// padding, or the summoned balloon minus its own.
  Rect panelContent(WidgetTester tester) {
    final balloon = find.byType(BigPBalloon);
    if (balloon.evaluate().isEmpty) return tester.getRect(find.byType(BigPGlassPanel)).deflate(32);
    return tester.widget<BigPBalloon>(balloon).padding.deflateRect(tester.getRect(balloon));
  }

  Rect focusedRect() => FocusManager.instance.primaryFocus!.rect;

  void expectInside(Rect inner, Rect outer, String what) => expect(
    outer.inflate(1).contains(inner.topLeft) && outer.inflate(1).contains(inner.bottomRight),
    isTrue,
    reason: '$what $inner is not inside the panel $outer',
  );

  /// Still checking, two streamed results: a library match and a request.
  Future<void> stillCheckingWith(WidgetTester tester) async {
    c
      ..prompt = 'Die film over Mars'
      ..state = AssistantSurfaceState.working
      ..answer = ''
      ..displays = [
        AssistantTitleMatches(AssistantToolContext(servers: MultiServerManager()), [_martian, _redPlanet]),
      ]
      ..stillChecking = true
      ..emit();
    await settle(tester);
  }

  /// The request card is readable but dimmed and does nothing on Select;
  /// the library card above it still opens its title.
  Future<void> expectRequestInertWhileChecking(WidgetTester tester) async {
    double opacityOf(String id) => tester
        .widget<Opacity>(
          find.descendant(
            of: find.byWidgetPredicate((w) => w is BigPMatchCard && w.match.matchId == id),
            matching: find.byType(Opacity),
          ),
        )
        .opacity;
    expect(opacityOf('m2'), lessThan(1));
    expect(opacityOf('m1'), 1);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedMatch(), 'm2', reason: 'still focusable for reading');
    await press(tester, LogicalKeyboardKey.select);
    expect(c.picked, isEmpty);
    expect(routes, isEmpty);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedMatch(), 'm1');
    await press(tester, LogicalKeyboardKey.select);
    expect(routes.single.id, 'tvDetail_${_martian.targets.single.item.globalKey}');
  }

  Future<void> showDisplay(WidgetTester tester, AssistantDisplay display) async {
    c
      ..prompt = 'Die film over Mars'
      ..state = AssistantSurfaceState.result
      ..answer = 'Ik vond deze titels.'
      ..displays = [display]
      ..emit();
    await settle(tester);
  }

  Future<void> showMatches(WidgetTester tester, List<AssistantTitleMatch> matches) =>
      showDisplay(tester, AssistantTitleMatches(AssistantToolContext(servers: MultiServerManager()), matches));

  group('on the surface', () {
    Future<void> pumpSurface(WidgetTester tester) async {
      final entry = AppleTvNativeTextEntry(channel: channel);
      await pumpTvFrame(
        tester,
        c,
        TvAssistantScreen(
          speech: SpeechSearchService(textEntry: entry),
          textEntry: entry,
        ),
      );
      await showMatches(tester, [_martian, _redPlanet, _episode]);
    }

    // Viewport audit 2 Oct 2026: with four found titles the panel content is
    // taller than the glass panel, and D-pad focus scrolled the reversed
    // panel the wrong way.
    testWidgets('still checking with four results keeps the question, the status and Cancel in the panel', (
      tester,
    ) async {
      await pumpSurface(tester);
      c
        ..state = AssistantSurfaceState.working
        ..answer = ''
        ..steps = const [AssistantStep(index: 0, tool: 'find_title', phase: AssistantStepPhase.done)]
        ..displays = [_fourMatches()]
        ..stillChecking = true
        ..emit();
      await settle(tester);

      final panel = panelContent(tester);
      expectInside(tester.getRect(find.byType(BigPQuestion)), panel, 'question');
      expectInside(tester.getRect(find.text(t.assistant.working.stillChecking)), panel, 'still-checking status');
      expect(focusedLabel(), 'assistant.cancel');
      expectInside(focusedRect(), panel, 'Cancel');
    });

    // Hardware, 3 oct 2026: the answer took the room of the results and its
    // last line faded out. Above cards the lead stands alone.
    testWidgets('a long answer above the cards shows its lead in two lines at most and takes no focus', (tester) async {
      await pumpSurface(tester);
      final answer = List.filled(14, 'Ik heb veel films met Tom Cruise gevonden.').join(' ');
      // A new result, as a run delivers it: working first, then the answer.
      c
        ..state = AssistantSurfaceState.working
        ..emit();
      await settle(tester);
      c
        ..state = AssistantSurfaceState.result
        ..answer = answer
        ..emit();
      await settle(tester);
      final panel = panelContent(tester);
      expect(focusedMatch(), 'm1');
      expectInside(focusedRect(), panel, 'first card');
      final lead = tester.widget<Text>(find.byKey(const ValueKey('assistant.answer')));
      expect(lead.data, 'Ik heb veel films met Tom Cruise gevonden.');
      expect(lead.maxLines, 2);
      expect(find.byKey(const ValueKey('assistant.answer.body')), findsNothing);

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedMatch(), 'm1', reason: 'nothing to read above the first card');
    });

    // Seerr not set up: the titles are shown but none can be opened or
    // requested, so the cards cannot be walked through and do not replace
    // the list in the answer.
    testWidgets('title cards that cannot be chosen leave the answer its list', (tester) async {
      await pumpSurface(tester);
      const shown = [
        AssistantTitleMatch(matchId: 'u1', title: 'Heat', year: 1995, kind: 'movie', confidence: 'high', targets: []),
        AssistantTitleMatch(matchId: 'u2', title: 'Ronin', year: 1998, kind: 'movie', confidence: 'high', targets: []),
      ];
      await showMatches(tester, shown);
      c
        ..answer = 'Ik vond deze titels op het web:\n1. Heat (1995)\n2. Ronin (1998)'
        ..emit();
      await settle(tester);

      expect(find.byKey(const ValueKey('assistant.answer.body')), findsOneWidget);
      expect(find.textContaining('2. Ronin (1998)'), findsOneWidget);
    });

    testWidgets('D-pad through four results and on to the buttons keeps every focused control in the panel', (
      tester,
    ) async {
      await pumpSurface(tester);
      await showMatches(tester, [_martian, _redPlanet, _episode, _extra]);
      final panel = panelContent(tester);
      expect(focusedMatch(), 'm1');
      expectInside(focusedRect(), panel, 'first card');
      expectInside(tester.getRect(find.text('Ik vond deze titels.')), panel, 'answer with the first card focused');

      await press(tester, LogicalKeyboardKey.arrowDown, 3);
      expect(focusedMatch(), 'm4');
      expectInside(focusedRect(), panel, 'last card');

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedMatch(), isNull);
      expectInside(focusedRect(), panel, 'the button under the cards');
    });

    testWidgets('the first card takes the focus; a library match opens its detail page', (tester) async {
      await pumpSurface(tester);

      expect(find.byType(BigPMatchCard), findsNWidgets(3));
      expect(focusedMatch(), 'm1');
      expect(find.text(t.assistant.match.inLibrary(servers: 'Zolder')), findsNWidgets(2));
      await press(tester, LogicalKeyboardKey.select);

      expect(routes.single.id, 'tvDetail_${_martian.targets.single.item.globalKey}');
      expect(c.picked, isEmpty);
    });

    // Build 318: a search_catalog result was a card of text lines, nothing
    // to focus or open.
    testWidgets('a media grid draws its titles as cards: the first takes the focus and opens', (tester) async {
      await pumpSurface(tester);
      await showDisplay(tester, _grid);

      expect(find.byType(BigPMatchCard), findsNWidgets(12));
      expect(focusedMatch(), _grid.entries.first.item.globalKey);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedMatch(), _grid.entries[1].item.globalKey, reason: 'the order of the grid');
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.select);

      expect(routes.single.id, 'tvDetail_nas:mi0', reason: 'the representative copy, not the first source');
    });

    testWidgets('while still checking a request candidate is dimmed and inert, a library match opens', (tester) async {
      await pumpSurface(tester);
      await stillCheckingWith(tester);
      expect(focusedLabel(), 'assistant.cancel');
      await expectRequestInertWhileChecking(tester);
    });

    testWidgets('a request candidate goes to pickRequestOption and the Pleya card', (tester) async {
      await pumpSurface(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedMatch(), 'm2');
      expect(find.text(t.assistant.option.notRequested), findsOneWidget);
      await press(tester, LogicalKeyboardKey.select);

      expect(c.picked.single.seerrId, 'movie:10');
      expect(routes, isEmpty);
      c
        ..pending = AssistantPendingAction(
          kind: AssistantActionKind.requestTitle,
          serverId: ServerId('seerr'),
          serverName: 'Seerr',
          subject: 'Red Planet',
          execute: ({password}) async => const {},
        )
        ..emit();
      await settle(tester);
      expect(find.byType(BigPConfirmCard), findsOneWidget);
    });

    testWidgets('an episode opens its series scrolled to it', (tester) async {
      await pumpSurface(tester);
      await press(tester, LogicalKeyboardKey.arrowDown, 2);
      expect(focusedMatch(), 'm3');
      expect(find.textContaining('Lost · ${t.assistant.match.episodeCode(season: 4, episode: 5)}'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.select);

      expect(routes.single.id, 'tvDetail_${buildGlobalKey(ServerId(_zolder), '400')}_s404_e405');
    });

    testWidgets('only low confidence says "possibly"', (tester) async {
      await pumpSurface(tester);

      expect(find.textContaining(t.assistant.match.maybe), findsOneWidget);
      expect(find.text('${t.assistant.match.movie} · ${t.assistant.match.maybe}'), findsOneWidget);
    });

    testWidgets('the plot line is the text the title was matched on', (tester) async {
      await pumpSurface(tester);

      expect(find.text('Astronauts stranded on a dying Mars.'), findsOneWidget);
    });
  });

  group('in the summoned panel', () {
    late StreamController<void> presses;
    late FocusNode behind;

    setUp(() {
      presses = StreamController<void>.broadcast();
      behind = FocusNode(debugLabel: 'behind');
    });

    tearDown(() {
      unawaited(presses.close());
      behind.dispose();
    });

    Future<void> summon(WidgetTester tester, List<AssistantTitleMatch> matches, {AssistantDisplay? display}) async {
      final entry = AppleTvNativeTextEntry(channel: channel);
      await pumpTvFrame(
        tester,
        c,
        TvAssistantSummonHost(
          longPresses: presses.stream,
          speech: SpeechSearchService(textEntry: entry),
          textEntry: entry,
          child: Align(
            alignment: Alignment.topLeft,
            child: Focus(focusNode: behind, child: const SizedBox(width: 200, height: 200)),
          ),
        ),
      );
      behind.requestFocus();
      await settle(tester);
      presses.add(null);
      await settle(tester);
      await (display == null ? showMatches(tester, matches) : showDisplay(tester, display));
    }

    testWidgets('shows the matches in a window of three, stays, and Menu gives the remote back', (tester) async {
      await summon(tester, [_martian, _redPlanet, _episode, _extra]);

      expect(find.byType(BigPMatchCard), findsNWidgets(4));
      expect(focusedMatch(), 'm1');
      final window = tester.getRect(
        find.ancestor(of: find.byType(BigPMatchCard).first, matching: find.byType(SingleChildScrollView)).first,
      );
      expect(window.bottom, lessThanOrEqualTo(panelContent(tester).bottom + 1), reason: 'the list stays in the panel');
      // G (hardware round, 3 Oct): the summoned panel is wider and shows four cards at once.
      expect(tester.getRect(find.byType(BigPMatchCard).last).bottom, lessThanOrEqualTo(window.bottom + 1));
      expect(tester.getSize(find.byType(BigPMatchCard).first).width, greaterThan(600));

      await press(tester, LogicalKeyboardKey.arrowDown, 3);
      expect(focusedMatch(), 'm4');
      final last = tester.getRect(find.byType(BigPMatchCard).last);
      expect(last.bottom, lessThanOrEqualTo(window.bottom + 1), reason: 'focus scrolls the fourth card in');

      // A choice on screen: Big P does not leave on his own.
      await tester.pump(const Duration(seconds: 6));
      expect(focusedMatch(), 'm4');

      await press(tester, LogicalKeyboardKey.escape);
      expect(focusedLabel(), 'behind');
      expect(routes, isEmpty);
    });

    testWidgets('streamed results show in the window of three while Big P is still checking', (tester) async {
      await summon(tester, const []);
      c
        ..state = AssistantSurfaceState.working
        ..answer = ''
        ..displays = [_fourMatches()]
        ..stillChecking = true
        ..emit();
      await settle(tester);

      expect(find.text(t.assistant.working.stillChecking), findsOneWidget);
      expect(find.byType(BigPMatchCard), findsNWidgets(4));
      final window = tester.getRect(
        find.ancestor(of: find.byType(BigPMatchCard).first, matching: find.byType(SingleChildScrollView)).first,
      );
      expect(window.bottom, lessThanOrEqualTo(panelContent(tester).bottom + 1), reason: 'the list stays in the panel');
      expect(find.text(t.assistant.result.done), findsNothing, reason: 'not presented as finished');
      expect(focusedLabel(), 'assistant.cancel', reason: 'a streamed card does not take the remote');

      // Not a result yet: Big P does not leave on his own.
      await tester.pump(const Duration(seconds: 10));
      await settle(tester);
      expect(find.byType(BigPMatchCard), findsNWidgets(4));
      expect(focusedLabel(), 'assistant.cancel');

      await press(tester, LogicalKeyboardKey.escape);
      expect(focusedLabel(), 'behind');
    });

    testWidgets('a library match sends Big P away and opens the detail page', (tester) async {
      await summon(tester, [_martian, _redPlanet]);
      await press(tester, LogicalKeyboardKey.select);

      expect(routes.single.id, 'tvDetail_${_martian.targets.single.item.globalKey}');
      expect(find.byType(BigPMatchCard), findsNothing);
    });

    testWidgets('twelve cards under a long answer: the focused card and the first line are both in the panel', (
      tester,
    ) async {
      await summon(tester, const []);
      final answer = List.filled(40, 'Ik heb veel films met Tom Cruise gevonden.').join(' ');
      c
        ..state = AssistantSurfaceState.working
        ..emit();
      await settle(tester);
      c
        ..state = AssistantSurfaceState.result
        ..answer = answer
        ..displays = [_grid]
        ..emit();
      await settle(tester);

      final panel = panelContent(tester);
      expect(focusedMatch(), _grid.entries.first.item.globalKey);
      // Against the list's own viewport: inside the panel is not enough, a
      // card can sit behind the answer.
      final list = tester.getRect(
        find.ancestor(of: find.byType(BigPMatchCard).first, matching: find.byType(SingleChildScrollView)).first,
      );
      expectInside(focusedRect(), list, 'first card');
      expect(
        tester.getRect(find.byKey(const ValueKey('assistant.answer'))).top,
        inInclusiveRange(panel.top, panel.bottom),
      );
    });

    testWidgets('a media grid keeps Big P here and its first card opens the detail page', (tester) async {
      await summon(tester, const [], display: _grid);
      await tester.pump(const Duration(seconds: 10));
      await settle(tester);

      expect(focusedMatch(), _grid.entries.first.item.globalKey);
      await press(tester, LogicalKeyboardKey.select);

      expect(routes.single.id, 'tvDetail_${_grid.entries.first.item.globalKey}');
      expect(find.byType(BigPMatchCard), findsNothing);
    });

    testWidgets('while still checking a request candidate is dimmed and inert here too', (tester) async {
      await summon(tester, const []);
      await stillCheckingWith(tester);
      expect(focusedLabel(), 'assistant.cancel');
      await expectRequestInertWhileChecking(tester);
    });

    testWidgets('a request candidate goes to pickRequestOption', (tester) async {
      await summon(tester, [_martian, _redPlanet]);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);

      expect(c.picked.single.seerrId, 'movie:10');
      expect(routes, isEmpty);
    });
  });

  // One controller state machine for both: the summoned panel and the
  // surface show the same results in the same order and stand.
  group('surface and summoned panel from one controller state', () {
    late StreamController<void> presses;
    setUp(() => presses = StreamController<void>.broadcast());
    tearDown(() => unawaited(presses.close()));
    List<String> shown(WidgetTester tester) {
      final cards = find.byType(BigPMatchCard).evaluate().toList()
        ..sort(
          (a, b) =>
              tester.getTopLeft(find.byWidget(a.widget)).dy.compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy),
        );
      return [for (final e in cards) (e.widget as BigPMatchCard).match.matchId];
    }

    void setStillChecking() => c
      ..prompt = 'Die film over Mars'
      ..state = AssistantSurfaceState.working
      ..answer = ''
      ..steps = const [AssistantStep(index: 0, tool: 'find_title', phase: AssistantStepPhase.done)]
      ..displays = [_fourMatches()]
      ..stillChecking = true;

    void setResult() => c
      ..state = AssistantSurfaceState.result
      ..answer = 'Ik vond deze titels.'
      ..stillChecking = false;

    Future<(List<String>, String?, List<String>, String?)> run(
      WidgetTester tester,
      Widget host, {
      bool summon = false,
    }) async {
      await pumpTvFrame(tester, c, host);
      if (summon) {
        presses.add(null);
        await settle(tester);
      }
      setStillChecking();
      c.emit();
      await settle(tester);
      final checking = (
        shown(tester),
        find.text(t.assistant.working.stillChecking).evaluate().isEmpty ? null : 'checking',
      );
      setResult();
      c.emit();
      await settle(tester);
      return (
        checking.$1,
        checking.$2,
        shown(tester),
        find.text('Ik vond deze titels.').evaluate().isEmpty ? null : 'answer',
      );
    }

    testWidgets('same results, same order, same stand', (tester) async {
      final entry = AppleTvNativeTextEntry(channel: channel);
      final surface = await run(
        tester,
        TvAssistantScreen(
          speech: SpeechSearchService(textEntry: entry),
          textEntry: entry,
        ),
      );
      await tester.pumpWidget(const SizedBox());
      final summoned = await run(
        tester,
        TvAssistantSummonHost(
          longPresses: presses.stream,
          speech: SpeechSearchService(textEntry: entry),
          textEntry: entry,
          child: const SizedBox(),
        ),
        summon: true,
      );

      // Records compare lists by identity; their printed form compares content.
      expect('$surface', '([m1, m2, m3, m4], checking, [m1, m2, m3, m4], answer)');
      expect('$summoned', '$surface');
    });
  });
}
