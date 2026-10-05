part of 'assistant_controller.dart';

// What the controller reads before an ask: whether Big P can be offered,
// and a warm model on an Ollama server.

extension _AssistantReads on AssistantController {
  Future<AssistantAvailability> _computeAvailability() async {
    if (!_rolloutEnabled) return AssistantAvailability.hidden;
    final ctx = _buildContext(null);
    if (ctx.userServers.isEmpty && ctx.requests?.client() == null) return AssistantAvailability.hidden;
    if (await _entitlement.check() != AssistantEntitlementState.entitled) return AssistantAvailability.locked;
    final AssistantProviderConfig? config;
    try {
      config = await _loadConfig();
    } on AssistantProviderStoreException {
      // An unreadable keychain is not "not configured": keep the last answer.
      // Without one (hidden is only the initial value past the checks above)
      // setup stays reachable. A save there does not write over the item it
      // could not read: it stays on this device and goes up later only into
      // an empty keychain. Every refresh reads again.
      return _availability == AssistantAvailability.hidden ? AssistantAvailability.needsSetup : _availability;
    }
    if (config == null || !config.isComplete) return AssistantAvailability.needsSetup;
    return AssistantAvailability.ready;
  }

  /// Warms the Ollama server's model while the user speaks, so the first
  /// answer does not wait for loading. Fire and forget: never blocks, never
  /// surfaces an error. Ollama Cloud and OpenRouter keep models hot already.
  Future<void> _preload() async {
    final now = _now();
    final last = _lastPreload;
    if (last != null && now.difference(last) < preloadWindow) return;
    _lastPreload = now;
    AssistantModelClient? client;
    try {
      final config = await _loadConfig();
      if (_disposed || config == null || !config.isComplete || config.kind != AssistantProviderKind.ollamaServer) {
        return;
      }
      client = _modelFor(config);
      await client.preload(keepAlive: AssistantController._preloadKeepAlive);
    } catch (e) {
      // Type only: a message could echo the server address or a header.
      appLogger.d('Assistant model preload failed', error: e.runtimeType);
    } finally {
      client?.close();
    }
  }
}
