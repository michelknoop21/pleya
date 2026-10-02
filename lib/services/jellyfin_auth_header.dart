import '../connection/connection.dart';

/// Build the `MediaBrowser` Authorization header value the way the Jellyfin
/// SDK formats it. Used at auth time and on every authenticated request so
/// the server sees a consistent client identity.
String buildJellyfinAuthHeader({
  required String clientName,
  required String clientVersion,
  required String deviceName,
  required String deviceId,
  String? accessToken,
}) {
  final parts = <String>[
    'Client="$clientName"',
    'Device="$deviceName"',
    'DeviceId="$deviceId"',
    'Version="$clientVersion"',
    if (accessToken != null && accessToken.isNotEmpty) 'Token="$accessToken"',
  ];
  return 'MediaBrowser ${parts.join(', ')}';
}

/// The auth header map for [value]. Emby reads `X-Emby-Authorization` first,
/// so an Emby server gets the same value under both names.
Map<String, String> jellyfinAuthHeaders(String value, {required bool isEmby}) => {
  'Authorization': value,
  if (isEmby) 'X-Emby-Authorization': value,
};

String _segment(String value) => Uri.encodeComponent(value);

/// The per-user routes where Jellyfin 10.9+ and Emby part ways. Jellyfin moved
/// them to `/UserItems` and friends; Emby still only serves `/Users/{id}/...`.
extension JellyfinUserRoutes on JellyfinConnection {
  String get _user => '/Users/${_segment(userId)}';

  String get currentUserPath => isEmby ? _user : '/Users/Me';

  String get resumeItemsPath => isEmby ? '$_user/Items/Resume' : '/UserItems/Resume';

  String playedItemPath(String itemId) =>
      isEmby ? '$_user/PlayedItems/${_segment(itemId)}' : '/UserPlayedItems/${_segment(itemId)}';

  String ratingPath(String itemId) =>
      isEmby ? '$_user/Items/${_segment(itemId)}/Rating' : '/UserItems/${_segment(itemId)}/Rating';

  /// `LocalTrailers` / `SpecialFeatures`: Jellyfin serves them under `/Items`,
  /// Emby only under the user.
  String itemExtrasPath(String itemId, String kind) =>
      isEmby ? '$_user/Items/${_segment(itemId)}/$kind' : '/Items/${_segment(itemId)}/$kind';

  /// Emby answers `/Sessions/Playing` and `/Progress` without a
  /// `PlaySessionId` with a 400 ("Value cannot be null. (Parameter 'key')").
  /// External-player and offline-sync reports carry none, so Emby gets a
  /// stable id per device and item; Jellyfin keeps the field optional.
  String? playSessionIdFor(String itemId, String? negotiated) =>
      negotiated ?? (isEmby ? 'pleya-$deviceId-$itemId' : null);
}
