import 'dart:convert';

import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/services/pleya_server_api_cache.dart';

import 'pleya_fake_server.dart';

void main() {
  test('account cache namespace hydrates the physical server identity without decrypting credentials', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    PleyaServerApiCache.initialize(db);
    final fake = PleyaFakeServer();
    fake.addItem(id: 'movie', kind: 'movie', title: 'Offline', durationMs: 60000);
    await db
        .into(db.connections)
        .insert(
          ConnectionsCompanion.insert(
            id: 'opaque-account-connection',
            kind: 'pleyaServer',
            displayName: 'Account A',
            configJson: jsonEncode({
              'serverId': 'physical-server',
              'serverName': 'My server',
              'refreshToken': 'enc:v1:unreadable-test-credential',
            }),
            createdAt: 0,
          ),
        );
    final cache = PleyaServerApiCache.instance;
    await cache.put(ServerId('opaque-account-connection'), '/items/movie', fake.items['movie']!);
    await cache.pinForOffline(ServerId('opaque-account-connection'), 'movie');

    final metadata = await cache.getMetadata(ServerId('opaque-account-connection'), 'movie');
    expect(metadata?.serverId, 'physical-server');
    expect(metadata?.serverName, 'My server');
    final pinned = await cache.getAllPinnedMetadata();
    expect(pinned.keys, ['physical-server:movie']);
    expect(pinned.values.single.serverId, 'physical-server');
    await db
        .into(db.downloadedMedia)
        .insert(
          DownloadedMediaCompanion.insert(
            serverId: 'physical-server',
            clientScopeId: const Value('opaque-account-connection'),
            ratingKey: 'movie',
            globalKey: 'physical-server:movie',
            type: 'movie',
            status: 3,
          ),
        );
    await db.delete(db.connections).go();
    expect((await cache.getMetadata(ServerId('opaque-account-connection'), 'movie'))?.serverId, 'physical-server');
    expect((await cache.getAllPinnedMetadata()).keys, ['physical-server:movie']);
  });
}
