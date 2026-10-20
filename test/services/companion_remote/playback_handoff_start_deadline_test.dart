import 'dart:async';

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
import 'package:provider/provider.dart';

PlaybackHandoffRequest _request(String id) => PlaybackHandoffRequest(
  id: id,
  serverId: 'server_1',
  itemId: 'item_9',
  positionMs: 1000,
  title: 'Big Buck Bunny',
  from: 'iPhone van Anna',
);

class _Client extends Fake implements MediaServerClient {
  _Client(this.fetch);
  final Future<MediaItem?> Function() fetch;

  @override
  Future<MediaItem?> fetchItem(String id) => fetch();
}

class _Servers extends MultiServerProvider {
  _Servers(super.manager, super.aggregation, this.client);
  final MediaServerClient client;

  @override
  MediaServerClient? getClientForServer(ServerId serverId) => client;
}

class _PushCounter extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

/// The start deadline of a handoff after a profile switch (A-23b): the Apple TV
/// never opens the player after the last start time, and a fetch that hangs
/// does not keep the receiver busy.
void main() {
  late Completer<MediaItem?> fetch;
  late _PushCounter pushes;
  late BuildContext context;

  Future<void> pump(WidgetTester tester) async {
    fetch = Completer<MediaItem?>();
    pushes = _PushCounter();
    final manager = MultiServerManager();
    addTearDown(manager.dispose);
    final servers = _Servers(manager, DataAggregationService(manager), _Client(() => fetch.future));
    addTearDown(servers.dispose);
    final remote = CompanionRemoteProvider();
    addTearDown(remote.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
          ChangeNotifierProvider<CompanionRemoteProvider>.value(value: remote),
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

  final movie = MediaItem(id: 'item_9', backend: MediaBackend.jellyfin, kind: MediaKind.movie, title: 'Big Buck Bunny');

  testWidgets('a fetch that hangs past the deadline fails the handoff and frees the receiver', (tester) async {
    await pump(tester);
    final id = 'hang-${DateTime.now().microsecondsSinceEpoch}';
    var done = false;
    await tester.runAsync(() async {
      unawaited(
        receivePlaybackHandoff(
          context,
          _request(id),
          mayStart: () => true,
          startWithin: const Duration(milliseconds: 50),
        ).then((_) => done = true),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    expect(done, isTrue, reason: 'the receiver does not wait for the fetch past the deadline');
    expect(playbackHandoffLedger.outcomeOf(id), PlaybackHandoffOutcome.failed);

    // The late fetch result is ignored: nothing opens.
    fetch.complete(movie);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(pushes.pushes, 0);

    // The guard is free: a next handoff is handled (an unplayable item is answered, not skipped).
    fetch = Completer<MediaItem?>()..complete(null);
    final next = 'next-$id';
    await tester.runAsync(() => receivePlaybackHandoff(context, _request(next)));
    expect(playbackHandoffLedger.outcomeOf(next), PlaybackHandoffOutcome.failed);
  });

  testWidgets('a fetch that ends after the last start time does not open the player', (tester) async {
    await pump(tester);
    final id = 'late-${DateTime.now().microsecondsSinceEpoch}';
    var late = false;
    final receiving = receivePlaybackHandoff(context, _request(id), mayStart: () => !late);
    late = true;
    fetch.complete(movie);
    await tester.runAsync(() => receiving);
    expect(pushes.pushes, 0);
    expect(playbackHandoffLedger.outcomeOf(id), PlaybackHandoffOutcome.failed);
  });

  testWidgets('a context that is gone when the deadline passes still fails the handoff and frees the receiver', (
    tester,
  ) async {
    await pump(tester);
    final id = 'gone-${DateTime.now().microsecondsSinceEpoch}';
    var done = false;
    await tester.runAsync(() async {
      unawaited(
        receivePlaybackHandoff(
          context,
          _request(id),
          mayStart: () => true,
          startWithin: const Duration(milliseconds: 50),
        ).then((_) => done = true),
      );
      await tester.pumpWidget(const SizedBox());
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    expect(done, isTrue);
    expect(playbackHandoffLedger.outcomeOf(id), PlaybackHandoffOutcome.failed);
  });

  testWidgets('a fetch that ends in time reports once', (tester) async {
    await pump(tester);
    final id = 'once-${DateTime.now().microsecondsSinceEpoch}';
    await tester.runAsync(() async {
      final receiving = receivePlaybackHandoff(
        context,
        _request(id),
        mayStart: () => true,
        startWithin: const Duration(milliseconds: 80),
      );
      fetch.complete(null);
      await receiving;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    expect(playbackHandoffLedger.outcomeOf(id), PlaybackHandoffOutcome.failed);
    expect(pushes.pushes, 0);
  });
}
