import '../../../assistant/assistant_capabilities.dart';
import '../../../i18n/strings.g.dart';

/// The start questions that show [capability], in the UI's language. Every
/// capability has at least one: a new value without a text does not compile.
List<String> assistantExamples(AssistantCapability capability) {
  final e = t.assistant.examples;
  return switch (capability) {
    AssistantCapability.tonight => e.tonight,
    AssistantCapability.startSeries => e.startSeries,
    AssistantCapability.forKids => e.forKids,
    AssistantCapability.unwatched => e.unwatched,
    AssistantCapability.recentlyAdded => e.recentlyAdded,
    AssistantCapability.describe => e.describe,
    AssistantCapability.trending => e.trending,
    AssistantCapability.request => e.request,
    AssistantCapability.trakt => e.trakt,
    AssistantCapability.history => e.history,
    AssistantCapability.memory => e.memory,
    AssistantCapability.watchStats => e.watchStats,
    AssistantCapability.together => e.together,
    AssistantCapability.servers => e.servers,
    AssistantCapability.jobs => e.jobs,
    AssistantCapability.retryJobs => e.retryJobs,
    AssistantCapability.users => e.users,
    AssistantCapability.compare => e.compare,
    AssistantCapability.doctor => e.doctor,
    AssistantCapability.homeRow => e.homeRow,
    AssistantCapability.scan => e.scan,
    AssistantCapability.playback => e.playback,
  };
}
