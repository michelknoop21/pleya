import 'package:flutter/foundation.dart';

/// Where an account id comes from. The same person has a different id in each.
enum AssistantAccountProvider { plexTv, plexServer, jellyfin, emby, pleyaServer, trakt }

/// One account on one source: provider, server and the id that source uses.
/// Names are display only; two accounts that share a name are two keys.
@immutable
class AssistantAccountKey {
  const AssistantAccountKey(this.provider, this.accountId, {this.serverId});

  final AssistantAccountProvider provider;

  /// The server this id is valid on. Null for plex.tv and Trakt, whose ids
  /// are global to the service.
  final String? serverId;
  final String accountId;

  @override
  bool operator ==(Object other) =>
      other is AssistantAccountKey &&
      other.provider == provider &&
      other.serverId == serverId &&
      other.accountId == accountId;

  @override
  int get hashCode => Object.hash(provider, serverId, accountId);

  @override
  String toString() => '${provider.name}|${serverId ?? ''}|$accountId';
}
