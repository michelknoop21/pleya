import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/providers/tautulli_provider.dart';
import 'package:pleya/services/tautulli/tautulli_constants.dart';
import 'package:pleya/services/tautulli/tautulli_integration_store.dart';
import 'package:pleya/services/tautulli/tautulli_server_integration.dart';
import 'package:pleya/services/tautulli/tautulli_session.dart';

import '../test_helpers/prefs.dart';

/// The Tautulli credential is a *household admin's* API key. One profile pairs
/// it, every profile in the house benefits from the history it unlocks, and no
/// profile but the admin's may ever hold it.
///
/// These are architecture assertions, not behaviour tests: they are here to
/// fail when a future change quietly widens the boundary, which is the failure
/// mode that would not show up in any feature test. Two halves:
///
///  * source-level, so a type that carries the token cannot even be named on
///    the consuming side of the boundary;
///  * behavioural, so the runtime answer for a non-admin profile is checked
///    rather than assumed from the types.
const _machine = 'pms-1';

String _source(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path moved; update this test rather than deleting it');
  return file.readAsStringSync();
}

/// The source lines worth asserting on: everything that is not a comment or
/// blank. It does *not* filter private members — the call sites below name
/// their own exclusions, and that list is load-bearing, so a new private member
/// mentioning a credential-bearing type will fail the assertion until it is
/// either excluded on purpose or turns out to be a real leak. That is the
/// intended bias: a false alarm costs a line here, a miss costs a credential.
Iterable<String> _codeLines(String source) sync* {
  for (final raw in source.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('//') || line.startsWith('///') || line.startsWith('*')) continue;
    yield line;
  }
}

void main() {
  setUp(resetSharedPreferencesForTest);

  group('the consuming side cannot name a credential-bearing type', () {
    // The import graph is the enforcement. `TautulliServerIntegration` holds the
    // token, `TautulliSession` is the token in a call-ready shape and
    // `TautulliClient` is a session with a socket attached; the binding and the
    // importer are resolved in *every* profile's context, so neither may be able
    // to mention any of them.
    const consumers = [
      'lib/services/recommendations/tautulli_import_binding.dart',
      'lib/services/recommendations/tautulli_history_importer.dart',
    ];
    const forbidden = [
      'tautulli_server_integration.dart',
      'tautulli_session.dart',
      'tautulli_client.dart',
      'tautulli_integration_store.dart',
      'credential_vault.dart',
    ];

    for (final path in consumers) {
      test('$path does not import a credential-bearing library', () {
        final imports = _codeLines(_source(path)).where((l) => l.startsWith('import ')).toList();
        for (final banned in forbidden) {
          expect(
            imports.where((i) => i.contains(banned)),
            isEmpty,
            reason:
                '$path may only see the credential-free view. Importing $banned puts a token '
                'one field access away from a profile that must never hold one.',
          );
        }
      });
    }

    test('the status view carries no credential-shaped field', () {
      final source = _source('lib/services/tautulli/tautulli_integration_status.dart');
      for (final field in ['token', 'session', 'client', 'apiKey', 'baseUrl', 'deviceId']) {
        expect(
          source,
          isNot(contains(' $field;')),
          reason: 'TautulliIntegrationStatus is the type a non-admin profile holds; $field has no place on it',
        );
      }
      // And it cannot reach one indirectly either: it imports nothing at all.
      expect(_codeLines(source).where((l) => l.startsWith('import ')), isEmpty);
    });

    test('no public member of TautulliProvider hands out an integration record', () {
      final source = _source('lib/providers/tautulli_provider.dart');
      // `_adminIntegration` is private and stays private; anything public that
      // returned the record would put the token in reach of the settings screen
      // and of any other consumer that can read the provider.
      final publicReturns = _codeLines(source).where(
        (l) =>
            l.contains('TautulliServerIntegration') &&
            !l.contains('_adminIntegration') &&
            !l.contains('Map<String, TautulliServerIntegration> _integrations') &&
            !l.contains('TautulliServerIntegration.fromSession') &&
            !l.contains('import '),
      );
      expect(
        publicReturns,
        isEmpty,
        reason: 'found a public member typed on the credential-bearing record:\n${publicReturns.join('\n')}',
      );
    });
  });

  group('what a regular profile actually gets at runtime', () {
    Future<TautulliProvider> boundAs({
      required bool isAdmin,
      String uuid = 'uuid-kid',
      List<String> servers = const [_machine],
      int? accountId = 4725462,
    }) async {
      await TautulliIntegrationStore.instance.save(
        const TautulliServerIntegration(
          machineIdentifier: _machine,
          baseUrl: 'https://tautulli.example',
          authMode: TautulliAuthMode.device,
          token: 'super-secret-admin-key',
        ),
      );
      final p = TautulliProvider();
      p.attachServerResolvers(
        serverIds: () => servers,
        isOwnerOrAdmin: (_) => isAdmin,
        selfAccountId: (profileId) => profileId == uuid ? accountId : null,
      );
      await p.onActiveProfileChanged(uuid);
      return p;
    }

    test('no session, no client, no admin surface — and import still works', () async {
      final p = await boundAs(isAdmin: false);
      addTearDown(p.dispose);

      // Everything that could carry the credential is absent…
      expect(p.session, isNull);
      expect(p.client, isNull);
      expect(p.adminStatus, isNull);
      expect(p.isConfigured, isFalse);
      expect(p.host, isNull);

      // …while the credential-free view says what the import needs to know.
      final status = p.importStatusFor(ServerId(_machine));
      expect(status, isNotNull);
      expect(status!.importEnabled, isTrue);
      expect(status.toString(), isNot(contains('super-secret-admin-key')));
      expect(p.enabledImportServerIds(), {_machine});
    });

    test('the record never reaches a log line, not even through toString', () {
      const record = TautulliServerIntegration(
        machineIdentifier: _machine,
        baseUrl: 'https://tautulli.example',
        authMode: TautulliAuthMode.device,
        token: 'super-secret-admin-key',
      );
      expect(record.toString(), isNot(contains('super-secret-admin-key')));
      expect(record.status.toString(), isNot(contains('super-secret-admin-key')));
      expect(record.status.toString(), isNot(contains('tautulli.example')));
    });

    test('a caller cannot aim the credential at another profile', () async {
      final p = await boundAs(isAdmin: false);
      addTearDown(p.dispose);

      // The active profile is the only one that resolves. There is no parameter
      // that names a user, so this is the strongest a caller can try.
      expect(
        await p.fetchImportHistory(ServerId(_machine), profileId: 'uuid-someone-else', length: 5, start: 0),
        isNull,
      );
      expect(await p.fetchImportHistory(ServerId(_machine), profileId: '', length: 5, start: 0), isNull);
    });

    test('a profile without the server neither scores nor fetches it', () async {
      final p = await boundAs(isAdmin: false, servers: const ['some-other-server']);
      addTearDown(p.dispose);

      expect(p.enabledImportServerIds(), isEmpty, reason: 'the household shares a pairing, not a catalogue');
      expect(await p.fetchImportHistory(ServerId(_machine), profileId: 'uuid-kid', length: 5, start: 0), isNull);
    });

    test('the authority cannot be re-wired after the fact', () async {
      // The subtler bypass: not reading the credential, but replacing the three
      // closures that decide who this profile is and what it administers. A
      // second wiring would let any code in the tree declare itself an admin
      // and point the credential at an arbitrary account.
      final p = await boundAs(isAdmin: false);
      addTearDown(p.dispose);

      p.attachServerResolvers(
        serverIds: () => const [_machine],
        isOwnerOrAdmin: (_) => true,
        selfAccountId: (_) => 999999,
      );

      expect(p.session, isNull, reason: 'the second wiring is refused, so the admin binding does not open up');
      expect(p.client, isNull);
      expect(p.adminStatus, isNull);
      expect(
        await p.fetchImportHistory(ServerId(_machine), profileId: 'uuid-someone-else', length: 5, start: 0),
        isNull,
      );
    });

    test('a profile whose Plex account cannot be resolved fetches nothing', () async {
      final p = await boundAs(isAdmin: false, accountId: null);
      addTearDown(p.dispose);
      expect(await p.fetchImportHistory(ServerId(_machine), profileId: 'uuid-kid', length: 5, start: 0), isNull);
    });
  });

  test('a legacy pairing stays with the profile that made it', () async {
    // The one credential a non-admin can hold is the one it paired itself, and
    // it is profile-scoped storage, so it is not the admin's.
    final session = TautulliSession(
      baseUrl: 'https://own.example',
      authMode: TautulliAuthMode.apiKey,
      token: 'own-key',
    );
    await TautulliIntegrationStore.instance.saveLegacySession('uuid-kid', session);

    final other = TautulliProvider();
    other.attachServerResolvers(serverIds: () => const [_machine], isOwnerOrAdmin: (_) => true);
    await other.onActiveProfileChanged('uuid-someone-else');
    addTearDown(other.dispose);

    expect(other.session, isNull, reason: 'another profile never inherits a profile-scoped pairing');
  });
}
