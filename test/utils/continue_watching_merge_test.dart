import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/utils/continue_watching_merge.dart';

/// The one merge rule Jellyfin and Pleya Server share (DEC-119 fase 2). The
/// Jellyfin client's own tests still prove the HTTP side; this proves the rule.
void main() {
  MediaItem ep(String id, {required String series, int? lastViewedAt, int? viewOffsetMs}) => MediaItem(
    id: id,
    backend: MediaBackend.jellyfin,
    kind: MediaKind.episode,
    title: id,
    grandparentId: series,
    grandparentTitle: series,
    lastViewedAt: lastViewedAt,
    viewOffsetMs: viewOffsetMs,
    durationMs: 1000,
  );

  test('stamps the origin on every item', () {
    final merged = mergeContinueWatchingAndNextUp(
      resume: [ep('r', series: 'a', lastViewedAt: 10, viewOffsetMs: 10)],
      nextUp: [ep('n', series: 'b', lastViewedAt: 5)],
      limit: null,
    );
    expect(merged.map((i) => i.continueWatchingKind), [ContinueWatchingKind.resume, ContinueWatchingKind.nextUp]);
  });

  test('an in-progress episode beats the same series next episode', () {
    final merged = mergeContinueWatchingAndNextUp(
      resume: [ep('r', series: 'a', lastViewedAt: 1, viewOffsetMs: 10)],
      nextUp: [ep('n', series: 'a', lastViewedAt: 99)],
      limit: null,
    );
    expect(merged.map((i) => i.id), ['r']);
  });

  test('orders by recency across both sources and applies the limit after', () {
    final merged = mergeContinueWatchingAndNextUp(
      resume: [
        ep('old', series: 'a', lastViewedAt: 1, viewOffsetMs: 10),
        ep('mid', series: 'b', lastViewedAt: 5, viewOffsetMs: 10),
      ],
      nextUp: [ep('new', series: 'c', lastViewedAt: 9)],
      limit: 2,
    );
    expect(merged.map((i) => i.id), ['new', 'mid']);
  });

  test('a non-positive limit yields nothing', () {
    expect(
      mergeContinueWatchingAndNextUp(
        resume: [ep('r', series: 'a')],
        nextUp: const [],
        limit: 0,
      ),
      isEmpty,
    );
  });
}
