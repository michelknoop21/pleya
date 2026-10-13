import '../services/jellyfin_client.dart';
import 'assistant_run.dart';
import 'assistant_tool_context.dart';
import 'assistant_tools.dart';

/// The five kinds of start question. The greeting shows three questions from
/// three different groups, so one summon never shows only library questions.
enum AssistantCapabilityGroup { watch, discover, yours, household, manage }

// The catalog answers from the live servers: with none online a library
// question has nothing to show, though search_catalog itself is still served.
bool _serverOnline(AssistantToolContext ctx) => ctx.userServers.any((id) => ctx.userClient(id) != null);

bool _trendingSource(AssistantToolContext ctx) => ctx.requests?.client() != null || ctx.titleFacts?.tmdb() != null;

bool _playerActive(AssistantToolContext ctx) => ctx.playback?.available() ?? false;

bool _traktReadable(AssistantToolContext ctx) => ctx.trakt != null && ctx.trakt!.blocked() == null;

// recommend_together proves "unwatched by everyone" only as a Jellyfin
// administrator; anywhere else it answers that it cannot.
bool _cohortServer(AssistantToolContext ctx) => ctx.userServers.any(
  (id) => switch (ctx.adminClient(id)) {
    final JellyfinClient client => !client.connection.isEmby,
    _ => false,
  },
);

/// Something Big P can do that a start question may show. One source for the
/// greeting on every platform: the texts are looked up per value
/// (`assistantExamples`), so a value without a text does not compile.
///
/// A capability is offered when at least one of its [tools] is served for the
/// profile and its servers (`assistantServedTools`) and [works] agrees. [tools]
/// names only tools the question is meant to reach, never a helper on the way.
/// A tool without a start question is listed, with the reason, in
/// `test/assistant/assistant_capabilities_test.dart`; a test walks every tool.
enum AssistantCapability {
  tonight(AssistantCapabilityGroup.watch, {'search_catalog', 'find_media'}, works: _serverOnline),
  startSeries(AssistantCapabilityGroup.watch, {'search_catalog', 'find_media'}, works: _serverOnline),
  forKids(AssistantCapabilityGroup.watch, {'search_catalog', 'find_media'}, works: _serverOnline),
  unwatched(AssistantCapabilityGroup.watch, {'search_catalog'}, works: _serverOnline),
  recentlyAdded(AssistantCapabilityGroup.watch, {'search_catalog'}, works: _serverOnline),
  describe(AssistantCapabilityGroup.watch, {'find_title'}),
  trending(AssistantCapabilityGroup.discover, {'trending_titles'}, works: _trendingSource),
  request(AssistantCapabilityGroup.discover, {'discover_request_titles'}),
  trakt(AssistantCapabilityGroup.discover, {'trakt_watchlist'}, works: _traktReadable),
  history(AssistantCapabilityGroup.yours, {'my_watching'}),
  memory(AssistantCapabilityGroup.yours, {'recall_memory'}),
  watchStats(AssistantCapabilityGroup.household, {'watch_stats'}),
  together(AssistantCapabilityGroup.household, {'recommend_together'}, works: _cohortServer),
  servers(AssistantCapabilityGroup.manage, {'list_servers'}),
  jobs(AssistantCapabilityGroup.manage, {'list_jobs'}),
  retryJobs(AssistantCapabilityGroup.manage, {'retry_job'}),
  users(AssistantCapabilityGroup.manage, {'list_users'}),
  compare(AssistantCapabilityGroup.manage, {'compare_servers'}),
  doctor(AssistantCapabilityGroup.manage, {'diagnose_library'}, works: _serverOnline),
  homeRow(AssistantCapabilityGroup.manage, {'create_home_row'}, works: _serverOnline),
  scan(AssistantCapabilityGroup.manage, {'scan_library'}),
  playback(AssistantCapabilityGroup.manage, {'diagnose_playback'}, works: _playerActive);

  const AssistantCapability(this.group, this.tools, {this.works});

  final AssistantCapabilityGroup group;
  final Set<String> tools;

  /// Where a tool's own `serves` is wider than "this question works here".
  final bool Function(AssistantToolContext ctx)? works;

  /// The start questions when nothing is served (every server offline): the
  /// greeting still shows three, and the answer says what is unreachable.
  static const fallback = [tonight, startSeries, recentlyAdded];
}

/// The capabilities [ctx] can answer right now, from the tools it serves.
///
/// [kids]: a children's profile gets watch questions only, and only those a
/// tool answers through the age gate (`kidsToolPolicy`): a tool that is blocked
/// or returns no titles never carries a question there.
Set<AssistantCapability> assistantCapabilitiesFor(
  AssistantToolContext ctx, {
  required bool kids,
  Iterable<AssistantTool>? tools,
}) {
  final served = {for (final tool in assistantServedTools(ctx, tools ?? assistantTools).keys) tool.name};
  bool reaches(String tool) => served.contains(tool) && (!kids || kidsToolPolicy[tool] == KidsTool.gated);
  return {
    for (final c in AssistantCapability.values)
      if ((!kids || c.group == AssistantCapabilityGroup.watch) && c.tools.any(reaches) && (c.works?.call(ctx) ?? true))
        c,
  };
}
