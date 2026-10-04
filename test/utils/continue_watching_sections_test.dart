import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/utils/continue_watching_sections.dart';

/// Mockup 38 D / 23 (DEC-119 fase 2): four sections, every item in exactly
/// one, empty sections gone, and "Eerder begonnen" only for something begun.
void main() {
  const minute = 60 * 1000;
  final now = DateTime(2026, 10, 4, 12);
  int secondsAgo(Duration d) => now.subtract(d).millisecondsSinceEpoch ~/ 1000;

  MediaItem episode(String id, {int? viewOffsetMs, int? lastViewedAt, ContinueWatchingKind? kind}) => MediaItem(
    id: id,
    backend: MediaBackend.jellyfin,
    kind: MediaKind.episode,
    title: 'ep',
    grandparentTitle: 'show',
    parentIndex: 1,
    index: 2,
    durationMs: 48 * minute,
    viewOffsetMs: viewOffsetMs,
    lastViewedAt: lastViewedAt,
    continueWatchingKind: kind,
  );
  MediaItem film(String id, {int? viewOffsetMs, int? lastViewedAt}) => MediaItem(
    id: id,
    backend: MediaBackend.plex,
    kind: MediaKind.movie,
    title: 'film',
    durationMs: 120 * minute,
    viewOffsetMs: viewOffsetMs,
    lastViewedAt: lastViewedAt,
  );

  test('begun episodes and films land in their own section, next episodes in theirs', () {
    final sections = continueWatchingSections(
      [
        episode('e-resume', viewOffsetMs: 10 * minute, lastViewedAt: secondsAgo(const Duration(days: 2))),
        film('f-resume', viewOffsetMs: 30 * minute, lastViewedAt: secondsAgo(const Duration(days: 1))),
        episode('e-next', kind: ContinueWatchingKind.nextUp, lastViewedAt: secondsAgo(const Duration(days: 3))),
      ],
      itemOf: (i) => i,
      now: now,
    );
    expect(sections.map((s) => s.$1), [
      ContinueWatchingSection.resumeShows,
      ContinueWatchingSection.resumeMovies,
      ContinueWatchingSection.nextEpisodes,
    ]);
    expect(sections.map((s) => s.$2.single.id), ['e-resume', 'f-resume', 'e-next']);
  });

  test('something begun more than three months ago is Eerder begonnen', () {
    final sections = continueWatchingSections(
      [
        film('old', viewOffsetMs: 30 * minute, lastViewedAt: secondsAgo(const Duration(days: 120))),
        film('fresh', viewOffsetMs: 30 * minute, lastViewedAt: secondsAgo(const Duration(days: 89))),
      ],
      itemOf: (i) => i,
      now: now,
    );
    expect(sections.map((s) => s.$1), [ContinueWatchingSection.resumeMovies, ContinueWatchingSection.stale]);
    expect(sections.last.$2.single.id, 'old');
  });

  test('a next episode is never old, whatever the series last-watched date says', () {
    final sections = continueWatchingSections(
      [
        episode(
          'next-old-series',
          kind: ContinueWatchingKind.nextUp,
          lastViewedAt: secondsAgo(const Duration(days: 400)),
        ),
      ],
      itemOf: (i) => i,
      now: now,
    );
    expect(sections.single.$1, ContinueWatchingSection.nextEpisodes);
  });

  test('a missing date is never old', () {
    final sections = continueWatchingSections(
      [episode('undated', viewOffsetMs: 5 * minute)],
      itemOf: (i) => i,
      now: now,
    );
    expect(sections.single.$1, ContinueWatchingSection.resumeShows);
  });

  test('the backend origin wins over progress: a resume item without offset stays begun', () {
    final sections = continueWatchingSections(
      [episode('resume-no-offset', kind: ContinueWatchingKind.resume, viewOffsetMs: 48 * minute)],
      itemOf: (i) => i,
      now: now,
    );
    expect(sections.single.$1, ContinueWatchingSection.resumeShows);
  });

  test('empty sections are left out and order within a section is kept', () {
    final sections = continueWatchingSections(
      [film('b', viewOffsetMs: 1), film('a', viewOffsetMs: 1)],
      itemOf: (i) => i,
      now: now,
    );
    expect(sections, hasLength(1));
    expect(sections.single.$2.map((i) => i.id), ['b', 'a']);
  });
}
