import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/server_administration.dart';
import 'package:pleya/services/multi_server_manager.dart';

import 'assistant_find_fakes.dart' as find;

class _Manager extends MultiServerManager {
  bool admin = true;
  @override
  bool canAdministerServer(ServerId id) => admin;
  @override
  Future<void> checkServerHealth() async {}
}

/// An administered server whose slow reads can flip the rights while they run.
class _Admin extends find.FakeServer
    implements
        ServerJobsClient,
        RetryableJobsClient,
        LibraryScanClient,
        ItemMetadataRefreshClient,
        ServerUserAdministration {
  _Admin(super.id, {super.libraries});
  void Function()? onRead;
  var scans = 0;
  var refreshes = 0;

  @override
  bool get supportsServerAdministration => true;
  @override
  Future<List<ServerJob>> listJobs() async {
    onRead?.call();
    return const [ServerJob(id: 'j1', title: 'Scan', state: ServerJobState.running, cancellable: true)];
  }

  @override
  Future<List<MediaLibrary>> fetchLibraries() async {
    final libraries = await super.fetchLibraries();
    onRead?.call();
    return libraries;
  }

  @override
  Future<MediaItem?> fetchItem(String itemId) async {
    onRead?.call();
    return find.fakeItem(itemId, 'Dune');
  }

  @override
  Future<List<ServerUser>> listUsers() async {
    onRead?.call();
    return const [ServerUser(id: 'u1', name: 'Anna', role: ServerUserRole.member, allLibraries: true)];
  }

  @override
  Future<void> scanLibrary(String libraryId) async => scans++;
  @override
  Future<void> refreshItemMetadata(String itemId) async => refreshes++;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

AssistantTool _tool(String name) => assistantTools.singleWhere((t) => t.name == name);

Matcher get _notAllowed => throwsA(isA<AssistantToolError>().having((e) => e.code, 'code', 'not_allowed'));

void main() {
  late _Manager manager;
  late _Admin server;
  late AssistantToolContext ctx;
  final id = ServerId('srv');

  setUp(() {
    manager = _Manager();
    addTearDown(manager.dispose);
    server = _Admin(
      'srv',
      libraries: {
        'films': [find.fakeItem('d', 'Dune')],
      },
    );
    manager.debugRegisterClientForTesting(server);
    ctx = AssistantToolContext(servers: manager);
  });

  void revokeWhileReading() => server.onRead = () => manager.admin = false;

  test('control: with the rights kept, every read and action goes through', () async {
    ctx.showItem(id, 'd');
    expect(((await _tool('list_jobs').run(ctx, id, {})) as AssistantToolResult).data['jobs'], hasLength(1));
    expect(((await _tool('list_users').run(ctx, id, {})) as AssistantToolResult).data['users'], hasLength(1));
    await _tool('scan_library').run(ctx, id, {'library_id': 'films'});
    await _tool('refresh_metadata').run(ctx, id, {'item_id': 'd'});
    expect((server.scans, server.refreshes), (1, 1));
  });

  test('list_jobs: rights revoked during the read publish nothing', () async {
    revokeWhileReading();
    await expectLater(_tool('list_jobs').run(ctx, id, {}), _notAllowed);
    expect(() => ctx.requireShownJob(id, 'j1'), throwsA(isA<AssistantToolError>()), reason: 'no job was registered');
  });

  test('list_users: rights revoked during the read publish nothing', () async {
    revokeWhileReading();
    await expectLater(_tool('list_users').run(ctx, id, {}), _notAllowed);
    expect(() => ctx.requireShownUser(id, 'u1'), throwsA(isA<AssistantToolError>()));
  });

  test('scan_library: rights revoked during the library lookup start no scan', () async {
    revokeWhileReading();
    await expectLater(_tool('scan_library').run(ctx, id, {'library_id': 'films'}), _notAllowed);
    expect(server.scans, 0);
  });

  test('refresh_metadata: rights revoked during the item read start no refresh', () async {
    ctx.showItem(id, 'd');
    revokeWhileReading();
    await expectLater(_tool('refresh_metadata').run(ctx, id, {'item_id': 'd'}), _notAllowed);
    expect(server.refreshes, 0);
  });

  test('cancel_job: rights revoked while the job is read prepare no card', () async {
    ctx.showJob(id, 'j1', 'Scan');
    revokeWhileReading();
    await expectLater(_tool('cancel_job').run(ctx, id, {'job_id': 'j1'}), _notAllowed);
  });

  test('a connection replaced during the read counts as revoked', () async {
    server.onRead = () {
      manager.debugRegisterClientForTesting(_Admin('srv'));
    };
    await expectLater(_tool('list_jobs').run(ctx, id, {}), _notAllowed);
  });
}
