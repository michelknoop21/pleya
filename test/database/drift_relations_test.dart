import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// De relatie tussen `connections` en `profile_connections` bestaat alleen in
/// gegenereerde code. Een upgrade van de analyzer-stack liet drift_dev die
/// relatie stil weglaten: geen foreign key, geen `ON DELETE CASCADE`, geen
/// writepropagatie naar streamqueries en geen reference manager — 298 regels
/// weg, zonder compilefout en zonder waarschuwing. De app compileert en draait
/// dan gewoon door, met een database die verweesde rijen kan overhouden.
///
/// Deze test kijkt daarom naar de gegenereerde output zelf. `flutter analyze`
/// en de typechecker kunnen dit niet zien, want er verdwijnt niets waar iets
/// anders naar verwijst. Zie [DEC-024](../../docs/DECISIONS.md#dec-024).
void main() {
  late String generated;

  setUpAll(() {
    generated = File('lib/database/app_database.g.dart').readAsStringSync();
  });

  test('profile_connections houdt zijn foreign key met cascade', () {
    expect(
      generated,
      contains("'REFERENCES connections (id) ON DELETE CASCADE'"),
      reason:
          'drift_dev genereert de foreign-keyconstraint niet meer. '
          'Vrijwel zeker een analyzer-stack die te ver vooruit staat — zie DEC-024.',
    );
  });

  test('het verwijderen van een connection propageert naar streamqueries', () {
    expect(generated, contains('StreamQueryUpdateRules'));
    expect(generated, contains('WritePropagation'));
    expect(
      generated,
      contains("TableUpdate('profile_connections', kind: UpdateKind.delete)"),
      reason:
          'zonder deze regel blijven streamqueries op profile_connections stale '
          'na het verwijderen van een connection — zie DEC-024.',
    );
  });

  test('de reference manager tussen connections en profile_connections bestaat', () {
    expect(generated, contains(r'$$ConnectionsTableReferences'));
    expect(
      generated,
      contains('profileConnectionsRefs'),
      reason: 'de gegenereerde manager om van een connection naar zijn profielen te lopen is weg — zie DEC-024.',
    );
  });
}
