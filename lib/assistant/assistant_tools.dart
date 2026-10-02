import '../media/ids.dart';
import '../media/media_kind.dart';
import '../media/media_library.dart';
import '../media/server_administration.dart';
import '../utils/app_logger.dart';
import 'assistant_tool_context.dart';

enum AssistantToolRisk { read, mutation, sensitive }

/// What a tool hands back: data for the model, or an action that waits for
/// the user's confirmation in Pleya.
sealed class AssistantToolOutcome {
  const AssistantToolOutcome();
}

class AssistantToolResult extends AssistantToolOutcome {
  const AssistantToolResult(this.data, {this.record});
  final Map<String, Object?> data;

  /// Set for a mutation that ran, so the UI can show what happened.
  final AssistantActionRecord? record;
}

enum AssistantActionKind { scanLibrary, refreshMetadata, cancelJob, retryJob, createUser, setLibraryAccess, removeUser }

/// How the backend really models the action, for the card's fine print.
enum AssistantBackendNote { none, plexManagedHomeUser, plexShare, plexHomeMember, replacesAllAccess }

enum AssistantPasswordMode { none, optional, required }

/// What Pleya shows after an action: built from validated data only.
class AssistantActionRecord {
  const AssistantActionRecord({required this.kind, required this.serverName, required this.subject});
  final AssistantActionKind kind;
  final String serverName;
  final String subject;
}

/// A sensitive action waiting for the user. The UI renders it as a Pleya
/// card; the model only ever learns whether it ran. Every field comes from
/// server data or from ids Pleya validated, never from model prose.
class AssistantPendingAction extends AssistantToolOutcome {
  const AssistantPendingAction({
    required this.kind,
    required this.serverId,
    required this.serverName,
    required this.subject,
    required this.execute,
    this.libraryNames = const [],
    this.allLibraries = false,
    this.note = AssistantBackendNote.none,
    this.password = AssistantPasswordMode.none,
  });

  final AssistantActionKind kind;
  final ServerId serverId;
  final String serverName;

  /// The user the action is about.
  final String subject;
  final List<String> libraryNames;
  final bool allLibraries;
  final AssistantBackendNote note;
  final AssistantPasswordMode password;

  /// Runs the action. [password] comes from Pleya's secure input, never
  /// from the model.
  final Future<Map<String, Object?>> Function({String? password}) execute;

  AssistantActionRecord get record => AssistantActionRecord(kind: kind, serverName: serverName, subject: subject);
}

class AssistantTool {
  const AssistantTool({
    required this.name,
    required this.description,
    required this.risk,
    required this.properties,
    required this.serves,
    required this.run,
    this.required = const [],
    this.needsServer = true,
  });

  final String name;
  final String description;
  final AssistantToolRisk risk;
  final Map<String, Object?> properties;
  final List<String> required;
  final bool needsServer;

  /// Whether this tool can act on [serverId] right now.
  final bool Function(AssistantToolContext ctx, ServerId serverId) serves;
  final Future<AssistantToolOutcome> Function(AssistantToolContext ctx, ServerId? serverId, Map<String, Object?> args)
  run;

  /// The OpenAI-format spec, with `server_id` limited to [serverIds].
  Map<String, Object?> spec(List<String> serverIds) => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': {
          if (needsServer) 'server_id': {'type': 'string', 'enum': serverIds},
          ...properties,
        },
        'required': [if (needsServer) 'server_id', ...required],
        'additionalProperties': false,
      },
    },
  };
}

/// Text from a server is data. Clip it and drop control characters so a
/// title cannot carry a wall of instructions or fake message boundaries.
String clipText(String? value, [int max = 80]) {
  final clean = (value ?? '').replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ').trim();
  return clean.length <= max ? clean : '${clean.substring(0, max)}…';
}

String _string(Map<String, Object?> args, String key) {
  final value = args[key];
  if (value is! String || value.trim().isEmpty) throw AssistantToolError('missing_$key');
  return value.trim();
}

List<String> _strings(Map<String, Object?> args, String key) {
  final value = args[key];
  if (value == null) return const [];
  if (value is! List || value.any((v) => v is! String)) throw AssistantToolError('invalid_$key');
  return value.cast<String>().toSet().toList();
}

bool _bool(Map<String, Object?> args, String key) => args[key] == true;

String _userName(Map<String, Object?> args) {
  final name = _string(args, 'name');
  // Control and format characters (bidi overrides, zero-width) would make
  // the card show a different name than the one created.
  if (name.length > 64 || RegExp(r'[\p{Cc}\p{Cf}/\\]', unicode: true).hasMatch(name)) {
    throw const AssistantToolError('invalid_name');
  }
  return name;
}

Future<List<MediaLibrary>> _resolveLibraries(AssistantToolContext ctx, ServerId id, List<String> ids) async => [
  for (final libraryId in ids) await ctx.library(id, libraryId),
];

ServerUserAdministration? _userAdmin(AssistantToolContext ctx, ServerId id) => ctx.admin<ServerUserAdministration>(id);

bool _managesUsers(AssistantToolContext ctx, ServerId id) => _userAdmin(ctx, id) != null || ctx.plexSharing(id) != null;

/// After a create the user exists, whatever happens next. A failed grant is
/// reported as exactly that, so nobody creates the same user twice.
Future<Map<String, Object?>> _grantAfterCreate(String name, bool grant, Future<void> Function() apply) async {
  if (grant) {
    try {
      await apply();
    } catch (e) {
      appLogger.w('Assistant: user created, granting library access failed', error: e.runtimeType);
      return {'status': 'created', 'name': name, 'library_access': 'failed'};
    }
  }
  return {'status': 'created', 'name': name};
}

const _serverIdNote = 'Use ids exactly as earlier tool results returned them.';

/// The complete allow-list. Nothing outside it can reach a server.
final List<AssistantTool> assistantTools = [
  AssistantTool(
    name: 'list_servers',
    description: 'Media servers this user administers, with whether each is online.',
    risk: AssistantToolRisk.read,
    properties: const {},
    needsServer: false,
    serves: (_, _) => true,
    run: (ctx, _, _) async => AssistantToolResult({
      'servers': [
        for (final id in ctx.administeredServers)
          {
            'server_id': id.value,
            'name': clipText(ctx.serverName(id)),
            'backend': ctx.servers.getClient(id)?.backend.name,
            'online': ctx.adminClient(id) != null,
          },
      ],
    }),
  ),
  AssistantTool(
    name: 'list_libraries',
    description: 'Libraries on one server.',
    risk: AssistantToolRisk.read,
    properties: const {},
    serves: (ctx, id) => ctx.adminClient(id) != null,
    run: (ctx, id, _) async => AssistantToolResult({
      'libraries': [
        for (final l in await ctx.libraries(id!)) {'library_id': l.id, 'title': clipText(l.title), 'kind': l.kind.name},
      ],
    }),
  ),
  AssistantTool(
    name: 'find_media',
    description: 'Search a server for films, series or albums by title, to get an item_id.',
    risk: AssistantToolRisk.read,
    properties: const {
      'query': {'type': 'string'},
    },
    required: const ['query'],
    serves: (ctx, id) => ctx.admin<ItemMetadataRefreshClient>(id) != null,
    run: (ctx, id, args) async {
      final query = _string(args, 'query');
      final items = await ctx.adminClient(id!)!.searchItems(clipText(query, 100), limit: 10);
      const kinds = {
        MediaKind.movie,
        MediaKind.show,
        MediaKind.season,
        MediaKind.episode,
        MediaKind.album,
        MediaKind.artist,
      };
      return AssistantToolResult({
        'items': [
          for (final item in items.where((i) => kinds.contains(i.kind)).take(10))
            () {
              ctx.showItem(id, item.id);
              return {
                'item_id': item.id,
                'title': clipText(item.title),
                if (item.grandparentTitle != null) 'series': clipText(item.grandparentTitle),
                if (item.year != null) 'year': item.year,
                'kind': item.kind.name,
              };
            }(),
        ],
      });
    },
  ),
  AssistantTool(
    name: 'list_jobs',
    description: 'Background jobs on a server: scans, scheduled tasks, failures.',
    risk: AssistantToolRisk.read,
    properties: const {},
    serves: (ctx, id) => ctx.admin<ServerJobsClient>(id) != null,
    run: (ctx, id, _) async {
      final jobs = await ctx.admin<ServerJobsClient>(id!)!.listJobs();
      return AssistantToolResult({
        'jobs': [
          for (final job in jobs.take(30))
            () {
              ctx.showJob(id, job.id);
              return {
                'job_id': job.id,
                'title': clipText(job.title),
                'state': job.state.name,
                if (job.progress != null) 'progress_percent': (job.progress! * 100).round(),
                if (job.error != null) 'error': clipText(job.error, 120),
                'can_cancel': job.cancellable,
                'can_retry': job.retryable,
              };
            }(),
        ],
      });
    },
  ),
  AssistantTool(
    name: 'list_users',
    description:
        'Users on a server and which libraries each can see. access_known false means the server does not report it.',
    risk: AssistantToolRisk.read,
    properties: const {},
    serves: _managesUsers,
    run: (ctx, id, _) async {
      final sharing = ctx.plexSharing(id!);
      if (sharing != null) {
        final shares = await sharing.listShares();
        return AssistantToolResult({
          'users': [
            for (final s in shares)
              () {
                ctx.showUser(
                  id,
                  s.userId,
                  AssistantKnownUser(name: s.name, plexHomeMember: s.homeMember, plexManaged: s.managed),
                );
                return {
                  'user_id': s.userId,
                  'name': clipText(s.name),
                  'kind': s.managed ? 'plex_managed_home_user' : (s.homeMember ? 'plex_home_member' : 'plex_friend'),
                  'all_libraries': s.shared && s.allLibraries,
                  'library_ids': s.shared ? s.libraryIds : const <String>[],
                  'access_known': true,
                };
              }(),
          ],
        });
      }
      final users = await _userAdmin(ctx, id)!.listUsers();
      return AssistantToolResult({
        'users': [
          for (final u in users)
            () {
              final admin = u.role == ServerUserRole.owner || u.role == ServerUserRole.admin;
              ctx.showUser(id, u.id, AssistantKnownUser(name: u.name, isAdmin: admin));
              return {
                'user_id': u.id,
                'name': clipText(u.name),
                'role': u.role.name,
                'disabled': u.disabled,
                'access_known': u.libraryAccessKnown,
                if (u.libraryAccessKnown) 'all_libraries': u.allLibraries,
                if (u.libraryAccessKnown) 'library_ids': u.libraryIds,
              };
            }(),
        ],
      });
    },
  ),
  AssistantTool(
    name: 'scan_library',
    description: 'Scan one library for new, changed and removed files. $_serverIdNote',
    risk: AssistantToolRisk.mutation,
    properties: const {
      'library_id': {'type': 'string'},
    },
    required: const ['library_id'],
    serves: (ctx, id) => ctx.admin<LibraryScanClient>(id) != null,
    run: (ctx, id, args) async {
      final library = await ctx.library(id!, _string(args, 'library_id'));
      await ctx.admin<LibraryScanClient>(id)!.scanLibrary(library.id);
      return AssistantToolResult(
        {'status': 'scan_started', 'library': clipText(library.title)},
        record: AssistantActionRecord(
          kind: AssistantActionKind.scanLibrary,
          serverName: ctx.serverName(id),
          subject: library.title,
        ),
      );
    },
  ),
  AssistantTool(
    name: 'refresh_metadata',
    description: 'Re-read metadata for one item found with find_media. $_serverIdNote',
    risk: AssistantToolRisk.mutation,
    properties: const {
      'item_id': {'type': 'string'},
    },
    required: const ['item_id'],
    serves: (ctx, id) => ctx.admin<ItemMetadataRefreshClient>(id) != null,
    run: (ctx, id, args) async {
      final itemId = _string(args, 'item_id');
      ctx.requireShownItem(id!, itemId);
      final item = await ctx.adminClient(id)!.fetchItem(itemId);
      if (item == null) throw const AssistantToolError('unknown_item_id');
      await ctx.admin<ItemMetadataRefreshClient>(id)!.refreshItemMetadata(itemId);
      final title = item.title ?? itemId;
      return AssistantToolResult(
        {'status': 'refresh_started', 'title': clipText(title)},
        record: AssistantActionRecord(
          kind: AssistantActionKind.refreshMetadata,
          serverName: ctx.serverName(id),
          subject: title,
        ),
      );
    },
  ),
  AssistantTool(
    name: 'cancel_job',
    description: 'Stop a running job listed by list_jobs. $_serverIdNote',
    risk: AssistantToolRisk.mutation,
    properties: const {
      'job_id': {'type': 'string'},
    },
    required: const ['job_id'],
    serves: (ctx, id) => ctx.admin<ServerJobsClient>(id) != null,
    run: (ctx, id, args) async {
      final jobId = _string(args, 'job_id');
      ctx.requireShownJob(id!, jobId);
      await ctx.admin<ServerJobsClient>(id)!.cancelJob(jobId);
      return AssistantToolResult(
        {'status': 'cancel_requested'},
        record: AssistantActionRecord(
          kind: AssistantActionKind.cancelJob,
          serverName: ctx.serverName(id),
          subject: jobId,
        ),
      );
    },
  ),
  AssistantTool(
    name: 'retry_job',
    description: 'Run a finished or failed job listed by list_jobs again. $_serverIdNote',
    risk: AssistantToolRisk.mutation,
    properties: const {
      'job_id': {'type': 'string'},
    },
    required: const ['job_id'],
    serves: (ctx, id) => ctx.admin<RetryableJobsClient>(id) != null,
    run: (ctx, id, args) async {
      final jobId = _string(args, 'job_id');
      ctx.requireShownJob(id!, jobId);
      await ctx.admin<RetryableJobsClient>(id)!.retryJob(jobId);
      return AssistantToolResult(
        {'status': 'retry_started'},
        record: AssistantActionRecord(
          kind: AssistantActionKind.retryJob,
          serverName: ctx.serverName(id),
          subject: jobId,
        ),
      );
    },
  ),
  AssistantTool(
    name: 'create_user',
    description:
        'Create a regular user, optionally limited to some libraries. The user confirms in Pleya and sets any password there; never ask for one. $_serverIdNote',
    risk: AssistantToolRisk.sensitive,
    properties: const {
      'name': {'type': 'string'},
      'library_ids': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'all_libraries': {'type': 'boolean'},
    },
    required: const ['name'],
    serves: _managesUsers,
    run: (ctx, id, args) async {
      final name = _userName(args);
      final all = _bool(args, 'all_libraries');
      final libraries = all ? const <MediaLibrary>[] : await _resolveLibraries(ctx, id!, _strings(args, 'library_ids'));
      final sharing = ctx.plexSharing(id!);
      if (sharing != null) {
        return AssistantPendingAction(
          kind: AssistantActionKind.createUser,
          serverId: id,
          serverName: ctx.serverName(id),
          subject: name,
          libraryNames: [for (final l in libraries) l.title],
          allLibraries: all,
          note: AssistantBackendNote.plexManagedHomeUser,
          execute: ({password}) async {
            final userId = await ctx.plexSharing(id)!.createManagedHomeUser(name);
            return _grantAfterCreate(
              name,
              all || libraries.isNotEmpty,
              () => ctx
                  .plexSharing(id)!
                  .setShareLibraries(userId, allLibraries: all, libraryIds: [for (final l in libraries) l.id]),
            );
          },
        );
      }
      final admin = _userAdmin(ctx, id)!;
      return AssistantPendingAction(
        kind: AssistantActionKind.createUser,
        serverId: id,
        serverName: ctx.serverName(id),
        subject: name,
        libraryNames: [for (final l in libraries) l.title],
        allLibraries: all,
        password: admin.createUserRequiresPassword ? AssistantPasswordMode.required : AssistantPasswordMode.optional,
        execute: ({password}) async {
          final users = _userAdmin(ctx, id) ?? (throw const AssistantToolError('server_not_available'));
          final user = await users.createUser(name: name, password: password);
          return _grantAfterCreate(
            name,
            all || libraries.isNotEmpty,
            () => users.setUserLibraryAccess(user.id, allLibraries: all, libraryIds: [for (final l in libraries) l.id]),
          );
        },
      );
    },
  ),
  AssistantTool(
    name: 'set_user_library_access',
    description:
        'Replace which libraries a user from list_users can see. Send the complete new set, not a change. $_serverIdNote',
    risk: AssistantToolRisk.sensitive,
    properties: const {
      'user_id': {'type': 'string'},
      'library_ids': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'all_libraries': {'type': 'boolean'},
    },
    required: const ['user_id'],
    serves: _managesUsers,
    run: (ctx, id, args) async {
      final userId = _string(args, 'user_id');
      final user = ctx.requireShownUser(id!, userId);
      if (user.isAdmin) throw const AssistantToolError('user_is_admin');
      final all = _bool(args, 'all_libraries');
      final libraries = all ? const <MediaLibrary>[] : await _resolveLibraries(ctx, id, _strings(args, 'library_ids'));
      final ids = [for (final l in libraries) l.id];
      final plex = ctx.plexSharing(id) != null;
      return AssistantPendingAction(
        kind: AssistantActionKind.setLibraryAccess,
        serverId: id,
        serverName: ctx.serverName(id),
        subject: user.name,
        libraryNames: [for (final l in libraries) l.title],
        allLibraries: all,
        note: plex ? AssistantBackendNote.plexShare : AssistantBackendNote.replacesAllAccess,
        execute: ({password}) async {
          if (plex) {
            await (ctx.plexSharing(id) ?? (throw const AssistantToolError('server_not_available'))).setShareLibraries(
              userId,
              allLibraries: all,
              libraryIds: ids,
            );
          } else {
            await (_userAdmin(ctx, id) ?? (throw const AssistantToolError('server_not_available')))
                .setUserLibraryAccess(userId, allLibraries: all, libraryIds: ids);
          }
          return {'status': 'access_updated', 'name': user.name};
        },
      );
    },
  ),
  AssistantTool(
    name: 'remove_user',
    description: 'Remove a user from list_users. Administrators cannot be removed this way. $_serverIdNote',
    risk: AssistantToolRisk.sensitive,
    properties: const {
      'user_id': {'type': 'string'},
    },
    required: const ['user_id'],
    serves: _managesUsers,
    run: (ctx, id, args) async {
      final userId = _string(args, 'user_id');
      final user = ctx.requireShownUser(id!, userId);
      if (user.isAdmin) throw const AssistantToolError('user_is_admin');
      final plex = ctx.plexSharing(id) != null;
      return AssistantPendingAction(
        kind: AssistantActionKind.removeUser,
        serverId: id,
        serverName: ctx.serverName(id),
        subject: user.name,
        note: !plex
            ? AssistantBackendNote.none
            : (user.plexHomeMember ? AssistantBackendNote.plexHomeMember : AssistantBackendNote.plexShare),
        execute: ({password}) async {
          if (plex) {
            final sharing = ctx.plexSharing(id) ?? (throw const AssistantToolError('server_not_available'));
            if (user.plexHomeMember) {
              await sharing.removeHomeUser(userId);
            } else {
              await sharing.removeShare(userId);
            }
          } else {
            await (_userAdmin(ctx, id) ?? (throw const AssistantToolError('server_not_available'))).deleteUser(userId);
          }
          return {'status': 'removed', 'name': user.name};
        },
      );
    },
  ),
];
