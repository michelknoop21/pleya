// Meenemen from the Apple TV's Fly picker (A-23e): the phone receives a
// handoff that carries a session to follow. It joins that session instead of
// opening the player itself, and reports once it joined.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/providers/companion_remote_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/companion_remote/playback_handoff.dart';
import 'package:pleya/services/companion_remote/playback_handoff_receiver.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/watch_together/providers/watch_together_provider.dart';
import 'package:provider/provider.dart';

const _session = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

class _Client extends Fake implements MediaServerClient {
  @override
  Future<MediaItem?> fetchItem(String id) async =>
      MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Dune: Part Two');
}

class _Servers extends MultiServerProvider {
  _Servers(super.manager, super.aggregation);

  @override
  MediaServerClient? getClientForServer(ServerId serverId) => _Client();
}

class _PushCounter extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

class _WatchTogether extends WatchTogetherProvider {
  _WatchTogether({this.codeSession = false});
  final bool codeSession;
  final joins = <({String id, bool fly, String? relay})>[];

  @override
  bool get isInSession => codeSession;

  @override
  Future<void> joinSession(String sessionId, {String? displayName, bool flySession = false, String? relayUrl}) async =>
      joins.add((id: sessionId, fly: flySession, relay: relayUrl));
}

PlaybackHandoffRequest _request(String id, {String? session = _session}) => PlaybackHandoffRequest(
  id: id,
  serverId: 'server_1',
  itemId: 'item_9',
  positionMs: 4602000,
  title: 'Dune: Part Two',
  from: 'Woonkamer',
  followSessionId: session,
  relayUrl: session == null ? null : 'https://relay.example',
);

void main() {
  late BuildContext context;
  late _PushCounter pushes;

  Future<void> pump(WidgetTester tester, _WatchTogether watchTogether) async {
    pushes = _PushCounter();
    final manager = MultiServerManager();
    addTearDown(manager.dispose);
    final servers = _Servers(manager, DataAggregationService(manager));
    addTearDown(servers.dispose);
    final remote = CompanionRemoteProvider();
    addTearDown(remote.dispose);
    addTearDown(watchTogether.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
          ChangeNotifierProvider<CompanionRemoteProvider>.value(value: remote),
          ChangeNotifierProvider<WatchTogetherProvider>.value(value: watchTogether),
        ],
        child: MaterialApp(
          navigatorObservers: [pushes],
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    pushes.pushes = 0;
  }

  testWidgets('a follow joins the session as a follower, with the TV relay, and opens no player itself', (
    tester,
  ) async {
    final watchTogether = _WatchTogether();
    await pump(tester, watchTogether);
    final id = 'follow-${DateTime.now().microsecondsSinceEpoch}';
    await tester.runAsync(() => receivePlaybackHandoff(context, _request(id)));

    expect(watchTogether.joins, [(id: _session, fly: true, relay: 'https://relay.example')]);
    expect(playbackHandoffLedger.outcomeOf(id), PlaybackHandoffOutcome.playing);
    expect(pushes.pushes, 0, reason: 'the session state opens the player, not the receiver');
  });

  testWidgets('a phone in its own Samen kijken session refuses instead of leaving it', (tester) async {
    final watchTogether = _WatchTogether(codeSession: true);
    await pump(tester, watchTogether);
    final id = 'busy-${DateTime.now().microsecondsSinceEpoch}';
    await tester.runAsync(() => receivePlaybackHandoff(context, _request(id)));

    expect(watchTogether.joins, isEmpty);
    expect(playbackHandoffLedger.outcomeOf(id), PlaybackHandoffOutcome.failed);
  });
}
