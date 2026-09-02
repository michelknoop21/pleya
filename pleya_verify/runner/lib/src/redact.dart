/// A Dart port of `LogRedactionManager`'s static denylist
/// (`lib/utils/log_redaction_manager.dart`), for redacting evidence-bundle
/// logs the runner captures itself (e.g. `driver.log`) — text this
/// process reads cold, with no access to the app's in-memory registered-
/// token/URL set. That registration layer (`registerToken`/
/// `registerServerUrl`) has no equivalent here for exactly that reason;
/// everything below is the pattern-based, always-on part of the app's
/// rules, in the same order the app applies them so a string containing
/// no registered value redacts identically on both sides.
///
/// `test/redact_test.dart` and the app's own
/// `test/utils/log_redaction_manager_test.dart`-adjacent parity test both
/// read `pleya_verify/redact/cases.json` — the shared vectors that keep
/// the two from drifting apart.
library;

final RegExp _ipv4Pattern = RegExp(r'\b(\d{1,3})([.-])(\d{1,3})\2(\d{1,3})\2(\d{1,3})\b');

const String _secretNames =
    'api[_-]?key|access[_-]?token|refresh[_-]?token|id[_-]?token|auth[_-]?token|'
    'token|secret|password|passwd|pwd|credential|signature|sig|session[_-]?id|'
    'client[_-]?secret|device[_-]?token|x-plex-token';

final RegExp _plexTokenQueryParam = RegExp(r'X-Plex-Token=[^&#\s]+', caseSensitive: false);
final RegExp _jellyfinApiKeyQueryParam = RegExp(r'api_key=[^&#\s]+', caseSensitive: false);
final RegExp _jellyfinQuickConnectSecretQueryParam = RegExp(r'secret=[^&#\s]+', caseSensitive: false);
final RegExp _embyTokenHeader = RegExp(r'X-Emby-Token[:=]\s*[^,;&#\s"]+', caseSensitive: false);
final RegExp _mediaBrowserTokenHeader = RegExp(r'Token="[^"]+"', caseSensitive: false);

final RegExp _secretQueryParam = RegExp(
  r'(?<![A-Za-z0-9])((?:' + _secretNames + r')\s*=\s*)(?!\[REDACTED)[^&#\s"\\]+',
  caseSensitive: false,
);

final RegExp _secretQuotedField = RegExp(
  r'(?<![A-Za-z0-9])((?:' + _secretNames + r')\s*=\s*")(?!\[REDACTED)[^"]*"',
  caseSensitive: false,
);

final RegExp _schemeCredential = RegExp(
  r'(?<![A-Za-z0-9])((?:authorization|proxy-authorization)\s*[:=]\s*'
  r'(?:bearer|basic|digest|token|apikey)\s+)(?!\[REDACTED)[^\s,;]+',
  caseSensitive: false,
);

final RegExp _credentialHeader = RegExp(
  r'(?<![A-Za-z0-9])((?:authorization|proxy-authorization|x-api-key|x-auth-token|'
  r'cookie|set-cookie)\s*[:=]\s*)(?![^\n\r]*\[REDACTED)[^\n\r]+',
  caseSensitive: false,
);

/// Redacts known-sensitive patterns from evidence-bundle log text. Order
/// matches `LogRedactionManager.redact()` exactly (minus the registered-
/// value pass, which this process has nothing to register into).
String redact(String message) {
  var redacted = message.replaceAllMapped(
    _ipv4Pattern,
    (m) => '${m.group(1)}${m.group(2)}x${m.group(2)}x${m.group(2)}${m.group(5)}',
  );

  redacted = redacted.replaceAll(_plexTokenQueryParam, 'X-Plex-Token=[REDACTED]');
  redacted = redacted.replaceAll(_jellyfinApiKeyQueryParam, 'api_key=[REDACTED]');
  redacted = redacted.replaceAll(_jellyfinQuickConnectSecretQueryParam, 'secret=[REDACTED]');
  redacted = redacted.replaceAllMapped(_embyTokenHeader, (m) {
    final value = m.group(0)!;
    final separator = value.contains(':') ? ':' : '=';
    return 'X-Emby-Token$separator [REDACTED]';
  });
  redacted = redacted.replaceAll(_mediaBrowserTokenHeader, 'Token="[REDACTED]"');

  redacted = redacted.replaceAllMapped(_secretQueryParam, (m) => '${m.group(1)}[REDACTED]');
  redacted = redacted.replaceAllMapped(_secretQuotedField, (m) => '${m.group(1)}[REDACTED]"');
  redacted = redacted.replaceAllMapped(_schemeCredential, (m) => '${m.group(1)}[REDACTED]');
  redacted = redacted.replaceAllMapped(_credentialHeader, (m) => '${m.group(1)}[REDACTED]');

  return redacted;
}

/// Every field-name alternative [_isSecretKey] matches on, including the
/// header names outside [_secretNames] proper.
const String _secretKeyNames =
    '$_secretNames|authorization|proxy-authorization|x-api-key|x-auth-token|cookie|set-cookie';

/// [_secretKeyNames], each alternative split into its underscore-delimited
/// word sequence — `access[_-]?token` -> `['access', 'token']`,
/// `x-plex-token` -> `['x', 'plex', 'token']`. The structural counterpart to
/// [redact]'s pattern matching, driving [_isSecretKey]'s word-subsequence
/// check rather than an exact full-name match.
final List<List<String>> _secretKeySegmentSequences = _secretKeyNames
    .split('|')
    .map((alt) => alt.replaceAll('[_-]?', '_').replaceAll('-', '_').split('_').where((s) => s.isNotEmpty).toList())
    .toList();

/// Splits a JSON key into lowercase, underscore/hyphen/case-boundary
/// delimited words: `userAccessToken` and `server-api-key` both become
/// `['user', 'access', 'token']`-shaped lists, the same normal form
/// `_secretKeySegmentSequences` was built in.
List<String> _keySegments(String key) {
  final snake = key
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
      .replaceAll(RegExp(r'[-\s]+'), '_')
      .toLowerCase();
  return snake.split('_').where((s) => s.isNotEmpty).toList();
}

/// Whether [needle] occurs in [segments] as a contiguous run of whole words
/// — `['access', 'token']` matches `['user', 'access', 'token']` (from
/// `userAccessToken`) but not `['tokenizer']` (no case boundary to split on,
/// so it stays one word and never collides with the bare `token` rule).
bool _containsWordSequence(List<String> segments, List<String> needle) {
  if (needle.isEmpty || needle.length > segments.length) return false;
  for (var i = 0; i <= segments.length - needle.length; i++) {
    if (Iterable.generate(needle.length, (j) => segments[i + j]).toList().join('_') == needle.join('_')) return true;
  }
  return false;
}

/// A field name whose *value* is a credential regardless of what the value
/// looks like — the structural counterpart to [redact]'s pattern matching.
///
/// Word-boundary matching, not a substring or exact-name match: a composite
/// field like `oldPassword`, `userAccessToken` or `server-api-key` redacts
/// the same as its bare form would, while a key that merely contains one of
/// these words as part of a single, unsplit word (`tokenizer`,
/// `passwordless` — neither has a case boundary or separator to split on)
/// is left alone: only a whole word (or whole word sequence) match counts.
bool _isSecretKey(String key) {
  final segments = _keySegments(key);
  if (segments.isEmpty) return false;
  return _secretKeySegmentSequences.any((needle) => _containsWordSequence(segments, needle));
}

/// Redacts a decoded JSON value in place of its encoded text.
///
/// [redact] alone is wrong for JSON, in both directions. It is *lossy*:
/// `X-Plex-Token=[^&#\s]+` has no reason to stop at a quote, so on an
/// encoded line it eats the closing `"}` too and leaves invalid JSON in an
/// evidence file meant to be machine-readable. And it is *incomplete*:
/// those patterns want `header: value`, while JSON writes
/// `"Authorization":"Bearer …"`, where the quote between the colon and the
/// value defeats every one of them — a real token would have travelled into
/// the bundle untouched.
///
/// So: walk the structure, apply [redact] to each string on its own (where
/// the patterns work as designed and encoding happens afterwards), and
/// replace outright any value whose *key* names a credential.
Object? redactJson(Object? value) {
  if (value is String) return redact(value);
  if (value is List) return [for (final item in value) redactJson(item)];
  if (value is Map) {
    return {
      for (final entry in value.entries)
        '${entry.key}': _isSecretKey('${entry.key}') ? '[REDACTED]' : redactJson(entry.value),
    };
  }
  return value;
}
