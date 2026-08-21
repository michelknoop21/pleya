/// Parse helpers shared by the Pleya Protocol wire types.
///
/// Deliberately strict. A required field that is missing or carries the wrong
/// type is a contract violation, and a parser that fills in a default there
/// turns a server bug into a screen that quietly shows the wrong thing. The
/// one place leniency is correct is an unknown enum value on a field the
/// contract marks `x-unknown-safe`, and that is handled by the enums
/// themselves rather than here.
library;

import 'pleya_wire.dart' show PleyaWireFormatException;

Never fail(String what) => throw PleyaWireFormatException(what);

Map<String, dynamic> obj(Object? raw, String what) =>
    raw is Map<String, dynamic> ? raw : fail('$what is not an object');

String str(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String ? value : fail('$key is missing or not a string');
}

String? strOrNull(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String ? value : null;
}

int integer(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is int ? value : fail('$key is missing or not an integer');
}

int? integerOrNull(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is int ? value : null;
}

double? doubleOrNull(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is num ? value.toDouble() : null;
}

bool boolean(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is bool ? value : fail('$key is missing or not a boolean');
}

/// A boolean the contract declares with a default. Absent means the default,
/// which is not the same as a missing required field.
bool booleanOr(Map<String, dynamic> json, String key, {required bool orElse}) {
  final value = json[key];
  return value is bool ? value : orElse;
}

/// A boolean the contract marks optional. Absent stays absent: the caller has
/// to be able to tell "the server did not say" from "the server said false".
bool? booleanOrNull(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is bool ? value : null;
}

/// RFC 3339 in UTC per the contract. A timestamp that will not parse is a
/// contract violation, not something to paper over with the current time.
DateTime timestamp(Map<String, dynamic> json, String key) {
  final raw = str(json, key);
  return DateTime.tryParse(raw)?.toUtc() ?? fail('$key is not an RFC 3339 timestamp: "$raw"');
}

List<Map<String, dynamic>> objectList(Object? raw, String what) {
  if (raw == null) return const [];
  if (raw is! List) fail('$what is not an array');
  return [for (final element in raw) obj(element, '$what element')];
}
