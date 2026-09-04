import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:flutter/material.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/rating_actions.dart';
import 'package:provider/provider.dart';

/// The fan-out half of [DEC-075](../../docs/DECISIONS.md#dec-075): a rating
/// describes the title, so it is written to every membership of it.
///
/// Driven through `RatingMirror.withTargets`, which is the whole reason that
/// constructor exists. The resolution half needs providers and a widget tree;
/// what these tests are about is the write loop, and the two properties it has
/// to hold are both invisible in a widget test: that a failing sibling does not
/// stop the others, and that a burst of values ends on the last one rather than
/// on whichever PUT happened to land last.

class _RecordingClient implements MediaServerClient {
  _RecordingClient({this.failWith, this.gate});

  /// Thrown by every [rate] call when set.
  final Object? failWith;

  /// Held before each write completes, so a test can interleave calls.
  final Future<void> Function()? gate;

  final List<double> writes = [];

  @override
  Future<void> rate(MediaItem item, double rating) async {
    if (gate != null) await gate!();
    writes.add(rating);
    if (failWith != null) throw failWith!;
  }

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  ServerId get serverId => ServerId('s');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

RatingMirrorTarget _target(String key, MediaServerClient client) => RatingMirrorTarget(
  sourceKey: key,
  client: client,
  item: MediaItem(
    id: key.split(':').last,
    backend: MediaBackend.plex,
    kind: MediaKind.unknown,
    title: 'Dune',
    serverId: key.split(':').first,
  ),
);

void main() {
  _resolutionTests();

  group('the write reaches every sibling', () {
    test('a rating lands on all of them, and the origin is counted too', () async {
      final a = _RecordingClient();
      final b = _RecordingClient();
      final mirror = RatingMirror.withTargets([_target('s2:i2', a), _target('s3:i3', b)]);

      mirror.write(8);
      await mirror.settled;

      expect(a.writes, [8.0]);
      expect(b.writes, [8.0]);
      expect(mirror.doneCount, 3, reason: 'the sheet wrote the origin itself before this mirror ever ran');
      expect(mirror.intendedTargetCount, 3);
      expect(mirror.failedSourceKeys, isEmpty);
    });

    test('the clear sentinel is passed through, not flattened to a zero', () async {
      // The bug this feature would otherwise have shipped with: `0` is a real
      // 0/10 on Plex, so mirroring the display value would turn "wis mijn
      // cijfer" into "ik vond het niets" on every other server.
      final sibling = _RecordingClient();
      final mirror = RatingMirror.withTargets([_target('s2:i2', sibling)]);

      mirror.write(-1);
      await mirror.settled;

      expect(sibling.writes, [-1.0]);
    });

    test('one refusing server does not stop the others', () async {
      final ok = _RecordingClient();
      final broken = _RecordingClient(failWith: StateError('nope'));
      final mirror = RatingMirror.withTargets([_target('s2:i2', broken), _target('s3:i3', ok)]);

      mirror.write(6);
      await mirror.settled;

      expect(ok.writes, [6.0], reason: 'the loop collects failures rather than aborting on the first');
      expect(mirror.failedSourceKeys, {'s2:i2'});
      expect(mirror.doneCount, 2, reason: 'origin plus the one that took it');
      expect(mirror.intendedTargetCount, 3);
    });
  });

  group('the denominator is the intent', () {
    test('an unreachable membership is counted but never written to', () async {
      final sibling = _RecordingClient();
      final mirror = RatingMirror.withTargets([_target('s2:i2', sibling)], unreachableCount: 1);

      mirror.write(4);
      await mirror.settled;

      expect(sibling.writes, [4.0]);
      expect(mirror.doneCount, 2);
      expect(
        mirror.intendedTargetCount,
        3,
        reason: 'a rating holds nothing for later, so being counted is the only thing that happens to it',
      );
    });

    test('a mirror with nothing to write to still reports the membership it could not reach', () async {
      final mirror = RatingMirror.withTargets([], unreachableCount: 1);

      mirror.write(4);
      await mirror.settled;

      expect(mirror.hasTargets, isFalse);
      expect(mirror.doneCount, 1);
      expect(mirror.intendedTargetCount, 2, reason: '"gelukt op 1 van 2" is the sentence this makes possible');
    });
  });

  group('a burst of values ends on the last one', () {
    test('writes are serialised and intermediate values are dropped', () async {
      // Not an optimisation. Two concurrent PUTs of 6 and then 8 to the same
      // server can land in either order and leave it on 6, so the drag has to
      // be collapsed rather than replayed.
      final release = Completer<void>();
      var gated = true;
      final sibling = _RecordingClient(
        gate: () async {
          if (!gated) return;
          gated = false;
          await release.future;
        },
      );
      final mirror = RatingMirror.withTargets([_target('s2:i2', sibling)]);

      mirror.write(2);
      await Future<void>.delayed(Duration.zero);
      mirror.write(6);
      mirror.write(8);
      release.complete();
      await mirror.settled;

      expect(sibling.writes, [
        2.0,
        8.0,
      ], reason: 'the 6 is superseded before it is ever sent, and the last value is what survives');
    });

    test('a second burst after the first settled still writes', () async {
      final sibling = _RecordingClient();
      final mirror = RatingMirror.withTargets([_target('s2:i2', sibling)]);

      mirror.write(2);
      await mirror.settled;
      mirror.write(9);
      await mirror.settled;

      expect(sibling.writes, [2.0, 9.0], reason: 'the chain has to re-arm, or the dispose flush is lost');
    });

    test('the same value twice is written once', () async {
      final sibling = _RecordingClient();
      final mirror = RatingMirror.withTargets([_target('s2:i2', sibling)]);

      mirror.write(7);
      await mirror.settled;
      mirror.write(7);
      await mirror.settled;

      expect(sibling.writes, [7.0]);
    });
  });
}

/// The resolution half, for the one property that is invisible without it:
/// every membership this rating set out to reach has to stay in the
/// denominator, whatever the reason it could not be written to.
class _CapabilityClient implements MediaServerClient {
  _CapabilityClient({required this.id, required this.rating});

  final String id;
  final bool rating;

  @override
  ServerId get serverId => ServerId(id);

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => rating ? ServerCapabilities.plex : ServerCapabilities.local;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _resolutionTests() {
  testWidgets('a membership on a backend that cannot rate stays in the denominator', (tester) async {
    // It used to be skipped outright, so the tally read "done on all 2" for a
    // title on three servers and the message was suppressed as complete.
    // DEC-075 says the fan-out reaches everything it can *and reports the
    // rest*; a membership that is neither reached nor reported is neither.
    final manager = MultiServerManager()
      ..debugRegisterClientForTesting(_CapabilityClient(id: 's1', rating: true))
      ..debugRegisterClientForTesting(_CapabilityClient(id: 's2', rating: true))
      ..debugRegisterClientForTesting(_CapabilityClient(id: 's3', rating: false));
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(multiServer.dispose);

    late BuildContext ctx;
    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: multiServer,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final mirror = RatingMirror.fromSourceKeys(
      ctx,
      sourceKeys: const ['s1:i1', 's2:i2', 's3:i3'],
      originSourceKey: 's1:i1',
    );

    expect(mirror.intendedTargetCount, 3, reason: 'origin, the sibling that can be written, and the one that cannot');
  });
}
