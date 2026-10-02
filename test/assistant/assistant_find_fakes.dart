import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/assistant/assistant_web_lookup.dart';
import 'package:pleya/assistant/assistant_web_search.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_identity.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/seerr/seerr_client.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/seerr/seerr_session.dart';
import 'package:pleya/services/unified_catalog/home_custom_row_loader.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;

http.Response jsonResponse(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: const {'content-type': 'application/json'});

MediaItem fakeItem(
  String id,
  String title, {
  MediaKind kind = MediaKind.movie,
  int? year,
  String? summary,
  String? lib,
}) => MediaItem(
  id: id,
  backend: MediaBackend.jellyfin,
  kind: kind,
  title: title,
  year: year,
  summary: summary,
  libraryId: lib,
);

/// A media server holding [libraries] (library id → items), with external
/// ids per item and children per parent.
class FakeServer implements MediaServerClient {
  FakeServer(String id, {this.libraries = const {}, this.ids = const {}, this.children = const {}})
    : serverId = ServerId(id);
  @override
  final ServerId serverId;
  final Map<String, List<MediaItem>> libraries;
  final Map<String, ExternalIds> ids;
  final Map<String, List<MediaItem>> children;
  final identities = <MediaIdentity>[];

  /// How long a library page takes to arrive.
  Duration latency = Duration.zero;

  @override
  MediaBackend get backend => MediaBackend.jellyfin;
  @override
  String get serverName => serverId.value;

  Iterable<MediaItem> get _all => libraries.entries.expand((e) => e.value.map((i) => i.copyWith(libraryId: e.key)));

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryContent(String libraryId, LibraryQuery query) async {
    await Future<void>.delayed(latency);
    final items = [
      for (final i in libraries[libraryId] ?? const <MediaItem>[])
        if (i.kind == query.kind) i.copyWith(libraryId: libraryId),
    ];
    return LibraryPage(items: query.offset == 0 ? items : const [], totalCount: items.length);
  }

  @override
  Future<List<MediaItem>> findAllByIdentity(MediaIdentity identity) async {
    identities.add(identity);
    return identity.pickAllMatches([
      for (final i in _all) MediaIdentity.candidate(i, ids[i.id] ?? const ExternalIds()),
    ]);
  }

  @override
  Future<List<MediaItem>> searchItems(String query, {int limit = 100}) async => [
    for (final i in _all)
      if ((i.title ?? '').toLowerCase().contains(query.toLowerCase())) i,
  ];

  @override
  Future<List<MediaLibrary>> fetchLibraries() async => [
    for (final MapEntry(:key, :value) in libraries.entries)
      fakeLib(serverId.value, key, kind: value.firstOrNull?.kind ?? MediaKind.movie),
  ];

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => ids[itemId] ?? const ExternalIds();

  @override
  Future<List<MediaItem>> fetchChildren(String parentId) async => children[parentId] ?? const [];

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaLibrary fakeLib(String server, String id, {MediaKind kind = MediaKind.movie}) =>
    MediaLibrary(id: id, backend: MediaBackend.jellyfin, title: id, kind: kind, serverId: server, serverName: server);

/// Wikipedia, Wikidata and the web search behind fakes, counting every call.
/// A request waits on [stall] when set, and ends with
/// [http.RequestAbortedException] once its abort trigger fires, as the real
/// clients do; [aborted] records those hosts.
class FakeWeb {
  final hosts = <String>[];
  final aborted = <String>[];
  Map<String, Object> wiki = const {};
  Map<String, Object> entities = const {};
  Completer<void>? stall;
  final search = FakeSearch();

  late final services = AssistantWebServices(
    search: search,
    client: MockClient.streaming((request, _) async {
      hosts.add(request.url.host);
      final trigger = request is http.Abortable ? request.abortTrigger : null;
      var cut = false;
      unawaited(trigger?.then((_) => cut = true));
      if (stall != null) await Future.any([stall!.future, ?trigger]);
      await Future<void>.delayed(Duration.zero);
      if (cut) {
        aborted.add(request.url.host);
        throw http.RequestAbortedException(request.url);
      }
      final Object body;
      if (request.url.host == 'www.wikidata.org') {
        body = {'entities': entities};
      } else {
        final pages = wiki[request.url.queryParameters['gsrsearch']];
        body = {
          if (pages != null && request.url.host.startsWith('en.')) 'query': {'pages': pages},
        };
      }
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        200,
        headers: const {'content-type': 'application/json'},
      );
    }),
  );
}

class FakeSearch implements WebSearchClient {
  final queries = <String>[];
  List<WebSearchHit> hits = const [];
  @override
  Future<List<WebSearchHit>> search(String query, {int maxResults = 5, AbortController? abort}) async {
    queries.add(query);
    return hits;
  }
}

/// Overseerr behind fake HTTP.
class FakeSeerr {
  final paths = <String>[];
  Map<String, List<Map<String, Object?>>> search = {};
  Map<String, Map<String, Object?>> details = {};

  late final client = SeerrClient(
    SeerrSession(baseUrl: 'http://seerr.lan', authMode: SeerrAuthMode.apiKey, apiKey: 'k'),
    httpClient: MockClient((request) async {
      final path = request.url.path.replaceFirst('/api/v1', '');
      paths.add(path == '/search' ? 'search:${request.url.queryParameters['query']}' : path);
      if (path == '/search') {
        return jsonResponse({
          'page': 1,
          'totalPages': 1,
          'results': search[request.url.queryParameters['query']] ?? [],
        });
      }
      return jsonResponse(details[path] ?? {});
    }),
  );
}

AssistantToolContext findCtx(
  List<FakeServer> servers, {
  List<MediaLibrary> libraries = const [],
  Set<String> hidden = const {},
  Set<String>? visible,
  FakeSeerr? seerr,
  FakeWeb? web,
}) {
  final m = MultiServerManager();
  addTearDown(m.dispose);
  for (final s in servers) {
    m.debugRegisterClientForTesting(s);
  }
  m.setVisibleServerIds(visible);
  return AssistantToolContext(
    servers: m,
    catalog: AssistantCatalogServices(
      rowLoader: CatalogHomeCustomRowLoader(
        libraries: () => libraries,
        isServerVisible: m.isServerVisible,
        hiddenLibraryKeys: () => hidden,
        clientFor: m.getClient,
      ),
      profileId: 'p',
      activeProfileId: () => 'p',
    ),
    requests: seerr == null ? null : AssistantRequestServices(client: () => seerr.client),
    web: web?.services,
  );
}

Future<Map<String, Object?>> runFind(AssistantToolContext ctx, Map<String, Object?> args) async {
  final tool = assistantTools.firstWhere((t) => t.name == 'find_title');
  return ((await tool.run(ctx, null, args)) as AssistantToolResult).data;
}

List<Map<String, Object?>> matchesOf(Map<String, Object?> data) => (data['matches'] as List).cast();
