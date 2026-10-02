/// find_title's results on TV (38-motion-7): a found title in a library
/// opens its detail page, one only Seerr knows goes to the request card,
/// on the surface and in the summoned panel.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/navigation/tv/tv_content_route_registry.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_confirm_card.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_match_card.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_screen.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_summon.dart';
import 'package:pleya/services/apple_tv_native_text_entry.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/speech_search_service.dart';
import 'package:pleya/utils/native_input_session.dart';
import 'package:pleya/utils/global_key_utils.dart';
import 'package:pleya/utils/platform_detector.dart';

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
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvAssistantMatchCard>()?.match.matchId;

  Future<void> showMatches(WidgetTester tester, List<AssistantTitleMatch> matches) async {
    c
      ..prompt = 'Die film over Mars'
      ..state = AssistantSurfaceState.result
      ..answer = 'Ik vond deze titels.'
      ..displays = [AssistantTitleMatches(AssistantToolContext(servers: MultiServerManager()), matches)]
      ..emit();
    await settle(tester);
  }

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

    testWidgets('the first card takes the focus; a library match opens its detail page', (tester) async {
      await pumpSurface(tester);

      expect(find.byType(TvAssistantMatchCard), findsNWidgets(3));
      expect(focusedMatch(), 'm1');
      expect(find.text(t.assistant.match.inLibrary(servers: 'Zolder')), findsNWidgets(2));
      await press(tester, LogicalKeyboardKey.select);

      expect(routes.single.id, 'tvDetail_${_martian.targets.single.item.globalKey}');
      expect(c.picked, isEmpty);
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
      expect(find.byType(TvAssistantConfirmCard), findsOneWidget);
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

    Future<void> summon(WidgetTester tester, List<AssistantTitleMatch> matches) async {
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
      await showMatches(tester, matches);
    }

    testWidgets('shows the matches in a window of three, stays, and Menu gives the remote back', (tester) async {
      await summon(tester, [_martian, _redPlanet, _episode, _extra]);

      expect(find.byType(TvAssistantMatchCard), findsNWidgets(4));
      expect(focusedMatch(), 'm1');
      final window = tester.getRect(
        find.ancestor(of: find.byType(TvAssistantMatchCard).first, matching: find.byType(ConstrainedBox)).first,
      );
      expect(window.height, lessThanOrEqualTo(3 * 134 + 1));

      await press(tester, LogicalKeyboardKey.arrowDown, 3);
      expect(focusedMatch(), 'm4');
      final last = tester.getRect(find.byType(TvAssistantMatchCard).last);
      expect(last.bottom, lessThanOrEqualTo(window.bottom + 1), reason: 'focus scrolls the fourth card in');

      // A choice on screen: Big P does not leave on his own.
      await tester.pump(const Duration(seconds: 6));
      expect(focusedMatch(), 'm4');

      await press(tester, LogicalKeyboardKey.escape);
      expect(focusedLabel(), 'behind');
      expect(routes, isEmpty);
    });

    testWidgets('a library match sends Big P away and opens the detail page', (tester) async {
      await summon(tester, [_martian, _redPlanet]);
      await press(tester, LogicalKeyboardKey.select);

      expect(routes.single.id, 'tvDetail_${_martian.targets.single.item.globalKey}');
      expect(find.byType(TvAssistantMatchCard), findsNothing);
    });

    testWidgets('a request candidate goes to pickRequestOption', (tester) async {
      await summon(tester, [_martian, _redPlanet]);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);

      expect(c.picked.single.seerrId, 'movie:10');
      expect(routes, isEmpty);
    });
  });
}
