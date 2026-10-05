import '../media/ids.dart';
import '../media/media_backend.dart';
import '../models/plex/plex_home_user.dart';
import '../profiles/plex_self_account.dart';
import '../services/jellyfin_client.dart';
import '../services/multi_server_manager.dart';
import 'current_user_context.dart';

/// Names the signed-in person on every connected server, from what the app
/// already knows: the Plex Home profile, the connection's own user id, the
/// linked Trakt account. Nothing is guessed: a source that cannot say stays
/// unknown.
CurrentUserContext currentUserContextFor(
  MultiServerManager manager, {
  required String? profileId,
  required Map<String, List<PlexHomeUser>> plexHome,
  String? traktAccountId,
}) {
  final plexTvAccount = plexSelfAccountIdIn(profileId, plexHome);
  return CurrentUserContext.build([
    for (final id in manager.serverIds)
      if (manager.getClient(ServerId(id)) case final client?)
        switch (client.backend) {
          MediaBackend.plex => AssistantSelfSource(
            serverId: id,
            backend: MediaBackend.plex,
            plexOwner: manager.getPlexServer(ServerId(id))?.owned == true,
            plexTvAccountId: plexTvAccount,
          ),
          MediaBackend.jellyfin => AssistantSelfSource(
            serverId: id,
            backend: MediaBackend.jellyfin,
            userId: client is JellyfinClient ? client.connection.userId : null,
            emby: client is JellyfinClient && client.connection.isEmby,
          ),
          // The id from /users/me is not stored yet, only the role.
          MediaBackend.pleyaServer => AssistantSelfSource(serverId: id, backend: MediaBackend.pleyaServer),
          _ => AssistantSelfSource(serverId: id, backend: client.backend),
        },
  ], traktAccountId: traktAccountId);
}
