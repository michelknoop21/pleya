import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_kids_profile_store.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/navigation/profile_memory_sync.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_connection.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/memory/memory_service.dart';
import 'package:pleya/services/multi_server_manager.dart';

import '../services/memory/memory_test_support.dart';

class _Profile extends ChangeNotifier implements ActiveProfileProvider {
  @override
  final Profile active = Profile.local(id: 'profile-a', displayName: 'A', createdAt: DateTime.utc(2026));
  @override
  String get activeId => active.id;
  @override
  bool get isBinding => false;
  @override
  bool get lastBindingSucceeded => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Servers extends ChangeNotifier implements MultiServerProvider {
  @override
  final serverManager = MultiServerManager();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Connections extends ProfileConnectionRegistry {
  _Connections(AppDatabase db) : super(db);
  Completer<List<ProfileConnection>>? held;
  @override
  Future<List<ProfileConnection>> listForProfile(String id) async => held == null ? [] : held!.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('kids toggle blocks immediately and an old refresh cannot enable sync again', () async {
    final storage = await resetMemoryPrefs();
    await storage.setActiveProfileId('profile-a');
    final db = memoryTestDatabase();
    final memory = MemoryService(database: db, profileId: 'profile-a');
    final profile = _Profile();
    final servers = _Servers();
    final connections = _Connections(db);
    final binding = ProfileMemorySync(
      memory: memory,
      activeProfile: profile,
      multiServer: servers,
      connections: connections,
    );
    await binding.refresh();
    expect(binding.eligible, isTrue);
    connections.held = Completer<List<ProfileConnection>>();
    final stale = binding.refresh();
    await Future<void>.delayed(Duration.zero);
    var becameEligible = false;
    binding.addListener(() {
      if (binding.eligible) becameEligible = true;
    });
    await KidsProfileStore().save(true);
    expect(binding.eligible, isFalse, reason: 'No await may leave an old PUT permitted');
    connections.held!.complete([]);
    await stale;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(binding.eligible, isFalse);
    expect(becameEligible, isFalse, reason: 'The pre-toggle settings read must be discarded');
    binding.dispose();
    profile.dispose();
    servers.dispose();
    memory.dispose();
    servers.serverManager.dispose();
    await db.close();
  });
}
