import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/playback_resume_resolver.dart';

// Coverage:
//   - Tier 1: restart and an explicitly requested position short-circuit.
//   - Tier 2: a deliberate local action that is provably newer beats the
//     backend; a passive one does not beat a *fresh* backend value.
//   - Tier 3/4: fresh backend progress outranks cached screen metadata.
//   - Tier 5: local progress is used only when the backend has nothing.
//   - The Mutiny report: a paused player must not push a further-along active
//     player backwards.
//   - The online/offline mix-up: playing a downloaded file while online used
//     to prefer the local value unconditionally.

final _t0 = DateTime.utc(2026, 8, 20, 20, 0);

LocalResumeProgress _local(
  Duration position, {
  required DateTime updatedAt,
  PlaybackResumeIntent intent = PlaybackResumeIntent.passive,
  PlaybackResumeOrigin origin = PlaybackResumeOrigin.offlinePlayback,
}) {
  return LocalResumeProgress(position: position, updatedAt: updatedAt, intent: intent, origin: origin);
}

BackendResumeProgress _backend(Duration position, {required bool isFresh, DateTime? updatedAt}) {
  return BackendResumeProgress(position: position, isFresh: isFresh, updatedAt: updatedAt);
}

void main() {
  group('tier 1 — explicit intent', () {
    test('restart wins over every other source', () {
      final result = PlaybackResumeResolver.resolve(
        restartFromBeginning: true,
        requestedPosition: const Duration(minutes: 30),
        local: _local(const Duration(minutes: 40), updatedAt: _t0),
        backend: _backend(const Duration(minutes: 20), isFresh: true, updatedAt: _t0),
      );

      expect(result.source, PlaybackResumeSource.restart);
      expect(result.position, Duration.zero);
    });

    test('a requested position wins over local and backend', () {
      final result = PlaybackResumeResolver.resolve(
        requestedPosition: const Duration(minutes: 5),
        local: _local(const Duration(minutes: 40), updatedAt: _t0),
        backend: _backend(const Duration(minutes: 20), isFresh: true, updatedAt: _t0),
      );

      expect(result.source, PlaybackResumeSource.requested);
      expect(result.position, const Duration(minutes: 5));
    });

    test('rewinding to an earlier position stays possible', () {
      final result = PlaybackResumeResolver.resolve(
        requestedPosition: const Duration(minutes: 2),
        backend: _backend(const Duration(minutes: 55), isFresh: true, updatedAt: _t0),
      );

      expect(result.position, const Duration(minutes: 2));
    });
  });

  group('tier 2 — a local action that is provably newer', () {
    test('a deliberate user action newer than fresh backend progress wins', () {
      final result = PlaybackResumeResolver.resolve(
        local: _local(
          const Duration(minutes: 42),
          updatedAt: _t0.add(const Duration(minutes: 10)),
          intent: PlaybackResumeIntent.explicit,
          origin: PlaybackResumeOrigin.userAction,
        ),
        backend: _backend(const Duration(minutes: 12), isFresh: true, updatedAt: _t0),
      );

      expect(result.source, PlaybackResumeSource.localNewer);
      expect(result.position, const Duration(minutes: 42));
    });

    test('a passive local write does not beat fresh backend progress, even when newer', () {
      final result = PlaybackResumeResolver.resolve(
        local: _local(const Duration(minutes: 42), updatedAt: _t0.add(const Duration(minutes: 10))),
        backend: _backend(const Duration(minutes: 12), isFresh: true, updatedAt: _t0),
      );

      expect(result.source, PlaybackResumeSource.freshBackend);
      expect(result.position, const Duration(minutes: 12));
    });

    test('an explicit intent with an offline-playback origin is not treated as deliberate', () {
      final result = PlaybackResumeResolver.resolve(
        local: _local(
          const Duration(minutes: 42),
          updatedAt: _t0.add(const Duration(minutes: 10)),
          intent: PlaybackResumeIntent.explicit,
        ),
        backend: _backend(const Duration(minutes: 12), isFresh: true, updatedAt: _t0),
      );

      expect(result.source, PlaybackResumeSource.freshBackend);
    });

    test('an older local record never wins, however deliberate', () {
      final result = PlaybackResumeResolver.resolve(
        local: _local(
          const Duration(minutes: 42),
          updatedAt: _t0.subtract(const Duration(minutes: 10)),
          intent: PlaybackResumeIntent.explicit,
          origin: PlaybackResumeOrigin.userAction,
        ),
        backend: _backend(const Duration(minutes: 12), isFresh: true, updatedAt: _t0),
      );

      expect(result.source, PlaybackResumeSource.freshBackend);
      expect(result.position, const Duration(minutes: 12));
    });

    test('a newer passive local record does beat a stale cached value', () {
      final result = PlaybackResumeResolver.resolve(
        local: _local(const Duration(minutes: 42), updatedAt: _t0.add(const Duration(minutes: 10))),
        backend: _backend(const Duration(minutes: 12), isFresh: false, updatedAt: _t0),
      );

      expect(result.source, PlaybackResumeSource.localNewer);
      expect(result.position, const Duration(minutes: 42));
    });

    test('without a backend timestamp a fresh backend value keeps precedence', () {
      final result = PlaybackResumeResolver.resolve(
        local: _local(
          const Duration(minutes: 42),
          updatedAt: _t0,
          intent: PlaybackResumeIntent.explicit,
          origin: PlaybackResumeOrigin.userAction,
        ),
        backend: _backend(const Duration(minutes: 12), isFresh: true),
      );

      expect(result.source, PlaybackResumeSource.freshBackend);
    });

    test('without a backend timestamp a deliberate action still beats cached metadata', () {
      final result = PlaybackResumeResolver.resolve(
        local: _local(
          const Duration(minutes: 42),
          updatedAt: _t0,
          intent: PlaybackResumeIntent.explicit,
          origin: PlaybackResumeOrigin.userAction,
        ),
        backend: _backend(const Duration(minutes: 12), isFresh: false),
      );

      expect(result.source, PlaybackResumeSource.localNewer);
    });

    test('a simultaneous timestamp is not newer', () {
      final result = PlaybackResumeResolver.resolve(
        local: _local(
          const Duration(minutes: 42),
          updatedAt: _t0,
          intent: PlaybackResumeIntent.explicit,
          origin: PlaybackResumeOrigin.userAction,
        ),
        backend: _backend(const Duration(minutes: 12), isFresh: true, updatedAt: _t0),
      );

      expect(result.source, PlaybackResumeSource.freshBackend);
    });
  });

  group('tier 3 and 4 — backend progress', () {
    test('fresh backend progress is used when nothing local is newer', () {
      final result = PlaybackResumeResolver.resolve(backend: _backend(const Duration(minutes: 12), isFresh: true));

      expect(result.source, PlaybackResumeSource.freshBackend);
      expect(result.position, const Duration(minutes: 12));
    });

    test('cached screen metadata is the fallback when the fetch produced nothing', () {
      final result = PlaybackResumeResolver.resolve(backend: _backend(const Duration(minutes: 12), isFresh: false));

      expect(result.source, PlaybackResumeSource.cachedMetadata);
      expect(result.position, const Duration(minutes: 12));
    });

    test('a stale detail screen still yields to the freshly fetched position', () {
      // Same call shape the navigation layer produces: the screen snapshot is
      // dropped in favour of the refetch, so only the fresh value can be seen.
      final result = PlaybackResumeResolver.resolve(backend: _backend(const Duration(minutes: 3), isFresh: true));

      expect(result.position, const Duration(minutes: 3));
      expect(result.source, PlaybackResumeSource.freshBackend);
    });
  });

  group('tier 5 — local as last resort', () {
    test('local progress is used when the backend has nothing at all', () {
      final result = PlaybackResumeResolver.resolve(local: _local(const Duration(minutes: 42), updatedAt: _t0));

      expect(result.source, PlaybackResumeSource.localFallback);
      expect(result.position, const Duration(minutes: 42));
    });

    test('no source at all resolves to null, not to zero', () {
      final result = PlaybackResumeResolver.resolve();

      expect(result.source, PlaybackResumeSource.none);
      expect(result.position, isNull);
    });
  });

  group('reported regressions', () {
    test('Mutiny: a paused player does not push the further-along active player back', () {
      // MacBook sat paused with 1:03 remaining while the Apple TV played on to
      // 0:57 remaining. The MacBook's local record is passive and older than
      // the server state the Apple TV just wrote, so it must lose.
      const runtime = Duration(hours: 1, minutes: 40);
      final appleTvWroteAt = _t0.add(const Duration(minutes: 6));

      final result = PlaybackResumeResolver.resolve(
        local: _local(runtime - const Duration(minutes: 63), updatedAt: _t0),
        backend: _backend(runtime - const Duration(minutes: 57), isFresh: true, updatedAt: appleTvWroteAt),
      );

      expect(result.source, PlaybackResumeSource.freshBackend);
      expect(result.position, runtime - const Duration(minutes: 57));
    });

    test('a downloaded file played while online no longer prefers the local value blindly', () {
      // Pre-change behaviour: offline playback mode read the local offset first
      // and returned it whenever it was > 0, regardless of the server value.
      final result = PlaybackResumeResolver.resolve(
        local: _local(const Duration(minutes: 10), updatedAt: _t0),
        backend: _backend(const Duration(minutes: 55), isFresh: true, updatedAt: _t0.add(const Duration(hours: 2))),
      );

      expect(result.source, PlaybackResumeSource.freshBackend);
      expect(result.position, const Duration(minutes: 55));
    });

    test('a genuinely offline session still resumes from its own local progress', () {
      // No network: no fresh fetch, and the cached snapshot is older than what
      // was actually watched on this device.
      final result = PlaybackResumeResolver.resolve(
        local: _local(const Duration(minutes: 40), updatedAt: _t0.add(const Duration(hours: 1))),
        backend: _backend(const Duration(minutes: 10), isFresh: false, updatedAt: _t0),
      );

      expect(result.source, PlaybackResumeSource.localNewer);
      expect(result.position, const Duration(minutes: 40));
    });
  });
}
