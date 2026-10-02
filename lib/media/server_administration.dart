/// Optional server-administration capabilities of a [MediaServerClient].
///
/// Same pattern as `PersonSearchClient`: a client implements the interfaces
/// its backend really supports, and callers test with `is`. Nothing here is on
/// [MediaServerClient] itself, which is already too broad (architecture §5.3).
///
/// Every method is a server mutation or an admin read and asserts
/// `ServerAuthorityGuard.assertCanAdministerServer` before it touches the
/// network. Library ids are always the app's own `MediaLibrary.id`; a backend
/// that keys access on another id (Emby's folder Guid, plex.tv's section id)
/// translates inside its implementation.
library;

import 'media_server_client.dart';

/// One path segment built from an id the caller supplied. Encodes `/`, and
/// refuses the empty, `.` and `..` ids that `Uri` would otherwise normalise
/// into a different route (`/activities/../library/metadata/1` is a media
/// delete). Every admin implementation builds its paths through this.
String adminPathSegment(String id) {
  if (id.isEmpty || id == '.' || id == '..') throw ArgumentError.value(id, 'id', 'not a valid id');
  return Uri.encodeComponent(id);
}

/// Base of every interface below.
abstract interface class ServerAdministrationClient {
  /// Whether this server exposes administration right now. Plex and
  /// Jellyfin always do; a Pleya Server only when it advertises the
  /// `administration` capability.
  bool get supportsServerAdministration;
}

/// Look for new, changed and removed files in one library.
abstract interface class LibraryScanClient implements ServerAdministrationClient {
  Future<void> scanLibrary(String libraryId);
}

/// Re-read metadata for one item (a film, a series) from its providers.
abstract interface class ItemMetadataRefreshClient implements ServerAdministrationClient {
  Future<void> refreshItemMetadata(String itemId);
}

enum ServerJobState { queued, running, succeeded, failed, cancelled, unknown }

/// A background job on the server: a scan, a scheduled task, a Plex activity.
class ServerJob {
  const ServerJob({
    required this.id,
    required this.title,
    required this.state,
    this.progress,
    this.libraryId,
    this.error,
    this.updatedAt,
    this.cancellable = false,
    this.retryable = false,
  });

  final String id;
  final String title;
  final ServerJobState state;

  /// 0.0 to 1.0 when the server reports it.
  final double? progress;
  final String? libraryId;
  final String? error;
  final DateTime? updatedAt;
  final bool cancellable;
  final bool retryable;
}

abstract interface class ServerJobsClient implements ServerAdministrationClient {
  Future<List<ServerJob>> listJobs();
  Future<void> cancelJob(String jobId);
}

/// Jobs that can be started again: a failed Pleya Server job, a Jellyfin
/// scheduled task.
abstract interface class RetryableJobsClient implements ServerJobsClient {
  Future<void> retryJob(String jobId);
}

enum ServerUserRole { owner, admin, member, restricted, unknown }

/// An account on the server itself (Jellyfin, Emby, Pleya Server).
class ServerUser {
  const ServerUser({
    required this.id,
    required this.name,
    required this.role,
    required this.allLibraries,
    this.libraryIds = const [],
    this.disabled = false,
    this.libraryAccessKnown = true,
  });

  final String id;
  final String name;
  final ServerUserRole role;
  final bool disabled;

  /// False when the server does not say which libraries this user sees
  /// (Pleya Server has no read route for a member's grants). [allLibraries]
  /// and [libraryIds] then mean nothing and must not be shown as "no access".
  final bool libraryAccessKnown;

  /// True when the user sees every library. On Jellyfin and Emby that
  /// includes libraries added later; Pleya Server owners and admins see
  /// everything by role.
  final bool allLibraries;

  /// The libraries the user may see when [allLibraries] is false.
  final List<String> libraryIds;
}

/// Accounts that live on the server: Jellyfin, Emby, Pleya Server. Plex has
/// no such thing; see [PlexSharingAdministration].
abstract interface class ServerUserAdministration implements ServerAdministrationClient {
  Future<List<ServerUser>> listUsers();

  /// Whether [createUser] needs a password (Pleya Server does).
  bool get createUserRequiresPassword;

  /// Whether [setUserLibraryAccess] can change an existing user. False where
  /// the server cannot report a user's current grants (Pleya Server): a
  /// replace there would silently drop levels nobody asked to change.
  bool get canChangeLibraryAccess;

  /// Creates a regular, non-admin user (never a role above member) with this
  /// initial library access. A new user has no grants yet, so setting them
  /// here changes nothing that was there before.
  ///
  /// Throws [ServerUserAccessNotGranted] when the user exists but the access
  /// could not be set; any other failure means no user was left behind.
  Future<ServerUser> createUser({
    required String name,
    String? password,
    bool allLibraries = false,
    List<String> libraryIds = const [],
  });

  /// Replaces the user's whole library access with exactly this. An empty
  /// [libraryIds] with [allLibraries] false means no libraries. Refuses
  /// before the network when [canChangeLibraryAccess] is false.
  Future<void> setUserLibraryAccess(String userId, {required bool allLibraries, List<String> libraryIds = const []});

  Future<void> deleteUser(String userId);
}

/// [ServerUserAdministration.createUser] made the user, then failed to set
/// its library access. The user exists without the requested access.
class ServerUserAccessNotGranted implements Exception {
  const ServerUserAccessNotGranted(this.user, this.cause);
  final ServerUser user;
  final Object cause;

  @override
  String toString() => 'ServerUserAccessNotGranted(${user.id}: $cause)';
}

/// Someone who reaches an owned Plex server: a Plex Home member or a friend,
/// each through a server share on plex.tv.
class PlexShare {
  const PlexShare({
    required this.userId,
    required this.name,
    required this.homeMember,
    required this.managed,
    required this.allLibraries,
    this.libraryIds = const [],
    this.shared = true,
  });

  /// plex.tv user id.
  final String userId;
  final String name;
  final bool homeMember;

  /// A managed Home user: no plex.tv login of its own.
  final bool managed;

  /// False for a Home member without a share on this server yet.
  final bool shared;
  final bool allLibraries;

  /// PMS library section keys (the app's `MediaLibrary.id`).
  final List<String> libraryIds;
}

/// Plex user administration as Plex models it: Home membership plus server
/// shares, both on plex.tv rather than on the server.
///
/// The plex.tv sharing API is not officially documented. Implementations run
/// only with the Home admin's account token, never a `/switch` user token,
/// and fail closed on any response they do not recognise.
abstract interface class PlexSharingAdministration implements ServerAdministrationClient {
  Future<List<PlexShare>> listShares();

  /// Adds a managed Home user (no login of its own) and returns its plex.tv
  /// user id. The user sees nothing until [setShareLibraries].
  Future<String> createManagedHomeUser(String name);

  /// Creates or replaces the share for [userId] on this server. An empty
  /// list without [allLibraries] removes the share. [allLibraries] shares
  /// every library that exists now, not ones added later.
  Future<void> setShareLibraries(String userId, {required bool allLibraries, List<String> libraryIds = const []});

  Future<void> removeShare(String userId);

  Future<void> removeHomeUser(String userId);
}
