/// Pleya Fly Meenemen (A-23e): the Apple TV plays on and a phone plays the
/// same title in sync, through a Watch Together session the Apple TV opens for
/// it. No code and no join screen: the session id travels inside the
/// authenticated Companion Remote session, never in a beacon.
///
/// Two ways in. The phone asks the Apple TV with [RemoteCommandType.follow]
/// (the Home card, 45-h), and the Apple TV answers through `syncState`. Or the
/// Apple TV's Fly picker sends a [PlaybackHandoffRequest] that carries the
/// session (45-t3), which reuses the whole A-23d path, profile switch included.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// What the Apple TV plays, and the session to follow it in. A peek has no
/// [sessionId]: the Home card only shows what plays.
@immutable
class FlyFollowOffer {
  const FlyFollowOffer({
    required this.serverId,
    required this.itemId,
    required this.positionMs,
    required this.title,
    required this.from,
    this.sessionId,
    this.relayUrl,
  });

  final String serverId;
  final String itemId;
  final int positionMs;
  final String title;

  /// Name of the Apple TV ("Woonkamer").
  final String from;

  /// The Watch Together session, a [flySessionIdLength]-character secret.
  final String? sessionId;

  /// The relay of the Apple TV when it does not use the built-in one.
  final String? relayUrl;

  FlyFollowOffer withSession(String sessionId, {String? relayUrl}) => FlyFollowOffer(
    serverId: serverId,
    itemId: itemId,
    positionMs: positionMs,
    title: title,
    from: from,
    sessionId: sessionId,
    relayUrl: relayUrl,
  );

  Map<String, dynamic> toData() => {
    'serverId': serverId,
    'itemId': itemId,
    'positionMs': positionMs,
    'title': title,
    'from': from,
    'sessionId': ?sessionId,
    'relayUrl': ?relayUrl,
  };

  /// Null for a malformed offer: it came over the wire. A session id that is
  /// not a fly id, or a relay that is not http(s), drops the whole offer.
  static FlyFollowOffer? fromData(Map<String, dynamic>? data) {
    if (data == null) return null;
    final serverId = data['serverId'];
    final itemId = data['itemId'];
    final positionMs = data['positionMs'];
    if (serverId is! String || serverId.isEmpty) return null;
    if (itemId is! String || itemId.isEmpty) return null;
    if (positionMs is! int || positionMs < 0) return null;
    final sessionId = data['sessionId'];
    if (sessionId != null && (sessionId is! String || !isFlySessionId(sessionId))) return null;
    final relayUrl = data['relayUrl'];
    if (relayUrl != null && (relayUrl is! String || !isRelayUrl(relayUrl))) return null;
    final title = data['title'];
    final from = data['from'];
    return FlyFollowOffer(
      serverId: serverId,
      itemId: itemId,
      positionMs: positionMs,
      title: title is String ? title : '',
      from: from is String ? from : '',
      sessionId: sessionId as String?,
      relayUrl: relayUrl as String?,
    );
  }
}

/// Why the Apple TV has nothing to follow.
enum FlyFollowRefusal {
  /// No player is open.
  nothing,

  /// A local folder, Pleya Share or live TV: the phone cannot open it there.
  unsupported,

  /// Samen kijken with a code runs already; Meenemen does not take it over.
  busy,

  /// The session could not be opened (relay down), or no answer came.
  failed,
}

/// The Apple TV's answer: an [offer], or a [refusal] with the [title] when one plays.
@immutable
class FlyFollowAnswer {
  const FlyFollowAnswer.offer(FlyFollowOffer this.offer) : refusal = null, title = null;
  const FlyFollowAnswer.refused(FlyFollowRefusal this.refusal, {this.title}) : offer = null;

  final FlyFollowOffer? offer;
  final FlyFollowRefusal? refusal;

  /// What plays when the refusal is about the title (unsupported, busy).
  final String? title;
}

const flyFollowRequestKey = 'id';
const flyFollowPeekKey = 'peek';
const flyFollowAnswerKey = 'followAnswer';
const flyFollowOfferKey = 'followOffer';
const flyFollowRefusalKey = 'followRefusal';
const flyFollowTitleKey = 'followTitle';

/// The `syncState` data that answers request [id].
Map<String, dynamic> flyFollowAnswerData(String id, FlyFollowAnswer answer) => {
  flyFollowAnswerKey: id,
  if (answer.offer case final offer?) flyFollowOfferKey: offer.toData(),
  if (answer.refusal case final refusal?) flyFollowRefusalKey: refusal.name,
  flyFollowTitleKey: ?answer.title,
};

/// Reads an answer from `syncState` data; null when the data is no answer.
({String id, FlyFollowAnswer answer})? parseFlyFollowAnswer(Map<String, dynamic>? data) {
  final id = data?[flyFollowAnswerKey];
  if (id is! String) return null;
  final offer = FlyFollowOffer.fromData(switch (data?[flyFollowOfferKey]) {
    final Map<String, dynamic> map => map,
    _ => null,
  });
  if (offer != null) return (id: id, answer: FlyFollowAnswer.offer(offer));
  final refusal = FlyFollowRefusal.values.asNameMap()[data?[flyFollowRefusalKey]] ?? FlyFollowRefusal.failed;
  final title = data?[flyFollowTitleKey];
  return (id: id, answer: FlyFollowAnswer.refused(refusal, title: title is String ? title : null));
}

/// A fly session id: long enough not to be guessed (26 characters of a
/// 32-letter alphabet, 130 bits from [Random.secure]) where a code of Samen
/// kijken has five. Upper case, because the relay upper-cases session ids.
const flySessionIdLength = 26;
const _flyAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

String generateFlySessionId([Random? random]) {
  final source = random ?? Random.secure();
  return String.fromCharCodes(
    List.generate(flySessionIdLength, (_) => _flyAlphabet.codeUnitAt(source.nextInt(_flyAlphabet.length))),
  );
}

bool isFlySessionId(String id) => id.length == flySessionIdLength && id.split('').every(_flyAlphabet.contains);

/// A relay the phone may use: an absolute http(s) address.
bool isRelayUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;
}

/// Matches the Apple TV's answers to the follow requests a phone has out.
class FlyFollowTracker {
  final Map<String, Completer<FlyFollowAnswer>> _pending = {};

  /// The answer to [id], or [FlyFollowRefusal.failed] after [timeout].
  Future<FlyFollowAnswer> wait(String id, Duration timeout) async {
    final completer = _pending[id] = Completer<FlyFollowAnswer>();
    final timer = Timer(timeout, () => complete(id, const FlyFollowAnswer.refused(FlyFollowRefusal.failed)));
    try {
      return await completer.future;
    } finally {
      timer.cancel();
      if (identical(_pending[id], completer)) _pending.remove(id);
    }
  }

  void complete(String id, FlyFollowAnswer answer) {
    final completer = _pending[id];
    if (completer != null && !completer.isCompleted) completer.complete(answer);
  }

  /// The connection dropped: nothing will answer any more.
  void failAll() {
    for (final id in _pending.keys.toList()) {
      complete(id, const FlyFollowAnswer.refused(FlyFollowRefusal.failed));
    }
  }

  void handleSyncState(Map<String, dynamic>? data) {
    final parsed = parseFlyFollowAnswer(data);
    if (parsed != null) complete(parsed.id, parsed.answer);
  }
}

/// Apple TV side: answers the follow request in [data] with what the open
/// [player] says, or that nothing plays. A request without `peek: false`
/// only peeks, so a malformed one never opens a session.
Future<void> answerFlyFollowRequest(
  Map<String, dynamic>? data, {
  required Future<FlyFollowAnswer> Function({required bool peek})? player,
  required void Function(Map<String, dynamic> data) send,
}) async {
  final id = data?[flyFollowRequestKey];
  // Bounded: ids arrive from the network and go back out in the answer.
  if (id is! String || id.isEmpty || id.length > 64) return;
  final peek = data?[flyFollowPeekKey] != false;
  var answer = const FlyFollowAnswer.refused(FlyFollowRefusal.nothing);
  if (player != null) {
    try {
      answer = await player(peek: peek);
    } catch (e) {
      answer = const FlyFollowAnswer.refused(FlyFollowRefusal.failed);
    }
  }
  send(flyFollowAnswerData(id, answer));
}
