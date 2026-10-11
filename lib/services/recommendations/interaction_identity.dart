import 'dart:async';
import 'dart:convert';

import '../../database/app_database.dart';
import '../../media/ids.dart';
import '../../media/media_backend.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/identity_evidence.dart';
import '../../utils/app_logger.dart';
import '../../utils/external_ids.dart';
import '../../utils/global_key_utils.dart';

/// Who a watched title is, at title level, as written next to an interaction:
/// the movie, or the series for an episode. Built from the unified identity
/// primitives ([guidTokens], [externalIdTokens]); the row's `globalKey` stays
/// the source identity and is never replaced by this.
class InteractionIdentity {
  const InteractionIdentity({this.title, this.tokens = const {}});

  static const none = InteractionIdentity();

  final String? title;
  final Set<String> tokens;

  /// The `identity_json` column value; null when nothing is known.
  String? get tokensJson => tokens.isEmpty ? null : jsonEncode((tokens.toList()..sort()));

  bool get isEmpty => title == null && tokens.isEmpty;
}

/// The identity of [item] at title level.
///
/// An episode never contributes its own ids: only its series' guid and title
/// (`grandparentGuid`, `grandparentTitle`), because an episode id in a
/// series-level slot would make the same series on another server look like a
/// different title. [ids] must be the ids of the movie or series themselves;
/// without them a Jellyfin-family item still yields its inline `ProviderIds`.
InteractionIdentity interactionIdentityOf(MediaItem item, {ExternalIds? ids}) {
  switch (item.kind) {
    case MediaKind.episode:
      final title = _clean(item.grandparentTitle);
      return InteractionIdentity(title: title, tokens: _guidKeys('show', item.grandparentGuid, MediaKind.show));
    case MediaKind.movie:
    case MediaKind.show:
      final scope = item.kind == MediaKind.movie ? 'movie' : 'show';
      return InteractionIdentity(
        title: _clean(item.title),
        tokens: {
          ..._guidKeys(scope, item.guid, item.kind),
          ...externalIdTokens(scope: scope, ids: ids ?? _inlineIds(item)).map((t) => t.key),
        },
      );
    default:
      return InteractionIdentity.none;
  }
}

/// The catalogue guid as a token. Plex numbers items it could not match
/// `local://<ratingKey>`: a per-server number, which would "prove" two
/// different titles on two servers to be one.
Set<String> _guidKeys(String scope, String? guid, MediaKind kind) => {
  for (final t in guidTokens(scope: scope, guid: guid, kind: kind))
    if (!t.value.startsWith('local://')) t.key,
};

String? _clean(String? title) {
  final value = title?.trim();
  return value == null || value.isEmpty ? null : value;
}

/// Jellyfin and Emby ship the ids inline on every item; nothing else does.
ExternalIds _inlineIds(MediaItem item) {
  final provider = item.raw?['ProviderIds'];
  if (provider is! Map) return const ExternalIds();
  return ExternalIds.fromJellyfinProviderIds({
    for (final e in provider.entries)
      if (e.key is String) e.key as String: e.value,
  });
}

/// Whether two token sets say the same title: a shared token is proof.
bool interactionIdentityProves(Set<String> a, Set<String> b) => a.any(b.contains);

const _idSchemes = {identityTokenNamespaceImdb, identityTokenNamespaceTmdb, identityTokenNamespaceTvdb};

/// Whether two token sets say different titles: the same scope and scheme
/// (`movie:tmdb`) holding two different external ids. A differing catalogue
/// guid is not a conflict, an agent can change.
bool interactionIdentityConflicts(Set<String> a, Set<String> b) {
  final byScheme = <String, String>{};
  for (final token in a) {
    final parts = _split(token);
    if (parts != null && _idSchemes.contains(parts.$2)) byScheme['${parts.$1}:${parts.$2}'] = parts.$3;
  }
  for (final token in b) {
    final parts = _split(token);
    if (parts == null || !_idSchemes.contains(parts.$2)) continue;
    final other = byScheme['${parts.$1}:${parts.$2}'];
    if (other != null && other != parts.$3) return true;
  }
  return false;
}

(String, String, String)? _split(String token) {
  final first = token.indexOf(':');
  if (first < 0) return null;
  final second = token.indexOf(':', first + 1);
  if (second < 0) return null;
  return (token.substring(0, first), token.substring(first + 1, second), token.substring(second + 1));
}

/// Titles looked up per pass, and how often a pass may run.
const int kIdentityBackfillBatch = 25;
const Duration kIdentityBackfillInterval = Duration(minutes: 15);

/// A title that answered with nothing is asked again no sooner than this.
const Duration kIdentityRetryAfter = Duration(days: 7);

/// An answer that may only have been a failing server (an item that came back
/// empty, or a lookup that threw) is asked again sooner, so one persistently
/// failing title cannot hold the head of the queue and a restart does not cost
/// a week.
const Duration kIdentityRetryAfterEmpty = Duration(days: 1);
const Duration kIdentityRetryAfterError = Duration(hours: 1);

/// Concurrent lookups. Two keeps the burst next to Discover's own requests small.
const int kIdentityBackfillConcurrency = 2;

/// Fills in [InteractionIdentity] for rows written before v21 or without ids,
/// at most [kIdentityBackfillBatch] titles per call.
///
/// Only a title whose server has an online client is looked up, and a server
/// without one is skipped without being marked, so an offline server never
/// starves the rest. A title the server no longer has, or that now holds a
/// different year than the row recorded (a re-used server key), gets no
/// identity, only a "tried" mark. Nothing is overwritten and no row is added.
/// Returns how many titles were written.
Future<int> backfillInteractionIdentity({
  required AppDatabase database,
  required String profileId,
  required MediaServerClient? Function(ServerId serverId) clientOf,
  required Set<String> Function() enabledImportServerIds,
  required bool Function() isCurrentProfile,
  required double minWeight,
  int? nowMs,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final epoch = AppDatabase.recommendationEpoch(profileId);
  bool stillOurs() => isCurrentProfile() && AppDatabase.recommendationEpoch(profileId) == epoch;
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final gaps = await database.identityGaps(
    profileId,
    minWeight: minWeight,
    retryBeforeMs: now - kIdentityRetryAfter.inMilliseconds,
    limit: kEverSeenRowCap,
    enabledImportServerIds: enabledImportServerIds(),
  );
  // A mark that makes the title eligible again after [retryIn]: the selection
  // reads "tried more than [kIdentityRetryAfter] ago".
  Future<void> markTried(Iterable<String> keys, Duration retryIn) async {
    if (keys.isEmpty || !stillOurs()) return;
    await database.markIdentityTried(profileId, keys, triedAt: now - (kIdentityRetryAfter - retryIn).inMilliseconds);
  }

  final nothingToLearn = <String>[];
  final work = <({IdentityGap gap, MediaServerClient client, String ratingKey})>[];
  for (final gap in gaps) {
    if (work.length >= kIdentityBackfillBatch) break;
    final parsed = parseGlobalKey(gap.key);
    final client = parsed == null ? null : clientOf(parsed.serverId);
    if (parsed == null || client == null) continue;
    // Nothing more to learn: a backend that holds no external ids and a title
    // already known. Marked without a request and without taking a slot.
    final canHaveIds = client.backend == MediaBackend.plex || client.backend == MediaBackend.jellyfin;
    if (!canHaveIds && gap.hasTitle) {
      nothingToLearn.add(gap.key);
      continue;
    }
    work.add((gap: gap, client: client, ratingKey: parsed.ratingKey));
  }
  await markTried(nothingToLearn, kIdentityRetryAfter);
  var written = 0;
  Future<void> one(({IdentityGap gap, MediaServerClient client, String ratingKey}) w) async {
    MediaItem? item;
    ExternalIds? ids;
    try {
      item = await w.client.fetchItem(w.ratingKey).timeout(timeout);
      // Plex gives ids only on a second call; Jellyfin and Emby have them inline.
      if (item != null &&
          w.client.backend == MediaBackend.plex &&
          (item.kind == MediaKind.movie || item.kind == MediaKind.show)) {
        ids = await w.client.fetchExternalIds(w.ratingKey).timeout(timeout);
      }
    } catch (e) {
      // A failed lookup is not an answer, but it must not stay first in line
      // either: tried again after an hour.
      appLogger.d('identity backfill: lookup failed for ${w.gap.key}', error: e);
      await markTried([w.gap.key], kIdentityRetryAfterError);
      return;
    }
    if (!stillOurs()) return;
    if (item == null) {
      // Gone, or a server that answered badly: not known which, so tried
      // again after a day.
      await markTried([w.gap.key], kIdentityRetryAfterEmpty);
      return;
    }
    final yearMoved = w.gap.year != null && item.year != null && item.year != w.gap.year;
    final identity = yearMoved ? InteractionIdentity.none : interactionIdentityOf(item, ids: ids);
    await database.writeIdentity(profileId, w.gap.key, title: identity.title, tokens: identity.tokens, triedAt: now);
    if (!identity.isEmpty) written++;
  }

  for (var i = 0; i < work.length; i += kIdentityBackfillConcurrency) {
    if (!stillOurs()) break;
    await Future.wait([for (final w in work.skip(i).take(kIdentityBackfillConcurrency)) one(w)]);
  }
  return written;
}
