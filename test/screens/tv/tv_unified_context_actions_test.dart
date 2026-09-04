import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_availability.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/services/unified_action_outcome.dart';
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

/// Everything online unless named in [offline], [authError] or [unknown].
SourceAvailability Function(UnifiedMediaSource) _health({
  Set<String> offline = const {},
  Set<String> authError = const {},
  Set<String> unknown = const {},
}) => (source) {
  final id = source.serverId.value;
  if (offline.contains(id)) return SourceAvailability.offline;
  if (authError.contains(id)) return SourceAvailability.authError;
  if (unknown.contains(id)) return SourceAvailability.unknown;
  return SourceAvailability.online;
};

void main() {
  group('write scope follows the contract, not the action name', () {
    test('no action asks which source a write lands on (DEC-071, DEC-075)', () {
      // The scope vocabulary is gone, so this is now a property of every
      // action rather than a list of exceptions: a write covers the title.
      // Watch state got here first (one UnifiedWatchState per group, one
      // watched mark on the card, so asking which server asked about a
      // distinction the rest of the app does not make), and rating followed
      // for the same reason — one film, one number.
      for (final action in UnifiedGroupAction.values) {
        final target = resolveUnifiedActionTarget(
          action: action,
          group: _group([_source('s1'), _source('s2')]),
          availabilityFor: _health(),
        );

        expect(target, isA<ApplyActionToAllSources>(), reason: '${action.name} may not ask');
        expect(
          (target as ApplyActionToAllSources).sources.map((s) => s.serverId.value),
          unorderedEquals(['s1', 's2']),
          reason: '${action.name} must reach both memberships, not one of them',
        );
      }
    });

    test('rating is logical (DEC-075)', () {
      // The one that changed, on its own, so a regression names itself. Before
      // DEC-075 this returned a question with two rows in it, and whichever row
      // the user pressed left the other server on a different number.
      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.rate,
        group: _group([_source('s1'), _source('s2')]),
        availabilityFor: _health(),
      );

      expect(
        (target as ApplyActionToAllSources).sources.map((s) => s.serverId.value),
        unorderedEquals(['s1', 's2']),
        reason: 'een cijfer geldt voor de titel, niet voor de kopie',
      );
    });
  });

  group('G12 — one source', () {
    test('a single usable source is written to without a question (14.6)', () {
      // Still 14.6's rule, and it is now reached by the same road as every
      // other count: nothing asks, so "one source" stopped being a special case
      // rather than becoming one. Parametrised over every action because since
      // DEC-075 there is no action left that this could be false for.
      final only = _source('s1');
      for (final action in UnifiedGroupAction.values) {
        final target = resolveUnifiedActionTarget(action: action, group: _group([only]), availabilityFor: _health());

        final all = target as ApplyActionToAllSources;
        expect(all.sources.map((s) => s.sourceKey), [only.sourceKey], reason: action.name);
        expect(all.deferredSources, isEmpty, reason: action.name);
        expect(all.unreachableSources, isEmpty, reason: action.name);
      }
    });

    test('an unreachable membership is held rather than dropped', () {
      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.markWatched,
        group: _group([_source('s1'), _source('s2')]),
        availabilityFor: _health(offline: {'s2'}),
      );

      final all = target as ApplyActionToAllSources;
      expect(all.sources.map((s) => s.serverId.value), ['s1']);
      expect(
        all.deferredSources.map((s) => s.serverId.value),
        ['s2'],
        reason: 'stopping at the servers that happened to be up is the rule being broken quietly (DEC-071)',
      );
    });
  });

  group('G13 — several sources', () {
    test('marking watched never asks, it takes every membership (DEC-071)', () {
      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.markWatched,
        group: _group([_source('s1'), _source('s2')]),
        availabilityFor: _health(),
      );

      expect(target, isA<ApplyActionToAllSources>());
      expect((target as ApplyActionToAllSources).sources.map((s) => s.serverId.value), unorderedEquals(['s1', 's2']));
    });

    test('rating takes every membership, and never one of them', () {
      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.rate,
        group: _group([_source('s1'), _source('s2')]),
        availabilityFor: _health(),
      );

      final all = target as ApplyActionToAllSources;
      expect(all.sources.map((s) => s.serverId.value), unorderedEquals(['s1', 's2']));
      expect(all.intendedTargetCount, 2);
    });

    test('an offline source is written later, not written off', () {
      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.markWatched,
        group: _group([_source('s1'), _source('s2'), _source('s3')]),
        availabilityFor: _health(offline: {'s2'}),
      );

      final all = target as ApplyActionToAllSources;
      expect(all.sources.map((s) => s.serverId.value), unorderedEquals(['s1', 's3']));
      expect(all.deferredSources.map((s) => s.serverId.value), ['s2']);
    });

    test('an unreachable membership stays in a rating\'s denominator', () {
      // Rating queues nothing, so this membership is not coming back later:
      // it is counted so the message can say "1 van 2" instead of claiming
      // both, and it is handed back in its own list so nobody can mistake it
      // for something waiting on a reconnect (DEC-075).
      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.rate,
        group: _group([_source('s1'), _source('s2')]),
        availabilityFor: _health(offline: {'s2'}),
      );

      final all = target as ApplyActionToAllSources;
      expect(all.sources.map((s) => s.serverId.value), ['s1']);
      expect(all.deferredSources, isEmpty, reason: 'a rating has no queue, so nothing may be held');
      expect(all.unreachableSources.map((s) => s.serverId.value), ['s2']);
      expect(all.intendedTargetCount, 2, reason: 'the message says 1 of 2, so the 2 has to be real');
    });

    test('the two unreachable lists are never both filled', () {
      // They answer the same question for opposite kinds of action — held for
      // later, or reported and gone — and a target carrying both would mean
      // the same membership was counted twice.
      for (final action in UnifiedGroupAction.values) {
        final target =
            resolveUnifiedActionTarget(
                  action: action,
                  group: _group([_source('s1'), _source('s2')]),
                  availabilityFor: _health(offline: {'s2'}),
                )
                as ApplyActionToAllSources;

        expect(target.deferredSources.isEmpty || target.unreachableSources.isEmpty, isTrue, reason: action.name);
        expect(target.intendedTargetCount, 2, reason: action.name);
      }
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
    test('every action but the deferrable one reports the blocker rather than picking a dead source', () {
      for (final action in UnifiedGroupAction.values.where((a) => !a.queuesUnreachableMemberships)) {
        final target = resolveUnifiedActionTarget(
          action: action,
          group: _group([_source('s1'), _source('s2')]),
          availabilityFor: _health(offline: {'s1', 's2'}),
        );

        expect(target, isA<ActionUnavailable>(), reason: '${action.name} must not fall through to a dead source');
        expect((target as ActionUnavailable).blocker, UnifiedActionBlocker.noUsableSource);
      }
    });

    test('a removal with nothing online is deferred, not refused', () {
      // Hoofdstuk 13.4 point 3 gives this case real work to do: hold the
      // removal so the card goes away now and the write lands on reconnect.
      // "No usable source" would be the wrong answer to a question the
      // contract already answers.
      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.removeFromContinueWatching,
        group: _group([_source('s1'), _source('s2')]),
        availabilityFor: _health(offline: {'s1', 's2'}),
      );

      expect(target, isA<ApplyActionToAllSources>());
      final apply = target as ApplyActionToAllSources;
      expect(apply.sources, isEmpty);
      expect(apply.deferredSources.map((s) => s.serverId.value), ['s1', 's2']);
      expect(apply.intendedTargetCount, 2);
    });

    test('a removal with nothing but an auth-errored source is still refused', () {
      // Reconnecting does not sign the user back in, so there is nothing to
      // hold: the queue entry would retry until it hit its attempt cap under
      // a message promising otherwise.
      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.removeFromContinueWatching,
        group: _group([_source('s1')]),
        availabilityFor: _health(authError: {'s1'}),
      );

      expect(target, isA<ActionUnavailable>());
      // ...and refused with the reason the user can act on. "No source is
      // currently reachable" sends them to server management; the server is
      // reachable and wants them to sign in again (hoofdstuk 14.7, 21.5).
      expect((target as ActionUnavailable).blocker, UnifiedActionBlocker.signInRequired);
    });

    test('an offline membership alongside a signed-out one keeps the general refusal', () {
      // Two different ways out, so neither one of them is the whole truth.
      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.rate,
        group: _group([_source('s1'), _source('s2')]),
        availabilityFor: _health(authError: {'s1'}, offline: {'s2'}),
      );

      expect((target as ActionUnavailable).blocker, UnifiedActionBlocker.noUsableSource);
    });
  });

  // G10/G11: hoofdstuk 13.4's denominator is the intent, not the reachable
  // subset. "Verwijderd op 2 van 3 bronnen" only exists as a sentence if the
  // third membership is counted.
  group('G10: the intended target count', () {
    test('an unreachable membership stays in the denominator and is handed back to be queued', () {
      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.removeFromContinueWatching,
        group: _group([_source('s1'), _source('s2'), _source('s3')]),
        availabilityFor: _health(offline: {'s3'}),
      );

      final apply = target as ApplyActionToAllSources;
      expect(apply.sources.map((s) => s.serverId.value), unorderedEquals(['s1', 's2']));
      expect(apply.deferredSources.map((s) => s.serverId.value), ['s3']);
      expect(apply.intendedTargetCount, 3, reason: 'the message says 2 of 3, so the 3 has to be real');
    });

    test('an unchecked server is deferrable too', () {
      // hoofdstuk 4.2 keeps `unknown` distinct from offline because it means
      // "not asked". A membership nobody asked about is exactly one whose
      // removal should be held rather than dropped.
      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.removeFromContinueWatching,
        group: _group([_source('s1'), _source('s2')]),
        availabilityFor: _health(unknown: {'s2'}),
      );

      expect((target as ApplyActionToAllSources).deferredSources.map((s) => s.serverId.value), ['s2']);
    });

    test('an auth-errored membership is never deferred, so nothing promises it a retry', () {
      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.removeFromContinueWatching,
        group: _group([_source('s1'), _source('s2')]),
        availabilityFor: _health(authError: {'s2'}),
      );

      final apply = target as ApplyActionToAllSources;
      expect(apply.deferredSources, isEmpty, reason: 'a reconnect does not sign the user back in');
      // But it is still a membership this action set out to affect. It used to
      // fall out of all three buckets — not usable, deliberately not
      // deferrable, and the unreachable list named the deferral's own
      // condition — so the write reported "done on all 1" and, because that
      // reads as complete, said nothing at all. The title then showed watched
      // on the wall while the signed-out server still said unwatched, which is
      // what DEC-071 exists to prevent.
      expect(apply.unreachableSources.map((s) => s.serverId.value), ['s2']);
      expect(apply.intendedTargetCount, 2);
      expect(
        unifiedActionOutcomeMessage(done: apply.sources.length, total: apply.intendedTargetCount, queued: 0),
        isNotNull,
        reason: 'the honest denominator is what makes the user see the partial write at all',
      );
    });

    test('no other action defers anything, however unreachable its memberships are', () {
      // Deferral is granted by a contract, one action at a time: 13.4 for the
      // Continue Watching removal, DEC-071 for watch state. Everything else
      // still reports rather than promises.
      const defers = {
        UnifiedGroupAction.removeFromContinueWatching,
        UnifiedGroupAction.markWatched,
        UnifiedGroupAction.markUnwatched,
      };
      for (final action in UnifiedGroupAction.values.where((a) => !defers.contains(a))) {
        expect(action.queuesUnreachableMemberships, isFalse, reason: action.name);
      }

      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.removeFromWatchlist,
        group: _group([_source('s1'), _source('s2')]),
        availabilityFor: _health(offline: {'s2'}),
      );

      final apply = target as ApplyActionToAllSources;
      expect(apply.deferredSources, isEmpty, reason: 'nothing is held for an action with no queue behind it');
      expect(
        apply.unreachableSources.map((s) => s.serverId.value),
        ['s2'],
        reason: 'but it is still counted, because the user is told a fraction',
      );
    });

    test('everything online defers nothing and counts every membership', () {
      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.removeFromContinueWatching,
        group: _group([_source('s1'), _source('s2')]),
        availabilityFor: _health(),
      );

      final apply = target as ApplyActionToAllSources;
      expect(apply.deferredSources, isEmpty);
      expect(apply.intendedTargetCount, 2);
      expect(apply.sources, hasLength(2));
    });
  });

  // The two negative controls this contract exists for. A write that quietly
  // picks a source is invisible and permanent; both of the shortcuts below are
  // legitimate for *playback* and must never be reachable from here.
  group('DEC-071: a held watch-state write goes into the watch-state queue', () {
    // The dispatch itself lives in `_queueDeferred`, a private function reached
    // only through a BuildContext with a real OfflineWatchProvider, and that
    // provider needs a DownloadProvider no test in this repo constructs. So the
    // routing is guarded statically here, while what it routes *into* is proven
    // dynamically elsewhere: offline_watch_sync_service_test.dart persists the
    // `watched`/`unwatched` rows, and G11 replays them on reconnect.
    //
    // Worth guarding rather than trusting: before DEC-071 this function wrote a
    // Continue Watching removal for every deferred membership, so a watched
    // action inheriting that path would silently take the title off the shelf
    // instead of marking it watched, and nothing would fail.
    final menuSource = File('lib/screens/tv/tv_unified_context_menu.dart').readAsStringSync();
    final queueDeferred = RegExp(r'Future<int> _queueDeferred\([\s\S]*?\n\}').firstMatch(menuSource)?.group(0);

    test('the deferral routes per action instead of assuming one', () {
      expect(queueDeferred, isNotNull, reason: '_queueDeferred must exist to be guarded');
      expect(
        queueDeferred,
        contains('switch (action)'),
        reason: 'one hardcoded queue call is how a watched write became a Continue Watching removal',
      );
    });

    test('watched and unwatched reach the watch-state entry points', () {
      expect(queueDeferred, contains('markAsWatched('));
      expect(queueDeferred, contains('markAsUnwatched('));
      expect(
        queueDeferred,
        contains('queueRemoveFromContinueWatching('),
        reason: '13.4 keeps its own row: the two queues are not interchangeable',
      );
    });
  });

  group('DEC-075: the rating fan-out is wired to the group, not to one source', () {
    // Same reason the DEC-071 guards above are static: the rate branch reaches
    // `RatingBottomSheet` through an overlay, a `MultiServerProvider` and a
    // real client, and none of that is constructible here. What the resolver
    // hands over is proven above; what the menu does with it is guarded here.
    //
    // Worth guarding rather than trusting, because the old branch is one line
    // away and still compiles: `sources.single` plus one client was the whole
    // of it before this DEC, and a regression to it would rate one server
    // while the snackbar counted them all.
    final menuSource = File('lib/screens/tv/tv_unified_context_menu.dart').readAsStringSync();
    final rateBranch = RegExp(
      // `\n}\n` rather than `\n}`: the parameter list itself closes with a
      // `}` at column zero (`}) async {`), so the looser pattern stops before
      // the body it is supposed to be reading.
      r'Future<void> _rateEveryMembership\([\s\S]*?\n\}\n',
    ).firstMatch(menuSource)?.group(0);

    test('the write is built from every membership', () {
      expect(rateBranch, isNotNull, reason: '_rateEveryMembership must exist to be guarded');
      expect(
        rateBranch,
        contains('RatingMirror.fromSources'),
        reason: 'the fan-out reads the list; a single source would be the pre-DEC-075 behaviour',
      );
      expect(rateBranch, isNot(contains('sources.single')));
    });

    test('the mirror is fed the raw written value, not the display value', () {
      // `onServerRatingChanged` flattens the -1 clear sentinel to 0, and 0 is a
      // real rating on Plex. Hanging the mirror off it would turn every "wis
      // mijn cijfer" into a 0/10 on every other server.
      expect(rateBranch, contains('onServerRatingWritten: mirror.write'));
    });

    test('an unreachable membership reaches the denominator', () {
      expect(
        rateBranch,
        contains('additionalUnreachable: unreachableSources.length'),
        reason: 'rate queues nothing, so counting it is the only honest thing left to do',
      );
      expect(rateBranch, contains('mirror.intendedTargetCount'));
    });

    test('the detail screen is on the same seam', () {
      // Decision 1 was "overal waar je kunt waarderen", and the detail screen
      // is the other place you can. It derives its siblings from the route
      // context rather than from a group, but it must not do so by hand.
      final detailSource = File('lib/screens/media_detail_screen.dart').readAsStringSync();
      expect(detailSource, contains('RatingMirror.fromSourceKeys'));
      expect(detailSource, contains('onServerRatingWritten: mirror?.write'));
      expect(
        detailSource,
        contains('availableSourceKeys'),
        reason: 'the route context already names every membership; nothing else should be invented',
      );
    });
  });

  group('negative controls — a write never picks silently', () {
    test('the representative source absorbs nothing', () {
      // s2 outranks s1 on metadata completeness, so it is the representative
      // even though s1 is listed first — which is exactly the situation where
      // an accidental `group.representativeSource` would look like it worked.
      final s1 = _source('s1');
      final s2 = _source('s2', summary: 'A rich summary', thumbPath: '/art.jpg');
      final group = _group([s1, s2], representativeSourceKey: s2.sourceKey);

      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.rate,
        group: group,
        availabilityFor: _health(),
      );

      // The discriminator is not which row leads the list: 4.7 ranking may
      // legitimately put the representative first, and asserting otherwise
      // would pin an ordering nobody promised. It is that *both* are there.
      // What an implementation reaching for `group.representativeSource` would
      // produce is a list of one, on s2, with the other membership silently
      // gone — which is precisely the invisible, permanent half-write this
      // file exists to prevent.
      final all = target as ApplyActionToAllSources;
      expect(
        all.sources.map((s) => s.sourceKey),
        containsAll([s1.sourceKey, s2.sourceKey]),
        reason: 'both memberships are written to; the representative does not absorb the other',
      );
      expect(all.sources, hasLength(2));
    });

    test('the candidate list carries no preferred-source tier', () {
      // Same group, read the other way round. There is no question any more,
      // but the order is still load-bearing: `sources.first` is the membership
      // the rating sheet binds to, so it decides which control is drawn and
      // whose server name sits under "Opgeslagen". A remembered playback
      // preference floating to the front would put the visible half of a write
      // on a source the user never chose.
      final s1 = _source('s1', summary: 'A rich summary', thumbPath: '/art.jpg');
      final s2 = _source('s2');

      final target = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.rate,
        group: _group([s2, s1]),
        availabilityFor: _health(),
      );

      final sources = (target as ApplyActionToAllSources).sources;
      expect(
        sources.first.serverId.value,
        's1',
        reason: 'ordering is 4.7 completeness, not "the one activation would have used"',
      );
      expect(sources.length, 2, reason: 'and the other source is still written to, not ranked away');
    });

    test('resolution reads live availability, never the stamped value', () {
      // A source stamped online at page time, on a server that has since gone
      // down. Trusting the stamp would offer a write with nowhere to land.
      final stamped = UnifiedMediaSource.fromItem(_item('s1')).withAvailability(SourceAvailability.online);

      expect(
        resolveUnifiedActionTarget(
          action: UnifiedGroupAction.rate,
          group: _group([stamped]),
          availabilityFor: (_) => SourceAvailability.offline,
        ),
        isA<ActionUnavailable>(),
      );

      // The same rule for an action that may defer: the stamp does not get it
      // written now, it gets it held.
      final watched = resolveUnifiedActionTarget(
        action: UnifiedGroupAction.markWatched,
        group: _group([stamped]),
        availabilityFor: (_) => SourceAvailability.offline,
      );

      final all = watched as ApplyActionToAllSources;
      expect(all.sources, isEmpty, reason: 'nothing is written to a server that is not there');
      expect(all.deferredSources.map((s) => s.serverId.value), ['s1']);
    });
  });
}
