import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/integration_credential_changes.dart';

import '../test_helpers/prefs.dart';
import '../test_helpers/seerr_fake.dart';

void main() {
  setUp(resetSharedPreferencesForTest);

  test('queued credential operations remain exclusive', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var secondEntered = false;
    final first = IntegrationCredentialChanges.exclusively(() async {
      entered.complete();
      await release.future;
      return 1;
    });
    await entered.future;
    final second = IntegrationCredentialChanges.exclusively(() async {
      secondEntered = true;
      return 2;
    });
    await Future<void>.delayed(Duration.zero);
    expect(secondEntered, isFalse);
    release.complete();
    expect(await Future.wait([first, second]), [1, 2]);
  });

  test('a failed operation does not strand the next credential operation', () async {
    await expectLater(
      IntegrationCredentialChanges.exclusively<void>(() async => throw StateError('synthetic failure')),
      throwsStateError,
    );
    expect(await IntegrationCredentialChanges.exclusively(() async => 3), 3);
  });

  // Each widget test has its own fake async zone. A completed lock tail from
  // the previous zone must not leave the next profile load waiting forever.
  for (final value in [1, 2]) {
    testWidgets('credential storage remains usable in widget test $value', (tester) async {
      expect(await IntegrationCredentialChanges.exclusively(() async => value), value);
    }, timeout: const Timeout(Duration(seconds: 5)));
  }

  for (final value in [1, 2]) {
    testWidgets('Seerr profile remains usable in widget test $value', (tester) async {
      final provider = await seerrProvider(FakeSeerr());
      addTearDown(provider.dispose);
      expect(provider.isConfigured, isTrue);
      expect(provider.session?.userId, 7);
    }, timeout: const Timeout(Duration(seconds: 5)));
  }
}
