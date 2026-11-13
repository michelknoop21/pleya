/// One session-wide answer per external-id lookup, shared by every unified
/// projection (Home, Verder kijken, search). A series' provider numbers do not
/// change while the app runs, and Verder kijken asks for them on every
/// refresh; without this each refresh cost one request per series per server.
library;

import 'dart:async';

import '../../media/ids.dart';
import '../../utils/external_ids.dart';
import '../multi_server_manager.dart';
import '../pleya_server_client.dart';

/// How long an answer is reused. A rematch on the server shows up after this.
const identityLookupTtl = Duration(minutes: 30);

/// How long a caller waits for one answer. Verder kijken awaits these before
/// the row is shown, and Home awaits that row, so a server that lists its
/// titles but then answers item requests slowly must not hold Home for the
/// transport timeouts. The request itself runs on and fills the cache.
const identityLookupPatience = Duration(seconds: 3);

/// After a server kept a caller waiting that long, further lookups on it fail
/// at once for this long instead of each waiting again.
const identityLookupCooldown = Duration(seconds: 60);
const _maxEntries = 4000;

class _Entry {
  _Entry(this.future, this.storedAt);
  final Future<ExternalIds> future;
  final DateTime storedAt;
}

class _State {
  final Map<String, _Entry> answers = {};
  final Map<String, DateTime> slowSince = {};
}

final Expando<_State> _stateOf = Expando('identityLookupCache');

/// The provider numbers of [targetId] on [serverId], through [manager]'s live
/// client. Throws when the server has no client, the lookup fails or the
/// server is too slow, so the caller degrades that one item to guid-only
/// evidence and the row shows two cards instead of waiting.
///
/// Not remembered: a failed lookup (the next round retries it), and anything
/// from a Pleya Server. Its answer is only proof together with the identity
/// source the client reports at that moment (`canTrustStoredIdentity`), and
/// the client keeps its own short cache, which also sees a rematch sooner.
Future<ExternalIds> fetchExternalIdsForIdentity(
  MultiServerManager manager,
  String serverId,
  String targetId, {
  DateTime Function() now = DateTime.now,
  Duration patience = identityLookupPatience,
}) {
  final client = manager.getClient(ServerId(serverId));
  if (client == null) return Future.error(StateError('No client for server $serverId'));
  final state = _stateOf[manager] ??= _State();

  final key = '$serverId:$targetId';
  final cacheable = client is! PleyaServerClient;
  final hit = cacheable ? state.answers[key] : null;
  if (hit != null && now().difference(hit.storedAt) < identityLookupTtl) return _patient(hit.future, patience);

  final slow = state.slowSince[serverId];
  if (slow != null) {
    if (now().difference(slow) < identityLookupCooldown) {
      return Future.error(TimeoutException('Server $serverId answered identity lookups too slowly'));
    }
    state.slowSince.remove(serverId);
  }

  final future = client.fetchExternalIds(targetId);
  if (cacheable) {
    if (state.answers.length >= _maxEntries) state.answers.clear();
    final entry = _Entry(future, now());
    state.answers[key] = entry;
    // Ignored here, reported to the caller below: this only keeps a failed
    // answer out of the cache.
    future.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(state.answers[key], entry)) state.answers.remove(key);
      },
    );
  }
  return _patient(future, patience).catchError((Object error) {
    if (error is TimeoutException) state.slowSince[serverId] = now();
    throw error;
  });
}

Future<ExternalIds> _patient(Future<ExternalIds> future, Duration patience) {
  // A late failure of a request nobody waits for any more must not surface as
  // an unhandled error.
  future.then<void>((_) {}, onError: (Object _) {});
  return future.timeout(patience);
}
