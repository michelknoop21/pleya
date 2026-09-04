/// What a context menu on a unified card may offer, and — for a chosen action —
/// which concrete source or sources the write must land on.
///
/// Hoofdstuk 23 splits the actions into *safe group actions* and *actions that
/// require a source choice*, and 13.4/13.5 fix the semantics of the two the TV
/// surfaces need most. This file is the decision half of that contract and
/// nothing else: no widgets, no `BuildContext`, no dispatch. The menu asks it
/// what to do and then does it, which is what keeps the rule below testable
/// rather than merely stated.
///
/// **The rule this file exists to enforce.** A write never silently picks
/// `representativeSource` or the preferred server. Both are activation
/// conveniences — they answer "where would this user most likely want to play
/// it", which is a good guess precisely because a wrong guess is visible and
/// instantly correctable. A write is neither: marking the wrong copy watched
/// is invisible and permanent. So where playback resolves a single source by
/// ranking, an action applies to every membership of the group.
///
/// Every membership, for every action, is where this ended up. It did not
/// start there: 13.5 once granted markeer bekeken/onbekeken a source question
/// with an explicit "Alle bronnen" row, and rate kept that question until
/// [DEC-075](../../docs/DECISIONS.md#dec-075). Both went the same way and for
/// the same reason. The question presented a distinction the rest of the
/// product does not make — one watched mark per card, one rating per title —
/// and the answer a hurried user gave it produced a title that read one way on
/// the wall and another way on a server they were not looking at.
///
/// So the rule above is now enforced by shape rather than by discipline: there
/// is one target type for a write that lands, it carries a list, and the list
/// is every membership. An implementation that reached for
/// `representativeSource` would produce a list of one, which is what the
/// negative controls in `tv_unified_context_actions_test.dart` look for.
library;

import '../../media/unified/source_availability.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_source.dart';
import '../../services/unified_catalog/unified_activation_coordinator.dart';

/// The actions a unified TV card offers. Deliberately not "every action the
/// legacy `MediaContextMenu` has" — hoofdstuk 23 puts library management
/// (scan, analyse, collectiebeheer) somewhere else entirely, and the
/// source-bound ones it does allow (download, serverplaylist, metadata,
/// serverdelete) each need their own surface work.
enum UnifiedGroupAction {
  markWatched,
  markUnwatched,
  addToWatchlist,
  removeFromWatchlist,
  rate,
  removeFromContinueWatching;

  /// Whether a membership this action targets but cannot reach right now is
  /// *held* rather than dropped.
  ///
  /// Only remove-from-Continue-Watching. Hoofdstuk 13.4 is the one action
  /// contract that defines both halves of a deferral — point 3 stores a local
  /// suppression for unreachable sources, point 4 replays it on reconnect —
  /// and point 5's own example message ("Verwijderd op 2 van 3 bronnen") shows
  /// a denominator that counts a membership which was never online.
  ///
  /// Markeer bekeken/onbekeken joined it under DEC-071: once "bekeken is
  /// bekeken" is the rule, a write that stops at the servers that happened to
  /// be up is not the rule being kept, it is the rule being broken quietly.
  /// The queue this borrows is not invented for it either — the offline
  /// watch-state queue already carries `watched`/`unwatched` rows and already
  /// replays them on reconnect, which is what makes the promise keepable.
  ///
  /// The watchlist actions are still refused offline outright (DEC-020), for a
  /// reason a queue would reintroduce: a deferred write has no merge rule
  /// against what the same account did on plex.tv meanwhile.
  ///
  /// Rating stayed out for a plainer reason: there is nothing to hold it in.
  /// The offline queue's action types are progress, watched, unwatched and
  /// removed-from-Continue-Watching, and none of its rows carries a value. So
  /// DEC-075 fans a rating out to every membership it can reach *now* and
  /// reports the rest, which is why an unreachable membership for rate arrives
  /// as [ApplyActionToAllSources.unreachableSources] rather than as
  /// [ApplyActionToAllSources.deferredSources].
  bool get queuesUnreachableMemberships =>
      this == UnifiedGroupAction.removeFromContinueWatching ||
      this == UnifiedGroupAction.markWatched ||
      this == UnifiedGroupAction.markUnwatched;
}

/// Why an action cannot be offered or carried out right now.
enum UnifiedActionBlocker {
  /// The group has memberships, but none on a reachable server. A write has
  /// nowhere to land; hoofdstuk 14.7's "servers beheren" is the way out.
  noUsableSource,

  /// Same absence of a usable source, different cause and different way out:
  /// every membership is on a server that answered and refused. Hoofdstuk 14.7
  /// and 21.5 require these two to read differently — an auth error is
  /// something the user can fix from the couch, an offline server is not —
  /// and [SourceAvailability.authError]'s own contract names the wording
  /// ("Opnieuw aanmelden vereist"). Telling someone no source is reachable
  /// when the fix is to sign in again sends them to the wrong place.
  signInRequired,
}

/// What the menu should do once the user picks an action.
sealed class UnifiedActionTarget {
  const UnifiedActionTarget();
}

/// Write to every source in [sources] without asking.
///
/// The only target a write ever lands through. One usable source is not a
/// special case that skips a question; it is a list of length one, which is
/// what hoofdstuk 14.6 meant by "one usable source is not a question".
final class ApplyActionToAllSources extends UnifiedActionTarget {
  const ApplyActionToAllSources(this.sources, {this.deferredSources = const [], this.unreachableSources = const []});

  /// The memberships that can be written to now.
  final List<UnifiedMediaSource> sources;

  /// The memberships the action contract targets but that are not reachable,
  /// for an action whose contract says to hold them
  /// ([UnifiedGroupAction.queuesUnreachableMemberships]). Always empty for
  /// every other action.
  ///
  /// They are a separate list rather than folded into [sources] because the
  /// caller has to do two different things with them — write now versus queue
  /// — while counting them as one denominator. Hoofdstuk 13.4 point 5's
  /// message is "verwijderd op 2 van 3", and the 3 is [intendedTargetCount].
  final List<UnifiedMediaSource> deferredSources;

  /// The memberships the action targets but cannot reach, *and* that nothing
  /// will pick up later. Counted in [intendedTargetCount] and reported once;
  /// never retried, never held.
  ///
  /// The mirror image of [deferredSources], and the two are mutually exclusive
  /// by construction: an action either has a queue that keeps its promise
  /// ([UnifiedGroupAction.queuesUnreachableMemberships]) or it has this. What
  /// they share is the denominator, because that is the part the user reads.
  /// Rate is the action this exists for (DEC-075): it reaches everything it
  /// can and says plainly what it could not.
  final List<UnifiedMediaSource> unreachableSources;

  /// How many memberships this action set out to affect. The honest
  /// denominator: reporting "klaar op alle 2" while a third membership was
  /// never touched is the failure hoofdstuk 13.4 point 5 is written against.
  int get intendedTargetCount => sources.length + deferredSources.length + unreachableSources.length;
}

/// The action cannot proceed.
final class ActionUnavailable extends UnifiedActionTarget {
  const ActionUnavailable(this.blocker);

  final UnifiedActionBlocker blocker;
}

/// Decides what [action] on [group] should do, given live availability.
///
/// Availability is read through [availabilityFor] rather than off
/// [UnifiedMediaSource.availability], for the same reason activation does it:
/// the stamped value may predate the last server health change, and an action
/// menu can sit open across one.
///
/// Only usable sources are written to. A write to an offline server is not a
/// write; it is an error the user did not ask for. That does mean an action
/// can reach fewer sources than the group has, which is precisely the partial
/// case the callers report on (hoofdstuk 13.4 point 5 and 13.5's "mislukte
/// subset").
///
/// Unreachable is not the same as out of scope, though, and for an action with
/// [UnifiedGroupAction.queuesUnreachableMemberships] the difference is the
/// whole of hoofdstuk 13.4 points 3-5. Those memberships come back as
/// [ApplyActionToAllSources.deferredSources]: still counted in the
/// denominator, not written to now, and the caller's cue to queue them. An
/// [SourceAvailability.authError] source is deliberately **not** deferred —
/// reconnecting does not sign the user back in, so holding it would be a
/// promise nothing keeps — and it is reported as a plain failure instead.
///
/// For an action that holds nothing they come back as
/// [ApplyActionToAllSources.unreachableSources] instead: counted in the same
/// denominator, but named as what they are, so nobody promises a retry that
/// does not exist (DEC-075).
///
/// The same rule decides [ActionUnavailable]: with nothing online but a
/// deferrable membership present there is real work to do (hold it, and let
/// the replay finish it), so answering "no usable source" would be wrong. With
/// nothing online and no queue behind the action there is no such work, so the
/// blocker stands even though [ApplyActionToAllSources.unreachableSources]
/// would have had something to say.
UnifiedActionTarget resolveUnifiedActionTarget({
  required UnifiedGroupAction action,
  required UnifiedMediaGroup group,
  required SourceAvailability Function(UnifiedMediaSource source) availabilityFor,
}) {
  // Ranked without `preferredSourceKey` on purpose. The order is not cosmetic:
  // `sources.first` is the membership a rating sheet binds to, so a preferred
  // playback choice floating to the front would put the visible half of a
  // write on a source the user never chose.
  final usable = rankSources([
    for (final source in group.sources)
      if (availabilityFor(source).isUsable) source,
  ]);

  // Deferrable = targeted by the contract, not reachable now, and reachable
  // again by nothing more than the server coming back. `unknown` counts:
  // hoofdstuk 4.2 keeps it distinct from offline precisely because it means
  // "not asked", and a membership nobody asked about is exactly one whose
  // removal should be held rather than silently dropped.
  final deferred = action.queuesUnreachableMemberships
      ? [
          for (final source in group.sources)
            if (_isDeferrable(availabilityFor(source))) source,
        ]
      : const <UnifiedMediaSource>[];

  // Everything the action targets and neither writes to nor holds: counted so
  // the tally is honest, and handed back separately so no caller can mistake
  // it for something that will be retried.
  //
  // Defined as the remainder rather than as its own predicate, and that is the
  // point: every membership lands in exactly one of the three buckets, so
  // [ApplyActionToAllSources.intendedTargetCount] is always the group's own
  // source count. The version that named its own condition (`_isDeferrable`,
  // the deferral's mirror) dropped `authError` out of all three — it is not
  // usable, and it is deliberately not deferrable — so a title on one healthy
  // server and one signed-out server reported "done on 1 of 1" and then said
  // nothing at all, which is exactly the incoherence hoofdstuk 13.4 point 5
  // and DEC-071 are written against. The doc above this function has always
  // said such a membership "is reported as a plain failure instead"; this is
  // what makes that true.
  final held = {...usable, ...deferred};
  final unreachable = [
    for (final source in group.sources)
      if (!held.contains(source)) source,
  ];

  if (usable.isEmpty && deferred.isEmpty) {
    // Only when *every* membership is an auth error is the sign-in message the
    // whole truth. A group half offline and half signed-out has two different
    // ways out, and the general message is the honest one there.
    final allAuthError =
        group.sources.isNotEmpty &&
        group.sources.every((source) => availabilityFor(source) == SourceAvailability.authError);
    return ActionUnavailable(allAuthError ? UnifiedActionBlocker.signInRequired : UnifiedActionBlocker.noUsableSource);
  }

  return ApplyActionToAllSources(usable, deferredSources: deferred, unreachableSources: unreachable);
}

/// Whether an unreachable source is one a reconnect would fix.
///
/// [SourceAvailability.authError] is not: the server answered and refused, and
/// only the user signing in again changes that. Queueing it would leave a row
/// that retries until it hits its attempt cap, under a message that told the
/// user it would be retried "zodra deze online is" — which it already is.
bool _isDeferrable(SourceAvailability availability) => switch (availability) {
  SourceAvailability.offline || SourceAvailability.unknown => true,
  SourceAvailability.online || SourceAvailability.authError => false,
};
