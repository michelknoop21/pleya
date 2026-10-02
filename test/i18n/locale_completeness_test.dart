import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

class _JsonDuplicateFinder {
  _JsonDuplicateFinder(this.source);

  final String source;
  final duplicates = <String>[];
  var _offset = 0;

  void scan() {
    _value('');
    _space();
    if (_offset != source.length) throw FormatException('Unexpected JSON after offset $_offset');
  }

  void _value(String path) {
    _space();
    if (_peek('{')) {
      _object(path);
    } else if (_peek('[')) {
      _array(path);
    } else if (_peek('"')) {
      _string();
    } else {
      while (_offset < source.length && !',]} \r\n\t'.contains(source[_offset])) {
        _offset++;
      }
    }
  }

  void _object(String path) {
    _expect('{');
    _space();
    final keys = <String>{};
    if (_take('}')) return;
    while (true) {
      final key = _string();
      final keyPath = path.isEmpty ? key : '$path.$key';
      if (!keys.add(key)) duplicates.add(keyPath);
      _space();
      _expect(':');
      _value(keyPath);
      _space();
      if (_take('}')) return;
      _expect(',');
      _space();
    }
  }

  void _array(String path) {
    _expect('[');
    _space();
    if (_take(']')) return;
    var index = 0;
    while (true) {
      _value('$path[$index]');
      index++;
      _space();
      if (_take(']')) return;
      _expect(',');
    }
  }

  String _string() {
    _space();
    final start = _offset;
    _expect('"');
    var escaped = false;
    while (_offset < source.length) {
      final char = source[_offset++];
      if (!escaped && char == '"') {
        return jsonDecode(source.substring(start, _offset)) as String;
      }
      escaped = !escaped && char == '\\';
      if (char != '\\') escaped = false;
    }
    throw const FormatException('Unterminated JSON string');
  }

  void _space() {
    while (_offset < source.length && ' \r\n\t'.contains(source[_offset])) {
      _offset++;
    }
  }

  bool _peek(String char) => _offset < source.length && source[_offset] == char;

  bool _take(String char) {
    if (!_peek(char)) return false;
    _offset++;
    return true;
  }

  void _expect(String char) {
    if (!_take(char)) throw FormatException('Expected $char at offset $_offset');
  }
}

/// Every English key has a Dutch counterpart, in every section.
///
/// slang's `fallback_strategy: base_locale` means a key that only exists in
/// `en.i18n.json` silently renders English text in a Dutch app. Nothing
/// crashes when that happens, so only a check like this catches it — the five
/// log-upload messages shipped English-only for two builds exactly this way.
/// The seerr-specific test predates this one and stays as documentation of
/// where the pattern was first caught.
///
/// Deliberately en→nl only. The other fourteen locales are community
/// translations that trail by design; Dutch is the maintainer's own locale
/// and has no excuse to trail.
void main() {
  Map<String, dynamic> load(String locale) {
    final file = File('lib/i18n/$locale.i18n.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  List<String> missingKeys(Map<String, dynamic> base, Map<String, dynamic> other, String prefix) {
    final missing = <String>[];
    for (final entry in base.entries) {
      final path = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
      final value = entry.value;
      final counterpart = other[entry.key];
      if (value is Map<String, dynamic>) {
        if (counterpart is Map<String, dynamic>) {
          missing.addAll(missingKeys(value, counterpart, path));
        } else {
          missing.add('$path (whole section)');
        }
      } else if (counterpart == null) {
        missing.add(path);
      }
    }
    return missing;
  }

  test('every English key has a Dutch counterpart', () {
    final missing = missingKeys(load('en'), load('nl'), '');

    expect(
      missing,
      isEmpty,
      reason:
          'These keys fall back to English in the Dutch UI. Add each one to '
          'lib/i18n/nl.i18n.json and run scripts/codegen.sh.\n${missing.join('\n')}',
    );
  });

  test('locale JSON files contain no duplicate keys inside an object', () {
    final files = Directory('lib/i18n').listSync().whereType<File>().where((file) => file.path.endsWith('.i18n.json'))
      ..toList();
    final duplicates = <String>[];
    for (final file in files) {
      final finder = _JsonDuplicateFinder(file.readAsStringSync())..scan();
      duplicates.addAll(finder.duplicates.map((path) => '${file.path}: $path'));
    }

    expect(duplicates, isEmpty, reason: 'Duplicate JSON keys are silently overwritten:\n${duplicates.join('\n')}');
  });
}
