import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_version.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_availability.dart';
import 'package:pleya/media/unified/source_coverage_state.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_route_context.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/services/unified_catalog/unified_activation_coordinator.dart';

MediaItem _item(
  String serverId, {
  String id = 'i1',
  String? summary,
  int? year = 2010,
  String? thumbPath,
  String? artPath,
  int? lastViewedAt,
  List<MediaVersion>? mediaVersions,
  String? serverName,
}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Dune',
  year: year,
  summary: summary,
  thumbPath: thumbPath,
  artPath: artPath,
  lastViewedAt: lastViewedAt,
  mediaVersions: mediaVersions,
  serverId: serverId,
  serverName: serverName ?? serverId,
);

UnifiedMediaSource _source(
  String serverId, {
  String id = 'i1',
  SourceAvailability availability = SourceAvailability.online,
  String? summary,
  String? thumbPath,
  String? artPath,
  int? lastViewedAt,
  List<MediaVersion>? mediaVersions,
  String? serverName,
}) => UnifiedMediaSource.fromItem(
  _item(
    serverId,
    id: id,
    summary: summary,
    thumbPath: thumbPath,
    artPath: artPath,
    lastViewedAt: lastViewedAt,
    mediaVersions: mediaVersions,
    serverName: serverName,
  ),
  availability: availability,
);

UnifiedMediaGroup _group(List<UnifiedMediaSource> sources, {CanonicalMediaIdentity? identity, String groupId = 'g1'}) =>
    UnifiedMediaGroup(
      groupId: groupId,
      identity: identity ?? CanonicalMediaIdentity.movie(title: 'Dune', year: 2010),
      sources: sources,
      representativeSourceKey: sources.first.sourceKey,
      watchState: UnifiedWatchState(representativeSourceKey: sources.first.sourceKey),
    );

/// Availability as the source already carries it — the normal case for tests
/// that are not exercising a live server-state change.
SourceAvailability _stamped(UnifiedMediaSource source) => source.availability;

const _coordinator = UnifiedActivationCoordinator();

void main() {
  group('direct versus picker', () {
    test('F1: exactly one online source skips the picker and routes directly', () {
      final group = _group([_source('nas')]);

      final decision = _coordinator.decide(
        group: group,
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
      );

      expect(decision, isA<ActivateSourceDirectly>());
      final direct = decision as ActivateSourceDirectly;
      expect(direct.source.sourceKey, 'nas:i1');
      // Hoofdstuk 4.1/4.4: the existing route receives one concrete MediaItem.
      expect(direct.item.serverId, 'nas');
      expect(direct.item.id, 'i1');
    });

    test('F2: two online sources open the picker', () {
      final decision = _coordinator.decide(
        group: _group([_source('nas'), _source('attic')]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
      );

      expect(decision, isA<ShowSourcePicker>());
      expect((decision as ShowSourcePicker).sources, hasLength(2));
    });

    test('F5/14.6: one online source plus an offline one still skips the picker', () {
      final decision = _coordinator.decide(
        group: _group([_source('nas'), _source('attic', availability: SourceAvailability.offline)]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
      );

      expect(decision, isA<ActivateSourceDirectly>());
      expect((decision as ActivateSourceDirectly).source.sourceKey, 'nas:i1');
    });

    test('an unchecked source is not usable, so it never counts toward the picker threshold', () {
      final decision = _coordinator.decide(
        group: _group([_source('nas'), _source('attic', availability: SourceAvailability.unknown)]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
      );

      expect(decision, isA<ActivateSourceDirectly>());
    });

    test('live server state overrides the availability stamped on the source', () {
      final group = _group([_source('nas'), _source('attic')]);

      final decision = _coordinator.decide(
        group: group,
        intent: UnifiedActivationIntent.play,
        availabilityFor: (s) => s.serverId.value == 'attic' ? SourceAvailability.offline : SourceAvailability.online,
      );

      expect(decision, isA<ActivateSourceDirectly>());
      expect((decision as ActivateSourceDirectly).source.sourceKey, 'nas:i1');
    });

    test('F6: every source offline reports allOffline, keeping all rows', () {
      final decision = _coordinator.decide(
        group: _group([
          _source('nas', availability: SourceAvailability.offline),
          _source('attic', availability: SourceAvailability.offline),
        ]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
      );

      expect(decision, isA<NoUsableSource>());
      final none = decision as NoUsableSource;
      expect(none.reason, NoUsableSourceReason.allOffline);
      expect(none.sources, hasLength(2));
    });

    test('F7: an auth error outranks offline, so the user gets the actionable message', () {
      final decision = _coordinator.decide(
        group: _group([
          _source('nas', availability: SourceAvailability.offline),
          _source('attic', availability: SourceAvailability.authError),
        ]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
      );

      expect((decision as NoUsableSource).reason, NoUsableSourceReason.authRequired);
    });

    test('F4/F9: the route context carries coverage and every source key', () {
      final coverage = SourceCoverageState(
        expectedServerIds: {'nas', 'attic', 'shed'},
        checkedServerIds: {'nas', 'attic'},
        uncheckedReasons: {'shed': UncheckedSourceReason.offline},
      );

      final decision = _coordinator.decide(
        group: _group([_source('nas'), _source('attic', availability: SourceAvailability.offline)]),
        intent: UnifiedActivationIntent.details,
        availabilityFor: _stamped,
        coverage: coverage,
      );

      final context = (decision as ActivateSourceDirectly).routeContext;
      expect(context.sourceKey, 'nas:i1');
      expect(context.availableSourceKeys, ['nas:i1', 'attic:i1']);
      expect(context.hasAlternativeSources, isTrue);
      expect(context.intent, UnifiedActivationIntent.details);
      expect(context.coverage.isComplete, isFalse);
      expect(context.coverage.uncheckedCount, 1);
    });

    test('the picker keeps unusable rows so a user can see which server is down', () {
      final decision = _coordinator.decide(
        group: _group([_source('nas'), _source('attic'), _source('shed', availability: SourceAvailability.authError)]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
      );

      expect((decision as ShowSourcePicker).sources.map((s) => s.sourceKey), containsAll(['shed:i1']));
    });
  });

  group('deterministic ranking (hoofdstuk 4.7)', () {
    test('a remembered source outranks everything else', () {
      final ranked = rankSources([
        _source('attic', summary: 'rich', thumbPath: '/a', artPath: '/b'),
        _source('nas'),
      ], preferredSourceKey: 'nas:i1');

      expect(ranked.first.sourceKey, 'nas:i1');
    });

    test('online outranks offline, and offline never wins on richer metadata', () {
      final ranked = rankSources([
        _source('attic', availability: SourceAvailability.offline, summary: 'rich', thumbPath: '/a', artPath: '/b'),
        _source('nas'),
      ]);

      expect(ranked.first.sourceKey, 'nas:i1');
    });

    test('an auth error ranks above an outright offline server', () {
      final ranked = rankSources([
        _source('offline-one', availability: SourceAvailability.offline),
        _source('auth-one', availability: SourceAvailability.authError),
      ]);

      expect(ranked.first.serverId.value, 'auth-one');
    });

    test('metadata completeness breaks a tie before artwork does', () {
      final ranked = rankSources([
        _source('a-server', thumbPath: '/a', artPath: '/b'),
        _source('b-server', summary: 'has a synopsis'),
      ]);

      expect(ranked.first.serverId.value, 'b-server');
    });

    test('artwork completeness breaks a tie before quality information does', () {
      final ranked = rankSources([
        _source(
          'a-server',
          mediaVersions: [const MediaVersion(id: 'v', videoResolution: '2160')],
        ),
        _source('b-server', thumbPath: '/a'),
      ]);

      expect(ranked.first.serverId.value, 'b-server');
    });

    test('quality information breaks a tie before server name does', () {
      final ranked = rankSources([
        _source('a-server'),
        _source(
          'b-server',
          mediaVersions: [const MediaVersion(id: 'v', videoResolution: '1080')],
        ),
      ]);

      expect(ranked.first.serverId.value, 'b-server');
    });

    test('server name breaks a tie before server id does', () {
      final ranked = rankSources([_source('zzz', serverName: 'Attic'), _source('aaa', serverName: 'NAS')]);

      expect(ranked.first.serverId.value, 'zzz');
    });

    test('F12: duplicate server names fall through to server id, then item id', () {
      final ranked = rankSources([_source('server-b', serverName: 'NAS'), _source('server-a', serverName: 'NAS')]);

      expect(ranked.map((s) => s.serverId.value), ['server-a', 'server-b']);
    });

    test('two items on one server are ordered by item id, never by input order', () {
      final ranked = rankSources([_source('nas', id: 'z'), _source('nas', id: 'a')]);

      expect(ranked.map((s) => s.item.id), ['a', 'z']);
    });

    test('ranking is independent of input order — no response-time bias', () {
      final a = _source('nas', summary: 'x');
      final b = _source('attic', availability: SourceAvailability.offline);
      final c = _source('shed');

      expect(rankSources([a, b, c]).map((s) => s.sourceKey), rankSources([c, b, a]).map((s) => s.sourceKey));
      expect(rankSources([b, c, a]).map((s) => s.sourceKey), rankSources([a, b, c]).map((s) => s.sourceKey));
    });
  });

  group('initial focus (hoofdstuk 14.4)', () {
    test('a valid online remembered source takes focus', () {
      final ordered = rankSources([_source('nas', summary: 'x'), _source('attic')]);

      expect(selectInitialFocus(ordered, preferredSourceKey: 'attic:i1'), 'attic:i1');
    });

    test('F16: an offline remembered source falls back rather than focusing a dead row', () {
      final ordered = rankSources([_source('nas'), _source('attic', availability: SourceAvailability.offline)]);

      expect(selectInitialFocus(ordered, preferredSourceKey: 'attic:i1'), 'nas:i1');
    });

    test('a remembered source that no longer exists falls back', () {
      final ordered = rankSources([_source('nas')]);

      expect(selectInitialFocus(ordered, preferredSourceKey: 'gone:i1'), 'nas:i1');
    });

    test('F15: with no remembered source, the most recent progress takes focus', () {
      final ordered = rankSources([
        _source('nas', summary: 'x', lastViewedAt: 100),
        _source('attic', lastViewedAt: 900),
      ]);

      expect(selectInitialFocus(ordered), 'attic:i1');
    });

    test('progress never pulls focus onto an offline source', () {
      final ordered = rankSources([
        _source('nas'),
        _source('attic', availability: SourceAvailability.offline, lastViewedAt: 900),
      ]);

      expect(selectInitialFocus(ordered), 'nas:i1');
    });

    test('with neither preference nor progress, the best online source takes focus', () {
      final ordered = rankSources([_source('attic'), _source('nas', summary: 'x')]);

      expect(selectInitialFocus(ordered), 'nas:i1');
    });

    test('equal progress leaves the deterministic winner in place', () {
      final ordered = rankSources([
        _source('nas', summary: 'x', lastViewedAt: 500),
        _source('attic', lastViewedAt: 500),
      ]);

      expect(selectInitialFocus(ordered), 'nas:i1');
    });

    test('F6: with nothing online there is still a focused row for the disabled state', () {
      final ordered = rankSources([
        _source('nas', availability: SourceAvailability.offline),
        _source('attic', availability: SourceAvailability.offline),
      ]);

      expect(selectInitialFocus(ordered), isNotNull);
    });

    test('an empty list has no focus', () {
      expect(selectInitialFocus(const []), isNull);
    });

    test('the picker decision reports a preferred key only when it still exists', () {
      final decision =
          _coordinator.decide(
                group: _group([_source('nas'), _source('attic')]),
                intent: UnifiedActivationIntent.play,
                availabilityFor: _stamped,
                preferredSourceKey: 'gone:i1',
              )
              as ShowSourcePicker;

      expect(decision.preferredSourceKey, isNull);
      expect(decision.initialFocusSourceKey, isNotNull);
    });
  });

  group('focus after a source stops being usable (hoofdstuk 14.4)', () {
    test('a still-online focused row keeps focus', () {
      final ordered = [_source('a'), _source('b'), _source('c')];

      expect(nextFocusAfterAvailabilityChange(ordered: ordered, focusedSourceKey: 'b:i1'), 'b:i1');
    });

    test('focus moves to the nearest online row, preferring the one below', () {
      final ordered = [_source('a'), _source('b', availability: SourceAvailability.offline), _source('c')];

      expect(nextFocusAfterAvailabilityChange(ordered: ordered, focusedSourceKey: 'b:i1'), 'c:i1');
    });

    test('focus falls back upward when nothing below is online', () {
      final ordered = [
        _source('a'),
        _source('b', availability: SourceAvailability.offline),
        _source('c', availability: SourceAvailability.offline),
      ];

      expect(nextFocusAfterAvailabilityChange(ordered: ordered, focusedSourceKey: 'b:i1'), 'a:i1');
    });

    test('F11: a focused row that disappeared entirely lands on the best online row', () {
      final ordered = [_source('a', availability: SourceAvailability.offline), _source('b')];

      expect(nextFocusAfterAvailabilityChange(ordered: ordered, focusedSourceKey: 'gone:i1'), 'b:i1');
    });

    test('nothing online yields null, so the UI moves focus to its own controls', () {
      final ordered = [
        _source('a', availability: SourceAvailability.offline),
        _source('b', availability: SourceAvailability.authError),
      ];

      expect(nextFocusAfterAvailabilityChange(ordered: ordered, focusedSourceKey: 'a:i1'), isNull);
    });
  });

  group('F10: sources arriving while the modal is open', () {
    test('a new source is appended without disturbing the visible order', () {
      final current = [_source('nas'), _source('attic')];
      // Ranks first on metadata, and must still not jump the queue.
      final late = _source('shed', summary: 'rich', thumbPath: '/a');

      final merged = mergeLateSources(current, [late]);

      expect(merged.map((s) => s.serverId.value), ['nas', 'attic', 'shed']);
    });

    test('a source already on screen is refreshed in place, not duplicated', () {
      final current = [_source('nas'), _source('attic')];
      final refreshed = _source('attic', availability: SourceAvailability.offline);

      final merged = mergeLateSources(current, [refreshed]);

      expect(merged, hasLength(2));
      expect(merged[1].availability, SourceAvailability.offline);
      expect(merged.map((s) => s.serverId.value), ['nas', 'attic']);
    });

    test('several arrivals are ranked among themselves, so the tail is deterministic', () {
      final current = [_source('nas')];
      final first = _source('b-server');
      final second = _source('a-server', summary: 'rich');

      expect(
        mergeLateSources(current, [first, second]).map((s) => s.serverId.value),
        mergeLateSources(current, [second, first]).map((s) => s.serverId.value),
      );
      expect(mergeLateSources(current, [first, second]).map((s) => s.serverId.value), ['nas', 'a-server', 'b-server']);
    });

    test('no arrivals leaves the list untouched', () {
      final current = [_source('nas'), _source('attic')];

      expect(mergeLateSources(current, const []).map((s) => s.sourceKey), current.map((s) => s.sourceKey));
    });
  });

  group('F18: playback failure offers an alternative but never takes it', () {
    test('other online sources become explicit alternatives', () {
      final options = _coordinator.evaluatePlaybackFailure(
        sources: [_source('nas'), _source('attic'), _source('shed')],
        failedSourceKey: 'nas:i1',
        availabilityFor: _stamped,
      );

      expect(options.hasAlternatives, isTrue);
      expect(options.alternatives.map((s) => s.sourceKey), isNot(contains('nas:i1')));
      expect(options.alternatives, hasLength(2));
    });

    test('the failed source is excluded even though its server still reports online', () {
      final options = _coordinator.evaluatePlaybackFailure(
        sources: [_source('nas'), _source('attic')],
        failedSourceKey: 'nas:i1',
        availabilityFor: (_) => SourceAvailability.online,
      );

      expect(options.alternatives.map((s) => s.sourceKey), ['attic:i1']);
    });

    test('offline alternatives do not count, so no pointless offer is made', () {
      final options = _coordinator.evaluatePlaybackFailure(
        sources: [
          _source('nas'),
          _source('attic', availability: SourceAvailability.offline),
        ],
        failedSourceKey: 'nas:i1',
        availabilityFor: _stamped,
      );

      expect(options.hasAlternatives, isFalse);
    });

    test('a single-source group offers nothing', () {
      final options = _coordinator.evaluatePlaybackFailure(
        sources: [_source('nas')],
        failedSourceKey: 'nas:i1',
        availabilityFor: _stamped,
      );

      expect(options.hasAlternatives, isFalse);
      expect(options.alternatives, isEmpty);
    });

    test('alternatives arrive in deterministic order', () {
      final sources = [_source('b-server'), _source('a-server', summary: 'rich'), _source('nas')];

      final forward = _coordinator.evaluatePlaybackFailure(
        sources: sources,
        failedSourceKey: 'nas:i1',
        availabilityFor: _stamped,
      );
      final reversed = _coordinator.evaluatePlaybackFailure(
        sources: sources.reversed.toList(),
        failedSourceKey: 'nas:i1',
        availabilityFor: _stamped,
      );

      expect(forward.alternatives.map((s) => s.sourceKey), reversed.alternatives.map((s) => s.sourceKey));
      expect(forward.alternatives.first.serverId.value, 'a-server');
    });
  });

  // A15 shares F18's binding rule — the differing input is *when* availability
  // is read. A server that vanished between activation and the failed start is
  // still stamped `online` on every source it carries, so the alternatives may
  // only be derived from a live re-read, never from the stamp.
  group('A15: the server that vanished during the start takes its whole shelf with it', () {
    test('every source on the vanished server drops out, not just the one that failed', () {
      final options = _coordinator.evaluatePlaybackFailure(
        sources: [
          _source('nas', id: 'i1'),
          _source('nas', id: 'i2'),
          _source('attic', id: 'i1'),
        ],
        failedSourceKey: 'nas:i1',
        availabilityFor: (s) => s.serverId.value == 'nas' ? SourceAvailability.offline : SourceAvailability.online,
      );

      expect(
        options.alternatives.map((s) => s.sourceKey),
        ['attic:i1'],
        reason: 'the sibling on the dead server cannot be an alternative either',
      );
    });

    test('a stamp taken before the start does not survive the server going away', () {
      // Both sources were stamped online when the group was activated.
      final options = _coordinator.evaluatePlaybackFailure(
        sources: [_source('nas'), _source('attic')],
        failedSourceKey: 'nas:i1',
        availabilityFor: (_) => SourceAvailability.offline,
      );

      expect(
        options.hasAlternatives,
        isFalse,
        reason: 'offering the last known-good copy of a server that is gone is the offer that fails twice',
      );
    });

    test('the whole profile going away offers nothing at all', () {
      final options = _coordinator.evaluatePlaybackFailure(
        sources: [_source('nas'), _source('attic'), _source('shed')],
        failedSourceKey: 'nas:i1',
        availabilityFor: (_) => SourceAvailability.offline,
      );

      expect(options.alternatives, isEmpty);
      expect(options.hasAlternatives, isFalse);
    });
  });

  // A16/A17/A18 are three ways a server id can stop meaning what it meant.
  // Identity is always the id; the name is display plus one documented sort
  // tiebreaker, and a key naming a server that is not in the group simply
  // never matches.
  group('A16/A17/A18: a server that left, was renamed, or came back under a new id', () {
    test('A16: a preferred server removed from the profile does not apply', () {
      final decision = _coordinator.decide(
        group: _group([_source('nas'), _source('attic')]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
        preferredServerId: 'removed',
      );

      expect(
        decision,
        isA<ShowSourcePicker>(),
        reason: 'a default naming a server that is no longer here answers nothing, so the user is asked',
      );
    });

    test('A17: a rename moves a row, and moves nothing else', () {
      UnifiedActivationDecision decideWith(String atticName) => _coordinator.decide(
        group: _group([_source('nas', serverName: 'NAS'), _source('attic', serverName: atticName)]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
        preferredServerId: 'attic',
      );

      final before = decideWith('Zolder') as ActivateSourceDirectly;
      final after = decideWith('Kelder') as ActivateSourceDirectly;

      expect(before.source.serverId.value, 'attic');
      expect(after.source.serverId.value, 'attic', reason: 'the preference followed the machine, not the label on it');
    });

    test('A17: renaming reorders the picker without changing what is in it', () {
      List<String> keysFor(String atticName) => rankSources([
        _source('nas', serverName: 'NAS'),
        _source('attic', serverName: atticName),
      ]).map((s) => s.sourceKey).toList();

      // 'Aardkelder' sorts before 'NAS', 'Zolder' after — the documented
      // hoofdstuk 4.7 tiebreaker, which falls through to the id.
      expect(keysFor('Zolder'), ['nas:i1', 'attic:i1']);
      expect(keysFor('Aardkelder'), ['attic:i1', 'nas:i1']);
      expect(keysFor('Zolder').toSet(), keysFor('Aardkelder').toSet());
    });

    test('A18: the remembered key from before the re-add names nothing here', () {
      final decision =
          _coordinator.decide(
                group: _group([_source('server-9'), _source('attic')]),
                intent: UnifiedActivationIntent.details,
                availabilityFor: _stamped,
                preferredSourceKey: 'server-1:i1',
              )
              as ShowSourcePicker;

      expect(decision.preferredSourceKey, isNull);
      expect(decision.initialFocusSourceKey, isNotNull);
    });

    test('A18: the standing default does not survive an id change, so the user is asked', () {
      final decision = _coordinator.decide(
        group: _group([_source('server-9'), _source('attic')]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
        preferredServerId: 'server-1',
      );

      expect(
        decision,
        isA<ShowSourcePicker>(),
        reason: 'nothing here can know server-9 is the same machine server-1 was',
      );
    });

    test('A18: re-setting the preference on the new id works normally', () {
      final decision = _coordinator.decide(
        group: _group([_source('server-9'), _source('attic')]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
        preferredServerId: 'server-9',
      );

      expect((decision as ActivateSourceDirectly).source.serverId.value, 'server-9');
    });
  });

  group('route context', () {
    test('a source switch replaces the chosen key and keeps everything else', () {
      final context = UnifiedMediaRouteContext(
        groupId: 'g1',
        identity: CanonicalMediaIdentity.movie(title: 'Dune', year: 2010),
        sourceKey: 'nas:i1',
        availableSourceKeys: const ['nas:i1', 'attic:i1'],
        coverage: SourceCoverageState.complete(const {'nas', 'attic'}),
        intent: UnifiedActivationIntent.details,
      );

      final switched = context.withSourceKey('attic:i1');

      expect(switched.sourceKey, 'attic:i1');
      expect(switched.groupId, 'g1');
      expect(switched.availableSourceKeys, context.availableSourceKeys);
      expect(switched.intent, UnifiedActivationIntent.details);
    });

    test('a single-source context offers no switch affordance', () {
      final context = UnifiedMediaRouteContext(
        groupId: 'g1',
        identity: CanonicalMediaIdentity.movie(title: 'Dune', year: 2010),
        sourceKey: 'nas:i1',
        availableSourceKeys: const ['nas:i1'],
        coverage: SourceCoverageState.complete(const {'nas'}),
        intent: UnifiedActivationIntent.play,
      );

      expect(context.hasAlternativeSources, isFalse);
    });
  });

  // The contract change that supersedes, for this preference only, the rule
  // that every source preference may set focus and nothing more. The profile's
  // preferred server is a standing answer, so it selects; the remembered
  // per-title source is not, so it still only focuses.
  group('preferred server (profile default)', () {
    test('an online preferred server skips the picker even with several usable sources', () {
      final decision = _coordinator.decide(
        group: _group([_source('nas'), _source('attic'), _source('shed')]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
        preferredServerId: 'attic',
      );

      expect(decision, isA<ActivateSourceDirectly>());
      expect((decision as ActivateSourceDirectly).source.serverId.value, 'attic');
    });

    test('it wins on being preferred, not on having the better metadata', () {
      final rich = _source('nas', summary: 'A lot of metadata', thumbPath: '/t', artPath: '/a');
      final plain = _source('attic');

      final decision = _coordinator.decide(
        group: _group([rich, plain]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
        preferredServerId: 'attic',
      );

      expect((decision as ActivateSourceDirectly).source.serverId.value, 'attic');
    });

    test('with several sources on the preferred server, 4.7 picks which one', () {
      final poor = _source('attic', id: 'a1');
      final best = _source('attic', id: 'a2', summary: 'Full', thumbPath: '/t', artPath: '/a');

      final decision = _coordinator.decide(
        group: _group([poor, best, _source('nas')]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
        preferredServerId: 'attic',
      );

      expect((decision as ActivateSourceDirectly).source.sourceKey, 'attic:a2');
    });

    test('an offline preferred server plus one alternative still goes straight through', () {
      final decision = _coordinator.decide(
        group: _group([_source('attic', availability: SourceAvailability.offline), _source('nas')]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
        preferredServerId: 'attic',
      );

      expect((decision as ActivateSourceDirectly).source.serverId.value, 'nas');
    });

    test('an offline preferred server plus several alternatives asks', () {
      final decision = _coordinator.decide(
        group: _group([_source('attic', availability: SourceAvailability.offline), _source('nas'), _source('shed')]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
        preferredServerId: 'attic',
      );

      expect(decision, isA<ShowSourcePicker>());
      expect((decision as ShowSourcePicker).preferredServerId, 'attic');
    });

    test('an auth error on the preferred server is never selected through', () {
      final decision = _coordinator.decide(
        group: _group([_source('attic', availability: SourceAvailability.authError), _source('nas'), _source('shed')]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
        preferredServerId: 'attic',
      );

      expect(decision, isA<ShowSourcePicker>());
    });

    test('a server whose state was never established is not "usable enough" either', () {
      final decision = _coordinator.decide(
        group: _group([_source('attic', availability: SourceAvailability.unknown), _source('nas'), _source('shed')]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
        preferredServerId: 'attic',
      );

      expect(decision, isA<ShowSourcePicker>());
    });

    test('a preferred server hidden from this profile has no source here, so it does not apply', () {
      // Visibility closes before the fan-out (hoofdstuk 1.1), so a hidden
      // server simply contributes nothing to the group.
      final decision = _coordinator.decide(
        group: _group([_source('nas'), _source('shed')]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
        preferredServerId: 'attic',
      );

      expect(decision, isA<ShowSourcePicker>());
    });

    test('with everything offline the preferred server changes nothing', () {
      final decision = _coordinator.decide(
        group: _group([
          _source('attic', availability: SourceAvailability.offline),
          _source('nas', availability: SourceAvailability.offline),
        ]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
        preferredServerId: 'attic',
      );

      expect(decision, isA<NoUsableSource>());
    });

    test('the remembered per-title source still only focuses, it never selects', () {
      final decision = _coordinator.decide(
        group: _group([_source('nas'), _source('attic')]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
        preferredSourceKey: 'attic:i1',
      );

      expect(decision, isA<ShowSourcePicker>(), reason: 'no preferred server means the user is still asked');
      expect((decision as ShowSourcePicker).initialFocusSourceKey, 'attic:i1');
    });

    test('a remembered source on another server does not outvote the preferred server', () {
      final decision = _coordinator.decide(
        group: _group([_source('nas'), _source('attic')]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
        preferredSourceKey: 'attic:i1',
        preferredServerId: 'nas',
      );

      expect((decision as ActivateSourceDirectly).source.serverId.value, 'nas');
    });
  });

  // The preference is one setting per profile, not one per title: "Michel's
  // profile uses NAS" answers every duplicated title at once. These walk the
  // worked example straight through, so a future change that quietly re-keys it
  // on a canonical identity fails here rather than in someone's living room.
  group('the preferred server is global to the profile, not per title', () {
    const preferred = 'nas';

    UnifiedActivationDecision decideFor(UnifiedMediaGroup group) => _coordinator.decide(
      group: group,
      intent: UnifiedActivationIntent.play,
      availabilityFor: _stamped,
      preferredServerId: preferred,
    );

    test('film A on NAS + Zolder goes straight to NAS', () {
      final decision = decideFor(
        _group([_source('nas'), _source('attic')], identity: CanonicalMediaIdentity.movie(title: 'Film A', year: 2001)),
      );

      expect((decision as ActivateSourceDirectly).source.serverId.value, 'nas');
    });

    test('film B, a different title on NAS + Jellyfin, goes straight to NAS too', () {
      // The point of the second film: nothing was remembered for it, and
      // nothing needed to be.
      final decision = decideFor(
        _group(
          [_source('nas', id: 'b1'), _source('jelly', id: 'b2')],
          identity: CanonicalMediaIdentity.movie(title: 'Film B', year: 2002),
          groupId: 'g2',
        ),
      );

      expect((decision as ActivateSourceDirectly).source.serverId.value, 'nas');
    });

    test('series C follows the same setting as the films', () {
      final decision = decideFor(
        _group(
          [_source('nas', id: 'c1'), _source('attic', id: 'c2')],
          identity: CanonicalMediaIdentity.show(title: 'Serie C', year: 2003),
          groupId: 'g3',
        ),
      );

      expect((decision as ActivateSourceDirectly).source.serverId.value, 'nas');
    });

    test('film D, which NAS does not have, falls back to its only source', () {
      final decision = decideFor(
        _group([_source('attic', id: 'd1')], identity: CanonicalMediaIdentity.movie(title: 'Film D', year: 2004)),
      );

      expect((decision as ActivateSourceDirectly).source.serverId.value, 'attic');
    });

    test('film E: NAS offline with one alternative left still needs no question', () {
      final decision = decideFor(
        _group([
          _source('nas', id: 'e1', availability: SourceAvailability.offline),
          _source('attic', id: 'e2'),
        ], identity: CanonicalMediaIdentity.movie(title: 'Film E', year: 2005)),
      );

      expect((decision as ActivateSourceDirectly).source.serverId.value, 'attic');
    });

    test('film F: NAS offline with two alternatives is a real choice, so it is asked', () {
      final decision = decideFor(
        _group([
          _source('nas', id: 'f1', availability: SourceAvailability.offline),
          _source('attic', id: 'f2'),
          _source('shed', id: 'f3'),
        ], identity: CanonicalMediaIdentity.movie(title: 'Film F', year: 2006)),
      );

      expect(decision, isA<ShowSourcePicker>());
    });

    test('one setting decides every group in the profile, with nothing stored per title', () {
      // The same `preferredServerId` value, five unrelated identities, five
      // answers — and no per-title state anywhere in between. `decide` is pure,
      // so this is the whole of it: there is no other input it could consult.
      final groups = [
        _group([_source('nas'), _source('attic')], identity: CanonicalMediaIdentity.movie(title: 'A', year: 2001)),
        _group([_source('nas'), _source('attic')], identity: CanonicalMediaIdentity.movie(title: 'B', year: 2002)),
        _group([_source('nas'), _source('attic')], identity: CanonicalMediaIdentity.show(title: 'C', year: 2003)),
        _group([
          _source('nas'),
          _source('attic'),
        ], identity: CanonicalMediaIdentity.season(showTitle: 'C', seasonIndex: 1)),
        _group([_source('nas'), _source('attic')], identity: CanonicalMediaIdentity.opaque()),
      ];

      for (final group in groups) {
        final decision = decideFor(group);
        expect(decision, isA<ActivateSourceDirectly>(), reason: '${group.identity} still resolved without asking');
        expect((decision as ActivateSourceDirectly).source.serverId.value, 'nas');
      }
    });

    test('an explicit switch on one title does not change what the next title does', () {
      // The user opened film A, pressed Wijzigen and took Zolder. That choice
      // lives in the detail route, not in the coordinator and not in the
      // profile — so the next activation, of any other title, is answered by
      // the standing default again.
      final next = decideFor(
        _group([
          _source('nas', id: 'g1'),
          _source('attic', id: 'g2'),
        ], identity: CanonicalMediaIdentity.movie(title: 'Film G', year: 2007)),
      );

      expect((next as ActivateSourceDirectly).source.serverId.value, 'nas');
    });

    test('without a preferred server every one of those groups asks instead', () {
      // The mirror image, so the tests above cannot pass for some other reason.
      final decision = _coordinator.decide(
        group: _group([_source('nas'), _source('attic')], identity: CanonicalMediaIdentity.movie(title: 'A')),
        intent: UnifiedActivationIntent.play,
        availabilityFor: _stamped,
      );

      expect(decision, isA<ShowSourcePicker>());
    });
  });
}
