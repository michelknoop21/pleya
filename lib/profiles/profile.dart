import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../models/plex/plex_home_user.dart';

part 'profile.freezed.dart';

/// Top-level profile — the user-facing identity in the app.
///
/// Three kinds:
/// - [LocalProfile]: a Plezy-only profile created by the user. May have
///   an optional 4-digit PIN.
/// - [PlexHomeProfile]: auto-surfaced from a connected Plex account's
///   Home users. PIN protection is handled server-side by Plex via the
///   `/home/users/{uuid}/switch` flow — `pinHash` is unused.
/// - [PleyaServerProfile]: one account on one Pleya Server. Added in PS-9,
///   because a Pleya Server sign-in used to produce a [LocalProfile] and that
///   made two different things look the same: a local profile is a label the
///   app puts on a device, while this one *is* a server-side identity with a
///   role and its own library permissions. Resolving credentials for it must
///   never end at somebody else's token; see [PleyaServerCredentialResolver].
///
/// A profile owns 1+ connections via the `profile_connections` join table.
/// The join row carries the per-profile user-level token used to talk to
/// each connection.
@freezed
sealed class Profile with _$Profile {
  const Profile._();

  const factory Profile.local({
    required String id,
    required String displayName,
    String? avatarThumbUrl,

    /// Hashed PIN if set. The raw PIN is never persisted; see [computePinHash].
    String? pinHash,
    @Default(0) int sortOrder,
    required DateTime createdAt,
    DateTime? lastUsedAt,
  }) = LocalProfile;

  const factory Profile.plexHome({
    required String id,
    required String displayName,
    String? avatarThumbUrl,

    /// The parent Plex account's connection id.
    String? parentConnectionId,

    /// The Plex Home user UUID. Used by the active-profile binder to call
    /// `/home/users/{uuid}/switch`.
    String? plexHomeUserUuid,
    @Default(false) bool plexRestricted,
    @Default(false) bool plexAdmin,

    /// Plex's `protected` flag — true when the home user has a PIN that must
    /// be entered before `/home/users/{uuid}/switch` will succeed.
    @Default(false) bool plexProtected,
    @Default(0) int sortOrder,
    required DateTime createdAt,
    DateTime? lastUsedAt,
  }) = PlexHomeProfile;

  const factory Profile.pleyaServer({
    required String id,
    required String displayName,
    String? avatarThumbUrl,

    /// The Pleya Server connection this profile is the identity of. One
    /// connection carries exactly one account's refresh token, which is what
    /// makes the credential resolution unambiguous.
    String? pleyaConnectionId,

    /// The username this profile signs in with on that server. The account's
    /// server-side id is deliberately not stored: it lives inside the access
    /// token, and the protocol says a client never has to read that (chapter
    /// 6.3). The username is what the person typed and what the connection
    /// row already carries.
    String? pleyaUsername,
    @Default(0) int sortOrder,
    required DateTime createdAt,
    DateTime? lastUsedAt,
  }) = PleyaServerProfile;

  /// Construct an in-memory virtual `Profile` for a Plex Home user. These
  /// are never persisted — Plex owns the Home user list, so the picker
  /// reads them live from [PlexHomeService] and merges them with the local
  /// rows from `ProfileRegistry`.
  factory Profile.virtualPlexHome({
    required String connectionId,
    required PlexHomeUser homeUser,
    DateTime? lastUsedAt,
  }) => Profile.plexHome(
    id: plexHomeProfileId(accountConnectionId: connectionId, homeUserUuid: homeUser.uuid),
    displayName: homeUser.displayName,
    avatarThumbUrl: homeUser.thumb.isNotEmpty ? homeUser.thumb : null,
    parentConnectionId: connectionId,
    plexHomeUserUuid: homeUser.uuid,
    plexRestricted: homeUser.restricted,
    plexAdmin: homeUser.admin,
    plexProtected: homeUser.protected,
    sortOrder: homeUser.admin ? 0 : 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    lastUsedAt: lastUsedAt,
  );

  factory Profile.fromRow({
    required String id,
    required String kind,
    required String displayName,
    required String? avatarThumbUrl,
    required Map<String, Object?> json,
    required int sortOrder,
    required DateTime createdAt,
    required DateTime? lastUsedAt,
  }) {
    final parsedKind = ProfileKind.fromId(kind);
    return switch (parsedKind) {
      ProfileKind.local => Profile.local(
        id: id,
        displayName: displayName,
        avatarThumbUrl: avatarThumbUrl,
        pinHash: json['pinHash'] as String?,
        sortOrder: sortOrder,
        createdAt: createdAt,
        lastUsedAt: lastUsedAt,
      ),
      ProfileKind.plexHome => Profile.plexHome(
        id: id,
        displayName: displayName,
        avatarThumbUrl: avatarThumbUrl,
        parentConnectionId: json['parentConnectionId'] as String?,
        plexRestricted: json['restricted'] as bool? ?? false,
        plexAdmin: json['admin'] as bool? ?? false,
        plexProtected: (json['protected'] as bool?) ?? (json['hasPassword'] as bool? ?? false),
        sortOrder: sortOrder,
        createdAt: createdAt,
        lastUsedAt: lastUsedAt,
      ),
      ProfileKind.pleyaServer => Profile.pleyaServer(
        id: id,
        displayName: displayName,
        avatarThumbUrl: avatarThumbUrl,
        pleyaConnectionId: json['pleyaConnectionId'] as String?,
        pleyaUsername: json['pleyaUsername'] as String?,
        sortOrder: sortOrder,
        createdAt: createdAt,
        lastUsedAt: lastUsedAt,
      ),
    };
  }

  bool get isLocal => this is LocalProfile;
  bool get isPlexHome => this is PlexHomeProfile;
  bool get isPleyaServer => this is PleyaServerProfile;

  ProfileKind get kind => switch (this) {
    LocalProfile() => ProfileKind.local,
    PlexHomeProfile() => ProfileKind.plexHome,
    PleyaServerProfile() => ProfileKind.pleyaServer,
  };

  /// True when entering this profile requires user-supplied PIN.
  ///
  /// Locals: gated by their own [pinHash].
  /// Plex Home: gated by Plex's own protected flag (`plexProtected`).
  /// Pleya Server profiles are not PIN-gated in this phase: the server has a
  /// real password per account, so a four-digit social barrier in front of it
  /// would suggest a protection that the account itself already provides
  /// better. Whether a household wants a quick switch guard on top is a
  /// product question for a later phase, not a gap here.
  bool get isPinProtected => switch (this) {
    LocalProfile(:final pinHash) => pinHash != null && pinHash.isNotEmpty,
    PlexHomeProfile(:final plexProtected) => plexProtected,
    PleyaServerProfile() => false,
  };

  /// Hashed PIN, only set for [LocalProfile]. Returns null for plexHome.
  String? get pinHash => switch (this) {
    LocalProfile(:final pinHash) => pinHash,
    PlexHomeProfile() => null,
    PleyaServerProfile() => null,
  };

  /// Parent Plex account connection id, only set for [PlexHomeProfile].
  String? get parentConnectionId => switch (this) {
    LocalProfile() => null,
    PlexHomeProfile(:final parentConnectionId) => parentConnectionId,
    PleyaServerProfile() => null,
  };

  /// The Pleya Server connection this profile is the identity of, only set for
  /// [PleyaServerProfile].
  String? get pleyaConnectionId => switch (this) {
    LocalProfile() => null,
    PlexHomeProfile() => null,
    PleyaServerProfile(:final pleyaConnectionId) => pleyaConnectionId,
  };

  /// The username on that server, only set for [PleyaServerProfile].
  String? get pleyaUsername => switch (this) {
    LocalProfile() => null,
    PlexHomeProfile() => null,
    PleyaServerProfile(:final pleyaUsername) => pleyaUsername,
  };

  /// Plex Home user UUID, only set for [PlexHomeProfile].
  String? get plexHomeUserUuid => switch (this) {
    LocalProfile() => null,
    PlexHomeProfile(:final plexHomeUserUuid) => plexHomeUserUuid,
    PleyaServerProfile() => null,
  };

  bool get plexRestricted => switch (this) {
    LocalProfile() => false,
    PlexHomeProfile(:final plexRestricted) => plexRestricted,
    PleyaServerProfile() => false,
  };

  bool get plexAdmin => switch (this) {
    LocalProfile() => false,
    PlexHomeProfile(:final plexAdmin) => plexAdmin,
    PleyaServerProfile() => false,
  };

  bool get plexProtected => switch (this) {
    LocalProfile() => false,
    PlexHomeProfile(:final plexProtected) => plexProtected,
    PleyaServerProfile() => false,
  };

  Map<String, Object?> toConfigJson() => switch (this) {
    LocalProfile(:final pinHash) => {'pinHash': pinHash},
    PlexHomeProfile(:final parentConnectionId, :final plexRestricted, :final plexAdmin, :final plexProtected) => {
      'parentConnectionId': parentConnectionId,
      'restricted': plexRestricted,
      'admin': plexAdmin,
      'protected': plexProtected,
    },
    PleyaServerProfile(:final pleyaConnectionId, :final pleyaUsername) => {
      'pleyaConnectionId': pleyaConnectionId,
      'pleyaUsername': pleyaUsername,
    },
  };
}

enum ProfileKind {
  local,
  plexHome,
  pleyaServer;

  String get id => switch (this) {
    ProfileKind.local => 'local',
    ProfileKind.plexHome => 'plex_home',
    ProfileKind.pleyaServer => 'pleya_server',
  };

  static ProfileKind fromId(String id) => switch (id) {
    'local' => ProfileKind.local,
    'plex_home' => ProfileKind.plexHome,
    'pleya_server' => ProfileKind.pleyaServer,
    _ => throw ArgumentError('Unknown ProfileKind id: $id'),
  };
}

/// Salted SHA-256 of the PIN. The salt is fixed (per-app) — this is a
/// social-barrier hash, not real authentication. The threat model is
/// "kid bypassing parent's profile", not "adversary with device access".
const _pinSalt = 'pleya-app-profile-pin-v1';

String computePinHash(String rawPin) {
  final digest = sha256.convert(utf8.encode('$_pinSalt:$rawPin'));
  return digest.toString();
}

bool verifyPin(String rawPin, String hash) {
  return computePinHash(rawPin) == hash;
}

/// Deterministic id for a Plex Home profile so re-discovery is idempotent.
String plexHomeProfileId({required String accountConnectionId, required String homeUserUuid}) {
  return 'plex-home-$accountConnectionId-$homeUserUuid';
}

/// Anchor on the trailing 36-char UUID — both `accountConnectionId` and
/// `homeUserUuid` may contain hyphens, so a `lastIndexOf('-')` would slice
/// inside the UUID itself.
final RegExp _trailingHomeUserUuidPattern = RegExp(
  r'-([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$',
);

/// Inverse of [plexHomeProfileId]. Returns `null` if [id] doesn't match the
/// `plex-home-{accountConnectionId}-{homeUserUuid}` shape.
({String accountConnectionId, String homeUserUuid})? parsePlexHomeProfileId(String id) {
  const prefix = 'plex-home-';
  if (!id.startsWith(prefix)) return null;
  final rest = id.substring(prefix.length);
  final match = _trailingHomeUserUuidPattern.firstMatch(rest);
  if (match == null) return null;
  final accountId = rest.substring(0, match.start);
  if (accountId.isEmpty) return null;
  return (accountConnectionId: accountId, homeUserUuid: match.group(1)!);
}
