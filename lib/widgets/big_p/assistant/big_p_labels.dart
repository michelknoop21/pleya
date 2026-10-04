/// Text for Big P's surface, built from Pleya data only: tool names, server
/// names and action records the run validated. Model prose never passes
/// through here (DEC-142).
library;

import '../../../assistant/assistant_controller.dart';
import '../../../assistant/assistant_provider.dart';
import '../../../assistant/assistant_run.dart';
import '../../../assistant/assistant_tools.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_kind.dart';
import '../big_p_avatar.dart';

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

/// "Scan gestart · Films · Zolder" (mockup 38 G), or while Pleya follows
/// the job: "Scan loopt · 40% · Films · Zolder", "Scan klaar · Films · Zolder".
String assistantActionLabel(AssistantActionRecord record) => [
  _jobPhaseLabel(record) ?? assistantActionKindLabel(record.kind),
  if (record.progress case AssistantJobProgress(phase: AssistantJobPhase.running, :final percent?)) '$percent%',
  record.subject,
  record.serverName,
].where((part) => part.isNotEmpty).join(' · ');

String? _jobPhaseLabel(AssistantActionRecord record) {
  final j = t.assistant.jobs;
  final (running, done, failed, background) = switch (record.kind) {
    AssistantActionKind.scanLibrary => (
      j.scanLibrary.running,
      j.scanLibrary.done,
      j.scanLibrary.failed,
      j.scanLibrary.background,
    ),
    _ => (j.retryJob.running, j.retryJob.done, j.retryJob.failed, j.retryJob.background),
  };
  return switch (record.progress?.phase) {
    AssistantJobPhase.running => running,
    AssistantJobPhase.done => done,
    AssistantJobPhase.failed => failed,
    AssistantJobPhase.background => background,
    // Not followed: the action's own "gestart".
    AssistantJobPhase.started || null => null,
  };
}

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
/// else Pleya's reason the run ended.
String assistantHeadline(AssistantController c) {
  if (assistantPlainAnswer(c.answer) case final answer when answer.isNotEmpty) return answer;
  if (!c.resultIsError) return '';
  // The chosen model is gone from the server: say so, it is the one thing
  // the user can fix (in Big P instellen).
  if (c.modelMissing) return t.assistant.ends.modelMissing;
  return assistantEndLabel(c.lastEnd, c.lastProviderError) ?? t.assistant.ends.nothingChanged;
}

/// Three questions that follow from what the run showed, in the UI's
/// language, after every answer. Pleya builds them from the displays and the
/// actions, never from model prose, and each one stands on its own: a new ask
/// carries no memory of this one. They carry no server, user or title names:
/// a follow-up is sent as the user's own words, and those names come from
/// servers, not from the user. The question just asked is never offered.
List<String> assistantFollowUps(List<AssistantDisplay> displays, {bool jobs = false, String? prompt}) {
  final f = t.assistant.followUp;
  final fitting = <String>[
    // Only after a job Pleya follows (a scan, a refresh): those are admin
    // tools, and a request or download has no task to ask about.
    if (jobs) ...[f.jobs, f.failedJobs],
    for (final d in displays)
      ...switch (d) {
        AssistantWatchStats(days: null) => [f.watchToday, f.watchWeek, f.watchMonth],
        AssistantWatchStats(:final days?) => [
          f.watchNow,
          if (days < 30) f.watchMonth else f.watchWeek,
          if (days > 1) f.watchToday else f.watchWeek,
        ],
        AssistantServerComparison(:final kind) => [
          kind == MediaKind.show ? f.missingMovies : f.missingShows,
          f.unwatched,
        ],
        AssistantRequestOptions() => [f.popular, f.recent],
        AssistantTitleMatches() || AssistantMediaGrid() => [f.tonight, f.unwatched, f.recent],
        _ => const <String>[],
      },
    // Always three: the general questions fill what the result left open.
    f.watchWeek, f.tonight, f.recent, f.unwatched,
  ];
  String key(String q) => q.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');
  final asked = key(prompt ?? '');
  return [
    for (final q in {...fitting})
      if (key(q) != asked) q,
  ].take(3).toList();
}

// ponytail: one pass over paired marks on one line; nested emphasis keeps
// its inner marks. A Markdown renderer is the upgrade if answers need more.
final _markdownMarks = RegExp(
  r'(?<![\w*])\*{2,3}(\S(?:[^\n]*?\S)?)\*{2,3}(?![\w*])|(?<![\w*])\*(\S(?:[^*\n]*?\S)?)\*(?![\w*])|(?<!\w)`([^`\n]+)`(?!\w)'
  r'|(?<![\w_])_{1,2}(\S(?:[^_\n]*?\S)?)_{1,2}(?![\w_])',
);
final _markdownHeading = RegExp(r'^#{1,6}\s+', multiLine: true);
final _marksOnly = RegExp(r'^[\s*`#]+$');
final _markdownLink = RegExp(r'!?\[([^\]\n]+)\]\((?:[^)\s]+)\)');
final _markdownBullet = RegExp(r'^[ \t]*[-*+][ \t]+', multiLine: true);

// One or two digits: "1917. Oorlogsfilm." is a title, not item 1917.
final _listItem = RegExp(r'^\s*(?:\d{1,2}[.)]|•)\s');

/// The answer without its list items, for above cards that show the same
/// titles: the cards are the list, and the lines they free go to the cards.
// ponytail: drops every list line, also one that says more than its card.
// Matching lines to cards by title is the upgrade.
String assistantWithoutList(String answer) =>
    answer.split('\n').where((line) => !_listItem.hasMatch(line)).join('\n').trim();

// ": «A», «B» en «C»." in any language: a colon, then marked titles joined
// by commas or one short word ("en", "and", "und", "et").
final _inlineList = RegExp(r':\s*«[^»\n]*»(?:[\s,;]+(?:[^\s«»]{1,4}\s+)?«[^»\n]*»)*\s*[.!]?');

/// "Hoi Michel, ..." or, without a profile name, "Hoi, ...": the space
/// the name leaves before the punctuation goes too, in every language.
String assistantGreeting(String name) => t.assistant.idle
    .greeting(name: name.trim())
    .replaceAll(RegExp(r' +(?=[,.!?])'), '')
    .replaceAll(RegExp(' {2,}'), ' ');

/// The lead above title cards: [assistantHeadline] without the titles the
/// cards show, as a list on their own lines or as "kandidaten: «A», «B»".
/// Cut to two lines, the inline list read "Interstellar en ...".
String assistantCardsLead(AssistantController c) {
  final stripped = c.answer.replaceAll(_inlineList, '.');
  return assistantWithoutList(stripped == c.answer ? assistantHeadline(c) : assistantPlainAnswer(stripped));
}

/// The model's answer as the panel shows it. The panel draws plain text, so
/// Markdown emphasis (`**bold**`, `*italic*`, `` `code` ``) and heading marks
/// are dropped and their text kept; a link shows its text and a list item
/// a bullet; runs of blank lines become one. An asterisk inside a word or a
/// sum, as in `M*A*S*H` or `2 * 3`, stays.
String assistantPlainAnswer(String answer) => answer
    .replaceAllMapped(_markdownMarks, (m) => m[1] ?? m[2] ?? m[3] ?? m[4]!)
    .replaceAll(_markdownHeading, '')
    .replaceAllMapped(_markdownLink, (m) => m[1]!)
    .replaceAll(_markdownBullet, '• ')
    .replaceAll(RegExp('[«»]'), '')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .replaceFirst(_marksOnly, '')
    .trim();

/// Big P's mood for the controller's stand; a waiting card wins.
BigPMood bigPMood(AssistantController c) {
  if (c.pending != null) return BigPMood.attentive;
  return switch (c.state) {
    AssistantSurfaceState.idle => BigPMood.idle,
    AssistantSurfaceState.listening => BigPMood.listening,
    AssistantSurfaceState.working => BigPMood.working,
    AssistantSurfaceState.result => c.resultIsError ? BigPMood.error : BigPMood.success,
  };
}
