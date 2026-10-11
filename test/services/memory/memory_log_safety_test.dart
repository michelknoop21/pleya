import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/services/memory/memory_service.dart';
import 'package:pleya/services/memory/memory_store.dart';
import 'package:pleya/utils/app_logger.dart';

import 'memory_test_support.dart';

/// No log line and no error on the memory path carries a fact, a key, a
/// question, an overview or an id.
///
/// The scanner works from an allow list. In the scanned files a log call has
/// exactly one argument: a single-quoted literal whose only interpolation is
/// `${e.runtimeType}`. Everything else is an offence: a variable, a
/// concatenation, a second argument, `error:`. A `throw` may only carry a
/// literal without interpolation, and `rethrow` is out, because a database
/// error quotes its statement parameters.
const _scannedFiles = ['lib/database/assistant_memory_wipe.dart'];
const _scannedDirectory = 'lib/services/memory';

final _logCall = RegExp(r'\.(t|d|i|w|e|f|v|wtf|log|trace|debug|info|warning|error|fatal)\(');
final _allowedArguments = RegExp(r"^\s*'(?:[^'\\$]|\$\{e\.runtimeType\})*'\s*,?\s*$");
final _throw = RegExp(r'\bthrow\b([^;]*);');
final _allowedThrow = RegExp(r"^\s*(?:const\s+)?[A-Z]\w*(?:\.\w+)?\(\s*(?:'[^'\\$]*')?\s*\)\s*$");
final _otherSink = RegExp(r'\b(print|debugPrint|debugPrintStack)\(|\bdeveloper\.log\(|\bstd(out|err)\b|\brethrow\b');

/// The text between the parenthesis at [open] and the one that closes it. A
/// string literal is skipped as a whole, so a `);` inside it ends nothing.
String _argumentsAt(String source, int open) {
  var depth = 1;
  var i = open + 1;
  while (i < source.length) {
    final char = source[i];
    if (char == "'" || char == '"') {
      i++;
      while (i < source.length && source[i] != char) {
        i += source[i] == r'\' ? 2 : 1;
      }
    } else if (char == '(') {
      depth++;
    } else if (char == ')') {
      depth--;
      if (depth == 0) return source.substring(open + 1, i);
    }
    i++;
  }
  return source.substring(open + 1);
}

int _logCalls(String source) => _logCall.allMatches(source).length;

List<String> _offenders(String path, String source) {
  final offenders = <String>[];
  for (final call in _logCall.allMatches(source)) {
    final arguments = _argumentsAt(source, call.end - 1);
    if (!_allowedArguments.hasMatch(arguments)) offenders.add('$path: log call with ($arguments)');
  }
  for (final thrown in _throw.allMatches(source)) {
    if (!_allowedThrow.hasMatch(thrown.group(1)!)) offenders.add('$path: throw${thrown.group(1)}');
  }
  if (_otherSink.hasMatch(source)) offenders.add('$path: rethrows or writes outside appLogger');
  return offenders;
}

void main() {
  group('the scanner', () {
    test('accepts a literal, with or without the error type', () {
      expect(_offenders('x', "appLogger.w('Memory storage failed');"), isEmpty);
      expect(_offenders('x', r"appLogger.w('Memory storage failed: ${e.runtimeType}');"), isEmpty);
      expect(_offenders('x', "appLogger.w(\n  'Memory storage failed',\n);"), isEmpty);
      expect(_offenders('x', "throw StateError('no profile');"), isEmpty);
    });

    // The eight ways around the first scanner, from the review of this step.
    const bypasses = {
      'a bare variable': 'appLogger.w(value);',
      'a concatenation': "appLogger.w('kept ' + fact.value);",
      'a row printed whole': 'appLogger.w(row.toString());',
      'a positional error object': "appLogger.w('x', e);",
      'a message built first': r"final msg = 'kept $value'; appLogger.w(msg);",
      'another name for the logger': r"log.w('kept $value');",
      'a throw with the value': r"throw StateError('bad $value');",
      'a closing parenthesis inside the literal': r"appLogger.w('a (${e.runtimeType}); $value');",
    };
    for (final MapEntry(key: name, value: source) in bypasses.entries) {
      test('refuses $name', () => expect(_offenders('x', source), isNotEmpty, reason: source));
    }

    test('refuses a named error, another interpolation, a rethrow and a print', () {
      expect(_offenders('x', "appLogger.w('failed', error: e);"), isNotEmpty);
      expect(_offenders('x', "appLogger.w(\n  'failed \${fact.id}',\n);"), isNotEmpty);
      expect(_offenders('x', r"appLogger.w('failed: $e');"), isNotEmpty);
      expect(_offenders('x', r"appLogger.w('failed: ${e.runtimeType} ${e.message}');"), isNotEmpty);
      expect(_offenders('x', 'try { run(); } catch (e) { rethrow; }'), isNotEmpty);
      expect(_offenders('x', "print('x');"), isNotEmpty);
    });
  });

  test('no memory source logs or throws anything but a literal and an error type', () {
    final files = [
      ...Directory(_scannedDirectory).listSync(recursive: true).whereType<File>(),
      for (final path in _scannedFiles) File(path),
    ];
    expect(files.length, greaterThanOrEqualTo(8));

    var statements = 0;
    final offenders = <String>[];
    for (final file in files) {
      final source = file.readAsStringSync();
      statements += _logCalls(source);
      offenders.addAll(_offenders(file.path, source));
    }

    expect(statements, greaterThan(0), reason: 'the scanner found no log statement, so it proved nothing');
    expect(offenders, isEmpty);
  });

  test('the database logs nothing variable about the memory tables', () {
    final lines = File('lib/database/app_database.dart').readAsLinesSync();
    final memoryLogs = [
      for (final line in lines)
        if (line.contains('appLogger') && line.toLowerCase().contains('memor')) line,
    ];
    expect(memoryLogs, hasLength(1), reason: 'only the migration announcement');
    expect(memoryLogs.single.contains(r'$'), isFalse);
    expect(lines.where((line) => line.contains('deleteAssistantMemoryForProfile')), isEmpty);
  });

  group('a full run', () {
    const marker = 'zebrastreep';
    late AppDatabase db;
    late MemoryService memory;

    setUp(() async {
      await resetMemoryPrefs();
      MemoryLogOutput.clearLogs();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      memory = MemoryService(database: db, profileId: 'profile-a');
    });

    tearDown(() => db.close());

    List<String> logged() => MemoryLogOutput.getLogs().map((e) => '${e.message} ${e.error ?? ''}').toList();

    test('a failing lookup included, leaves no content in the log', () async {
      final added = await memory.remember('Houdt van $marker films');
      final id = added.fact!.id;
      await memory.remember('Houdt van $marker films', category: MemoryCategory.other);
      await memory.remember('Onze dochter is 8 $marker', category: MemoryCategory.household);
      await memory.update(id, value: 'Houdt erg van $marker films');
      await memory.update('missing-$marker', value: 'x');
      await memory.resolve(added.fact!.ref);
      await memory.relevantFor('Welke $marker films zijn er?');
      await memory.saveOverview(
        factsHash: await memory.factsHash(locale: 'nl'),
        locale: 'nl',
        status: MemoryOverviewStatus.ok,
        body: '{"overview":"$marker"}',
      );
      await memory.saveOverview(factsHash: 'x', locale: 'nl', status: MemoryOverviewStatus.ok, body: '{"$marker');
      await memory.delete(id);
      await memory.clearAll();

      await db.close();
      expect(await memory.relevantFor('Welke $marker films zijn er?'), isEmpty);

      final messages = logged();
      expect(messages.where((m) => m.contains('Memory storage failed')), isNotEmpty);
      for (final message in messages) {
        expect(message.contains(marker), isFalse, reason: message);
        expect(message.contains(id), isFalse, reason: message);
        expect(message.contains(added.fact!.ref), isFalse, reason: message);
      }
    });

    test('a database error gives a fixed code, and neither the answer nor the log holds the fact', () async {
      final added = await memory.remember('Houdt van $marker films');
      final fact = added.fact!;
      final hash = await memory.factsHash(locale: 'nl');
      const body = '{"overview":"samenvatting $marker"}';

      // Every write aborts, as on a full disk.
      for (final (table, action) in [
        ('assistant_memories', 'INSERT'),
        ('assistant_memories', 'UPDATE'),
        ('assistant_memories', 'DELETE'),
        ('assistant_memory_overviews', 'INSERT'),
      ]) {
        await db.customStatement(
          "CREATE TRIGGER boom_${table}_$action BEFORE $action ON $table BEGIN SELECT RAISE(ABORT, 'disk'); END",
        );
      }

      // The premise: the raw error quotes the fact it was asked to store.
      await expectLater(
        MemoryStore(db, 'profile-a').insert(
          id: 'raw-id',
          category: 'other',
          value: 'Geheim $marker feit',
          valueKey: 'geheim $marker feit',
          source: 'user_explicit',
          at: 1,
        ),
        throwsA(isA<SqliteException>().having((e) => e.toString(), 'text', contains('Geheim $marker feit'))),
      );

      final writes = [
        await memory.remember('Geheim $marker feit'),
        await memory.update(fact.id, value: 'Nieuw $marker feit'),
        await memory.delete(fact.id),
        await memory.saveOverview(factsHash: hash, locale: 'nl', status: MemoryOverviewStatus.ok, body: body),
        await memory.clearAll(),
      ];
      expect([for (final result in writes) result.code], everyElement(MemoryCode.storageFailed));
      expect([for (final result in writes) result.fact], everyElement(isNull));
      expect(await memory.values(), ['Houdt van $marker films'], reason: 'nothing was written or removed');

      // Every read fails too, with the id and the key among the parameters.
      await db.customStatement('DROP TABLE assistant_memories');
      await db.customStatement('DROP TABLE assistant_memory_overviews');

      expect(await memory.list(query: marker), isEmpty);
      expect((await memory.resolve(fact.ref)).code, MemoryCode.storageFailed);
      expect((await memory.resolve(fact.id)).fact, isNull);
      expect(await memory.overview(), isNull);
      expect(await memory.factsHash(locale: 'nl'), isEmpty);
      expect(await memory.overviewIsStale(locale: 'nl'), isFalse);
      expect(await memory.relevantFor('Welke $marker films?'), isEmpty);
      expect((await memory.remember('Laatste $marker feit')).code, MemoryCode.storageFailed);
      expect((await memory.update(fact.id, value: 'Nog een $marker feit')).code, MemoryCode.storageFailed);
      expect((await memory.delete(fact.id)).code, MemoryCode.storageFailed);

      final messages = logged();
      expect(messages.where((m) => m.contains('Memory storage failed')).length, greaterThanOrEqualTo(13));
      for (final message in messages) {
        for (final secret in [marker, fact.id, fact.ref, 'raw-id', 'samenvatting', 'profile-a']) {
          expect(message.contains(secret), isFalse, reason: message);
        }
      }
    });
  });
}
