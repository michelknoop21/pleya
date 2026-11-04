import 'dart:async';

import 'package:flutter/widgets.dart';

import '../assistant/assistant_kids_profile_store.dart';
import '../media/ids.dart';
import '../profiles/active_profile_provider.dart';
import '../profiles/pleya_server_credentials.dart';
import '../profiles/profile_connection_registry.dart';
import '../providers/multi_server_provider.dart';
import '../services/memory/memory_service.dart';
import '../services/pleya_server_client.dart';

/// The active profile owns the one sync instance, its identity checks and polling.
class ProfileMemorySync extends ChangeNotifier with WidgetsBindingObserver {
  ProfileMemorySync({
    required MemoryService memory,
    required this.activeProfile,
    required this.multiServer,
    required this.connections,
  }) : _profileId = memory.profileId {
    sync = MemorySyncService(
      memory: memory,
      transportFor: _transportFor,
      isEligible: () => !_kids,
      isCurrent: _current,
    );
    sync.addListener(_changed);
    KidsProfileStore.changes.addListener(_kidsChanged);
    activeProfile.addListener(_refreshAndSync);
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshAndSync());
    unawaited(_start());
  }

  final ActiveProfileProvider activeProfile;
  final MultiServerProvider multiServer;
  final ProfileConnectionRegistry connections;
  final String _profileId;
  late final MemorySyncService sync;
  late final Timer _timer;
  bool _disposed = false;
  bool _kids = true;
  int _eligibilityGeneration = 0;
  bool _foreground = true;
  List<({String key, String label})> _accounts = const [];
  List<({String key, String label})> get accounts => _accounts;
  bool get eligible => !_kids && _current();

  bool _current() =>
      !_disposed &&
      _foreground &&
      activeProfile.activeId == _profileId &&
      !activeProfile.isBinding &&
      activeProfile.lastBindingSucceeded;

  Future<void> _start() async {
    try {
      await refresh();
      if (_current()) {
        await sync.load();
        await sync.sync();
      }
    } catch (_) {
      // Startup failures leave the local memory usable and are retried on resume.
    }
  }

  Future<void> refresh() async {
    if (!_current()) return;
    final generation = _eligibilityGeneration;
    final kids = await assistantIsKidsProfile(activeProfile.active);
    final joins = await connections.listForProfile(_profileId);
    if (!_current() || generation != _eligibilityGeneration) return;
    _kids = kids;
    final ids = joins.map((row) => row.connectionId).toSet();
    _accounts = [
      if (!kids)
        for (final id in multiServer.serverManager.serverIds)
          if (multiServer.getClientForServer(ServerId(id)) case final PleyaServerClient client)
            if (ids.contains(client.connection.id) &&
                client.connection.accountUserId != null &&
                const {'owner', 'admin', 'member'}.contains(client.connection.role) &&
                const PleyaServerCredentialResolver().resolve(activeProfile.active, client.connection).isHit &&
                client.wireCapabilities.assistantMemory)
              (key: client.connection.id, label: client.connection.displayName),
    ];
    _changed();
  }

  Future<MemorySyncTransport?> _transportFor(String key) async {
    await refresh();
    if (!eligible || !_accounts.any((account) => account.key == key)) return null;
    for (final id in multiServer.serverManager.serverIds) {
      final client = multiServer.getClientForServer(ServerId(id));
      if (client is PleyaServerClient && client.connection.id == key) {
        final generation = _eligibilityGeneration;
        return client.assistantMemoryTransport(
          isCurrent: () =>
              eligible &&
              generation == _eligibilityGeneration &&
              identical(multiServer.getClientForServer(ServerId(id)), client) &&
              _accounts.any((account) => account.key == key),
        );
      }
    }
    return null;
  }

  void _kidsChanged() {
    // Invalidate before awaiting preferences: an in-flight PUT must stop immediately.
    _eligibilityGeneration++;
    _kids = true;
    _accounts = const [];
    _changed();
    _refreshAndSync();
  }

  void _refreshAndSync() => unawaited(_run());
  Future<void> _run() async {
    try {
      await refresh();
      if (eligible) await sync.sync();
    } catch (_) {
      // Profile teardown and database failures must not expose personal content.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _refreshAndSync();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    KidsProfileStore.changes.removeListener(_kidsChanged);
    activeProfile.removeListener(_refreshAndSync);
    sync.removeListener(_changed);
    sync.dispose();
    super.dispose();
  }
}
