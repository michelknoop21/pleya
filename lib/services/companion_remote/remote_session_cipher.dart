import 'dart:async';
import 'dart:convert';

import 'remote_auth_service.dart';

/// Encrypted send/receive state of one Companion Remote session: the session
/// key, the AEAD counters and the chains that keep them in frame order.
///
/// Both directions are serialized. Frames that arrive in one TCP read start
/// their handlers back to back, so without a receive chain they would all
/// decrypt against the same expected counter and every frame after the first
/// would fail (A-23d).
class RemoteSessionCipher {
  List<int>? _key;
  int _sendCounter = 0;
  int _recvCounter = 0;
  Future<void>? _sendChain;
  Future<void>? _recvChain;
  int _consecutiveFailures = 0;

  /// Bumped on every [start] and [reset]; a frame queued for an older session
  /// is dropped instead of being decrypted with the new session's counter.
  int _generation = 0;

  bool get hasKey => _key != null;

  /// Decrypt failures in a row, since the last successful frame.
  int get consecutiveFailures => _consecutiveFailures;

  /// Begin a session with [key]: counters and chains start fresh.
  void start(List<int> key) {
    reset();
    _key = key;
  }

  void reset() {
    _generation++;
    _key = null;
    _sendCounter = 0;
    _recvCounter = 0;
    _sendChain = null;
    _recvChain = null;
    _consecutiveFailures = 0;
  }

  /// Encrypt [plaintext] with the next send counter. Callers that send over a
  /// socket go through [runSend] so the counter order is the wire order.
  Future<List<int>> encrypt(String plaintext, {required bool isHost}) async {
    final key = _key;
    if (key == null) throw StateError('No session key');
    final encrypted = await RemoteAuthService.instance.encrypt(
      key,
      utf8.encode(plaintext),
      isHost: isHost,
      counter: _sendCounter,
    );
    _sendCounter++;
    return encrypted;
  }

  /// Run [task] after every earlier send has finished.
  void runSend(Future<void> Function() task) {
    _sendChain = (_sendChain ?? Future.value()).then((_) => task());
  }

  /// Decrypt one incoming frame. The call order is the arrival order, because
  /// the socket listeners call this synchronously before their first await.
  /// Returns null when the session ended or restarted while the frame waited;
  /// throws when the frame does not authenticate.
  Future<String?> decrypt(dynamic data, {required bool fromHost}) {
    final key = _key;
    if (key == null) return Future.value(null);
    final generation = _generation;
    final previous = _recvChain ?? Future.value();
    final result = previous.then<String?>((_) async {
      if (generation != _generation) return null;
      try {
        final bytes = data is List<int> ? data : utf8.encode(data as String);
        final decrypted = await RemoteAuthService.instance.decrypt(
          bytes,
          key,
          fromHost: fromHost,
          expectedCounter: _recvCounter,
        );
        if (generation != _generation) return null;
        _recvCounter++;
        _consecutiveFailures = 0;
        return utf8.decode(decrypted);
      } catch (_) {
        if (generation == _generation) _consecutiveFailures++;
        rethrow;
      }
    });
    _recvChain = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}
