import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_capabilities.dart';
import 'package:pleya/assistant/assistant_memory.dart';
import 'package:pleya/assistant/assistant_playback.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/assistant/assistant_trakt_services.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/services/api_cache.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/local_folder_client.dart';
import 'package:pleya/services/memory/memory_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/pleya_server_client.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_auth_service.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya/services/recommendations/taste_profile.dart';
import 'package:pleya/services/seerr/seerr_client.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/seerr/seerr_session.dart';
import 'package:pleya/services/unified_catalog/home_custom_row_loader.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_examples.dart';

http.Response _json(Object? body, {int status = 200}) =>
    http.Response(body == null ? '' : jsonEncode(body), status, headers: const {'content-type': 'application/json'});

JellyfinClient _jellyfin({required bool admin, String id = 'jf-1'}) => JellyfinClient.forTesting(
  connection: JellyfinConnection(
    id: '$id/user-a',
    baseUrl: 'https://jellyfin.example',
    serverName: 'Jelly',
    serverMachineId: id,
    userId: 'user-a',
    userName: 'User A',
    accessToken: 'token',
    deviceId: 'device',
    isAdministrator: admin,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  ),
  httpClient: MockClient((_) async => _json(null, status: 404)),
);

Future<PleyaServerClient> _pleyaServer({required String role}) async {
  final client = PleyaServerClient.create(
    PleyaServerConnection(
      id: 'pleyaServer.srv-1',
      baseUrl: 'http://nas.lan:8832',
      serverId: 'srv-1',
      serverName: 'Zolder',
      userName: 'michel',
      refreshToken: 'rt-1',
      role: role,
      createdAt: DateTime.utc(2026, 10, 2),
    ),
    httpClientFactory: () => MockClient((request) async {
      final path = request.url.path.replaceFirst('/pleya/v1', '');
      if (path == '/auth/refresh') {
        return _json(const {
          'access_token': 'at',
          'refresh_token': 'rt-2',
          'token_type': 'bearer',
          'expires_in_ms': 900000,
        });
      }
      if (path == '/info') {
        return _json({
          'protocol': {'major': 1, 'feature_level': 1, 'profile': 'full'},
          'server': {'id': 'srv-1'},
          'capabilities': {
            'browse': true,
            'search': true,
            'artwork': true,
            'watch_state': true,
            'users': true,
            'administration': true,
          },
          'auth': {
            'methods': ['password'],
            'setup_required': false,
          },
        });
      }
      return _json(null, status: 404);
    }),
  );
  await client.refreshCapabilities();
  return client;
}

Future<MultiServerManager> _manager({
  List<JellyfinClient> jellyfin = const [],
  List<MediaServerClient> others = const [],
  bool ownedPlex = false,
  bool online = true,
}) async {
  final m = MultiServerManager();
  addTearDown(m.dispose);
  for (final client in jellyfin) {
    m.debugRegisterJellyfinClientForTesting(client, online: online);
  }
  for (final client in others) {
    m.debugRegisterClientForTesting(client, online: online);
  }
  if (ownedPlex) {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    addTearDown(db.close);
    m.debugRegisterClientForTesting(
      PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: 'https://plex.example',
          token: 'token',
          clientIdentifier: 'client-id',
          product: 'Pleya',
          version: 'test',
        ),
        serverId: ServerId('plex-1'),
        serverName: 'Woonkamer',
        httpClient: MockClient((_) async => _json({'MediaContainer': <String, Object?>{}})),
      ),
      online: online,
    );
    await m.refreshTokensForProfile(
      PlexAccountConnection(
        id: 'account-1',
        accountToken: 'account-token',
        clientIdentifier: 'account-client',
        accountLabel: 'Account',
        servers: [
          PlexServer(
            name: 'Woonkamer',
            clientIdentifier: 'plex-1',
            accessToken: 'token',
            connections: const [],
            owned: true,
          ),
        ],
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
  }
  return m;
}

AssistantCatalogServices _catalog(MultiServerManager m, {bool canSaveRow = true}) => AssistantCatalogServices(
  rowLoader: CatalogHomeCustomRowLoader(
    libraries: () => const [],
    isServerVisible: m.isServerVisible,
    hiddenLibraryKeys: () => const {},
    clientFor: m.getClient,
  ),
  saveRow: canSaveRow ? (_) async {} : null,
  profileId: 'p1',
  activeProfileId: () => 'p1',
);

final _seerr = AssistantRequestServices(
  client: () => SeerrClient(
    SeerrSession(baseUrl: 'http://seerr.lan:5055', authMode: SeerrAuthMode.apiKey, apiKey: 'k'),
    httpClient: MockClient((_) async => _json(null, status: 404)),
  ),
);

final _personal = AssistantPersonalServices(
  userName: 'Michel',
  recent: () async => const [],
  everSeen: () async => const {},
  taste: () async => AffinityVector.empty,
  picks: (_) async => const [],
);

AssistantPlaybackServices _player({required bool active}) =>
    AssistantPlaybackServices(available: () => active, sample: () async => null, isCurrent: (_) => false);

/// Tools without a start question, each with the reason. A new tool goes here
/// or into a capability.
const assistantExampleExempt = <String, String>{
  'list_libraries': 'a step on the way to a scan or an access change, no question of its own',
  'refresh_metadata': 'needs a named title or library',
  'cancel_job': 'needs a running job',
  'create_user': 'needs a name',
  'set_user_library_access': 'needs a user',
  'remove_user': 'needs a user',
  'create_collection': 'needs titles',
  'similar_titles': 'needs a title',
  'find_request_title': 'needs a title',
  'request_status': 'needs a title shown in the same ask',
  'request_title': 'needs a title shown in the same ask',
  'download_next': 'needs a series',
  'find_subtitles': 'needs a title',
  'download_subtitle': 'needs a title',
  'change_playback': 'needs a running player and a choice',
  'spoiler_context': 'needs the title being watched',
  // A chip is never the user's own typed words, so it cannot store a fact.
  'remember_fact': 'writes the memory',
  'forget_fact': 'writes the memory',
};

Set<AssistantCapability> _group(AssistantCapabilityGroup group) => {
  for (final c in AssistantCapability.values)
    if (c.group == group) c,
};

void main() {
  // The Plex fixture starts the manager's network monitoring, a platform channel.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the catalogue', () {
    final names = {for (final tool in assistantTools) tool.name, assistantSpoilerTool.name};
    final covered = {for (final c in AssistantCapability.values) ...c.tools};

    test('every tool carries a start question or says why not', () {
      expect(
        names.where((n) => !covered.contains(n) && !assistantExampleExempt.containsKey(n)),
        isEmpty,
        reason: 'add the tool to an AssistantCapability or to assistantExampleExempt',
      );
      expect(covered.where(assistantExampleExempt.containsKey), isEmpty, reason: 'a tool is one or the other');
      expect({...covered, ...assistantExampleExempt.keys}.difference(names), isEmpty, reason: 'no stale names');
      expect(assistantExampleExempt.values, everyElement(isNotEmpty));
    });

    test('the fallback is watch questions a children\'s profile may also get', () {
      for (final c in AssistantCapability.fallback) {
        expect(c.group, AssistantCapabilityGroup.watch);
        expect(c.tools.any((tool) => kidsToolPolicy[tool] == KidsTool.gated), isTrue, reason: c.name);
      }
      expect(AssistantCapability.fallback.toSet(), hasLength(3));
    });

    for (final locale in [AppLocale.en, AppLocale.nl]) {
      test('${locale.name}: every capability has its phrasings, plainly written', () async {
        addTearDown(() => LocaleSettings.setLocale(AppLocale.en));
        await LocaleSettings.setLocale(AppLocale.en);
        final english = {for (final c in AssistantCapability.values) c: assistantExamples(c).length};
        await LocaleSettings.setLocale(locale);
        final all = <String>[];
        for (final c in AssistantCapability.values) {
          final phrasings = assistantExamples(c);
          expect(phrasings, isNotEmpty, reason: c.name);
          expect(phrasings, hasLength(english[c]), reason: '${c.name}: as many phrasings as in English');
          all.addAll(phrasings);
          for (final q in phrasings) {
            expect(q, isNot(matches(RegExp('[‒-―]'))), reason: 'no dash as a pause: $q');
            expect(q, matches(RegExp(r'^\p{Lu}.*[?.]$', unicode: true)), reason: q);
            // A start question never names a title: nothing in quotes, no year.
            expect(q, isNot(matches(RegExp('["“”‘]|\\b(19|20)\\d\\d\\b'))), reason: q);
            expect(q.length, lessThanOrEqualTo(70), reason: 'fits a chip: $q');
          }
        }
        expect(all.toSet(), hasLength(all.length), reason: 'one phrasing, one capability');
      });
    }
  });

  group('what a profile is offered', () {
    Set<AssistantCapability> offered(AssistantToolContext ctx, {bool kids = false, bool memory = false}) {
      ctx.memoryTurn = AssistantMemoryTurn(enabled: memory);
      return assistantCapabilitiesFor(ctx, kids: kids);
    }

    test('a Jellyfin administrator with everything connected gets every capability but compare', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final m = await _manager(jellyfin: [_jellyfin(admin: true)]);
      final ctx = AssistantToolContext(
        servers: m,
        catalog: _catalog(m),
        requests: _seerr,
        personal: _personal,
        playback: _player(active: true),
        trakt: AssistantTraktServices(blocked: () => null, watchlist: () async => const []),
        memory: AssistantMemoryServices(
          service: MemoryService(database: db, profileId: 'p1'),
          activeProfileId: () => 'p1',
        ),
      );
      expect(
        AssistantCapability.values.toSet().difference(offered(ctx, memory: true)),
        // One server: nothing to compare with.
        {AssistantCapability.compare},
      );
    });

    test('two administered servers: compare is offered', () async {
      final m = await _manager(jellyfin: [_jellyfin(admin: true)], ownedPlex: true);
      expect(offered(AssistantToolContext(servers: m)), contains(AssistantCapability.compare));
    });

    test('an owned Plex server: administration, no cohort question', () async {
      final m = await _manager(ownedPlex: true);
      final got = offered(AssistantToolContext(servers: m, catalog: _catalog(m)));
      expect(
        got,
        containsAll([
          AssistantCapability.tonight,
          AssistantCapability.jobs,
          AssistantCapability.users,
          AssistantCapability.scan,
          AssistantCapability.watchStats,
          AssistantCapability.doctor,
        ]),
      );
      // recommend_together is served on Plex, but only a Jellyfin administrator gets an answer.
      expect(got, isNot(contains(AssistantCapability.together)));
    });

    test('a Pleya Server administrator: its own administration', () async {
      final m = await _manager(others: [await _pleyaServer(role: 'admin')]);
      final got = offered(AssistantToolContext(servers: m, catalog: _catalog(m)));
      expect(
        got,
        containsAll([
          AssistantCapability.tonight,
          AssistantCapability.unwatched,
          AssistantCapability.jobs,
          AssistantCapability.retryJobs,
          AssistantCapability.users,
          AssistantCapability.scan,
        ]),
      );
      expect(got, isNot(contains(AssistantCapability.together)));
      expect(got, isNot(contains(AssistantCapability.compare)));
    });

    test('only a local folder: watch questions and the server list, nothing to administer', () async {
      final m = await _manager(
        others: [
          LocalFolderClient(
            connection: LocalFolderConnection(
              id: 'local-1',
              directoryUri: 'file:///films',
              displayName: 'Films',
              createdAt: DateTime(2026),
            ),
            cache: ApiCache.forBackend(MediaBackend.local),
          ),
        ],
      );
      final got = offered(AssistantToolContext(servers: m, catalog: _catalog(m), personal: _personal));
      expect(got, containsAll(_group(AssistantCapabilityGroup.watch)));
      expect(got, contains(AssistantCapability.servers));
      expect(got.intersection(_group(AssistantCapabilityGroup.household)), isEmpty);
      expect(got.intersection(_group(AssistantCapabilityGroup.manage)), {
        AssistantCapability.servers,
        AssistantCapability.doctor,
        AssistantCapability.homeRow,
      }, reason: 'what any profile may do as itself');
    });

    group('negative controls', () {
      test('not an administrator: no administration or household question', () async {
        for (final m in [
          await _manager(jellyfin: [_jellyfin(admin: false)]),
          await _manager(others: [await _pleyaServer(role: 'member')]),
        ]) {
          final got = offered(AssistantToolContext(servers: m, catalog: _catalog(m)));
          for (final c in [
            AssistantCapability.jobs,
            AssistantCapability.retryJobs,
            AssistantCapability.users,
            AssistantCapability.scan,
            AssistantCapability.compare,
            AssistantCapability.watchStats,
            AssistantCapability.together,
          ]) {
            expect(got, isNot(contains(c)), reason: c.name);
          }
          expect(got, contains(AssistantCapability.tonight));
        }
      });

      test('without Seerr: no request question, and no trending without a TMDB key', () async {
        final m = await _manager(jellyfin: [_jellyfin(admin: true)]);
        final without = offered(AssistantToolContext(servers: m, catalog: _catalog(m)));
        expect(without, isNot(contains(AssistantCapability.request)));
        expect(without, isNot(contains(AssistantCapability.trending)));
        final withSeerr = offered(AssistantToolContext(servers: m, catalog: _catalog(m), requests: _seerr));
        expect(withSeerr, containsAll([AssistantCapability.request, AssistantCapability.trending]));
      });

      test('the gates that are wider than "this works"', () async {
        final m = await _manager(jellyfin: [_jellyfin(admin: true)]);
        final got = offered(
          AssistantToolContext(
            servers: m,
            catalog: _catalog(m, canSaveRow: false),
            // The session always hands a playback service; nothing plays.
            playback: _player(active: false),
            trakt: AssistantTraktServices(blocked: () => 'trakt_not_connected', watchlist: () async => null),
          ),
        );
        expect(got, isNot(contains(AssistantCapability.playback)));
        expect(got, isNot(contains(AssistantCapability.trakt)));
        expect(got, isNot(contains(AssistantCapability.homeRow)));
        expect(got, isNot(contains(AssistantCapability.memory)), reason: 'no memory service');
        expect(got, isNot(contains(AssistantCapability.history)), reason: 'no personal service');
      });

      test('the memory is offered only while it is on', () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final m = await _manager(jellyfin: [_jellyfin(admin: true)]);
        AssistantToolContext ctx() => AssistantToolContext(
          servers: m,
          memory: AssistantMemoryServices(
            service: MemoryService(database: db, profileId: 'p1'),
            activeProfileId: () => 'p1',
          ),
        );
        expect(offered(ctx(), memory: true), contains(AssistantCapability.memory));
        expect(offered(ctx()), isNot(contains(AssistantCapability.memory)));
      });

      test('a children\'s profile: watch questions only, whatever is connected', () async {
        final m = await _manager(jellyfin: [_jellyfin(admin: true)], ownedPlex: true);
        final ctx = AssistantToolContext(
          servers: m,
          catalog: _catalog(m),
          requests: _seerr,
          personal: _personal,
          playback: _player(active: true),
        );
        final got = offered(ctx, kids: true, memory: true);
        expect(got, _group(AssistantCapabilityGroup.watch));
        // Each of them through a tool whose titles pass the age gate.
        for (final c in got) {
          expect(c.tools.any((tool) => kidsToolPolicy[tool] == KidsTool.gated), isTrue, reason: c.name);
        }
      });

      test('every server offline: only the question which servers are online', () async {
        final m = await _manager(jellyfin: [_jellyfin(admin: true)], online: false);
        final got = offered(AssistantToolContext(servers: m, catalog: _catalog(m), personal: _personal));
        // search_catalog is still served there; the capability is not.
        expect(got, {AssistantCapability.servers, AssistantCapability.history});
      });
    });
  });
}
