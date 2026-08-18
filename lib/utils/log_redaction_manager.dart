import 'url_utils.dart';

class LogRedactionManager {
  // Size limits for bounded sets (FIFO eviction when exceeded)
  static const int _maxTokens = 50;
  static const int _maxUrls = 20;
  static const int _maxCustomValues = 50;

  // Use LinkedHashSet for FIFO ordering
  static final Set<String> _tokens = <String>{};
  static final Set<String> _urls = <String>{};
  static final Set<String> _customValues = <String>{};

  static final RegExp _ipv4Pattern = RegExp(r'\b(\d{1,3})([.-])(\d{1,3})\2(\d{1,3})\2(\d{1,3})\b');
  static final RegExp _ipv4HostPattern = RegExp(r'^\d{1,3}([.-]\d{1,3}){3}$');

  /// Parameter and field names that carry a credential. Shared by the query
  /// string and the header rules so the two cannot drift apart.
  static const String _secretNames =
      'api[_-]?key|access[_-]?token|refresh[_-]?token|id[_-]?token|auth[_-]?token|'
      'token|secret|password|passwd|pwd|credential|signature|sig|session[_-]?id|'
      'client[_-]?secret|device[_-]?token|x-plex-token';

  /// Pattern-based catch-all for Plex tokens in query strings/headers.
  static final RegExp _plexTokenQueryParam = RegExp(r'X-Plex-Token=[^&#\s]+', caseSensitive: false);

  /// Pattern-based catch-all for Jellyfin tokens carried as `api_key=` query
  /// params (URL-embedded auth path used for thumbnails and direct streams).
  static final RegExp _jellyfinApiKeyQueryParam = RegExp(r'api_key=[^&#\s]+', caseSensitive: false);

  /// Pattern-based catch-all for Jellyfin Quick Connect auth handles.
  static final RegExp _jellyfinQuickConnectSecretQueryParam = RegExp(r'secret=[^&#\s]+', caseSensitive: false);

  /// Pattern-based catch-all for the legacy Emby/Jellyfin header form.
  static final RegExp _embyTokenHeader = RegExp(r'X-Emby-Token[:=]\s*[^,;&#\s"]+', caseSensitive: false);

  /// Pattern-based catch-all for the `Authorization: MediaBrowser ... Token="..."`
  /// header that Jellyfin's SDK and Findroid both send.
  static final RegExp _mediaBrowserTokenHeader = RegExp(r'Token="[^"]+"', caseSensitive: false);

  /// Default-deny for credentials carried in a query string.
  ///
  /// The patterns above name one vendor each, and registration only covers
  /// values somebody remembered to register, so every new integration leaks in
  /// full until someone notices. Tautulli did exactly that: its parameter is
  /// `apikey=`, which matches neither `api_key=` nor any registered value, so a
  /// master key that opens `sql` and `delete_all_user_history` ended up
  /// verbatim in a log the user uploaded to a public relay.
  ///
  /// Matching on the parameter *name* turns that around: a new backend is
  /// covered before anyone thinks about it, and the name survives so the log
  /// still shows which call was made. Deliberately not every parameter, because
  /// `cmd=`, `rating_key=` and `count=` are what make a log worth reading.
  ///
  /// The lookbehind replaces a word boundary, which does not hold after an
  /// underscore: `pms_token=` and `user_token=` would otherwise slip through
  /// while `apikey=` was caught. The lookahead leaves an existing placeholder
  /// alone so a registered value keeps its more specific label.
  static final RegExp _secretQueryParam = RegExp(
    r'(?<![A-Za-z0-9])((?:' + _secretNames + r')\s*=\s*)(?!\[REDACTED)[^&#\s"\\]+',
    caseSensitive: false,
  );

  /// The same names again, but as a quoted field inside a structured header:
  /// `Authorization: MediaBrowser Client="Pleya", Token="..."`. Only the secret
  /// field goes; the surrounding metadata says which client made the call and
  /// is worth keeping.
  static final RegExp _secretQuotedField = RegExp(
    r'(?<![A-Za-z0-9])((?:' + _secretNames + r')\s*=\s*")(?!\[REDACTED)[^"]*"',
    caseSensitive: false,
  );

  /// A bare credential after an auth scheme: `Authorization: Bearer eyJ...`.
  /// The scheme stays, because knowing that a request was Bearer rather than
  /// Basic costs nothing and helps.
  static final RegExp _schemeCredential = RegExp(
    r'(?<![A-Za-z0-9])((?:authorization|proxy-authorization)\s*[:=]\s*'
    r'(?:bearer|basic|digest|token|apikey)\s+)(?!\[REDACTED)[^\s,;]+',
    caseSensitive: false,
  );

  /// Last resort for an auth header nothing above recognised: take the whole
  /// value. The lookahead spares any line where something was already
  /// redacted, so `Authorization: Bearer [REDACTED]` keeps its scheme and the
  /// MediaBrowser form keeps its `Client="..."` metadata.
  static final RegExp _credentialHeader = RegExp(
    r'(?<![A-Za-z0-9])((?:authorization|proxy-authorization|x-api-key|x-auth-token|'
    r'cookie|set-cookie)\s*[:=]\s*)(?![^\n\r]*\[REDACTED)[^\n\r]+',
    caseSensitive: false,
  );

  // Combined regex for single-pass redaction (rebuilt on set changes)
  static RegExp? _combinedPattern;

  /// Register a server access token or Plex.tv token for redaction.
  static void registerToken(String? token) {
    final normalized = _normalize(token);
    if (normalized == null) return;

    _addWithLimit(_tokens, normalized, _maxTokens);

    // Tokens often appear URL encoded in query params.
    final encoded = Uri.encodeQueryComponent(normalized);
    if (encoded != normalized) {
      _addWithLimit(_tokens, encoded, _maxTokens);
    }

    _rebuildCombinedPattern();
  }

  /// Register the server/base URL currently in use.
  static void registerServerUrl(String? url) {
    final normalized = _normalize(url);
    if (normalized == null) return;

    final uri = Uri.tryParse(normalized);
    final host = uri?.host;
    if (host != null && host.isNotEmpty && _isIpv4Like(host)) {
      // Do not register full IP-based URLs; regex redaction handles them.
      return;
    }

    if (host == null && _isIpv4Like(normalized)) {
      return;
    }

    final strippedSlash = stripTrailingSlash(normalized);

    if (strippedSlash.isNotEmpty) {
      _addWithLimit(_urls, strippedSlash, _maxUrls);
      _addWithLimit(_urls, '$strippedSlash/', _maxUrls);
    }

    // Capture origin and host-level strings as well to cover most cases.
    if (uri != null && uri.host.isNotEmpty) {
      final origin = '${uri.scheme.isEmpty ? 'https' : uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
      _addWithLimit(_urls, origin, _maxUrls);
      if (origin.endsWith('/')) {
        _addWithLimit(_urls, origin.substring(0, origin.length - 1), _maxUrls);
      }
    }

    _rebuildCombinedPattern();
  }

  /// Convenience: register a server's URL and access token together.
  /// Call this before any HTTP traffic so the very first probe URL doesn't
  /// leak credentials verbatim.
  static void registerServer(String? url, String? token) {
    registerServerUrl(url);
    registerToken(token);
  }

  /// Register other sensitive values that need redaction.
  static void registerCustomValue(String? value) {
    final normalized = _normalize(value);
    if (normalized == null) return;
    _addWithLimit(_customValues, normalized, _maxCustomValues);
    _rebuildCombinedPattern();
  }

  /// Reset any tracked sensitive values (e.g., on logout).
  static void clearTrackedValues() {
    _tokens.clear();
    _urls.clear();
    _customValues.clear();
    _combinedPattern = null;
  }

  /// Redact known sensitive values from the provided message.
  ///
  /// Order matters. Registered values go first so a token the app knows about
  /// keeps its more specific `[REDACTED_TOKEN]` label instead of disappearing
  /// into the generic net; every rule after it refuses to touch a value that
  /// already starts with a placeholder.
  static String redact(String message) {
    var redacted = message.replaceAllMapped(
      _ipv4Pattern,
      (match) => _maskIpv4(match.group(1)!, match.group(2)!, match.group(5)!),
    );

    if (_combinedPattern != null) {
      redacted = redacted.replaceAllMapped(_combinedPattern!, (match) {
        final value = match.group(0)!;
        if (_tokens.contains(value)) return '[REDACTED_TOKEN]';
        if (_urls.contains(value)) return '[REDACTED_URL]';
        return '[REDACTED]';
      });
    }

    redacted = redacted.replaceAll(_plexTokenQueryParam, 'X-Plex-Token=[REDACTED]');

    redacted = redacted.replaceAll(_jellyfinApiKeyQueryParam, 'api_key=[REDACTED]');
    redacted = redacted.replaceAll(_jellyfinQuickConnectSecretQueryParam, 'secret=[REDACTED]');
    redacted = redacted.replaceAllMapped(_embyTokenHeader, (m) {
      final value = m.group(0)!;
      final separator = value.contains(':') ? ':' : '=';
      return 'X-Emby-Token$separator [REDACTED]';
    });
    redacted = redacted.replaceAll(_mediaBrowserTokenHeader, 'Token="[REDACTED]"');

    // The default-deny net, for everything no vendor rule and no registration
    // covers. This is what a new integration falls into before anyone has
    // thought about it.
    redacted = redacted.replaceAllMapped(_secretQueryParam, (m) => '${m.group(1)}[REDACTED]');
    redacted = redacted.replaceAllMapped(_secretQuotedField, (m) => '${m.group(1)}[REDACTED]"');
    redacted = redacted.replaceAllMapped(_schemeCredential, (m) => '${m.group(1)}[REDACTED]');
    redacted = redacted.replaceAllMapped(_credentialHeader, (m) => '${m.group(1)}[REDACTED]');

    return redacted;
  }

  /// Rebuild the combined regex pattern from all tracked values.
  static void _rebuildCombinedPattern() {
    final allLiterals = [
      ..._tokens.map(RegExp.escape),
      ..._urls.map(RegExp.escape),
      ..._customValues.map(RegExp.escape),
    ];

    if (allLiterals.isEmpty) {
      _combinedPattern = null;
      return;
    }

    // Sort by length descending so longer matches are preferred
    allLiterals.sort((a, b) => b.length.compareTo(a.length));
    _combinedPattern = RegExp(allLiterals.join('|'));
  }

  /// Add value to set with FIFO eviction if limit exceeded.
  static void _addWithLimit(Set<String> set, String value, int maxSize) {
    if (set.contains(value)) return;

    while (set.length >= maxSize) {
      set.remove(set.first);
    }
    set.add(value);
  }

  static String? _normalize(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  static bool _isIpv4Like(String value) {
    return _ipv4HostPattern.hasMatch(value);
  }

  static String _maskIpv4(String first, String separator, String last) {
    return '$first$separator'
        'x$separator'
        'x$separator'
        '$last';
  }
}
