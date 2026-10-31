/// Finds the other sources of a title when the play did not bring them along:
/// a Verder kijken row that only held one source, a library row, a playlist
/// (besluit 3 of DEC-XXX "Eén titel over servers heen").
///
/// A write needs proof, so a same-named title is not a source here: a server
/// only counts with the same guid or a shared provider number. That is stricter
/// than the picker, which also offers a title match for the viewer to judge.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../media/ids.dart';
import '../../media/media_identity.dart';
import '../../media/media_item.dart';
import '../../media/media_item_types.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/canonical_media_identity.dart';
import '../../media/unified/source_coverage_state.dart';
import '../../media/unified/unified_media_source.dart';
import '../../media/unified/unified_route_context.dart';
import '../../providers/hidden_libraries_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../utils/app_logger.dart';
import '../../utils/external_ids.dart';
import 'source_resolver.dart';
import 'unified_title_playback.dart';
import 'unified_title_scope.dart';

class UnifiedTitleDiscovery {
  UnifiedTitleDiscovery({
    required this.findSources,
    required this.gate,
    this.timeout = const Duration(seconds: 20),
    this.serverWait = const Duration(seconds: 8),
  });

  /// Every title that claims to be [MediaIdentity] on the other servers, each
  /// stamped with the server that answered.
  final Future<List<MediaItem>> Function(MediaIdentity identity, ServerId except) findSources;
  final UnifiedSourceGate gate;
  final Duration timeout;
  final Duration serverWait;

  /// Null for a single-server viewer, who never pays for this, or when no server
  /// can answer. The playing server can be the one that is down, so a second
  /// reachable server is not required here. [serverWait] is what one
  /// server gets: a slow one must not cost the others their write.
  static UnifiedTitleDiscovery? of(BuildContext context, {Duration serverWait = const Duration(seconds: 8)}) {
    final multiServer = context.read<MultiServerProvider?>();
    final gate = unifiedSourceGateOf(context);
    if (multiServer == null || gate == null) return null;
    final manager = multiServer.serverManager;
    final hiddenLibraries = context.read<HiddenLibrariesProvider?>();
    final servers = eligibleSourceServers(
      expectedServerIds: multiServer.expectedServerIds,
      visibleServerIds: multiServer.serverIds,
      clientFor: manager.getClient,
      isOnline: manager.isServerOnline,
      authErrorServerIds: manager.authErrorServerIds,
    ).where((s) => isIdentityEligibleBackend(s.backend) && s.online && !s.hasAuthError && s.client != null).toList();
    if (multiServer.expectedServerIds.length < 2 || servers.isEmpty) return null;

    Future<List<MediaItem>> ask(EligibleSourceServer server, MediaIdentity identity) async {
      final found = <MediaItem>[];
      await fanOutFindAllByIdentity(
        servers: [(serverId: server.serverId, client: server.client, online: server.online)],
        identity: identity,
        maxConcurrent: 1,
        onBatch: (batch) {
          for (final answer in batch) {
            final hidden = hiddenLibraries?.hiddenLibraryKeys ?? const <String>{};
            final visible = visibleMatchesFromServer(answer.matches, answer.serverId, hidden);
            found.addAll(visible.map((m) => m.copyWith(serverId: answer.serverId.value)));
          }
          return false;
        },
      ).timeout(serverWait, onTimeout: () {});
      return found;
    }

    return UnifiedTitleDiscovery(
      gate: gate,
      serverWait: serverWait,
      findSources: (identity, except) async {
        final answers = await Future.wait([
          for (final server in servers)
            if (server.serverId != except) ask(server, identity),
        ]);
        return [for (final answer in answers) ...answer];
      },
    );
  }

  /// The title [item] belongs to across servers, with [item]'s source as the
  /// chosen one. Null when no other server proves it has it, or does not answer
  /// in time. Never throws: this runs behind a mark or a play that already
  /// landed.
  Future<UnifiedTitlePlayback?> titleOf(MediaItem item) async {
    try {
      return await _find(item).timeout(timeout, onTimeout: () => null);
    } catch (e, st) {
      appLogger.d('Could not look up the other sources of ${item.globalKey}', error: e, stackTrace: st);
      return null;
    }
  }

  Future<UnifiedTitlePlayback?> _find(MediaItem item) async {
    // A children's profile writes to the sources it already sees.
    if (await gate.isRestrictedProfile()) return null;
    final serverId = serverIdOrNull(item.serverId);
    final title = _titleFacts(item);
    final client = serverId == null ? null : gate.clientFor(serverId);
    if (serverId == null || title == null || client == null) return null;

    final ids = await _idsOf(client, title.id);
    if ((title.guid ?? '').isEmpty && !ids.hasAny) return null;
    final identity = MediaIdentity(
      guid: title.guid,
      externalIds: ids,
      title: title.name,
      year: item.isMovie ? item.year : null,
      kind: title.kind,
    );

    final found = await findSources(identity, serverId);
    // Side by side: one after the other, a few slow servers use up [timeout]
    // and the fast ones lose their write with them.
    final candidates = await Future.wait([
      for (final match in found)
        if (serverIdOrNull(match.serverId) case final answering? when gate.clientFor(answering) != null)
          _idsOf(
            gate.clientFor(answering)!,
            match.id,
          ).then((ids) => (server: answering.value, candidate: MediaIdentity.candidate(match, ids))),
    ]);
    final byServer = <String, List<({MediaItem item, ExternalIds ids})>>{};
    for (final (:server, :candidate) in candidates) {
      (byServer[server] ??= []).add(candidate);
    }
    // Per server: a guid match on one must not end the search by number on the
    // next, and one film can hold a guid on Plex and a number on Pleya Server.
    final proven = [
      for (final candidates in byServer.values) ...identity.pickAllMatches(candidates, allowTitleFallback: false),
    ];
    if (proven.isEmpty) return null;

    final own = UnifiedMediaSource.fromItem(item);
    final sources = [own, ...proven.map(UnifiedMediaSource.fromItem)];
    final canonical = canonicalIdentityOf(item);
    if (canonical == null) return null;
    return UnifiedTitlePlayback(
      routeContext: UnifiedMediaRouteContext(
        groupId: 'found:${item.globalKey}',
        identity: canonical,
        sourceKey: own.sourceKey,
        titleSources: sources,
        availableSourceKeys: [for (final s in sources) s.sourceKey],
        coverage: SourceCoverageState.none,
        intent: UnifiedActivationIntent.play,
      ),
      sources: sources,
      gate: gate,
    );
  }

  /// A server that does not answer proves nothing, which is not a reason to
  /// give up on the others: a guid can still carry the lookup.
  Future<ExternalIds> _idsOf(MediaServerClient client, String id) async {
    try {
      return await client.fetchExternalIds(id).timeout(serverWait);
    } catch (e) {
      appLogger.d('No provider numbers for $id', error: e);
      return const ExternalIds();
    }
  }

  /// The film or series [item] is, or belongs to.
  static ({String id, String? guid, String? name, MediaKind kind})? _titleFacts(MediaItem item) {
    return switch (item.kind) {
      MediaKind.movie => (id: item.id, guid: item.guid, name: item.title, kind: MediaKind.movie),
      MediaKind.show => (id: item.id, guid: item.guid, name: item.title, kind: MediaKind.show),
      MediaKind.season when item.parentId != null => (
        id: item.parentId!,
        guid: null,
        name: item.parentTitle,
        kind: MediaKind.show,
      ),
      MediaKind.episode when item.grandparentId != null => (
        id: item.grandparentId!,
        guid: item.grandparentGuid,
        name: item.grandparentTitle,
        kind: MediaKind.show,
      ),
      _ => null,
    };
  }
}
