import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_availability.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/screens/tv/tv_unified_context_actions.dart';

/// [summary] and [thumbPath] exist only to move a source up hoofdstuk 4.7's
/// ranking, which is how the negative controls below build a group whose
/// representative is *not* the first-listed source.
MediaItem _item(String serverId, {String id = 'i1', String? summary, String? thumbPath}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Dune',
  year: 2021,
  summary: summary,
  thumbPath: thumbPath,
  serverId: serverId,
  serverName: serverId,
);

UnifiedMediaSource _source(String serverId, {String id = 'i1', String? summary, String? thumbPath}) =>
    UnifiedMediaSource.fromItem(_item(serverId, id: id, summary: summary, thumbPath: thumbPath));

UnifiedMediaGroup _group(List<UnifiedMediaSource> sources, {String? representativeSourceKey, bool watched = false}) {
  final representative = representativeSourceKey ?? sources.first.sourceKey;
  return UnifiedMediaGroup(
    groupId: 'g1',
    identity: CanonicalMediaIdentity.movie(title: 'Dune', year: 2021),
    sources: sources,
    representativeSourceKey: representative,
    watchState: UnifiedWatchState(representativeSourceKey: representative, isWatched: watched),
  );
}

/// Everything online unless named in [offline].
SourceAvailability Function(UnifiedMediaSource) _health({Set<String> offline = const {}}) =>
    (source) => offline.contains(source.serverId.value) ? SourceAvailability.offline : SourceAvailability.online;

void main() {
  group('write scope follows the contract, not the action name', () {
    test('mark watched and unwatched are source-specific with an all-sources option (13.5)', () {
      expect(UnifiedGroupAction.markWatched.scope, UnifiedActionScope.sourceSpecificWithAllSources);
      expect(UnifiedGroupAction.markUnwatched.scope, UnifiedActionScope.sourceSpecificWithAllSources);
    });

    test('watchlist add and remove are logical (DEC-020)', () {
      expect(UnifiedGroupAction.addToWatchlist.scope, UnifiedActionScope.logical);
      expect(UnifiedGroupAction.removeFromWatchlist.scope, UnifiedActionScope.logical);
    });

    test('remove from continue watching is logical (13.4)', () {
      expect(UnifiedGroupAction.removeFromContinueWatching.scope, UnifiedActionScope.logical);
    });

    test('rate is source-specific with no all-sources option', () {
      expect(
        UnifiedGroupAction.rate.scope,
        UnifiedActionScope.sourceSpecific,
        reason: '13.5 grants "Alle bronnen" to watched/unwatched by name and to nothing else',
      );
    });
  });

  group('G12 — one source', () {
    test('a single usable source is written to without a question (14.6)', () {
      final only = _source('s1');
      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.markWatched,
        group: _group([only]),
        availabilityFor: _health(),
      );

      expect(target, isA<ApplyActionToSource>());
      expect((target as ApplyActionToSource).source.sourceKey, only.sourceKey);
      expect(target.chosen, isFalse, reason: 'nothing was chosen, so nothing may later be remembered as a choice');
    });

    test('two sources with only one reachable is still not a question', () {
      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.markWatched,
        group: _group([_source('s1'), _source('s2')]),
        availabilityFor: _health(offline: {'s2'}),
      );

      expect((target as ApplyActionToSource).source.serverId.value, 's1');
    });
  });

  group('G13 — several sources', () {
    test('two usable sources ask, with an explicit all-sources row', () {
      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.markWatched,
        group: _group([_source('s1'), _source('s2')]),
        availabilityFor: _health(),
      );

      expect(target, isA<AskForActionScope>());
      final ask = target as AskForActionScope;
      expect(ask.allowAllSources, isTrue);
      expect(ask.sources.map((s) => s.serverId.value), unorderedEquals(['s1', 's2']));
    });

    test('rate asks the same question without the all-sources row', () {
      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.rate,
        group: _group([_source('s1'), _source('s2')]),
        availabilityFor: _health(),
      );

      expect((target as AskForActionScope).allowAllSources, isFalse);
    });

    test('an offline source is not offered as a scope', () {
      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.markWatched,
        group: _group([_source('s1'), _source('s2'), _source('s3')]),
        availabilityFor: _health(offline: {'s2'}),
      );

      expect(
        (target as AskForActionScope).sources.map((s) => s.serverId.value),
        unorderedEquals(['s1', 's3']),
        reason: 'a write to an unreachable server is not a choice, it is an error the user did not ask for',
      );
    });
  });

  group('logical actions', () {
    test('a logical action takes every reachable membership, without asking', () {
      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.removeFromWatchlist,
        group: _group([_source('s1'), _source('s2'), _source('s3')]),
        availabilityFor: _health(),
      );

      expect(target, isA<ApplyActionToAllSources>());
      expect(
        (target as ApplyActionToAllSources).sources.map((s) => s.serverId.value),
        unorderedEquals(['s1', 's2', 's3']),
      );
    });

    test('a logical action still skips an unreachable membership', () {
      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.removeFromContinueWatching,
        group: _group([_source('s1'), _source('s2')]),
        availabilityFor: _health(offline: {'s1'}),
      );

      expect(
        (target as ApplyActionToAllSources).sources.map((s) => s.serverId.value),
        ['s2'],
        reason: 'hoofdstuk 13.4 point 5 reports a partial result rather than pretending the offline one was done',
      );
    });
  });

  group('nothing reachable', () {
    test('every action reports the blocker rather than picking a dead source', () {
      for (final action in UnifiedGroupAction.values) {
        final target = resolveUnifiedActionTarget(
          action: action,
          group: _group([_source('s1'), _source('s2')]),
          availabilityFor: _health(offline: {'s1', 's2'}),
        );

        expect(target, isA<ActionUnavailable>(), reason: '${action.name} must not fall through to a dead source');
        expect((target as ActionUnavailable).blocker, UnifiedActionBlocker.noUsableSource);
      }
    });
  });

  // The two negative controls this contract exists for. A write that quietly
  // picks a source is invisible and permanent; both of the shortcuts below are
  // legitimate for *playback* and must never be reachable from here.
  group('negative controls — a write never picks silently', () {
    test('the representative source is not chosen when a question is owed', () {
      // s2 outranks s1 on metadata completeness, so it is the representative
      // even though s1 is listed first — which is exactly the situation where
      // an accidental `group.representativeSource` would look like it worked.
      final s1 = _source('s1');
      final s2 = _source('s2', summary: 'A rich summary', thumbPath: '/art.jpg');
      final group = _group([s1, s2], representativeSourceKey: s2.sourceKey);

      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.markWatched,
        group: group,
        availabilityFor: _health(),
      );

      expect(
        target,
        isA<AskForActionScope>(),
        reason: 'a representative is an activation convenience; a write may not inherit it',
      );
      // The discriminator is that the question is *asked*, not which row leads
      // it: 4.7 ranking may legitimately put the representative first, and
      // asserting otherwise would pin an ordering nobody promised. What an
      // implementation reaching for `group.representativeSource` would produce
      // is an `ApplyActionToSource` on s2 with the other source silently gone.
      final ask = target as AskForActionScope;
      expect(
        ask.sources.map((s) => s.sourceKey),
        containsAll([s1.sourceKey, s2.sourceKey]),
        reason: 'both memberships stay on the table; the representative does not absorb the other',
      );
    });

    test('the best-ranked source does not lead the list of a write question', () {
      // Same group, read the other way round: what the picker shows first must
      // be plain hoofdstuk 4.7 order with no preference tier folded in, so no
      // remembered playback choice can float to the row a hurried user presses.
      final s1 = _source('s1', summary: 'A rich summary', thumbPath: '/art.jpg');
      final s2 = _source('s2');

      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.markWatched,
        group: _group([s2, s1]),
        availabilityFor: _health(),
      );

      final sources = (target as AskForActionScope).sources;
      expect(
        sources.first.serverId.value,
        's1',
        reason: 'ordering is 4.7 completeness, not "the one activation would have used"',
      );
      expect(sources.length, 2, reason: 'and the other source is still offered, not ranked away');
    });

    test('resolution reads live availability, never the stamped value', () {
      // A source stamped online at page time, on a server that has since gone
      // down. Trusting the stamp would offer a write with nowhere to land.
      final stamped = UnifiedMediaSource.fromItem(_item('s1')).withAvailability(SourceAvailability.online);

      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.markWatched,
        group: _group([stamped]),
        availabilityFor: (_) => SourceAvailability.offline,
      );

      expect(target, isA<ActionUnavailable>());
    });
  });
}
