/// PB-10 (MOC-20): `reduceMotion()` also honors `SettingsService.tvReduceMotion`,
/// not just the OS "reduce motion" accessibility toggle it already read.
///
/// Guards two things at once: the new app-level toggle actually collapses the
/// duration, and the defensive `instanceOrNull` read never throws for a
/// caller that has not bootstrapped `SettingsService` — the failure mode that
/// broke every golden and widget test built on `TvHeroBillboardCard` the
/// first time this used `SettingsService.instance` directly.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_tokens.dart';

import '../test_helpers/prefs.dart';

const _d = Duration(milliseconds: 250);

Widget _probe({required bool osDisableAnimations, required void Function(Duration) onBuilt}) => MediaQuery(
  data: MediaQueryData(disableAnimations: osDisableAnimations),
  child: Builder(
    builder: (context) {
      onBuilt(reduceMotion(context, _d));
      return const SizedBox.shrink();
    },
  ),
);

void main() {
  testWidgets('an uninitialized SettingsService never throws, and behaves as if the pref were off', (tester) async {
    SettingsService.resetForTesting();
    late Duration result;

    await tester.pumpWidget(_probe(osDisableAnimations: false, onBuilt: (d) => result = d));

    expect(result, _d);
  });

  testWidgets('the OS accessibility toggle still collapses the duration on its own', (tester) async {
    SettingsService.resetForTesting();
    late Duration result;

    await tester.pumpWidget(_probe(osDisableAnimations: true, onBuilt: (d) => result = d));

    expect(result, Duration.zero);
  });

  testWidgets('tvReduceMotion off keeps the given duration', (tester) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    late Duration result;

    await tester.pumpWidget(_probe(osDisableAnimations: false, onBuilt: (d) => result = d));

    expect(result, _d);
  });

  testWidgets('tvReduceMotion on collapses the duration even with the OS toggle off', (tester) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.tvReduceMotion, true);
    late Duration result;

    await tester.pumpWidget(_probe(osDisableAnimations: false, onBuilt: (d) => result = d));

    expect(result, Duration.zero);
  });
}
