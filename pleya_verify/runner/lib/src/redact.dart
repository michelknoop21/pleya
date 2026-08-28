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
