part of 'assistant_controller.dart';

// What the greeting may offer as a start question: the capabilities the
// active profile can use on its servers right now.

extension _AssistantIdle on AssistantController {
  Future<void> _refreshIdleProfile() async {
    if (!_rolloutEnabled || _disposed) return;
    final seq = ++_idleProfileSeq;
    final ctx = _buildContext(null);
    ({bool kids, bool memory}) read;
    try {
      final kids = await ctx.kidsProfile?.call() ?? false;
      final memory = ctx.memory;
      read = (kids: kids, memory: !kids && memory != null && memory.profileCurrent && await memory.service.enabled);
    } catch (e) {
      // An unreadable switch is not "an adult profile", also not the one a
      // read answered before: the questions fall back to those of a children's
      // profile until a read succeeds.
      appLogger.d('Assistant idle profile read failed', error: e.runtimeType);
      if (!_disposed && seq == _idleProfileSeq && _idleProfile != null) {
        _idleProfile = null;
        _notify();
      }
      return;
    }
    if (_disposed || seq != _idleProfileSeq || read == _idleProfile) return;
    _idleProfile = read;
    _notify();
  }

  Set<AssistantCapability> _idleCapabilities() {
    final ctx = _buildContext(null);
    final profile = _idleProfile;
    // The memory tools are served per ask from this switch (`_beginMemory`).
    ctx.memoryTurn = AssistantMemoryTurn(enabled: profile?.memory ?? false);
    return assistantCapabilitiesFor(ctx, kids: profile?.kids ?? true, tools: _tools);
  }
}
