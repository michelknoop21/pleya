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
/// ranking, an action either applies to every membership (because the contract
/// says the action is logical) or asks.
library;

import '../../media/unified/source_availability.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_source.dart';
import '../../services/unified_catalog/unified_activation_coordinator.dart';

/// The write-scope semantics of one action (hoofdstuk 23, 13.4, 13.5).
enum UnifiedActionScope {
  /// Applies to every membership at once; the user is not asked which. The
  /// action's own wording already refers to the logical title, so a source
  /// question would be answering something nobody asked.
  logical,

  /// One usable source goes straight through; several ask, and the question
  /// carries an explicit "Alle bronnen" alongside the concrete sources.
  /// Hoofdstuk 13.5 names markeer bekeken/onbekeken here by name.
  sourceSpecificWithAllSources,

  /// One usable source goes straight through; several ask, with concrete
  /// sources only. No all-sources row: offering one would invent semantics the
  /// contract does not give the action.
  sourceSpecific,
}

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

  /// Hoofdstuk 23's two lists, as a total function.
  ///
  /// Watchlist add and remove are both [logical]: DEC-020 established that an
  /// entry carries a list of memberships and that removal pulls the title from
  /// all of them without a source choice, because a per-source remove would
  /// let the title reappear from the membership nobody picked.
  ///
  /// [rate] is [sourceSpecific] rather than [sourceSpecificWithAllSources].
  /// 13.5 grants "Alle bronnen" to markeer bekeken/onbekeken and to nothing
  /// else, and a rating written to every copy is not obviously what a user who
  /// rated a film means — that is a product decision, and inventing it here
  /// would be exactly the kind of quiet widening this file guards against.
  UnifiedActionScope get scope => switch (this) {
    UnifiedGroupAction.markWatched ||
    UnifiedGroupAction.markUnwatched => UnifiedActionScope.sourceSpecificWithAllSources,
    UnifiedGroupAction.addToWatchlist ||
    UnifiedGroupAction.removeFromWatchlist ||
    UnifiedGroupAction.removeFromContinueWatching => UnifiedActionScope.logical,
    UnifiedGroupAction.rate => UnifiedActionScope.sourceSpecific,
  };
}

/// Why an action cannot be offered or carried out right now.
enum UnifiedActionBlocker {
  /// The group has memberships, but none on a reachable server. A write has
  /// nowhere to land; hoofdstuk 14.7's "servers beheren" is the way out.
  noUsableSource,
}

/// What the menu should do once the user picks an action.
sealed class UnifiedActionTarget {
  const UnifiedActionTarget();
}

/// Write to every source in [sources] without asking. Reached only by
/// [UnifiedActionScope.logical] — never by a source-specific action that
/// happens to have one candidate, which is [ApplyActionToSource].
final class ApplyActionToAllSources extends UnifiedActionTarget {
  const ApplyActionToAllSources(this.sources);

  final List<UnifiedMediaSource> sources;
}

/// Write to exactly [source], without a question.
///
/// Two different situations produce this and they must stay distinguishable at
/// the call site, because only one of them may be remembered as a preference:
/// [chosen] is false when a source-specific action had exactly one usable
/// candidate (hoofdstuk 14.6: one usable source is not a question, so it is not
/// asked, and nothing is remembered because the user chose nothing).
final class ApplyActionToSource extends UnifiedActionTarget {
  const ApplyActionToSource(this.source, {this.chosen = false});

  final UnifiedMediaSource source;
  final bool chosen;
}

/// Ask which source (or, when [allowAllSources], all of them).
///
/// [sources] is already in hoofdstuk 4.7 order, minus the preferred-source
/// tier: an action-scope question must not float the playback preference to
/// the top, because a row at the top of a list is the one a hurried user
/// picks.
final class AskForActionScope extends UnifiedActionTarget {
  const AskForActionScope({required this.sources, required this.allowAllSources});

  final List<UnifiedMediaSource> sources;
  final bool allowAllSources;
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
/// Only usable sources are candidates, including for the [logical] scope. A
/// write to an offline server is not a write; it is an error the user did not
/// ask for. That does mean a logical action can reach fewer sources than the
/// group has, which is precisely the partial case the callers report on
/// (hoofdstuk 13.4 point 5 and 13.5's "mislukte subset").
UnifiedActionTarget resolveUnifiedActionTarget({
  required UnifiedGroupAction action,
  required UnifiedMediaGroup group,
  required SourceAvailability Function(UnifiedMediaSource source) availabilityFor,
}) {
  // Ranked without `preferredSourceKey` on purpose — see [AskForActionScope].
  final usable = rankSources([
    for (final source in group.sources)
      if (availabilityFor(source).isUsable) source,
  ]);

  if (usable.isEmpty) return const ActionUnavailable(UnifiedActionBlocker.noUsableSource);

  switch (action.scope) {
    case UnifiedActionScope.logical:
      return ApplyActionToAllSources(usable);

    case UnifiedActionScope.sourceSpecificWithAllSources:
      if (usable.length == 1) return ApplyActionToSource(usable.single);
      return AskForActionScope(sources: usable, allowAllSources: true);

    case UnifiedActionScope.sourceSpecific:
      if (usable.length == 1) return ApplyActionToSource(usable.single);
      return AskForActionScope(sources: usable, allowAllSources: false);
  }
}
