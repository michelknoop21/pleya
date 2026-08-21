import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A16. Nothing on the preference-sync path logs a value, a key with an
/// identity in it, a token or a payload.
///
/// A review is a snapshot; this is the guard. It reads the sources, pulls every
/// interpolation out of every log statement, and demands that each one is on a
/// list of things that are safe to print. Adding `$value` to a log line turns
/// this red, which is the point: the keys on this path carry server ids and
/// library ids, and the values are the user's settings.
void main() {
  const paths = [
    'lib/services/preferences/preference_sync_coordinator.dart',
    'lib/services/preferences/icloud_kvs_transport.dart',
    'lib/services/preferences/preference_reconcile_scheduler.dart',
    'lib/services/preferences/preference_quarantine.dart',
    'lib/services/preferences/preference_legacy_bootstrap.dart',
    'lib/services/preferences/preference_merge_strategies.dart',
    'lib/services/preferences/preference_refresh.dart',
    'lib/services/icloud_sync_service.dart',
  ];

  /// Expressions that may appear inside a log statement.
  ///
  /// `_category` maps a key to its registered prefix, so `library_sort_<server:
  /// library>` prints as `library_sort_*`. `_errorCategory` prints a runtime
  /// type, never a message: an exception string can carry a URL or a token.
  /// A count is a number about this device and identifies nobody.
  const allowed = {'_category(baseKey)', '_errorCategory(e)', 'imported'};

  final logCall = RegExp(r'appLogger\.[a-z]+\((.*)\);');
  final interpolation = RegExp(r'\$\{([^}]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)');

  test('every interpolation in a sync log statement is on the safe list', () {
    final offenders = <String>[];
    var statements = 0;

    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final match = logCall.firstMatch(lines[i]);
        if (match == null) continue;
        statements++;
        for (final expression in interpolation.allMatches(match.group(1)!)) {
          final source = (expression.group(1) ?? expression.group(2))!.trim();
          if (!allowed.contains(source)) offenders.add('$path:${i + 1}: \$$source');
        }
      }
    }

    expect(statements, greaterThan(5), reason: 'the scanner found no log statements, so it proved nothing');
    expect(offenders, isEmpty);
  });

  test('no log statement names a preference key, a payload or a credential outright', () {
    final forbidden = [
      RegExp(r'appLogger\.[a-z]+\([^;]*\$\{?(mutation\.value|entry\.value|encoded|raw|portableValue)'),
      RegExp(r'appLogger\.[a-z]+\([^;]*\$\{?(cloudKey|fullKey|targetKey)\b'),
      RegExp(r'appLogger\.[a-z]+\([^;]*(token|password|secret|credential)', caseSensitive: false),
    ];

    final offenders = <String>[];
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final pattern in forbidden) {
          if (pattern.hasMatch(lines[i])) offenders.add('$path:${i + 1}');
        }
      }
    }

    expect(offenders, isEmpty);
  });

  test('the transport logs a failure without echoing what it was sending', () {
    final source = File('lib/services/preferences/icloud_kvs_transport.dart').readAsStringSync();

    // `error: e` is allowed: the plugin's own FlutterError messages are fixed
    // strings, and a channel exception carries the channel name, not the
    // arguments. What must not appear is the key or the encoded value.
    expect(source.contains(r"appLogger.w('iCloud set failed', error: e)"), isTrue);
    expect(RegExp(r"appLogger\.[a-z]+\([^;]*\$key").hasMatch(source), isFalse);
    expect(RegExp(r"appLogger\.[a-z]+\([^;]*\$encoded").hasMatch(source), isFalse);
  });
}
