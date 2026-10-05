import '../media/media_backend.dart';
import 'assistant_account_key.dart';

/// Why "me" cannot be named on a source. Unknown is not "everyone" and not
/// "nobody": the caller asks, or answers for what is known and says what was
/// left out.
enum AssistantSelfUnknown { notOwner, noPlexAccount, notStored, notLinked }

/// "Me" on one source: a key, or the reason there is none.
class AssistantSelf {
  const AssistantSelf.known(AssistantAccountKey this.key) : unknown = null;
  const AssistantSelf.unknown(AssistantSelfUnknown this.unknown) : key = null;

  final AssistantAccountKey? key;
  final AssistantSelfUnknown? unknown;
  bool get isKnown => key != null;
}

/// What the context needs to know about one connected server to name the
/// signed-in person on it.
class AssistantSelfSource {
  const AssistantSelfSource({
    required this.serverId,
    required this.backend,
    this.plexOwner = false,
    this.plexTvAccountId,
    this.userId,
    this.emby = false,
  });

  final String serverId;
  final MediaBackend backend;

  /// Plex: the signed-in account owns the server.
  final bool plexOwner;

  /// Plex: the plex.tv account id of the active profile (Tautulli's id space),
  /// null when it cannot be resolved.
  final int? plexTvAccountId;

  /// Jellyfin, Emby, Pleya Server: the account id on that server, when stored.
  final String? userId;

  /// A Jellyfin-protocol server that is Emby.
  final bool emby;
}

/// Who "I" am on every source, built once per question. Replaces the display
/// name as the only notion of the user.
class CurrentUserContext {
  const CurrentUserContext._(this._byServer, this.trakt);

  final Map<String, Map<AssistantAccountProvider, AssistantSelf>> _byServer;

  /// The linked Trakt account, null when none is linked.
  final AssistantSelf trakt;

  static const empty = CurrentUserContext._({}, AssistantSelf.unknown(AssistantSelfUnknown.notLinked));

  factory CurrentUserContext.build(Iterable<AssistantSelfSource> sources, {String? traktAccountId}) {
    final byServer = <String, Map<AssistantAccountProvider, AssistantSelf>>{};
    for (final s in sources) {
      byServer[s.serverId] = switch (s.backend) {
        MediaBackend.plex => {
          // Tautulli reports plex.tv ids; the server's own history numbers the
          // owner 1 and nobody else is known without a fixture proving it.
          AssistantAccountProvider.plexTv: s.plexTvAccountId == null
              ? const AssistantSelf.unknown(AssistantSelfUnknown.noPlexAccount)
              : AssistantSelf.known(AssistantAccountKey(AssistantAccountProvider.plexTv, '${s.plexTvAccountId}')),
          AssistantAccountProvider.plexServer: s.plexOwner
              ? AssistantSelf.known(AssistantAccountKey(AssistantAccountProvider.plexServer, '1', serverId: s.serverId))
              : const AssistantSelf.unknown(AssistantSelfUnknown.notOwner),
        },
        // Emby is a Jellyfin variant (DEC-141) with its own provider.
        MediaBackend.jellyfin => {
          (s.emby ? AssistantAccountProvider.emby : AssistantAccountProvider.jellyfin): _byUserId(
            s.emby ? AssistantAccountProvider.emby : AssistantAccountProvider.jellyfin,
            s,
          ),
        },
        MediaBackend.pleyaServer => {
          AssistantAccountProvider.pleyaServer: _byUserId(AssistantAccountProvider.pleyaServer, s),
        },
        _ => const {},
      };
    }
    return CurrentUserContext._(
      byServer,
      traktAccountId == null || traktAccountId.isEmpty
          ? const AssistantSelf.unknown(AssistantSelfUnknown.notLinked)
          : AssistantSelf.known(AssistantAccountKey(AssistantAccountProvider.trakt, traktAccountId)),
    );
  }

  static AssistantSelf _byUserId(AssistantAccountProvider provider, AssistantSelfSource s) {
    final id = s.userId;
    return id == null || id.isEmpty
        ? const AssistantSelf.unknown(AssistantSelfUnknown.notStored)
        : AssistantSelf.known(AssistantAccountKey(provider, id, serverId: s.serverId));
  }

  /// "Me" on [serverId] in the id space of [provider]; unknown when the
  /// source is not connected.
  AssistantSelf on(String serverId, AssistantAccountProvider provider) =>
      _byServer[serverId]?[provider] ?? const AssistantSelf.unknown(AssistantSelfUnknown.notLinked);

  /// Whether [key] is the signed-in person. Only a known self can match: an
  /// unknown self is never "everyone else's complement".
  bool isSelf(AssistantAccountKey key) =>
      _byServer.values.any((m) => m.values.any((s) => s.key == key)) || trakt.key == key;

  /// Whether "me" is known in the id space [key] lives in, so that "not me"
  /// is a statement and not a guess. plex.tv ids are global to the service;
  /// everything else is per server.
  bool canTell(AssistantAccountKey key) => switch (key.provider) {
    AssistantAccountProvider.trakt => trakt.isKnown,
    AssistantAccountProvider.plexTv => _byServer.values.any(
      (m) => m[AssistantAccountProvider.plexTv]?.isKnown ?? false,
    ),
    _ => key.serverId != null && (_byServer[key.serverId]?[key.provider]?.isKnown ?? false),
  };

  /// Servers on which "me" is unknown for [provider], for the "left out" note.
  List<String> unknownOn(AssistantAccountProvider provider) => [
    for (final e in _byServer.entries)
      if (e.value.containsKey(provider) && !e.value[provider]!.isKnown) e.key,
  ];
}
