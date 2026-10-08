import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/services/seerr/seerr_account_store.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/seerr/seerr_session.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:provider/provider.dart';

import 'notice_layer.dart';

/// A scriptable Seerr for widget tests: every call is recorded, and each route
/// answers with a value, a status, a thrown transport error or a future the
/// test completes when it wants the answer to land.
class FakeSeerr {
  final calls = <({String method, String path, Map<String, String> query, Object? body})>[];

  /// `'GET /request'` to a handler. A missing route answers 404.
  final routes = <String, FutureOr<http.Response> Function(http.Request request)>{};

  late final http.Client client = MockClient((request) async {
    final path = request.url.path.replaceFirst(SeerrConstants.apiPrefix, '');
    calls.add((
      method: request.method,
      path: path,
      query: request.url.queryParameters,
      body: request.body.isEmpty ? null : jsonDecode(request.body),
    ));
    final handler = routes['${request.method} $path'];
    if (handler == null) return json({'message': 'not found'}, 404);
    return await handler(request);
  });

  static http.Response json(Object? body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: const {'content-type': 'application/json'});

  void on(String route, Object? body, [int status = 200]) => routes[route] = (_) => json(body, status);

  /// The connection drops: no status, no body.
  void fail(String route) => routes[route] = (_) => throw http.ClientException('connection lost');

  /// An answer the test releases by completing the returned completer.
  Completer<http.Response> hold(String route) {
    final completer = Completer<http.Response>();
    routes[route] = (_) => completer.future;
    return completer;
  }

  Iterable<({String method, String path, Map<String, String> query, Object? body})> sent(String method, String path) =>
      calls.where((c) => c.method == method && c.path == path);
}

/// In-memory store, so provider tests need no shared preferences.
class MemorySeerrStore implements SeerrAccountStore {
  final Map<String, SeerrSession> sessions = {};

  @override
  Future<SeerrSession?> load(String userUuid) async => sessions[userUuid];

  @override
  Future<void> save(String userUuid, SeerrSession session) async => sessions[userUuid] = session;

  @override
  Future<void> clear(String userUuid) async => sessions.remove(userUuid);
}

const seerrPermRequest = SeerrPermission.request;
const seerrPermManage = SeerrPermission.request | SeerrPermission.manageRequests;
const seerrPermAdmin = SeerrPermission.admin;

SeerrSession seerrSession({int? userId = 7, int permissions = seerrPermRequest}) => SeerrSession(
  baseUrl: 'https://seerr.example',
  authMode: SeerrAuthMode.apiKey,
  apiKey: 'k',
  userId: userId,
  displayName: 'sanne',
  permissions: permissions,
);

/// A provider with an active session that talks to [fake].
Future<SeerrProvider> seerrProvider(
  FakeSeerr fake, {
  int? userId = 7,
  int permissions = seerrPermRequest,
  MemorySeerrStore? store,
}) async {
  final memory = store ?? MemorySeerrStore();
  memory.sessions['user-1'] = seerrSession(userId: userId, permissions: permissions);
  final provider = SeerrProvider(httpClient: fake.client, store: memory);
  await provider.onActiveProfileChanged('user-1');
  return provider;
}

/// Pumps [child] under the Seerr provider, the translations and an overlay
/// host, which is what every Requests surface stands in.
Future<void> pumpSeerr(WidgetTester tester, SeerrProvider provider, Widget child, {bool host = true}) async {
  await tester.pumpWidget(
    TranslationProvider(
      child: ChangeNotifierProvider<SeerrProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: monoTheme(dark: true),
          // Outcomes of an action are notices, and those render in this layer.
          builder: noticeLayer,
          home: InputModeTracker(
            child: host ? OverlaySheetHost(child: Scaffold(body: child)) : child,
          ),
        ),
      ),
    ),
  );
}

/// A `/request` row as Seerr sends it: no title, no artwork.
Map<String, dynamic> seerrRequestJson(
  int id, {
  int status = 1,
  String type = 'movie',
  int requestedBy = 7,
  List<int> seasons = const [],
  bool is4k = false,
  int? serverId,
  int? profileId,
  String? rootFolder,
  int? languageProfileId,
  List<int>? tags,
  int mediaStatus = 2,
}) => {
  'id': id,
  'status': status,
  'type': type,
  'is4k': is4k,
  'createdAt': '2026-10-06T00:00:00.000Z',
  'requestedBy': {'id': requestedBy, 'displayName': 'user$requestedBy'},
  'media': {'tmdbId': 1000 + id, 'mediaType': type, 'status': mediaStatus, 'title': 'Title $id'},
  'seasons': [
    for (final n in seasons) {'seasonNumber': n, 'status': 1},
  ],
  'serverId': ?serverId,
  'profileId': ?profileId,
  'rootFolder': ?rootFolder,
  'languageProfileId': ?languageProfileId,
  'tags': ?tags,
};

Map<String, dynamic> seerrPage(List<Map<String, dynamic>> results, {int pages = 1}) => {
  'pageInfo': {'pages': pages, 'results': results.length},
  'results': results,
};

/// The automation node with this id and instance.
Finder seerrNode(String id, [String? instance]) =>
    find.byWidgetPredicate((w) => w is AutomationNode && w.id == id && w.instance == instance);

/// Whether the primary focus is inside [within].
bool seerrHasFocus(WidgetTester tester, Finder within) {
  final focus = FocusManager.instance.primaryFocus?.context;
  if (focus == null) return false;
  final target = tester.element(within);
  var found = false;
  focus.visitAncestorElements((e) {
    if (e == target) found = true;
    return !found;
  });
  return found;
}

/// Lets scripted answers land. Not `pumpAndSettle`: a form that is waiting
/// shows a spinner, and a spinner never settles.
Future<void> seerrSettle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}
