/// What a play of one title does across its sources (DEC-XXX "Eén titel over
/// servers heen", hoofdstuk 13.2 and 15 of docs/tvos-unified-experience.md).
///
/// The page keeps the main source. Which concrete item a play starts, where it
/// starts, what follows it and which other copies hear about it is answered
/// here, so the page and the player cannot answer differently. Hoofdstuk 4.1
/// still holds: nothing here merges two sources into one [MediaItem], and
/// every answer is one concrete item on one server.
library;

import 'dart:async';

import '../../media/episode_collection.dart';
import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_item_types.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_source.dart';
import '../../media/unified/unified_route_context.dart';
import '../../media/unified/unified_watch_state.dart';
import '../../utils/app_logger.dart';
import '../../utils/global_key_utils.dart';
import 'source_episode_index.dart';
import 'source_resolver.dart';

/// What this profile may do with a server, read live at every decision: a
/// route outlives the moment its group was built.
class UnifiedSourceGate {
  const UnifiedSourceGate({
    required this.clientFor,
    required this.isOnline,
    required this.isAuthRejected,
    required this.isVisible,
    required this.hiddenLibraryKeys,
    required this.isRestrictedProfile,
    this.fresh,
  });

  final MediaServerClient? Function(ServerId serverId) clientFor;
  final bool Function(ServerId serverId) isOnline;
  final bool Function(ServerId serverId) isAuthRejected;
  final bool Function(ServerId serverId) isVisible;
  final Set<String> Function() hiddenLibraryKeys;

  /// A children's profile. It keeps to the source it chose and the one the page
  /// shows: a third server may hold what those two hide from this profile.
  final Future<bool> Function() isRestrictedProfile;

  /// The session's newest watch state of an item, when it has one.
  final MediaItem Function(MediaItem item)? fresh;

  MediaItem freshen(MediaItem item) => fresh?.call(item) ?? item;

  bool _inView(UnifiedMediaSource source) {
    if (!isVisible(source.serverId)) return false;
    final libraryId = source.libraryId;
    return libraryId == null || !hiddenLibraryKeys().contains(buildGlobalKey(source.serverId, libraryId));
  }

  /// Whether [source] may be asked something right now.
  bool mayRead(UnifiedMediaSource source) =>
      _inView(source) &&
      !isAuthRejected(source.serverId) &&
      isOnline(source.serverId) &&
      clientFor(source.serverId) != null;

  /// Whether a write may be addressed to [source]. A server that is merely
  /// offline stays in: the queue holds the write. A rejected token does not: a
  /// reconnect does not fix it, and a queued row would replay under whoever
  /// signs in next.
  bool mayWrite(UnifiedMediaSource source) => _inView(source) && !isAuthRejected(source.serverId);
}

/// The concrete item a play starts, and where, when the position lives on
/// another source than the one that plays.
class UnifiedPlayTarget {
  const UnifiedPlayTarget(this.item, {this.carriedResume});

  final MediaItem item;
  final Duration? carriedResume;
}

class UnifiedTitlePlayback {
  UnifiedTitlePlayback({
    required this.routeContext,
    required List<UnifiedMediaSource> sources,
    required this.gate,
    SourceEpisodeIndex? index,
    this.secondaryWait = const Duration(seconds: 3),
  }) : sources = List.unmodifiable(sources),
       index = index ?? SourceEpisodeIndex();

  /// The route this play came from, so a nested page keeps the chosen source.
  final UnifiedMediaRouteContext routeContext;

  /// Chosen source first, then the fallback order of hoofdstuk 4.7.
  final List<UnifiedMediaSource> sources;
  final UnifiedSourceGate gate;
  final SourceEpisodeIndex index;
  final Duration secondaryWait;

  String get chosenSourceKey => routeContext.sourceKey;

  /// The same title after the viewer picked another source. The episode lists
  /// stay: they do not depend on the choice.
  UnifiedTitlePlayback withRoute(UnifiedMediaRouteContext route) => UnifiedTitlePlayback(
    routeContext: route,
    sources: route.titleSources.isEmpty ? sources : route.titleSources,
    gate: gate,
    index: index,
    secondaryWait: secondaryWait,
  );

  /// Whether [item] is this title, or a season or episode of it. A related
  /// title, trailer or extra on the same page is not.
  bool holds(MediaItem item) => switch (item.kind) {
    MediaKind.movie || MediaKind.show => sources.any((s) => s.sourceKey == item.globalKey),
    MediaKind.episode => sources.any(
      (s) =>
          s.serverId.value == item.serverId && (seriesIdOf(s) == item.grandparentId || s.sourceKey == item.globalKey),
    ),
    MediaKind.season => sources.any((s) => s.serverId.value == item.serverId && seriesIdOf(s) == item.parentId),
    _ => false,
  };

  /// The route for a page of [item] below this title's own page.
  UnifiedMediaRouteContext? routeFor(MediaItem item) =>
      (item.isSeason || item.isEpisode) && holds(item) ? routeContext : null;

  /// Reads every source's episode list ahead of a play, so a source that goes
  /// away during it can still be addressed by the queue.
  Future<void> prime() async {
    if (sources.any((s) => seriesIdOf(s) != null)) await _episodeLists();
  }

  /// Forgets the episode lists: a play changed their watch state.
  void invalidate() => index.invalidate();

  /// The film a play of the page's [requested] item starts. Answered without a
  /// request, so the play button can draw it. A film stays on the chosen
  /// source: hoofdstuk 15 forbids a silent fallback to another edition.
  UnifiedPlayTarget movieTarget(MediaItem requested) {
    final copies = {
      for (final s in sources)
        if (s.item.isMovie) s.sourceKey: gate.freshen(s.item),
    };
    final chosen = copies[chosenSourceKey];
    if (chosen == null || !copies.containsKey(requested.globalKey)) return UnifiedPlayTarget(requested);
    return UnifiedPlayTarget(chosen, carriedResume: _carried(copies, chosen));
  }

  /// The concrete item a play of [requested] starts: the chosen source's copy,
  /// else the next source that has it (besluit 2, no notice). A source this
  /// profile may not read is not asked, chosen or not.
  Future<UnifiedPlayTarget> targetFor(MediaItem requested) async {
    if (requested.isMovie) return movieTarget(requested);
    final coordinate = episodeCoordinateOf(requested);
    if (coordinate == null || !holds(requested)) return UnifiedPlayTarget(requested);

    final copies = _copiesAt(coordinate, await _episodeLists(requested: requested));
    // The item on the page is a copy too, also when its list did not answer.
    if (_mayPlayFrom(requested)) copies.putIfAbsent(requested.globalKey, () => gate.freshen(requested));
    final target = copies.values.firstOrNull ?? requested;
    return UnifiedPlayTarget(target, carriedResume: _carried(copies, target));
  }

  /// The episode after or before [current]. The queue of the server that plays
  /// decides ([queued] is its answer), unless that server is not the chosen
  /// one or lacks the next coordinate: then the merged order of all sources
  /// does, and a play falls back to the chosen source as soon as it can.
  Future<MediaItem?> neighbourOf(MediaItem current, {required bool forward, MediaItem? queued}) async {
    final coordinate = episodeCoordinateOf(current);
    if (coordinate == null || !holds(current)) return queued;

    final lists = await _episodeLists(requested: current);
    final merged = <EpisodeCoordinate, MediaItem>{};
    for (final list in lists.values) {
      for (final episode in list.all) {
        merged.putIfAbsent(episodeCoordinateOf(episode)!, () => episode);
      }
    }
    if (!merged.containsKey(coordinate)) return queued;

    // A Special only follows a Special: which ones a queue interleaves is the
    // server's own order, and another server's Special is not a gap.
    final inSpecials = isSpecialSeasonNumber(coordinate.season);
    final ordered =
        merged.entries
            .where((e) => e.key == coordinate || inSpecials || !isSpecialSeasonNumber(e.key.season))
            .map((e) => e.value)
            .toList()
          ..sort(compareEpisodesByWatchOrder);
    final at = ordered.indexWhere((e) => episodeCoordinateOf(e) == coordinate);
    final neighbourAt = forward ? at + 1 : at - 1;
    final neighbour = neighbourAt < 0 || neighbourAt >= ordered.length ? null : ordered[neighbourAt];

    final chosen = sources.where((s) => s.sourceKey == chosenSourceKey).firstOrNull;
    final playsChosen = current.serverId == chosen?.serverId.value;
    final chosenList = lists[chosenSourceKey];
    final gap = neighbour != null && chosenList != null && chosenList.at(episodeCoordinateOf(neighbour)!) == null;
    final pick = queued != null && playsChosen && !gap ? queued : neighbour ?? queued;
    if (pick == null) return null;

    final pickAt = episodeCoordinateOf(pick);
    if (pickAt == null) return pick;
    final carried = _carried(_copiesAt(pickAt, lists), pick);
    return carried == null ? pick : pick.copyWith(viewOffsetMs: carried.inMilliseconds);
  }

  /// The episode this series continues at across its sources, given the one
  /// the page's own source reports. A source further along wins: watching on
  /// one server moves the series on all of them. Returns the page's own copy
  /// when it has one, so the page keeps talking about its own source.
  Future<MediaItem?> onDeckAcross(MediaItem? onDeck) async {
    final lists = await _episodeLists();
    if (lists.isEmpty) return onDeck;

    final byCoordinate = <EpisodeCoordinate, Map<String, MediaItem>>{};
    for (final list in lists.values) {
      for (final episode in list.all) {
        (byCoordinate[episodeCoordinateOf(episode)!] ??= {})[episode.globalKey] = gate.freshen(episode);
      }
    }
    final rows = byCoordinate.values.where((copies) => !isSpecialSeasonNumber(copies.values.first.parentIndex)).toList()
      ..sort((a, b) => compareEpisodesByWatchOrder(a.values.first, b.values.first));
    final states = [for (final row in rows) selectRepresentativeWatchState(row)];
    final lastStarted = states.lastIndexWhere((s) => s.hasActiveProgress);
    final lastDone = states.lastIndexWhere((s) => s.isWatched && !s.hasActiveProgress);

    final int acrossAt;
    if (lastStarted > lastDone) {
      acrossAt = lastStarted;
    } else if (lastDone == -1 || lastDone + 1 >= rows.length) {
      return onDeck;
    } else {
      acrossAt = lastDone + 1;
    }
    final across = rows[acrossAt].values.first;
    if (onDeck != null && compareEpisodesByWatchOrder(onDeck, across) >= 0) return onDeck;
    return lists[routeContext.pageSourceKey]?.at(episodeCoordinateOf(across)!) ?? across;
  }

  /// [item] on every other source this profile may write to: the targets of a
  /// watch-state write (besluit 3). Never the item itself.
  Future<List<MediaItem>> copiesOf(MediaItem item) async {
    final targets = sources.where(gate.mayWrite).toList();
    final copies = switch (item.kind) {
      MediaKind.movie || MediaKind.show => [
        for (final s in targets)
          if (s.item.kind == item.kind) s.item,
      ],
      MediaKind.episode => await _episodeCopies(item, targets),
      MediaKind.season => await _seasonCopies(item, targets),
      _ => const <MediaItem>[],
    };
    return [
      for (final copy in copies)
        if (copy.globalKey != item.globalKey) gate.freshen(copy),
    ];
  }

  Future<List<MediaItem>> _episodeCopies(MediaItem item, List<UnifiedMediaSource> targets) async {
    final coordinate = episodeCoordinateOf(item);
    if (coordinate == null) return const [];
    final found = await Future.wait(
      targets.map((source) async {
        final direct = episodeCoordinateOf(source.item) == coordinate ? source.item : null;
        final list = gate.mayRead(source) ? await _read(source) : index.loaded(source);
        return list?.at(coordinate) ?? direct;
      }),
    );
    return found.nonNulls.toList();
  }

  Future<List<MediaItem>> _seasonCopies(MediaItem item, List<UnifiedMediaSource> targets) async {
    final number = item.index;
    if (number == null) return const [];
    final found = await Future.wait(
      targets.where(gate.mayRead).map((source) async {
        final seriesId = seriesIdOf(source);
        if (seriesId == null) return null;
        try {
          final seasons = await gate.clientFor(source.serverId)?.fetchChildren(seriesId);
          final match = seasons?.where((s) => s.isSeason && s.index == number).firstOrNull;
          return match?.copyWith(serverId: source.serverId.value);
        } catch (e) {
          appLogger.d('Seasons of ${source.sourceKey} could not be read', error: e);
          return null;
        }
      }),
    );
    return found.nonNulls.toList();
  }

  Future<SourceEpisodes?> _read(UnifiedMediaSource source) {
    final client = gate.clientFor(source.serverId);
    return client == null ? Future.value(index.loaded(source)) : index.of(source, client);
  }

  Future<bool> _restricted() async {
    try {
      return await gate.isRestrictedProfile();
    } catch (e) {
      appLogger.w('Could not read the profile restriction; treating it as restricted', error: e);
      return true;
    }
  }

  /// The lists a play may use, chosen source first and keyed by source. A
  /// children's profile keeps to the chosen source, the page's source and the
  /// server of [requested]. A source other than the chosen one gets
  /// [secondaryWait]: the play must not stand still on a server it may not
  /// even need. Its list keeps loading for the next read.
  Future<Map<String, SourceEpisodes>> _episodeLists({MediaItem? requested}) async {
    final restricted = await _restricted();
    final allowed = sources.where(gate.mayRead).where((s) {
      if (!restricted) return true;
      return s.sourceKey == chosenSourceKey ||
          s.sourceKey == routeContext.pageSourceKey ||
          s.serverId.value == requested?.serverId;
    }).toList();
    final read = await Future.wait(
      allowed.map((source) {
        final list = _read(source);
        return source.sourceKey == chosenSourceKey
            ? list
            : list.timeout(secondaryWait, onTimeout: () => index.loaded(source));
      }),
    );
    final hidden = gate.hiddenLibraryKeys();
    final lists = <String, SourceEpisodes>{};
    for (var i = 0; i < allowed.length; i++) {
      final list = read[i];
      if (list == null) continue;
      final source = allowed[i];
      final visible = visibleMatchesFromServer(list.all.toList(), source.serverId, hidden);
      lists[source.sourceKey] = visible.length == list.all.length ? list : SourceEpisodes(visible);
    }
    return lists;
  }

  bool _mayPlayFrom(MediaItem item) => sources.where((s) => s.serverId.value == item.serverId).any(gate.mayRead);

  /// The copies at [coordinate] in fallback order, keyed by their own key. The
  /// item of an episode group out of Verder kijken counts when its list did
  /// not answer.
  Map<String, MediaItem> _copiesAt(EpisodeCoordinate coordinate, Map<String, SourceEpisodes> lists) {
    final copies = <String, MediaItem>{};
    for (final source in sources) {
      final direct = episodeCoordinateOf(source.item) == coordinate && gate.mayRead(source) ? source.item : null;
      final copy = lists[source.sourceKey]?.at(coordinate) ?? direct;
      if (copy != null) copies[copy.globalKey] = gate.freshen(copy);
    }
    return copies;
  }

  Duration? _carried(Map<String, MediaItem> copies, MediaItem target) {
    if (copies.length < 2) return null;
    final state = selectRepresentativeWatchState(copies, preferredSourceKey: target.globalKey);
    return resumeCarriedBetween(copies, state, target.globalKey);
  }
}
