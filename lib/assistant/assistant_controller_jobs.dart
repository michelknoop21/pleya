part of 'assistant_controller.dart';

/// What one look at the server's job list says about [watch]. [seen] is true
/// once the job was found queued or running; a miss counts towards giving
/// up. Returns null when this look decides nothing.
@visibleForTesting
AssistantJobProgress? assistantJobLook(AssistantJobWatch watch, List<ServerJob> jobs, {required bool seen}) {
  final job = watch.jobId != null
      ? jobs.where((j) => j.id == watch.jobId).firstOrNull
      // The newest job on the library: Pleya Server lists newest first and
      // refuses a second scan while one runs; Plex lists only running work.
      : jobs.where((j) => j.libraryId == watch.libraryId).firstOrNull;
  if (job == null) {
    // Plex drops an activity once it is over.
    return seen ? const AssistantJobProgress(AssistantJobPhase.done) : null;
  }
  switch (job.state) {
    case ServerJobState.queued || ServerJobState.running:
      final p = job.progress;
      return AssistantJobProgress(AssistantJobPhase.running, percent: p == null ? null : (p * 100).round());
    case ServerJobState.succeeded || ServerJobState.failed || ServerJobState.cancelled:
      // A retried job still shows its previous outcome until the server
      // picks it up: only an end after the start is this run's end.
      final ours = watch.libraryId != null || seen || (job.updatedAt?.isAfter(watch.startedAt) ?? false);
      if (!ours) return null;
      return AssistantJobProgress(
        job.state == ServerJobState.succeeded ? AssistantJobPhase.done : AssistantJobPhase.failed,
      );
    case ServerJobState.unknown:
      return null;
  }
}

extension _AssistantJobPolling on AssistantController {
  /// Each completed task owns its watches. Aggregate action offsets change
  /// when siblings finish, so they cannot identify an action across an await.
  Future<void> _watchJobs(_AssistantTaskState task) async {
    final seq = _jobsSeq;
    final deadline = _now().add(jobWatchLimit);
    final watches = task.actions.map((action) => action.job).nonNulls.toList();
    final context = _buildContext(null);
    final clients = {for (final watch in watches) watch.serverId: context.admin<ServerJobsClient>(watch.serverId)};
    final seen = <AssistantJobWatch>{};
    final misses = <AssistantJobWatch, int>{};
    bool current() => seq == _jobsSeq && _alive(task);
    bool authorized(AssistantJobWatch watch) {
      if (!current()) return false;
      if (_jobsFor != null) return true; // Explicit test transport.
      final latest = _buildContext(null);
      return clients[watch.serverId] != null &&
          identical(clients[watch.serverId], latest.admin<ServerJobsClient>(watch.serverId)) &&
          (context.catalog == null || context.catalog!.activeProfileId() == context.catalog!.profileId);
    }

    int indexOf(AssistantJobWatch watch) => task.actions.indexWhere((action) => identical(action.job, watch));
    while (current()) {
      await Future<void>.delayed(jobPollInterval);
      if (!current()) return;
      final open = watches.where((watch) {
        final index = indexOf(watch);
        return index >= 0 && !(task.actions[index].progress?.settled ?? false);
      }).toList();
      if (open.isEmpty) return;
      final timeUp = !_now().isBefore(deadline);
      final lists = <ServerId, List<ServerJob>?>{};
      for (final watch in open) {
        if (!authorized(watch)) return;
        if (!lists.containsKey(watch.serverId)) {
          List<ServerJob>? jobs;
          try {
            final remaining = deadline.difference(_now());
            if (remaining > Duration.zero) {
              jobs = await Future.any<List<ServerJob>?>([
                _operations.run(() {
                  if (!authorized(watch)) return Future<List<ServerJob>?>.value();
                  return _listJobs(watch.serverId);
                }),
                task.cancel.trigger.then<List<ServerJob>?>((_) => null),
              ]).timeout(remaining);
            }
          } catch (e) {
            appLogger.d('Assistant job poll failed', error: e.runtimeType);
          }
          if (!authorized(watch)) return;
          lists[watch.serverId] = jobs;
        }
        if (!authorized(watch)) return;
        final jobs = lists[watch.serverId];
        var next = jobs == null ? null : assistantJobLook(watch, jobs, seen: seen.contains(watch));
        if (next?.phase == AssistantJobPhase.running) seen.add(watch);
        if (next == null && jobs != null && !seen.contains(watch) && (misses[watch] = (misses[watch] ?? 0) + 1) >= 3) {
          next = const AssistantJobProgress(AssistantJobPhase.started);
        }
        if ((timeUp || !_now().isBefore(deadline)) && !(next?.settled ?? false)) {
          next = AssistantJobProgress(
            seen.contains(watch) ? AssistantJobPhase.background : AssistantJobPhase.started,
            percent: next?.percent,
          );
        }
        final index = indexOf(watch);
        if (next != null && index >= 0) task.actions[index] = task.actions[index].withProgress(next);
      }
      _update();
    }
  }

  Future<List<ServerJob>?> _listJobs(ServerId serverId) {
    final override = _jobsFor;
    if (override != null) return override(serverId);
    final client = _buildContext(null).admin<ServerJobsClient>(serverId);
    return client == null ? Future.value(null) : client.listJobs();
  }
}
