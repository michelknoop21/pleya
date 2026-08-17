import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `scripts/classify_lock_diff.sh` bepaalt welk bewijsniveau een
/// dependency-update nodig heeft. Die classificatie is het veiligheidsmechanisme
/// onder het ringbeleid, dus hij heeft zelf een vangnet nodig: als hij een
/// plugin met gewijzigde native code als ring 1 afvinkt, gaat er een
/// A/V-regressie mee naar TestFlight zonder dat iemand ernaar gekeken heeft.
///
/// De zes fixtures staan in `test/fixtures/lock_diff/` en dekken elk één regel
/// uit het beleid.
void main() {
  const fixtureRoot = 'test/fixtures/lock_diff';

  ProcessResult classify(String fixture) => Process.runSync('bash', [
    'scripts/classify_lock_diff.sh',
    '--old',
    '$fixtureRoot/$fixture/old.lock',
    '--new',
    '$fixtureRoot/$fixture/new.lock',
    '--cache',
    '$fixtureRoot/$fixture/cache',
  ]);

  /// De regel na `ring: ` voor het genoemde pakket.
  String ringOf(String stdout, String package) {
    final block = RegExp('^package: $package\$.*?^ring: (\\S+)\$', multiLine: true, dotAll: true);
    final match = block.firstMatch(stdout);
    expect(match, isNotNull, reason: 'geen blok voor $package in:\n$stdout');
    return match!.group(1)!;
  }

  String evidenceOf(String stdout, String key) {
    final match = RegExp('^  $key: (.*)\$', multiLine: true).firstMatch(stdout);
    expect(match, isNotNull, reason: 'geen bewijsregel "$key" in:\n$stdout');
    return match!.group(1)!.trim();
  }

  test('een pure Dart-patch is ring 1', () {
    final result = classify('pure_dart');
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final out = result.stdout as String;
    expect(ringOf(out, 'collection'), '1');
    expect(evidenceOf(out, 'plugin'), 'false');
    expect(evidenceOf(out, 'sources'), 'cache-hit/cache-hit');
    expect(out, contains('ring1=1'));
  });

  test('een generator-update promoveert naar ring 2', () {
    final result = classify('generator');
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final out = result.stdout as String;
    expect(ringOf(out, 'build_runner'), '2');
    expect(evidenceOf(out, 'generatedCodeParticipant'), 'true');
  });

  test('een plugin met gewijzigde native code is ring 3', () {
    final result = classify('plugin_native_diff');
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final out = result.stdout as String;
    expect(ringOf(out, 'path_provider_android'), '3');
    expect(evidenceOf(out, 'plugin'), 'true');
    expect(evidenceOf(out, 'nativeDiff'), 'differs');
  });

  test('dezelfde plugin met identieke native kant zakt naar ring 2', () {
    final result = classify('plugin_native_same');
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final out = result.stdout as String;
    expect(ringOf(out, 'path_provider_android'), '2');
    expect(evidenceOf(out, 'plugin'), 'true');
    expect(evidenceOf(out, 'nativeDiff'), 'identical');
  });

  test('een ontbrekende bron geeft UNKNOWN, niet ring 1', () {
    final result = classify('missing_old_source');
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final out = result.stdout as String;
    expect(ringOf(out, 'some_package'), 'UNKNOWN');
    expect(evidenceOf(out, 'sources'), 'cache-miss/cache-hit');
    expect(out, contains('unknown=1'));
    // Niet kunnen aantonen dat iets veilig is telt als niet veilig: UNKNOWN mag
    // nooit meetellen als ring 1.
    expect(out, contains('ring1=0'));
  });

  test('een onvolledige lockfile is een harde fout, geen ring 1', () {
    final result = classify('malformed');
    expect(result.exitCode, isNot(0));
    expect(result.stderr.toString(), contains("mist 'source'"));
    expect(result.stdout.toString(), isNot(contains('summary:')));
  });
}
