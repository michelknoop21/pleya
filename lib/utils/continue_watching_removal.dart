/// What the "take this out of Verder kijken" row says, and how far it reaches
/// (mockup 38 E, DEC-119 fase 3).
///
/// One row per title, and the wording follows what each source can actually
/// do. A source that removes server-side (Plex, Pleya Server) is removed
/// there; a source that cannot (Jellyfin, Emby, local folders) is hidden on
/// this device only. The scope line says which, so "Op alle bronnen" is only
/// ever shown when it is literally true: every source can remove server-side
/// and every one of them is reachable right now.
library;

import '../i18n/strings.g.dart';
import '../media/media_backend.dart';

/// One source of the title, reduced to the two facts the wording needs.
typedef ContinueWatchingRemovalSource = ({String? serverName, bool removesOnServer, bool reachable});

/// [hidesOnly] is true when nothing is removed on any server, so the row is a
/// hide and takes the hide icon.
typedef ContinueWatchingRemovalPresentation = ({String label, String? scope, bool hidesOnly});

ContinueWatchingRemovalPresentation continueWatchingRemovalPresentation(List<ContinueWatchingRemovalSource> sources) {
  final onServer = [
    for (final s in sources)
      if (s.removesOnServer) s,
  ];
  final local = [
    for (final s in sources)
      if (!s.removesOnServer) s,
  ];

  if (onServer.isEmpty) {
    return (label: t.mediaMenu.hideFromContinueWatching, scope: t.mediaMenu.cwScopeThisDevice, hidesOnly: true);
  }
  if (local.isEmpty) {
    // A single source needs no scope: there is nothing to be "all" of. With
    // several, the claim is only made when none of them is waiting in a queue.
    final guaranteed = sources.length > 1 && sources.every((s) => s.reachable);
    return (
      label: t.mediaMenu.removeFromContinueWatching,
      scope: guaranteed ? t.mediaMenu.cwScopeAllSources : null,
      hidesOnly: false,
    );
  }

  String? names(List<ContinueWatchingRemovalSource> list) {
    final values = {for (final s in list) s.serverName};
    if (values.any((n) => n == null || n.isEmpty)) return null;
    return values.join(', ');
  }

  final serverNames = names(onServer);
  final localNames = names(local);
  return (
    label: t.mediaMenu.removeFromContinueWatching,
    scope: serverNames == null || localNames == null
        ? t.mediaMenu.cwScopePartlyLocal
        : t.mediaMenu.cwScopeMixed(server: serverNames, local: localNames),
    hidesOnly: false,
  );
}

/// Whether a source on [backend] removes server-side when no client is bound
/// to say so itself (a cold start, a server that never answered). Plex does;
/// Pleya Server does when it offers watch state, which an unbound client cannot
/// confirm, so it is treated as server-side and its queued write is dropped on
/// replay if the server disagrees. Jellyfin, Emby and local folders do not.
bool backendRemovesFromContinueWatching(MediaBackend backend) => switch (backend) {
  MediaBackend.plex || MediaBackend.pleyaServer => true,
  MediaBackend.jellyfin || MediaBackend.local => false,
};
