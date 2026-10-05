import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_account_key.dart';
import 'package:pleya/assistant/current_user_context.dart';
import 'package:pleya/media/media_backend.dart';

void main() {
  const plexTv = AssistantAccountProvider.plexTv;
  final ctx = CurrentUserContext.build(const [
    AssistantSelfSource(serverId: 'plex-a', backend: MediaBackend.plex, plexOwner: true, plexTvAccountId: 42),
    AssistantSelfSource(serverId: 'plex-b', backend: MediaBackend.plex, plexTvAccountId: null),
    AssistantSelfSource(serverId: 'jf', backend: MediaBackend.jellyfin, userId: 'u-1'),
    AssistantSelfSource(serverId: 'ps', backend: MediaBackend.pleyaServer),
    AssistantSelfSource(serverId: 'em', backend: MediaBackend.jellyfin, emby: true, userId: 'e-9'),
  ], traktAccountId: 'michel');

  test('every source names me in its own id space', () {
    expect(ctx.on('plex-a', plexTv).key, const AssistantAccountKey(plexTv, '42'));
    expect(
      ctx.on('plex-a', AssistantAccountProvider.plexServer).key,
      const AssistantAccountKey(AssistantAccountProvider.plexServer, '1', serverId: 'plex-a'),
    );
    expect(
      ctx.on('jf', AssistantAccountProvider.jellyfin).key,
      const AssistantAccountKey(AssistantAccountProvider.jellyfin, 'u-1', serverId: 'jf'),
    );
    expect(
      ctx.on('em', AssistantAccountProvider.emby).key,
      const AssistantAccountKey(AssistantAccountProvider.emby, 'e-9', serverId: 'em'),
    );
    expect(ctx.trakt.key, const AssistantAccountKey(AssistantAccountProvider.trakt, 'michel'));
  });

  test('unknown stays unknown, with a reason, and is never a key', () {
    expect(ctx.on('plex-b', plexTv).unknown, AssistantSelfUnknown.noPlexAccount);
    expect(ctx.on('plex-b', AssistantAccountProvider.plexServer).unknown, AssistantSelfUnknown.notOwner);
    expect(ctx.on('ps', AssistantAccountProvider.pleyaServer).unknown, AssistantSelfUnknown.notStored);
    expect(ctx.on('nowhere', plexTv).unknown, AssistantSelfUnknown.notLinked);
    expect(ctx.unknownOn(plexTv), ['plex-b']);
    expect(CurrentUserContext.build(const []).trakt.unknown, AssistantSelfUnknown.notLinked);
  });

  test('isSelf matches ids, not names: the same id on another server is somebody else', () {
    expect(ctx.isSelf(const AssistantAccountKey(plexTv, '42')), isTrue);
    expect(ctx.isSelf(const AssistantAccountKey(AssistantAccountProvider.jellyfin, 'u-1', serverId: 'jf')), isTrue);
    expect(ctx.isSelf(const AssistantAccountKey(AssistantAccountProvider.jellyfin, 'u-1', serverId: 'other')), isFalse);
    expect(ctx.isSelf(const AssistantAccountKey(plexTv, '43')), isFalse);
  });

  test('two accounts with the same id on different servers are two keys', () {
    const a = AssistantAccountKey(AssistantAccountProvider.plexServer, '1', serverId: 'a');
    const b = AssistantAccountKey(AssistantAccountProvider.plexServer, '1', serverId: 'b');
    expect(a == b, isFalse);
    expect({a, b}, hasLength(2));
  });

  test('a Jellyfin or Emby GUID is one account with or without dashes and in either case', () {
    const dashed = AssistantAccountKey(
      AssistantAccountProvider.jellyfin,
      'A1B2C3D4-0000-1111-2222-333344445555',
      serverId: 'jf',
    );
    const plain = AssistantAccountKey(
      AssistantAccountProvider.jellyfin,
      'a1b2c3d4000011112222333 344445555',
      serverId: 'jf',
    );
    final compact = AssistantAccountKey(
      AssistantAccountProvider.jellyfin,
      'a1b2c3d4000011112222333344445555',
      serverId: 'jf',
    );
    expect(dashed == compact, isTrue);
    expect(dashed.hashCode, compact.hashCode);
    expect(dashed.toString(), compact.toString());
    expect(plain == compact, isFalse, reason: 'a space is not a dash');
    // Other providers compare exactly.
    expect(
      const AssistantAccountKey(AssistantAccountProvider.pleyaServer, 'A-b', serverId: 's') ==
          const AssistantAccountKey(AssistantAccountProvider.pleyaServer, 'ab', serverId: 's'),
      isFalse,
    );
  });
}
