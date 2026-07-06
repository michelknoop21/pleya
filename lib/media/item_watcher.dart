/// A single server user who has watched a given media item, resolved from
/// Plex's server-wide watch history (`/status/sessions/history/all`) joined
/// with the account roster (`/accounts`). Owner-token only, Plex-only.
class ItemWatcher {
  /// Plex `accountID` (1 == server owner).
  final int accountId;
  final String displayName;

  /// Absolute avatar URL (plex.tv), or null → initials fallback.
  final String? thumbUrl;

  /// Last-viewed epoch seconds; used to order most-recent-first.
  final int viewedAt;

  const ItemWatcher({
    required this.accountId,
    required this.displayName,
    this.thumbUrl,
    required this.viewedAt,
  });
}
