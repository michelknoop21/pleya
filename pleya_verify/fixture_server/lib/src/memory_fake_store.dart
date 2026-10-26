import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Contract-shaped state for native UI runs. Authorization stays in the routing
/// kernel; the real Go tests own validation parity and concurrent SQL locking.
class MemoryFakeStore {
  MemoryFakeStore(this.subject, this.now) : epoch = _uuid('$subject/0');
  final String subject;
  final DateTime Function() now;
  String epoch;
  int revision = 0;
  int _resets = 0;
  final Map<String, Map<String, dynamic>> _facts = {};
  final Set<String> _deleted = {};

  Map<String, dynamic> get snapshot => {'epoch': epoch, 'revision': revision, 'facts': _facts.values.toList()};

  http.Response handle(http.Request request, {required bool clear}) {
    if (request.method == 'GET' && !clear) return _json(snapshot);
    if ((!clear && request.method != 'PUT') || (clear && request.method != 'POST')) {
      return _error('memory.invalid', 405);
    }
    if (request.bodyBytes.length > 256 * 1024) return _error('memory.too_large', 413);
    try {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final fields = clear ? {'epoch', 'base_revision'} : {'epoch', 'base_revision', 'facts'};
      if (body.length != fields.length ||
          !fields.containsAll(body.keys) ||
          body['epoch'] is! String ||
          body['base_revision'] is! int ||
          (body['base_revision'] as int) < 0 ||
          (body['base_revision'] as int) > 9007199254740991) {
        return _error('memory.invalid', 400);
      }
      if (body['epoch'] != epoch) return _error('memory.epoch_changed', 409);
      if (body['base_revision'] != revision) return _error('memory.conflict', 409);
      if (clear) {
        epoch = _uuid('$subject/${++_resets}');
        revision++;
        _facts.clear();
        _deleted.clear();
        return _json(snapshot);
      }
      final input = body['facts'] as List;
      if (input.length > 200) return _error('memory.limit_reached', 409);
      final next = <String, Map<String, dynamic>>{};
      final keys = <String>{};
      for (final raw in input) {
        final fact = raw as Map<String, dynamic>;
        if (fact.length != 4 || !{'id', 'category', 'value', 'source'}.containsAll(fact.keys)) {
          return _error('memory.invalid', 400);
        }
        final id = (fact['id'] as String).toLowerCase();
        fact['id'] = id;
        final value = fact['value'] as String;
        if (!_uuidShape.hasMatch(id) ||
            value.isEmpty ||
            value.trim() != value ||
            value.runes.length > 200 ||
            _controls.hasMatch(value) ||
            !{'preference', 'dislike', 'habit', 'other'}.contains(fact['category']) ||
            !{'user_explicit', 'assistant_confirmed', 'settings_manual'}.contains(fact['source'])) {
          return _error('memory.invalid', 400);
        }
        final key = _valueKey(value);
        if (key.isEmpty) return _error('memory.invalid', 400);
        if (_deleted.contains(id)) return _error('memory.deleted', 409);
        if (next.containsKey(id) || !keys.add(key)) return _error('memory.duplicate', 409);
        final previous = _facts[id];
        final unchanged = previous != null && fact.entries.every((e) => previous[e.key] == e.value);
        final at = now().add(Duration(milliseconds: revision + 1)).toUtc().toIso8601String();
        next[id] = {
          ...fact,
          'created_at': previous?['created_at'] ?? at,
          'updated_at': unchanged ? previous['updated_at'] : at,
        };
      }
      _deleted.addAll(_facts.keys.where((id) => !next.containsKey(id)));
      _facts
        ..clear()
        ..addAll(next);
      revision++;
      return _json(snapshot);
    } catch (_) {
      return _error('memory.invalid', 400);
    }
  }

  static final _uuidShape = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  static final _controls = RegExp(
    r'[\u0000-\u001F\u007F-\u009F\u200E\u200F\u2028\u2029\u202A-\u202E\u2066-\u2069\uFEFF]',
  );
  static http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: const {'content-type': 'application/json', 'cache-control': 'no-store'},
  );
  static http.Response _error(String code, int status) => _json({
    'error': {'code': code, 'message': 'memory request refused', 'retryable': false},
  }, status);

  static String _uuid(String key) {
    final hash = sha256.convert(utf8.encode(key)).toString();
    return '${hash.substring(0, 8)}-${hash.substring(8, 12)}-4${hash.substring(13, 16)}-8${hash.substring(17, 20)}-${hash.substring(20, 32)}';
  }

  static String _valueKey(String value) {
    const accented = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿāăąćĉċčďēĕėęěĝğġģĥĩīĭįĵķĺļľńņňōŏőŕŗřśŝşšţťũūŭůűųŵŷźżž';
    const unaccented = 'aaaaaaceeeeiiiinooooouuuuyyaaaccccdeeeeegggghiiiijklllnnnooorrrssssttuuuuuuwyzzz';
    final folds = {for (var i = 0; i < accented.length; i++) accented.codeUnitAt(i): unaccented.codeUnitAt(i)};
    final lowered = value
        .replaceAll(RegExp(r'[\u00AD\u061C\u200B-\u200D\u2060\uFE00-\uFE0F\u{E0100}-\u{E01EF}]', unicode: true), '')
        .toLowerCase();
    return String.fromCharCodes([for (final unit in lowered.codeUnits) folds[unit] ?? unit])
        .replaceAll(RegExp(r'[\u0300-\u036F]'), '')
        .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
