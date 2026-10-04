import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../main.dart' show rootNavigatorKey;
import '../profiles/active_profile_provider.dart';
import '../profiles/profile.dart';
import '../profiles/profile_connection_registry.dart';
import '../profiles/profile_registry.dart';

/// `POST /v1/profiles/seed` body: `{"display_name": "..."}`.
///
/// Adds a second local profile that borrows every connection of the active
/// profile, and leaves the active profile active. It is the state a viewer
/// reaches through Profiel toevoegen plus Verbinding lenen, without typing a
/// name on the Apple TV keyboard: what a profile-scope scenario needs is two
/// profiles on the same server, not another proof of the add-profile form.
///
/// Runs after `/v1/signin`, so the active profile and its connection exist.
/// Reads the root navigator's context: every registry used here is provided
/// above the profile session.
Future<Map<String, Object?>> handleAutomationSeedProfile(Map<String, Object?> body) async {
  final name = (body['display_name'] as String?)?.trim() ?? '';
  if (name.isEmpty) return {'ok': false, 'error': 'display_name is required'};

  final context = rootNavigatorKey.currentContext;
  if (context == null || !context.mounted) {
    return {'ok': false, 'error': 'no root context available yet — the app has not finished booting'};
  }
  final active = context.read<ActiveProfileProvider>().active;
  if (active == null) return {'ok': false, 'error': 'no active profile to borrow from — sign in first'};
  final profileConnections = context.read<ProfileConnectionRegistry>();
  final profiles = context.read<ProfileRegistry>();

  final borrowed = await profileConnections.listForProfile(active.id);
  if (borrowed.isEmpty) return {'ok': false, 'error': 'the active profile has no connection to borrow'};

  final now = DateTime.now();
  final profile = Profile.local(
    id: 'local-${const Uuid().v4()}',
    displayName: name,
    sortOrder: now.millisecondsSinceEpoch,
    createdAt: now,
  );
  await profiles.upsert(profile);
  for (final connection in borrowed) {
    await profileConnections.upsert(connection.copyWith(profileId: profile.id, tokenAcquiredAt: now));
  }
  return {'ok': true, 'profileId': profile.id};
}
