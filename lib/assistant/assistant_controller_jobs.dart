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

extension _AssistantJobWatching on AssistantController {
  /// Follows the jobs the last ask started, so the result card shows them
  /// running and ending. Stops on a new ask, [reset], [dispose], when every
  /// job settled, or after [jobWatchLimit].
  Future<void> _watchJobs() async {
    final seq = ++_jobsSeq;
    final deadline = _now().add(jobWatchLimit);
    final seen = <int>{};
    final misses = <int, int>{};
    bool open(int i) => _actions[i].job != null && !(_actions[i].progress?.settled ?? false);
    while (true) {
      await Future<void>.delayed(jobPollInterval);
      if (seq != _jobsSeq || _disposed) return;
      final indexes = [
        for (var i = 0; i < _actions.length; i++)
          if (open(i)) i,
      ];
      if (indexes.isEmpty) return;
      final timeUp = !_now().isBefore(deadline);
      final lists = <ServerId, List<ServerJob>?>{};
      for (final i in indexes) {
        final watch = _actions[i].job!;
        if (!lists.containsKey(watch.serverId)) {
          List<ServerJob>? jobs;
          try {
            jobs = await _listJobs(watch.serverId);
          } catch (e) {
            // One failed look is not a failed job; the next one may answer.
            appLogger.d('Assistant job poll failed', error: e.runtimeType);
          }
          if (seq != _jobsSeq || _disposed) return;
          lists[watch.serverId] = jobs;
        }
        final jobs = lists[watch.serverId];
        var next = jobs == null ? null : assistantJobLook(watch, jobs, seen: seen.contains(i));
        if (next?.phase == AssistantJobPhase.running) seen.add(i);
        if (next == null && jobs != null && !seen.contains(i) && (misses[i] = (misses[i] ?? 0) + 1) >= 3) {
          // Nothing to follow: say what is known, that it started.
          next = const AssistantJobProgress(AssistantJobPhase.started);
        }
        if (timeUp && !(next?.settled ?? false)) {
          next = AssistantJobProgress(
            seen.contains(i) ? AssistantJobPhase.background : AssistantJobPhase.started,
            percent: next?.percent,
          );
        }
        if (next != null) _actions[i] = _actions[i].withProgress(next);
      }
      _notify();
    }
  }

  Future<List<ServerJob>?> _listJobs(ServerId serverId) {
    final override = _jobsFor;
    if (override != null) return override(serverId);
    // Authority is read live: a role lost mid-scan stops the look.
    final client = _buildContext(null).admin<ServerJobsClient>(serverId);
    return client == null ? Future.value(const []) : client.listJobs();
  }
}
