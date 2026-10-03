import 'dart:math';
import '../media/media_backend.dart';
import '../media/unified/unified_media_group.dart';
import '../services/unified_catalog/home_custom_row.dart';
import '../services/unified_catalog/home_custom_row_loader.dart';
import '../services/unified_catalog/unified_catalog_filters.dart';
import '../media/library_query.dart';
import '../media/unified/canonical_media_identity.dart';
import '../media/unified/identity_evidence.dart';
import '../media/unified/unified_media_source.dart';
import '../media/watch_session.dart';
import '../models/tautulli/tautulli_models.dart';
import '../services/now_watching_service.dart';
import '../services/tautulli/tautulli_client.dart';
import '../services/unified_catalog/grouping_service.dart';
import '../services/unified_catalog/identity_resolver.dart';
import '../i18n/strings.g.dart';
import '../models/seerr/seerr_media.dart';
import '../services/seerr/seerr_client.dart';
import '../services/seerr/seerr_constants.dart';
import '../services/jellyfin_client.dart';
import '../services/pleya_server_client.dart';
import '../media/ids.dart';
import '../media/episode_collection.dart';
import '../media/media_item.dart';
import '../media/participant_evidence.dart';
import 'assistant_strict_filters.dart';
import '../profiles/profile_server_identity.dart';
import '../media/media_server_client.dart';
import '../models/download_models.dart';
import '../models/plex/plex_subtitle_search_result.dart';
import '../services/plex_client.dart';
import '../media/media_kind.dart';
import '../media/media_library.dart';
import '../media/server_administration.dart';
import '../services/data_aggregation_service.dart' show filterHiddenLibraryItems;
import '../utils/app_logger.dart';
import '../utils/global_key_utils.dart';
import 'assistant_find_match.dart';
import 'assistant_find_route.dart';
import 'assistant_tool_context.dart';

part 'assistant_tools_general.dart';
part 'assistant_tools_admin.dart';
part 'assistant_tools_catalog.dart';
part 'assistant_tools_catalog_query.dart';
part 'assistant_tools_insights.dart';
part 'assistant_tools_insights_watch.dart';
part 'assistant_tools_requests.dart';
part 'assistant_tools_requests_options.dart';
part 'assistant_tools_find.dart';
part 'assistant_tools_media.dart';
part 'assistant_tools_recommendations.dart';

enum AssistantToolRisk { read, mutation, sensitive }

/// What a tool hands back: data for the model, or an action that waits for
/// the user's confirmation in Pleya.
sealed class AssistantToolOutcome {
  const AssistantToolOutcome();
}

/// Something the UI shows next to Big P's answer: a grid of titles, a list
/// of servers that differ. Each domain defines its own subclasses.
abstract class AssistantDisplay {
  const AssistantDisplay();
}

class AssistantToolResult extends AssistantToolOutcome {
  const AssistantToolResult(this.data, {this.record, this.display});
  final Map<String, Object?> data;

  /// Shown by the UI; never sent to the model.
  final AssistantDisplay? display;

  /// Set for a mutation that ran, so the UI can show what happened.
  final AssistantActionRecord? record;
}

enum AssistantActionKind {
  scanLibrary,
  refreshMetadata,
  cancelJob,
  retryJob,
  createUser,
  setLibraryAccess,
  removeUser,
  createHomeRow,
  createCollection,
  requestTitle,
  downloadEpisodes,
  downloadSubtitle,
}

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
    this.items = const [],
    this.preview,
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

  /// Titles the action is about (a new row, a collection), for the card.
  final List<String> items;

  /// A richer preview the card can render, when a list of titles is not enough.
  final AssistantDisplay? preview;

  /// Runs the action. [password] comes from Pleya's secure input, never
  /// from the model. A result with `done: false` means nothing changed, and
  /// the run then does not list the action as done.
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
  // Format characters too (bidi overrides, zero-width): they can make a card
  // show a different title than the one acted on.
  final clean = (value ?? '').replaceAll(RegExp(r'[\x00-\x1F\x7F]|\p{Cf}', unicode: true), ' ').trim();
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
  ..._generalTools,
  ..._adminTools,
  ..._catalogTools,
  ..._recommendationTools,
  ..._insightTools,
  ..._requestTools,
  ..._findTools,
  ..._mediaTools,
];
