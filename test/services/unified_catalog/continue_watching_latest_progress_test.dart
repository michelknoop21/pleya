import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/unified_catalog/home_projection_service.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/continue_watching_sections.dart';
import 'package:pleya/utils/continue_watching_order.dart';

MediaItem episode(String id, {int? watched, int? added, int number = 1, String series = 'Series'}) => MediaItem(
  id: id,
  serverId: id,
  backend: MediaBackend.plex,
  kind: MediaKind.episode,
  title: id,
  grandparentTitle: series,
  grandparentId: 'show',
  parentIndex: 1,
  index: number,
  lastViewedAt: watched,
  addedAt: added,
);

class _OnDeckClient implements MediaServerClient {
  _OnDeckClient(this.item) : serverId = ServerId(item.serverId!);
  final MediaItem item;
  @override
  final ServerId serverId;
  @override
  String get serverName => serverId.value;
  @override
  MediaBackend get backend => MediaBackend.plex;
  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;
  @override
  Future<List<MediaItem>> fetchContinueWatching({int? count = 20}) async => [item];
  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds(tvdb: 123);
  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final reconnect in [false, true]) {
    test(
      'aggregation ${reconnect ? 'reconnect' : 'initial fetch'} keeps known watch time before exact episode collapse',
      () async {
        final known = episode('known', watched: 100, number: 1);
        final unknown = episode('unknown', added: 999999, number: 1);
        final manager = MultiServerManager();
        addTearDown(manager.dispose);
        manager.debugRegisterClientForTesting(_OnDeckClient(known));
        manager.debugRegisterClientForTesting(_OnDeckClient(unknown));
        final service = DataAggregationService(manager);
        final items = reconnect
            ? await service.mergeContinueWatching([unknown], [known])
            : (await service.getOnDeckFromAllServers()).items;
        expect(items.map((item) => item.id), ['known']);
        expect(items.single.lastViewedAt, 100);
      },
    );
  }

  for (final reconnect in [false, true]) {
    test('Brothers year suffix resolves identity during ${reconnect ? 'reconnect' : 'initial aggregation'}', () async {
      final resumed = episode('resumed', watched: 200, number: 8, series: 'Brothers');
      final next = episode('next', added: 999999, number: 8, series: 'Brothers (2026)');
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      manager.debugRegisterClientForTesting(_OnDeckClient(resumed));
      manager.debugRegisterClientForTesting(_OnDeckClient(next));
      final service = DataAggregationService(manager);
      final items = reconnect
          ? await service.mergeContinueWatching([next], [resumed])
          : (await service.getOnDeckFromAllServers()).items;
      expect(items.map((item) => item.id), ['resumed']);
    });
  }

  for (final ids in [const ExternalIds(tvdb: 123), const ExternalIds(tvdb: 999), const ExternalIds()]) {
    test('Brothers title suffix only enables lookup; second ids $ids still decide grouping', () async {
      final calls = <String>[];
      final service = HomeProjectionService(
        fetchExternalIds: (server, _) async {
          calls.add(server);
          return server == 'resumed' ? const ExternalIds(tvdb: 123) : ids;
        },
      );
      final row = await service.projectContinueWatching([
        episode('resumed', watched: 200, number: 8, series: 'Brothers'),
        episode('next', added: 999999, number: 8, series: 'Brothers (2026)'),
      ], title: 'Continue watching');
      expect(calls, unorderedEquals(['resumed', 'next']));
      expect(row.groups, hasLength(ids.tvdb == 123 ? 1 : 2));
    });
  }

  test('Brothers year suffix also compares different episodes before latest watch selection', () async {
    final service = HomeProjectionService(fetchExternalIds: (_, _) async => const ExternalIds(tvdb: 123));
    final row = await service.projectContinueWatching([
      episode('next', added: 999999, number: 9, series: 'Brothers (2026)'),
      episode('resumed', watched: 200, number: 8, series: 'Brothers'),
    ], title: 'Continue watching');
    expect(row.groups, hasLength(1));
    expect(row.groups.single.representativeSource.item.id, 'resumed');
  });

  test('same Brothers episode appears only in resume shows, never also next episodes', () async {
    final service = HomeProjectionService(fetchExternalIds: (_, _) async => const ExternalIds(tvdb: 123));
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final row = await service.projectContinueWatching([
      episode(
        'next',
        added: now,
        number: 8,
        series: 'Brothers (2026)',
      ).copyWith(continueWatchingKind: ContinueWatchingKind.nextUp, durationMs: 1800000),
      episode(
        'resumed',
        watched: now,
        number: 8,
        series: 'Brothers',
      ).copyWith(continueWatchingKind: ContinueWatchingKind.resume, durationMs: 1800000, viewOffsetMs: 180000),
    ], title: 'Continue watching');
    final sections = continueWatchingSections(row.groups, itemOf: continueWatchingItemOf);
    expect(row.groups, hasLength(1));
    expect(sections, hasLength(1));
    expect(sections.single.$1, ContinueWatchingSection.resumeShows);
  });

  for (final reconnect in [false, true]) {
    test(
      'completed episode is excluded on ${reconnect ? 'reconnect' : 'initial fetch'}; active rewatch stays',
      () async {
        final done = episode('done', watched: 200).copyWith(viewCount: 1, durationMs: 1800000, viewOffsetMs: 0);
        final replay = episode(
          'replay',
          watched: 300,
          series: 'Other',
        ).copyWith(viewCount: 1, durationMs: 1800000, viewOffsetMs: 180000);
        final manager = MultiServerManager();
        addTearDown(manager.dispose);
        manager.debugRegisterClientForTesting(_OnDeckClient(done));
        manager.debugRegisterClientForTesting(_OnDeckClient(replay));
        final service = DataAggregationService(manager);
        final items = reconnect
            ? await service.mergeContinueWatching([done], [replay])
            : (await service.getOnDeckFromAllServers()).items;
        expect(items.map((item) => item.id), ['replay']);
      },
    );
  }
  test('projection drops a completed episode from a stored snapshot but retains a new unwatched episode', () async {
    final service = HomeProjectionService(fetchExternalIds: (_, _) async => const ExternalIds(tvdb: 123));
    final row = await service.projectContinueWatching([
      episode('done', watched: 300).copyWith(viewCount: 1, durationMs: 1800000, viewOffsetMs: 0),
      episode('next', watched: 100, number: 2).copyWith(viewCount: 0),
    ], title: 'Continue watching');
    expect(row.groups, hasLength(1));
    expect(row.groups.single.representativeSource.item.id, 'next');
  });

  for (final reconnect in [false, true]) {
    test(
      'newer completion beats stale resume across exact episode sources ${reconnect ? 'reconnect' : 'initial'}',
      () async {
        final done = episode('done', watched: 10000).copyWith(viewCount: 1, durationMs: 1800000, viewOffsetMs: 0);
        final stale = episode('stale', watched: 1000).copyWith(viewCount: 0, durationMs: 1800000, viewOffsetMs: 180000);
        final manager = MultiServerManager();
        addTearDown(manager.dispose);
        manager.debugRegisterClientForTesting(_OnDeckClient(done));
        manager.debugRegisterClientForTesting(_OnDeckClient(stale));
        final service = DataAggregationService(manager);
        final items = reconnect
            ? await service.mergeContinueWatching([stale], [done])
            : (await service.getOnDeckFromAllServers()).items;
        expect(items, isEmpty);
        final projection = HomeProjectionService(fetchExternalIds: (_, _) async => const ExternalIds(tvdb: 123));
        final row = await projection.projectContinueWatching([stale, done], title: 'Continue watching');
        expect(row.groups, isEmpty);
        final rewatch = stale.copyWith(lastViewedAt: 20000);
        final resumed = await projection.projectContinueWatching([done, rewatch], title: 'Continue watching');
        expect(resumed.groups, hasLength(1));
        expect(continueWatchingItemOf(resumed.groups.single).id, 'stale');
      },
    );
  }

  for (final reconnect in [false, true]) {
    test(
      'shared episode guid reconciles completion despite different titles ${reconnect ? 'reconnect' : 'initial'}',
      () async {
        final done = episode(
          'done',
          watched: 10000,
          series: 'Localized title',
        ).copyWith(guid: 'plex://episode/shared', viewCount: 1, durationMs: 1800000, viewOffsetMs: 0);
        final stale = episode(
          'stale',
          watched: 1000,
          series: 'Original title',
        ).copyWith(guid: 'plex://episode/shared', viewCount: 0, durationMs: 1800000, viewOffsetMs: 180000);
        final manager = MultiServerManager();
        addTearDown(manager.dispose);
        manager.debugRegisterClientForTesting(_OnDeckClient(done));
        manager.debugRegisterClientForTesting(_OnDeckClient(stale));
        final service = DataAggregationService(manager);
        final items = reconnect
            ? await service.mergeContinueWatching([stale], [done])
            : (await service.getOnDeckFromAllServers()).items;
        expect(items, isEmpty);
      },
    );
  }

  for (final reconnect in [false, true]) {
    test(
      'aggregation preserves watch-state holder active inside recency margin ${reconnect ? 'reconnect' : 'initial'}',
      () async {
        final done = episode('done', watched: 10000).copyWith(viewCount: 1, durationMs: 1800000, viewOffsetMs: 0);
        final active = episode(
          'active',
          watched: 9999,
        ).copyWith(viewCount: 0, durationMs: 1800000, viewOffsetMs: 180000);
        final manager = MultiServerManager();
        addTearDown(manager.dispose);
        manager.debugRegisterClientForTesting(_OnDeckClient(done));
        manager.debugRegisterClientForTesting(_OnDeckClient(active));
        final service = DataAggregationService(manager);
        final items = reconnect
            ? await service.mergeContinueWatching([active], [done])
            : (await service.getOnDeckFromAllServers()).items;
        expect(items.map((item) => item.id), ['active']);
        expect(items.single.hasActiveProgress, isTrue);
        final projection = HomeProjectionService(fetchExternalIds: (_, _) async => const ExternalIds(tvdb: 123));
        expect((await projection.projectContinueWatching(items, title: 'Continue watching')).groups, hasLength(1));
      },
    );
  }

  test('one series card uses known latest watch progress, never date added or highest episode', () async {
    final service = HomeProjectionService(fetchExternalIds: (_, _) async => const ExternalIds(tvdb: 123));
    final row = await service.projectContinueWatching([
      episode('unknown', added: 9999, number: 9),
      episode('old', watched: 100, number: 8),
      episode('last-watched', watched: 200, number: 3),
    ], title: 'Continue watching');
    expect(row.groups, hasLength(1));
    expect(row.groups.single.representativeSource.item.id, 'last-watched');
  });
}
