part of '../../pleya_server_client.dart';

class _PleyaMemoryTransport implements MemorySyncTransport {
  _PleyaMemoryTransport(this._client, this._isCurrent);
  final PleyaServerClient _client;
  final bool Function() _isCurrent;

  Future<Map<String, dynamic>> _request(String method, String path, [Map<String, dynamic>? body]) async {
    void check() {
      if (!_isCurrent() || _client.isOfflineMode || !_client.wireCapabilities.assistantMemory) {
        throw const MemorySyncFailure('unavailable');
      }
    }

    Future<MediaServerResponse> send() async {
      check();
      final headers = await _client._session.authHeaders();
      check();
      const timeout = MediaServerTimeouts.interactive;
      return switch (method) {
        'GET' => _client._http.get(path, headers: headers, timeout: timeout),
        'PUT' => _client._http.put(path, headers: headers, body: jsonEncode(body), timeout: timeout),
        'POST' => _client._http.post(path, headers: headers, body: jsonEncode(body), timeout: timeout),
        _ => throw const MemorySyncFailure('unavailable'),
      };
    }

    var response = await send();
    if (response.statusCode == 401) {
      check();
      _client._session.invalidateAccessToken();
      response = await send();
    }
    check();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code = PleyaError.tryParse(response.data)?.code;
      const allowed = {
        'memory.invalid',
        'memory.conflict',
        'memory.epoch_changed',
        'memory.deleted',
        'memory.limit_reached',
        'memory.duplicate',
        'memory.not_permitted',
        'memory.too_large',
      };
      throw MemorySyncFailure(allowed.contains(code) ? code! : 'unavailable');
    }
    final data = response.data;
    if (data is! Map<String, dynamic>) throw const MemorySyncFailure('invalid_snapshot');
    return data;
  }

  Future<MemorySyncSnapshot> _send(String method, String path, [Map<String, dynamic>? body]) async {
    try {
      if (!_isCurrent() || _client.isOfflineMode || !_client.wireCapabilities.assistantMemory) {
        throw const MemorySyncFailure('unavailable');
      }
      final expected = _client.connection.accountUserId;
      if (expected == null) throw const MemorySyncFailure('account_required');
      final me = await _request('GET', '/users/me');
      if (!_isCurrent() || me['id'] != expected || !const {'owner', 'admin', 'member'}.contains(me['role'])) {
        throw const MemorySyncFailure('memory.not_permitted');
      }
      final json = await _request(method, path, body);
      if (!_isCurrent()) throw const MemorySyncFailure('unavailable');
      return MemorySyncSnapshot.fromJson(json);
    } on MemorySyncFailure {
      rethrow;
    } on MediaServerHttpException catch (error) {
      final code = PleyaError.tryParse(error.responseData)?.code;
      const allowed = {
        'memory.invalid',
        'memory.conflict',
        'memory.epoch_changed',
        'memory.deleted',
        'memory.limit_reached',
        'memory.duplicate',
        'memory.not_permitted',
        'memory.too_large',
      };
      throw MemorySyncFailure(allowed.contains(code) ? code! : 'unavailable');
    } catch (_) {
      // Error bodies and decoder exceptions can quote personal text.
      throw const MemorySyncFailure('unavailable');
    }
  }

  @override
  Future<MemorySyncSnapshot> fetch() => _send('GET', '/users/me/memory');

  @override
  Future<MemorySyncSnapshot> replace({
    required String epoch,
    required int baseRevision,
    required List<MemoryFact> facts,
  }) {
    validateSyncFacts(facts);
    return _send('PUT', '/users/me/memory', {
      'epoch': epoch,
      'base_revision': baseRevision,
      'facts': [for (final fact in facts) memorySyncFactJson(fact, dates: false)],
    });
  }

  @override
  Future<MemorySyncSnapshot> clear({required String epoch, required int baseRevision}) =>
      _send('POST', '/users/me/memory/clear', {'epoch': epoch, 'base_revision': baseRevision});
}
