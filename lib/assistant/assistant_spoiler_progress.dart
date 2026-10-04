import 'dart:convert';

import '../media/ids.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../services/jellyfin_client.dart';
import 'assistant_spoiler_context.dart';

/// A narrowly supported persisted boundary. Every visible source must supply
/// complete current-user resume coverage; an unsupported/offline source closes
/// discovery rather than silently dropping a possible competing position.
Future<AssistantSpoilerResumeEvidence?> discoverAssistantSpoilerProgress({
  required String profileId,
  required bool Function() profileCurrent,
  required List<ServerId> Function() visibleServers,
  required MediaServerClient? Function(ServerId) clientFor,
  required bool Function(String, String) libraryVisible,
  required bool Function() cancelled,
}) async {
  final servers = visibleServers().toSet();
  if (servers.isEmpty || servers.length > 8) return null;
  final clients = <ServerId, JellyfinClient>{};
  final connections = <ServerId, Object>{};
  final roots = <ServerId, Set<String>>{};
  final visibility = <ServerId, Map<String, bool>>{};
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  bool live() =>
      !cancelled() &&
      profileCurrent() &&
      visibleServers().toSet().length == servers.length &&
      visibleServers().toSet().containsAll(servers) &&
      clients.entries.every(
        (entry) =>
            identical(clientFor(entry.key), entry.value) && identical(entry.value.connection, connections[entry.key]),
      ) &&
      visibility.entries.every(
        (entry) => entry.value.entries.every((root) => libraryVisible(entry.key.value, root.key) == root.value),
      );
  void check() {
    if (!live() || DateTime.now().isAfter(deadline)) throw StateError('spoiler_position_changed');
  }

  for (final id in servers) {
    final client = clientFor(id);
    if (client is! JellyfinClient || client.isOfflineMode || client.connection.isEmby) return null;
    clients[id] = client;
    connections[id] = client.connection;
  }
  if (!live()) return null;
  Future<({List<MediaItem> items, String fingerprint})?> read() async {
    final items = <MediaItem>[];
    final scope = <Object>[];
    for (final entry in clients.entries) {
      check();
      final libraries = await entry.value.fetchLibraries().timeout(deadline.difference(DateTime.now()));
      check();
      if (libraries.length > 12 || libraries.map((l) => l.id).toSet().length != libraries.length) return null;
      final states = {for (final library in libraries) library.id: libraryVisible(entry.key.value, library.id)};
      if (visibility.containsKey(entry.key) && jsonEncode(visibility[entry.key]) != jsonEncode(states)) return null;
      visibility[entry.key] = states;
      final visible = libraries.where((l) => states[l.id]!).toList();
      final ids = visible.map((l) => l.id).toSet();
      if (roots.containsKey(entry.key) &&
          (roots[entry.key]!.length != ids.length || !roots[entry.key]!.containsAll(ids))) {
        return null;
      }
      roots[entry.key] = ids;
      final evidence = await entry.value
          .readCurrentUserResumePositions(visibleLibraries: visible, checkCurrent: check)
          .timeout(deadline.difference(DateTime.now()));
      check();
      if (evidence == null) return null;
      items.addAll(evidence);
      scope.add([entry.key.value, (ids.toList()..sort())]);
    }
    // Includes partial movies/unknown kinds; these cannot be silently dropped
    // while claiming an episode is the sole current position.
    final fingerprint = jsonEncode([
      scope,
      for (final item in items)
        [
          item.serverId,
          item.libraryId,
          item.id,
          item.kind.name,
          item.grandparentId,
          item.parentIndex,
          item.index,
          item.viewOffsetMs,
          item.durationMs,
        ],
    ]);
    return (items: items, fingerprint: fingerprint);
  }

  try {
    final proof = await read();
    if (proof == null || proof.items.length != 1 || !live()) return null;
    final item = proof.items.single;
    if (item.kind != MediaKind.episode ||
        item.serverId == null ||
        item.libraryId == null ||
        item.grandparentId == null ||
        item.parentIndex == null ||
        item.index == null ||
        item.viewOffsetMs == null ||
        item.viewOffsetMs! <= 0 ||
        item.durationMs == null) {
      return null;
    }
    final boundary = AssistantWatchBoundary(
      profileId: profileId,
      serverId: item.serverId!,
      libraryId: item.libraryId!,
      showId: item.grandparentId!,
      episodeId: item.id,
      season: item.parentIndex!,
      episode: item.index!,
      positionMs: item.viewOffsetMs!,
      durationMs: item.durationMs!,
      sessionId: 'resume:$profileId',
      revision: proof.fingerprint,
    );
    if (!boundary.known) return null;
    var valid = true;
    return AssistantSpoilerResumeEvidence(
      boundary: boundary,
      current: () => valid && live(),
      refresh: () async {
        if (!valid || !live()) return false;
        try {
          final fresh = await read();
          return valid = fresh != null && fresh.fingerprint == proof.fingerprint && live();
        } catch (_) {
          return valid = false;
        }
      },
    );
  } catch (_) {
    return null;
  }
}
