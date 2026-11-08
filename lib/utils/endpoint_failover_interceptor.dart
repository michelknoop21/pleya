import '../utils/app_logger.dart';

/// Maintains the list of endpoints we can cycle through when one fails.
class EndpointFailoverManager {
  EndpointFailoverManager(List<String> urls) {
    _setEndpoints(urls);
  }

  late List<String> _endpoints;
  int _currentIndex = 0;

  /// Incremented every time the active endpoint changes. Requests stamped with
  /// an older generation should not trigger additional failover cascades.
  int _generation = 0;
  int get generation => _generation;

  List<String> get endpoints => List.unmodifiable(_endpoints);

  String get current => _endpoints[_currentIndex];

  /// Every other endpoint, preferred-first: the cascade's candidates after
  /// [failedUrl] failed. Walking the whole list (instead of one step down from
  /// the current index) means a failure on the last entry still tries the
  /// earlier ones before the server counts as exhausted.
  List<String> alternativesTo(String failedUrl) => [
    for (final url in _endpoints)
      if (url != failedUrl) url,
  ];

  /// Make [url] the active endpoint (it must be in the list).
  void switchTo(String url) {
    final index = _endpoints.indexOf(url);
    if (index < 0 || index == _currentIndex) return;
    _currentIndex = index;
    _generation++;
  }

  /// Reset back to the first (preferred) endpoint. Called when all endpoints
  /// are exhausted so the next failure cycle starts from the best candidate.
  String? resetToFirst() {
    if (_currentIndex != 0) {
      _currentIndex = 0;
      _generation++;
      appLogger.d('Failover endpoint list reset to first candidate');
      return _endpoints[_currentIndex];
    }
    return null;
  }

  /// Replace the endpoint list and optionally set the active endpoint.
  void reset(List<String> urls, {String? currentBaseUrl}) {
    _setEndpoints(urls);
    if (currentBaseUrl != null) {
      final index = _endpoints.indexOf(currentBaseUrl);
      _currentIndex = index >= 0 ? index : 0;
    } else {
      _currentIndex = 0;
    }
    _generation++;
  }

  void _setEndpoints(List<String> urls) {
    final sanitized = <String>[];
    final seen = <String>{};
    for (final url in urls) {
      if (url.isEmpty || seen.contains(url)) continue;
      seen.add(url);
      sanitized.add(url);
    }
    if (sanitized.isEmpty) {
      throw ArgumentError('At least one endpoint is required');
    }
    _endpoints = sanitized;
    _currentIndex = _currentIndex.clamp(0, _endpoints.length - 1);
  }
}
