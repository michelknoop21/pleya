import '../models/plex/plex_home_user.dart';
import 'plex_home_service.dart';
import 'profile.dart';

/// The plex.tv account id of the signed-in profile.
///
/// This is the id space Tautulli reports in, so it is what decides whether a
/// row is "you": the Plex Media Server numbers the same person differently
/// (owner 1 on an owned server). Null when it cannot be resolved, in which case
/// callers show nobody as themselves rather than guess, which is a cosmetic
/// miss instead of a wrong claim about who is watching.
int? plexSelfAccountId(String? profileId, PlexHomeService homeService) =>
    plexSelfAccountIdIn(profileId, homeService.current);

/// [plexSelfAccountId] against a snapshot of the Home users per connection.
///
/// A Plex Home profile carries the home user's uuid in its own id, which
/// resolves exactly. Anything else (a local profile bound to a Plex account, or
/// no profile picker in use at all) is signed in as the account itself, and the
/// account is the admin entry in its own Home list. Without that fallback the
/// signed-in admin was never recognised outside Plex Home, so their own stream
/// showed up as somebody else watching.
///
/// The fallback only speaks with a single Plex account connected. With two
/// there is nothing to say which one the caller means, and naming the wrong
/// person as "you" would hide a stream that is genuinely news.
int? plexSelfAccountIdIn(String? profileId, Map<String, List<PlexHomeUser>> homeUsers) {
  final parsed = profileId == null ? null : parsePlexHomeProfileId(profileId);
  if (parsed != null) {
    final users = homeUsers[parsed.accountConnectionId];
    return users?.where((u) => u.uuid == parsed.homeUserUuid).firstOrNull?.id;
  }

  final accounts = homeUsers.values.toList();
  if (accounts.length != 1) return null;
  return accounts.single.where((u) => u.admin).firstOrNull?.id;
}
