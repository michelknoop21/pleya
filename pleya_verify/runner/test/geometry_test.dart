import 'dart:convert';
import 'dart:io';

import 'package:pleya_verify_runner/src/geometry.dart';
import 'package:test/test.dart';

GeoRect _rect(Map<String, Object?> json) => GeoRect.fromJson(json);

GeometryVerdict _dispatch(String function, Map<String, Object?> args) {
  switch (function) {
    case 'insideViewport':
      return insideViewport(
        _rect(args['rect'] as Map<String, Object?>),
        _rect(args['viewport'] as Map<String, Object?>),
      );
    case 'notClipped':
      return notClipped(_rect(args['rect'] as Map<String, Object?>), _rect(args['clipBounds'] as Map<String, Object?>));
    case 'notOverlapping':
      return notOverlapping(_rect(args['a'] as Map<String, Object?>), _rect(args['b'] as Map<String, Object?>));
    case 'below':
      return below(_rect(args['a'] as Map<String, Object?>), _rect(args['b'] as Map<String, Object?>));
    case 'above':
      return above(_rect(args['a'] as Map<String, Object?>), _rect(args['b'] as Map<String, Object?>));
    case 'leftOf':
      return leftOf(_rect(args['a'] as Map<String, Object?>), _rect(args['b'] as Map<String, Object?>));
    case 'rightOf':
      return rightOf(_rect(args['a'] as Map<String, Object?>), _rect(args['b'] as Map<String, Object?>));
    case 'minimumTapTarget':
      final minSize = args['minSize'];
      return minimumTapTarget(
        _rect(args['rect'] as Map<String, Object?>),
        minSize: minSize == null ? 44.0 : (minSize as num).toDouble(),
      );
    case 'sameRow':
      final tolerance = args['tolerance'];
      return sameRow(
        _rect(args['a'] as Map<String, Object?>),
        _rect(args['b'] as Map<String, Object?>),
        tolerance: tolerance == null ? 1.0 : (tolerance as num).toDouble(),
      );
    case 'sameColumn':
      final tolerance = args['tolerance'];
      return sameColumn(
        _rect(args['a'] as Map<String, Object?>),
        _rect(args['b'] as Map<String, Object?>),
        tolerance: tolerance == null ? 1.0 : (tolerance as num).toDouble(),
      );
    default:
      throw ArgumentError('unknown geometry function in cases.json: $function');
  }
}

void main() {
  final doc = jsonDecode(File('../geometry/cases.json').readAsStringSync()) as Map<String, Object?>;
  final cases = doc['cases'] as List<Object?>;

  test('at least 60 vectors, per the Fase 7 plan', () {
    expect(cases.length, greaterThanOrEqualTo(60));
  });

  group('geometry vectors', () {
    for (final raw in cases) {
      final testCase = raw as Map<String, Object?>;
      final function = testCase['function'] as String;
      final description = testCase['description'] as String;
      final args = testCase['args'] as Map<String, Object?>;
      final expectOk = testCase['expectOk'] as bool;

      test('$function: $description', () {
        final verdict = _dispatch(function, args);
        expect(verdict.ok, expectOk, reason: verdict.message);
      });
    }
  });
}
