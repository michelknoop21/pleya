/// The plex.tv identity of whoever is using the app right now.
///
/// [isUserScoped] is the field that matters. `UserProfileProvider` has a
/// documented fallback to the account owner's token when the Home-user binder
/// has not finished, and for account-scoped data that fallback quietly shows
/// one family member the state of another. Callers that cannot live with that
/// check this flag and refuse.
typedef PlexAccountAuth = ({String token, String profileId, String accountId, String userId, bool isUserScoped});

/// Resolves the plex.tv auth for the profile that is active right now.
///
/// A function rather than a stored value, because the answer changes when the
/// user switches profile and anything that cached it would keep serving the
/// previous user's data.
typedef PlexAccountAuthResolver = Future<PlexAccountAuth?> Function();
