part of 'assistant_tools.dart';

/// Server administration: only where `canAdministerServer` holds.
final List<AssistantTool> _adminTools = [
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
              ctx.showJob(id, job.id, job.title);
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
                  AssistantKnownUser(name: clipText(s.name, 64), plexHomeMember: s.homeMember, plexManaged: s.managed),
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
              ctx.showUser(
                id,
                u.id,
                AssistantKnownUser(name: clipText(u.name, 64), isAdmin: admin, accessKnown: u.libraryAccessKnown),
              );
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
      'doctor_option_id': {'type': 'string'},
    },
    required: const ['library_id'],
    serves: (ctx, id) =>
        ctx.admin<LibraryScanClient>(id) != null &&
        (!ctx.libraryDoctorMode || ctx.libraryDoctorActions.contains('scan_library')),
    run: (ctx, id, args) async {
      if (ctx.libraryDoctorMode || args.containsKey('doctor_option_id')) {
        return _doctorPending(ctx, id!, args, AssistantActionKind.scanLibrary);
      }
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
      'doctor_option_id': {'type': 'string'},
    },
    required: const ['item_id'],
    serves: (ctx, id) =>
        ctx.admin<ItemMetadataRefreshClient>(id) != null &&
        (!ctx.libraryDoctorMode || ctx.libraryDoctorActions.contains('refresh_metadata')),
    run: (ctx, id, args) async {
      if (ctx.libraryDoctorMode || args.containsKey('doctor_option_id')) {
        return _doctorPending(ctx, id!, args, AssistantActionKind.refreshMetadata);
      }
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
    description: 'Stop a running job listed by list_jobs. The user confirms in Pleya. $_serverIdNote',
    // Stopping work is not undone by a retry of the same request, so it gets
    // a card, unlike a scan or a refresh.
    risk: AssistantToolRisk.sensitive,
    properties: const {
      'job_id': {'type': 'string'},
    },
    required: const ['job_id'],
    serves: (ctx, id) => ctx.admin<ServerJobsClient>(id) != null,
    run: (ctx, id, args) async {
      final jobId = _string(args, 'job_id');
      ctx.requireShownJob(id!, jobId);
      // The card names the job as the server lists it now, not as the model
      // calls it.
      final job = (await ctx.admin<ServerJobsClient>(id)!.listJobs()).where((j) => j.id == jobId).firstOrNull;
      if (job == null) throw const AssistantToolError('unknown_job_id');
      if (!job.cancellable) throw const AssistantToolError('job_not_cancellable');
      return AssistantPendingAction(
        kind: AssistantActionKind.cancelJob,
        serverId: id,
        serverName: ctx.serverName(id),
        subject: clipText(job.title),
        execute: ({password}) async {
          await (ctx.admin<ServerJobsClient>(id) ?? (throw const AssistantToolError('server_not_available'))).cancelJob(
            jobId,
          );
          return {'status': 'cancel_requested'};
        },
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
      final title = ctx.requireShownJob(id!, jobId);
      await ctx.admin<RetryableJobsClient>(id)!.retryJob(jobId);
      return AssistantToolResult(
        {'status': 'retry_started'},
        record: AssistantActionRecord(
          kind: AssistantActionKind.retryJob,
          serverName: ctx.serverName(id),
          subject: clipText(title),
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
          libraryNames: [for (final l in libraries) clipText(l.title)],
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
        libraryNames: [for (final l in libraries) clipText(l.title)],
        allLibraries: all,
        password: admin.createUserRequiresPassword ? AssistantPasswordMode.required : AssistantPasswordMode.optional,
        execute: ({password}) async {
          final users = _userAdmin(ctx, id) ?? (throw const AssistantToolError('server_not_available'));
          // One write path: the initial access goes with the create, where
          // the user's grants are known to be empty.
          try {
            await users.createUser(
              name: name,
              password: password,
              allLibraries: all,
              libraryIds: [for (final l in libraries) l.id],
            );
          } on ServerUserAccessNotGranted {
            return {'status': 'created', 'name': name, 'library_access': 'failed'};
          }
          return {'status': 'created', 'name': name};
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
    // Only where an existing user's access can be replaced without losing
    // anything nobody asked to change (not Pleya Server, see DEC-142).
    serves: (ctx, id) => ctx.plexSharing(id) != null || (_userAdmin(ctx, id)?.canChangeLibraryAccess ?? false),
    run: (ctx, id, args) async {
      final userId = _string(args, 'user_id');
      final user = ctx.requireShownUser(id!, userId);
      if (!user.accessKnown) throw const AssistantToolError('library_access_unknown');
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
        libraryNames: [for (final l in libraries) clipText(l.title)],
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
