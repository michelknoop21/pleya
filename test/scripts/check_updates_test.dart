import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `scripts/check_updates.sh` mag maar op één manier falen: door te zeggen dat
/// het iets niet weet. Een netwerkchecker die alleen "actueel" en "achter" kent
/// liegt zodra GitHub rate-limit geeft of een JSON-formaat verandert, en dan is
/// een groen rapport erger dan geen rapport.
///
/// De upstream-antwoorden komen hier uit `test/fixtures/check_updates/`, via de
/// injectie op `PLEYA_UPDATE_FIXTURES`. Zonder die injectie is "geeft een
/// gewijzigde upstream-API ook echt UNKNOWN?" niet te testen — en dat is de
/// gevaarlijkste van de vier, want die mag nooit per ongeluk CURRENT opleveren.
void main() {
  final fixtures = Directory('test/fixtures/check_updates').absolute.path;

  ProcessResult run({required String upstream, required String root, required String only}) => Process.runSync(
    'bash',
    ['scripts/check_updates.sh', '--only', only, '--root', '$fixtures/roots/$root'],
    environment: {'PLEYA_UPDATE_FIXTURES': '$fixtures/$upstream'},
  );

  test('engine op de nieuwste build van zijn lijn is CURRENT', () {
    final r = run(upstream: 'tags_ok', root: 'engine_current', only: 'engine');
    expect(r.stdout, contains('tvos-engine'));
    expect(r.stdout, contains('CURRENT'));
    expect(r.exitCode, 0);
  });

  test('engine twee builds achter is OUTDATED en noemt er twee', () {
    final r = run(upstream: 'tags_ok', root: 'engine_behind', only: 'engine');
    expect(r.stdout, contains('3.44.0+3 -> 3.44.0+5'));
    expect(r.stdout, contains('OUTDATED'));
    expect(r.stdout, contains('2 openstaande build(s)'));
    // Een bump hier vraagt opnieuw het bewijs uit DEC-019; dat hoort in het
    // rapport te staan, niet in iemands hoofd.
    expect(r.stdout, contains('engine press hook available=true'));
    // ring 3, dus buiten de strict-ring van de wekelijkse signalering.
    expect(r.exitCode, 0);
  });

  test('een nieuwere Flutter zonder tvOS-enginelijn is BLOCKED, niet OUTDATED', () {
    final r = run(upstream: 'tags_ok', root: 'flutter_blocked', only: 'flutter');
    expect(r.stdout, contains('3.44.0 -> 3.47.0'));
    expect(r.stdout, contains('BLOCKED'));
    expect(r.stdout, isNot(contains('OUTDATED')));
    expect(r.stdout, contains('tvOS-enginelijn'));
    expect(r.exitCode, 0);
  });

  test('een onbereikbare upstream is UNKNOWN met exit 2', () {
    final r = run(upstream: 'unreachable', root: 'engine_behind', only: 'engine');
    expect(r.stdout, contains('UNKNOWN'));
    expect(r.stdout, isNot(contains('CURRENT')));
    expect(r.exitCode, 2);
  });

  test('HTTP 200 met onverwachte JSON is UNKNOWN, nooit CURRENT', () {
    final r = run(upstream: 'weird_json', root: 'flutter_blocked', only: 'flutter');
    expect(r.stdout, contains('UNKNOWN'));
    expect(r.stdout, isNot(contains('CURRENT')));
    expect(r.stdout, isNot(contains('BLOCKED')));
    expect(r.exitCode, 2);
  });

  test('exit 2 wint van exit 1', () {
    // engine (ring 3, UNKNOWN) samen met een strict-ring die op zichzelf 1 zou
    // geven: het incomplete rapport hoort te winnen.
    final r = Process.runSync(
      'bash',
      [
        'scripts/check_updates.sh',
        '--only',
        'engine',
        '--strict-through-ring',
        '3',
        '--root',
        '$fixtures/roots/engine_behind',
      ],
      environment: {'PLEYA_UPDATE_FIXTURES': '$fixtures/unreachable'},
    );
    expect(r.exitCode, 2);
  });

  test('--strict-through-ring bepaalt wat mag laten falen', () {
    ProcessResult withRing(String ring) => Process.runSync(
      'bash',
      [
        'scripts/check_updates.sh',
        '--only',
        'engine',
        '--strict-through-ring',
        ring,
        '--root',
        '$fixtures/roots/engine_behind',
      ],
      environment: {'PLEYA_UPDATE_FIXTURES': '$fixtures/tags_ok'},
    );

    // De engine is ring 3 en staat OUTDATED.
    expect(withRing('1').exitCode, 0, reason: 'ring 3 mag ring-1-signalering niet rood zetten');
    expect(withRing('2').exitCode, 0);
    expect(withRing('3').exitCode, 1);
  });
}
