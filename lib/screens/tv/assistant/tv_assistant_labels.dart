/// Text for Big P's surface, built from Pleya data only: tool names, server
/// names and action records the run validated. Model prose never passes
/// through here (DEC-142).
library;

import '../../../assistant/assistant_controller.dart';
import '../../../assistant/assistant_provider.dart';
import '../../../assistant/assistant_run.dart';
import '../../../assistant/assistant_tools.dart';
import '../../../i18n/strings.g.dart';

String assistantToolLabel(String tool) {
  final s = t.assistant.steps;
  return switch (tool) {
    'list_servers' => s.listServers,
    'list_libraries' => s.listLibraries,
    'find_media' => s.findMedia,
    'list_jobs' => s.listJobs,
    'list_users' => s.listUsers,
    'scan_library' => s.scanLibrary,
    'refresh_metadata' => s.refreshMetadata,
    'cancel_job' => s.cancelJob,
    'retry_job' => s.retryJob,
    'create_user' => s.createUser,
    'set_user_library_access' => s.setUserLibraryAccess,
    'remove_user' => s.removeUser,
    'search_catalog' => s.searchCatalog,
    'create_home_row' => s.createHomeRow,
    'create_collection' => s.createCollection,
    'compare_servers' => s.compareServers,
    'watch_stats' => s.watchStats,
    'download_next' => s.downloadNext,
    'find_subtitles' => s.findSubtitles,
    'download_subtitle' => s.downloadSubtitle,
    'find_request_title' => s.findRequestTitle,
    'discover_request_titles' => s.discoverRequestTitles,
    'request_title' => s.requestTitle,
    'find_title' => s.findTitle,
    _ => s.fallback,
  };
}

/// "Zolder · Bibliotheek scannen", or the step alone for a serverless tool.
String assistantStepLabel(AssistantStep step) {
  final label = assistantToolLabel(step.tool);
  final server = step.serverName;
  return server == null || server.isEmpty ? label : t.assistant.steps.withServer(server: server, step: label);
}

String assistantActionKindLabel(AssistantActionKind kind) {
  final a = t.assistant.actions;
  return switch (kind) {
    AssistantActionKind.scanLibrary => a.scanLibrary,
    AssistantActionKind.refreshMetadata => a.refreshMetadata,
    AssistantActionKind.cancelJob => a.cancelJob,
    AssistantActionKind.retryJob => a.retryJob,
    AssistantActionKind.createUser => a.createUser,
    AssistantActionKind.setLibraryAccess => a.setLibraryAccess,
    AssistantActionKind.removeUser => a.removeUser,
    AssistantActionKind.createHomeRow => a.createHomeRow,
    AssistantActionKind.createCollection => a.createCollection,
    AssistantActionKind.requestTitle => a.requestTitle,
    AssistantActionKind.downloadEpisodes => a.downloadEpisodes,
    AssistantActionKind.downloadSubtitle => a.downloadSubtitle,
  };
}

/// "Scan gestart · Films · Zolder" (mockup 38 G).
String assistantActionLabel(AssistantActionRecord record) => [
  assistantActionKindLabel(record.kind),
  record.subject,
  record.serverName,
].where((part) => part.isNotEmpty).join(' · ');

String assistantConfirmTitle(AssistantActionKind kind) {
  final c = t.assistant.confirm.titles;
  return switch (kind) {
    AssistantActionKind.scanLibrary => c.scanLibrary,
    AssistantActionKind.refreshMetadata => c.refreshMetadata,
    AssistantActionKind.cancelJob => c.cancelJob,
    AssistantActionKind.retryJob => c.retryJob,
    AssistantActionKind.createUser => c.createUser,
    AssistantActionKind.setLibraryAccess => c.setLibraryAccess,
    AssistantActionKind.removeUser => c.removeUser,
    AssistantActionKind.createHomeRow => c.createHomeRow,
    AssistantActionKind.createCollection => c.createCollection,
    AssistantActionKind.requestTitle => c.requestTitle,
    AssistantActionKind.downloadEpisodes => c.downloadEpisodes,
    AssistantActionKind.downloadSubtitle => c.downloadSubtitle,
  };
}

String? assistantNoteLabel(AssistantBackendNote note) => switch (note) {
  AssistantBackendNote.none => null,
  AssistantBackendNote.plexManagedHomeUser => t.assistant.notes.plexManagedHomeUser,
  AssistantBackendNote.plexShare => t.assistant.notes.plexShare,
  AssistantBackendNote.plexHomeMember => t.assistant.notes.plexHomeMember,
  AssistantBackendNote.replacesAllAccess => t.assistant.notes.replacesAllAccess,
};

/// Why a run ended without an answer, in Pleya's words. Null for a run that
/// answered.
String? assistantEndLabel(AssistantRunEnd? end, AssistantModelError? providerError) {
  final e = t.assistant.ends;
  return switch (end) {
    AssistantRunEnd.answered => null,
    AssistantRunEnd.stepLimit => e.stepLimit,
    AssistantRunEnd.notEntitled => e.notEntitled,
    AssistantRunEnd.noTools => e.noTools,
    AssistantRunEnd.toolsUnsupported => e.toolsUnsupported,
    AssistantRunEnd.providerError => switch (providerError) {
      AssistantModelError.unauthorized => e.providerUnauthorized,
      AssistantModelError.unreachable => e.providerUnreachable,
      AssistantModelError.timeout => e.providerTimeout,
      AssistantModelError.toolsUnsupported => e.toolsUnsupported,
      AssistantModelError.badResponse || null => e.providerBadResponse,
    },
    null => e.nothingChanged,
  };
}

/// The headline under the question: the model's answer when there is one,
/// else Pleya's reason the run ended. Several tasks get Pleya's own count.
String assistantHeadline(AssistantController c) {
  if (c.tasks.length > 1) return assistantTasksHeadline(c.tasks);
  if (c.answer.trim().isNotEmpty) return c.answer.trim();
  if (!c.resultIsError) return '';
  // The chosen model is gone from the server: say so, it is the one thing
  // the user can fix (in Big P instellen).
  if (c.modelMissing) return t.assistant.ends.modelMissing;
  return assistantEndLabel(c.lastEnd, c.lastProviderError) ?? t.assistant.ends.nothingChanged;
}

bool assistantTaskCancellable(AssistantTask task) => switch (task.status) {
  AssistantTaskStatus.pending || AssistantTaskStatus.running || AssistantTaskStatus.waitingForConfirmation => true,
  AssistantTaskStatus.completed || AssistantTaskStatus.failed || AssistantTaskStatus.cancelled => false,
};

/// "Bezig met 3 taken · 1 klaar" while any task can still be stopped, then
/// how many of them ended well. Counted by Pleya, not said by the model.
String assistantTasksHeadline(List<AssistantTask> tasks) {
  final done = tasks.where((task) => task.status == AssistantTaskStatus.completed).length;
  if (tasks.any(assistantTaskCancellable)) return t.assistant.tasks.working(count: tasks.length, done: done);
  return done == tasks.length
      ? t.assistant.tasks.allDone(count: done)
      : t.assistant.tasks.someDone(count: tasks.length, done: done);
}

/// A task card's second line: where the task stands, and what Pleya knows
/// about it (the step it is on, what it did, why the run ended). A cancelled
/// task says only that: a call already sent is not taken back by cancelling.
({String status, String? detail}) assistantTaskStatusLabel(AssistantTask task) {
  final s = t.assistant.tasks;
  return switch (task.status) {
    AssistantTaskStatus.pending => (status: s.queued, detail: null),
    AssistantTaskStatus.running => (
      status: s.running,
      detail: switch (task.steps.lastOrNull) {
        final step? => assistantStepLabel(step),
        null => null,
      },
    ),
    AssistantTaskStatus.waitingForConfirmation => (status: s.waiting, detail: null),
    AssistantTaskStatus.completed => (
      status: switch (task.actions.lastOrNull) {
        final action? => assistantActionKindLabel(action.kind),
        null => switch (task.displays.whereType<AssistantTitleMatches>().fold(0, (n, d) => n + d.matches.length)) {
          0 => task.displays.any((d) => d is AssistantRequestOptions) ? s.choose : s.completed,
          final found => s.found(n: found),
        },
      },
      detail: null,
    ),
    AssistantTaskStatus.failed => (
      status: s.failed,
      detail: task.modelMissing
          ? t.assistant.ends.modelMissing
          : task.lastEnd == null
          ? null
          : assistantEndLabel(task.lastEnd, task.providerError),
    ),
    AssistantTaskStatus.cancelled => (status: s.cancelled, detail: null),
  };
}
