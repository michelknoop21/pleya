import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/playback_report_metadata.dart';
import 'package:pleya/services/playback_report_session.dart';
import 'package:pleya/services/playback_write_authority.dart';

class _RecordingClient implements MediaServerClient {
  final calls = <String>[];
  Completer<void>? startGate;
  Completer<void>? stopGate;
  bool failNextStop = false;

  @override
  Future<void> reportPlaybackStarted({
    required String itemId,
    required Duration position,
    Duration? duration,
    String? playSessionId,
    String? playMethod,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    final gate = startGate;
    if (gate != null) await gate.future;
    calls.add('started:${position.inMilliseconds}:$mediaSourceId:$audioStreamIndex:$subtitleStreamIndex');
  }

  @override
  Future<void> reportPlaybackProgress({
    required String itemId,
    required Duration position,
    required Duration duration,
    bool isPaused = false,
    String? playSessionId,
    String? playMethod,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    calls.add('${isPaused ? 'paused' : 'playing'}:${position.inMilliseconds}');
  }

  @override
  Future<void> reportPlaybackStopped({
    required String itemId,
    required Duration position,
    Duration? duration,
    String? playSessionId,
    String? mediaSourceId,
    PlaybackReportMetadata report = const PlaybackReportMetadata.live(),
  }) async {
    calls.add('stopped-attempt:${position.inMilliseconds}:$mediaSourceId');
    final gate = stopGate;
    if (gate != null) await gate.future;
    if (failNextStop) {
      failNextStop = false;
      throw StateError('stop failed');
    }
    calls.add('stopped:${position.inMilliseconds}:$mediaSourceId');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PlaybackReportSnapshot _snapshot(
  String state, {
  int positionMs = 1000,
  PlaybackStreamSelectionResolver resolveStreamSelection = _noStreamSelection,
}) {
  return PlaybackReportSnapshot(
    state: state,
    position: Duration(milliseconds: positionMs),
    duration: const Duration(minutes: 1),
    resolveStreamSelection: resolveStreamSelection,
  );
}

PlaybackStreamSelection _noStreamSelection() => PlaybackStreamSelection.none;

void main() {
  test('orders stopped after start even when stream selection is still resolving', () async {
    final client = _RecordingClient();
    final session = PlaybackReportSession(client: client, itemId: 'item-1');
    final selectionGate = Completer<PlaybackStreamSelection>();

    final startFuture = session.report(_snapshot('playing', resolveStreamSelection: () => selectionGate.future));
    await Future<void>.delayed(Duration.zero);

    final stopFuture = session.report(_snapshot('stopped', positionMs: 5000));
    await Future<void>.delayed(Duration.zero);
    expect(client.calls, isEmpty);

    selectionGate.complete(const PlaybackStreamSelection(mediaSourceId: 'source-1', audioStreamIndex: 2));
    await stopFuture;
    await startFuture;

    expect(client.calls, ['started:1000:source-1:2:null', 'stopped-attempt:5000:null', 'stopped:5000:null']);
  });

  test('coalesces duplicate starts while start report is in flight', () async {
    final client = _RecordingClient()..startGate = Completer<void>();
    final session = PlaybackReportSession(client: client, itemId: 'item-1');

    final first = session.report(_snapshot('playing', positionMs: 1000));
    final second = session.report(_snapshot('playing', positionMs: 2000));
    await Future<void>.delayed(Duration.zero);
    expect(client.calls, isEmpty);

    client.startGate!.complete();
    await Future.wait([first, second]);

    expect(client.calls, ['started:1000:null:null:null']);
  });

  test('coalesces a state change during start into one progress report after start', () async {
    final client = _RecordingClient()..startGate = Completer<void>();
    final session = PlaybackReportSession(client: client, itemId: 'item-1');

    final first = session.report(_snapshot('playing', positionMs: 1000));
    final second = session.report(_snapshot('paused', positionMs: 2000));
    await Future<void>.delayed(Duration.zero);

    client.startGate!.complete();
    await Future.wait([first, second]);

    expect(client.calls, ['started:1000:null:null:null', 'paused:2000']);
  });

  test('terminal stop suppresses in-flight progress after its stream selection resolves', () async {
    final client = _RecordingClient();
    final session = PlaybackReportSession(client: client, itemId: 'item-1');
    await session.report(_snapshot('playing', positionMs: 1000));
    client.calls.clear();

    final selectionGate = Completer<PlaybackStreamSelection>();
    final progressFuture = session.report(
      _snapshot('playing', positionMs: 2000, resolveStreamSelection: () => selectionGate.future),
    );
    await Future<void>.delayed(Duration.zero);

    final stopFuture = session.report(_snapshot('stopped', positionMs: 3000));
    selectionGate.complete(PlaybackStreamSelection.none);
    await stopFuture;
    expect(await progressFuture, isFalse);

    expect(client.calls, ['stopped-attempt:3000:null', 'stopped:3000:null']);
  });

  test('queued progress resolves false when terminal stop suppresses it during startup', () async {
    final client = _RecordingClient()..startGate = Completer<void>();
    final session = PlaybackReportSession(client: client, itemId: 'item-1');

    final startFuture = session.report(_snapshot('playing', positionMs: 1000));
    final progressFuture = session.report(_snapshot('paused', positionMs: 2000));
    await Future<void>.delayed(Duration.zero);

    final stopFuture = session.report(_snapshot('stopped', positionMs: 3000));
    client.startGate!.complete();

    await stopFuture;
    await startFuture;

    expect(await progressFuture, isFalse);
    expect(client.calls, ['started:1000:null:null:null', 'stopped-attempt:3000:null', 'stopped:3000:null']);
  });

  test('stop failure allows explicit stopped retry but ignores non-stop reports', () async {
    final client = _RecordingClient()..failNextStop = true;
    final session = PlaybackReportSession(client: client, itemId: 'item-1');

    await expectLater(session.report(_snapshot('stopped', positionMs: 1000)), throwsStateError);
    await session.report(_snapshot('playing', positionMs: 2000));
    await session.report(_snapshot('stopped', positionMs: 3000));

    expect(client.calls, ['stopped-attempt:1000:null', 'stopped-attempt:3000:null', 'stopped:3000:null']);
  });

  test('resetAfterStop during in-flight stop reopens reporting after stop completes', () async {
    final client = _RecordingClient()..stopGate = Completer<void>();
    final session = PlaybackReportSession(client: client, itemId: 'item-1');

    await session.report(_snapshot('playing', positionMs: 1000));
    client.calls.clear();

    final stopFuture = session.report(_snapshot('stopped', positionMs: 3000));
    await Future<void>.delayed(Duration.zero);
    expect(client.calls, ['stopped-attempt:3000:null']);

    session.resetAfterStop();
    client.stopGate!.complete();
    await stopFuture;

    expect(session.isIdle, isTrue);
    expect(await session.report(_snapshot('playing', positionMs: 4000)), isTrue);
    expect(client.calls, ['stopped-attempt:3000:null', 'stopped:3000:null', 'started:4000:null:null:null']);
  });

  test('resetAfterStop on a completed stop reopens reporting with a fresh start', () async {
    // The background path on a TV: the stop lands, the app comes back, and the
    // resume has to be able to open a new session. Without this the session
    // stays terminal and every later report is refused.
    final client = _RecordingClient();
    final session = PlaybackReportSession(client: client, itemId: 'item-1');

    await session.report(_snapshot('playing', positionMs: 1000));
    await session.report(_snapshot('stopped', positionMs: 3000));
    expect(session.isStopped, isTrue);
    client.calls.clear();

    session.resetAfterStop();
    expect(session.isIdle, isTrue);
    expect(await session.report(_snapshot('playing', positionMs: 3000)), isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(client.calls, ['started:3000:null:null:null']);
  });

  test('resetAfterStop while nothing was stopped is a no-op', () async {
    final client = _RecordingClient();
    final session = PlaybackReportSession(client: client, itemId: 'item-1');

    session.resetAfterStop();
    expect(session.isIdle, isTrue);

    await session.report(_snapshot('playing', positionMs: 1000));
    session.resetAfterStop();
    await Future<void>.delayed(Duration.zero);

    expect(await session.report(_snapshot('playing', positionMs: 2000)), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(client.calls, ['started:1000:null:null:null', 'playing:2000']);
  });

  group('observed write authority', () {
    ObservedPlaybackAuthority authority() => ObservedPlaybackAuthority(sessionId: 'this-device', itemId: 'item-1');

    test('a held authority changes nothing', () async {
      final client = _RecordingClient();
      final session = PlaybackReportSession(client: client, itemId: 'item-1', authority: authority());

      expect(await session.report(_snapshot('playing', positionMs: 1000)), isTrue);

      expect(client.calls, ['started:1000:null:null:null']);
    });

    test('a revoked authority blocks a late progress report', () async {
      final client = _RecordingClient();
      final held = authority();
      final session = PlaybackReportSession(client: client, itemId: 'item-1', authority: held);
      await session.report(_snapshot('playing', positionMs: 1000));
      client.calls.clear();

      held.observeForeignPlaying(itemId: 'item-1', sessionId: 'apple-tv');

      expect(await session.report(_snapshot('playing', positionMs: 2000)), isFalse);
      expect(client.calls, isEmpty);
    });

    test('a revoked authority blocks a late paused report', () async {
      final client = _RecordingClient();
      final held = authority();
      final session = PlaybackReportSession(client: client, itemId: 'item-1', authority: held);
      await session.report(_snapshot('playing', positionMs: 1000));
      client.calls.clear();

      held.observeForeignPlaying(itemId: 'item-1', sessionId: 'apple-tv');

      expect(await session.report(_snapshot('paused', positionMs: 2000)), isFalse);
      expect(client.calls, isEmpty);
    });

    test('a revoked authority blocks the stopped report, which is the rollback case', () async {
      // The Mutiny shape: this device sat paused while another played on. Its
      // stop report carries the older position, so it must never be sent.
      final client = _RecordingClient();
      final held = authority();
      final session = PlaybackReportSession(client: client, itemId: 'item-1', authority: held);
      await session.report(_snapshot('playing', positionMs: 1000));
      client.calls.clear();

      held.observeForeignPlaying(itemId: 'item-1', sessionId: 'apple-tv');

      expect(await session.report(_snapshot('stopped', positionMs: 2000)), isFalse);
      expect(client.calls, isEmpty);
    });

    test('a revocation during an in-flight stream selection still cancels the write', () async {
      final client = _RecordingClient();
      final held = authority();
      final session = PlaybackReportSession(client: client, itemId: 'item-1', authority: held);
      final selectionGate = Completer<PlaybackStreamSelection>();

      final startFuture = session.report(
        _snapshot('playing', positionMs: 1000, resolveStreamSelection: () => selectionGate.future),
      );
      await Future<void>.delayed(Duration.zero);

      held.observeForeignPlaying(itemId: 'item-1', sessionId: 'apple-tv');
      selectionGate.complete(PlaybackStreamSelection.none);
      await startFuture;

      expect(client.calls, isEmpty);
    });

    test('taking the authority back reopens reporting', () async {
      final client = _RecordingClient();
      final held = authority();
      final session = PlaybackReportSession(client: client, itemId: 'item-1', authority: held);
      held.observeForeignPlaying(itemId: 'item-1', sessionId: 'apple-tv');

      expect(await session.report(_snapshot('playing', positionMs: 1000)), isFalse);

      held.take(reason: 'user pressed play');

      expect(await session.report(_snapshot('playing', positionMs: 2000)), isTrue);
      expect(client.calls, ['started:2000:null:null:null']);
    });
  });
}
