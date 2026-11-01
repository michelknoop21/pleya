import 'dart:convert';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/unified/carried_external_ids.dart';
import 'package:pleya/utils/external_ids.dart';
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
  test('wire cache rehydrates applied evidence but never promotes old external_ids', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    PleyaServerApiCache.initialize(db);
    final fake = PleyaFakeServer();
    final legacy = fake.addItem(id: 'old', kind: 'movie', title: 'Old', externalIds: {'tmdb': 22});
    final applied = {
      ...legacy,
      'id': 'applied',
      pleyaExternalIdsSourceKey: 'applied',
      'applied_external_ids': {'tmdb': 11},
    };
    final unknown = {...legacy, 'id': 'unknown', 'applied_external_ids': null};
    final unqualifiedApplied = {
      ...legacy,
      'id': 'unqualified-applied',
      'applied_external_ids': {'tmdb': 11},
    };
    final cache = PleyaServerApiCache.instance;
    final server = ServerId('synthetic');
    for (final item in [legacy, applied, unknown, unqualifiedApplied]) {
      await cache.put(server, PleyaServerApiCache.itemEndpoint(item['id'] as String), item);
    }
    expect(externalIdsCarriedBy((await cache.getMetadata(server, 'old'))!), isNull);
    expect(externalIdsCarriedBy((await cache.getMetadata(server, 'unknown'))!), isNull);
    expect(externalIdsCarriedBy((await cache.getMetadata(server, 'unqualified-applied'))!), isNull);
    expect(externalIdsCarriedBy((await cache.getMetadata(server, 'applied'))!), const ExternalIds(tmdb: 11));
  });
  test('live cache retains the actually selected legacy source under explicit capfalse', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    PleyaServerApiCache.initialize(db);
    final fake = PleyaFakeServer();
    fake.addItem(id: 'movie', kind: 'movie', title: 'Film', externalIds: {'tmdb': 22})['applied_external_ids'] = {
      'tmdb': 11,
    };
    final client = fake.client();
    addTearDown(client.close);
    await client.refreshCapabilities();
    final live = (await client.fetchItem('movie'))!;
    final cached = (await PleyaServerApiCache.instance.getMetadata(ServerId(fake.connection().id), 'movie'))!;
    expect(externalIdsCarriedBy(live, allowLegacyPleya: true), const ExternalIds(tmdb: 22));
    expect(externalIdsCarriedBy(cached, allowLegacyPleya: true), const ExternalIds(tmdb: 22));
    expect(externalIdsCarriedBy(cached), isNull);
    expect(cached.raw?[pleyaExternalIdsSourceKey], 'legacy');
  });
}
