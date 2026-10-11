import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/services/memory/memory_service.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/utils/app_logger.dart';

import '../../test_helpers/prefs.dart';

/// No log line on the memory path carries a fact, a key, a question, an
/// overview or an id. The scanner reads every source under
/// `lib/services/memory/`, so a new file there is covered without being
/// listed.
const _allowed = {'e.runtimeType'};

final _logStatement = RegExp(r'appLogger\.[a-z]+\(([\s\S]*?)\);');
final _interpolation = RegExp(r'\$\{([^}]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)');
final _otherSink = RegExp(r'\b(print|debugPrint|debugPrintStack)\(|\bdeveloper\.log\(|\bstd(out|err)\b');

List<String> _offenders(String path, String source) {
  final offenders = <String>[];
  for (final statement in _logStatement.allMatches(source)) {
    final arguments = statement.group(1)!;
    for (final expression in _interpolation.allMatches(arguments)) {
      final found = (expression.group(1) ?? expression.group(2))!.trim();
      if (!_allowed.contains(found)) offenders.add('$path: \$$found');
    }
    // `error: e` hands the logger the whole exception, message included.
    if (RegExp(r'\b(error|stackTrace):').hasMatch(arguments)) offenders.add('$path: error object');
  }
  if (_otherSink.hasMatch(source)) offenders.add('$path: writes outside appLogger');
  return offenders;
}

void main() {
  test('the scanner catches a value, a bare error and a print', () {
    expect(_offenders('x', r"appLogger.w('kept $value');"), isNotEmpty);
    expect(_offenders('x', "appLogger.w(\n  'failed \${fact.id}',\n);"), isNotEmpty);
    expect(_offenders('x', "appLogger.w('failed', error: e);"), isNotEmpty);
    expect(_offenders('x', "print('x');"), isNotEmpty);
    expect(_offenders('x', r"appLogger.w('failed: ${e.runtimeType}');"), isEmpty);
  });

  test('no memory source logs anything but an error type', () {
    final files = Directory('lib/services/memory').listSync(recursive: true).whereType<File>().toList();
    expect(files.length, greaterThanOrEqualTo(5));

    var statements = 0;
    final offenders = <String>[];
    for (final file in files) {
      final source = file.readAsStringSync();
      statements += _logStatement.allMatches(source).length;
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
  });

  test('a full run, a failing lookup included, leaves no content in the log', () async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await StorageService.getInstance();
    await SettingsService.getInstance();
    MemoryLogOutput.clearLogs();

    const marker = 'zebrastreep';
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final memory = MemoryService(database: db, profileId: 'profile-a');

    final added = await memory.add(
      value: 'Houdt van $marker films',
      category: MemoryCategory.preference,
      source: MemorySource.userExplicit,
    );
    final id = added.fact!.id;
    await memory.add(
      value: 'Houdt van $marker films',
      category: MemoryCategory.other,
      source: MemorySource.userExplicit,
    );
    await memory.add(
      value: 'Onze dochter is 8 $marker',
      category: MemoryCategory.household,
      source: MemorySource.userExplicit,
    );
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
    await memory.delete(id);
    await memory.clearAll();

    await db.close();
    expect(await memory.relevantFor('Welke $marker films zijn er?'), isEmpty);

    final messages = MemoryLogOutput.getLogs().map((e) => '${e.message} ${e.error ?? ''}').toList();
    expect(messages.where((m) => m.contains('Memory lookup failed')), isNotEmpty);
    for (final message in messages) {
      expect(message.contains(marker), isFalse, reason: message);
      expect(message.contains(id), isFalse, reason: message);
      expect(message.contains(added.fact!.ref), isFalse, reason: message);
    }
  });
}
