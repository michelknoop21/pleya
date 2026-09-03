import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/unified_catalog/preferred_server_store.dart';

import '../../test_helpers/prefs.dart';

/// The profile's default server: the one preference in fase 4 allowed to select
/// a source rather than only focus one.
///
/// Without an active profile every test here runs in the empty scope, which is
/// a namespace of its own — that is exactly what the isolation test pins.
void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  test('a profile with no default reads as none, not as an empty server id', () async {
    expect(await PreferredServerStore.read(), isNull);
  });

  test('what was remembered comes back', () async {
    await PreferredServerStore.remember('nas-uuid');

    expect(await PreferredServerStore.read(), 'nas-uuid');
  });

  test('remembering again replaces rather than accumulates', () async {
    await PreferredServerStore.remember('nas-uuid');
    await PreferredServerStore.remember('attic-uuid');

    expect(await PreferredServerStore.read(), 'attic-uuid');
    final settings = await SettingsService.getInstance();
    expect(settings.read(SettingsService.preferredUnifiedServer), hasLength(1));
  });

  test('an empty id is not a preference and is refused', () async {
    await PreferredServerStore.remember('nas-uuid');
    await PreferredServerStore.remember('');

    expect(await PreferredServerStore.read(), 'nas-uuid');
  });

  test('clearing restores "ask me"', () async {
    await PreferredServerStore.remember('nas-uuid');
    await PreferredServerStore.clear();

    expect(await PreferredServerStore.read(), isNull);
  });

  test('deleting a profile takes its default with it, and leaves other profiles alone', () async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.preferredUnifiedServer, {'profile-a': 'nas-uuid', 'profile-b': 'attic-uuid'});

    await PreferredServerStore.clearForProfileScope('profile-a');

    expect(settings.read(SettingsService.preferredUnifiedServer), {'profile-b': 'attic-uuid'});
  });

  test('clearing a scope that has no entry writes nothing', () async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.preferredUnifiedServer, {'profile-b': 'attic-uuid'});

    await PreferredServerStore.clearForProfileScope('profile-a');

    expect(settings.read(SettingsService.preferredUnifiedServer), {'profile-b': 'attic-uuid'});
  });

  test('concurrent writes serialise instead of overwriting each other', () async {
    // The shared state is the whole map, so two writes in flight would each
    // read a snapshot from before the other queued — the same reason
    // `TrackPreferenceStore` and `SourcePreferenceStore` hold a write lock.
    await Future.wait([
      PreferredServerStore.remember('one'),
      PreferredServerStore.clearForProfileScope('other-profile'),
      PreferredServerStore.remember('two'),
    ]);

    expect(await PreferredServerStore.read(), 'two');
  });

  group('the preference is content-independent by construction', () {
    test('one entry per profile, whatever and however much you watch', () async {
      // `remember` takes a server id and nothing else — there is no identity,
      // groupId or itemId to key on, so no amount of use can grow the map.
      await PreferredServerStore.remember('nas-uuid');
      await PreferredServerStore.remember('nas-uuid');
      await PreferredServerStore.remember('nas-uuid');

      final settings = await SettingsService.getInstance();
      final stored = settings.read(SettingsService.preferredUnifiedServer);
      expect(stored, hasLength(1));
      expect(stored.values.single, 'nas-uuid');
    });

    test('the storage key is the profile scope, carrying no title identity', () async {
      await PreferredServerStore.remember('nas-uuid');

      final settings = await SettingsService.getInstance();
      final key = settings.read(SettingsService.preferredUnifiedServer).keys.single;

      // In a test there is no active profile, so the scope is the empty
      // namespace. What matters is the shape: no `|`, which is the separator
      // `SourcePreferenceStore` uses to append a CanonicalMediaIdentity bucket
      // key, and no `:` from a source key.
      expect(key, isNot(contains('|')));
      expect(key, isNot(contains(':')));
    });

    test('two profiles hold different servers at the same time', () async {
      final settings = await SettingsService.getInstance();
      await settings.write(SettingsService.preferredUnifiedServer, {
        'profile-michel': 'nas-uuid',
        'profile-guest': 'attic-uuid',
      });

      final stored = settings.read(SettingsService.preferredUnifiedServer);
      expect(stored['profile-michel'], 'nas-uuid');
      expect(stored['profile-guest'], 'attic-uuid');
    });
  });
}
