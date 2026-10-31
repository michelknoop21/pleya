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
  UnifiedTitleDiscovery({required this.findSources, required this.gate, this.timeout = const Duration(seconds: 20)});

  /// Every title that claims to be [MediaIdentity] on the other servers, each
  /// stamped with the server that answered.
  final Future<List<MediaItem>> Function(MediaIdentity identity, ServerId except) findSources;
  final UnifiedSourceGate gate;
  final Duration timeout;

  /// Null with fewer than two servers to ask: then there is nothing to find,
  /// and a single-server viewer never pays for this.
  static UnifiedTitleDiscovery? of(BuildContext context) {
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
    if (servers.length < 2) return null;

    return UnifiedTitleDiscovery(
      gate: gate,
      findSources: (identity, except) async {
        final found = <MediaItem>[];
        await fanOutFindAllByIdentity(
          servers: [
            for (final s in servers)
              if (s.serverId != except) (serverId: s.serverId, client: s.client, online: s.online),
          ],
          identity: identity,
          maxConcurrent: 4,
          onBatch: (batch) {
            for (final answer in batch) {
              final visible = visibleMatchesFromServer(
                answer.matches,
                answer.serverId,
                hiddenLibraries?.hiddenLibraryKeys ?? const {},
              );
              found.addAll(visible.map((m) => m.copyWith(serverId: answer.serverId.value)));
            }
            return false;
          },
        );
        return found;
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
    final serverId = serverIdOrNull(item.serverId);
    final title = _titleFacts(item);
    final client = serverId == null ? null : gate.clientFor(serverId);
    if (serverId == null || title == null || client == null) return null;

    final ids = await client.fetchExternalIds(title.id);
    if ((title.guid ?? '').isEmpty && !ids.hasAny) return null;
    final identity = MediaIdentity(
      guid: title.guid,
      externalIds: ids,
      title: title.name,
      year: item.isMovie ? item.year : null,
      kind: title.kind,
    );

    final found = await findSources(identity, serverId);
    final candidates = <({MediaItem item, ExternalIds ids})>[];
    for (final match in found) {
      final answering = serverIdOrNull(match.serverId);
      final other = answering == null ? null : gate.clientFor(answering);
      if (other == null) continue;
      try {
        candidates.add(MediaIdentity.candidate(match, await other.fetchExternalIds(match.id)));
      } catch (e) {
        appLogger.d('Could not prove ${match.globalKey}', error: e);
      }
    }
    final proven = identity.pickAllMatches(candidates, allowTitleFallback: false);
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
