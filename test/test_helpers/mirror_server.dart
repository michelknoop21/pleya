/// A server a mirrored play reaches: records what it was told and answers what
/// a test gives it.
library;

import 'dart:async';

import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/playback_report_metadata.dart';
import 'package:pleya/media/server_capabilities.dart';

/// Behaves as Jellyfin 10.x does where a test can notice: a start is a viewing,
/// so it clears [played], adds to [playCount] and moves [lastViewedAt]. A copy
/// write only moves the position. Every write remembers the [token] that sent
/// it, because a Plex client changes token in place on a profile switch.
class MirrorServer implements MediaServerClient, CopyStateClient, FreshMediaItemClient {
  MirrorServer(
    this._id, {
    this.refuses = false,
    this.failure,
    MediaItem? item,
    this.holdUntil,
    this.backend = MediaBackend.plex,
    this.startFails = false,
    this.movesCopyWithoutViewing = true,
    this.onRead,
    this.token = 'adult',
    this.holdsTitle = false,
    this.gone = false,
    this.freshIsEmpty = false,
    this.onStart,
  }) : _item = item,
       played = (item?.viewCount ?? 0) > 0,
       playCount = item?.viewCount ?? 0,
       position = item?.viewOffsetMs ?? 0;

  final String _id;
  final bool refuses;
  final Object? failure;
  final MediaItem? _item;
  final Future<void>? holdUntil;

  /// A viewing elsewhere holds the title, as on Pleya Server.
  final bool holdsTitle;

  /// Says the copy does not exist, as a 404 does.
  final bool gone;

  /// `fetchFreshItem` comes back empty, as it does on Pleya Server for a title
  /// nobody touched and on any backend in offline mode. The copy is still there.
  final bool freshIsEmpty;

  /// Runs inside a read, for what happens while a replay waits on one.
  final void Function()? onRead;

  /// Runs after a start landed.
  final void Function()? onStart;
  final bool startFails;
  String token;

  bool played;
  int playCount;
  int position;
  int? lastViewedAt;

  final positions = <int>[];
  final watched = <String>[];
  final unwatched = <String>[];
  final tokens = <String>[];
  var started = 0;
  var stopped = 0;

  final _waiters = <(int, Completer<void>)>[];

  /// Done once [count] positions came in.
  Future<void> positionsFor(int count) {
    if (positions.length >= count) return Future.value();
    final waiter = Completer<void>();
    _waiters.add((count, waiter));
    return waiter.future;
  }

  @override
  ServerId get serverId => ServerId(_id);

  @override
  final MediaBackend backend;

  @override
  final bool movesCopyWithoutViewing;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  double get watchedThreshold => 0.9;

  @override
  bool get marksWatchedOnPlaybackStopped => false;

  @override
  void close() {}

  /// As each mapper fills `viewCount`. Plex and Jellyfin report nothing once a
  /// title is unwatched; Pleya Server keeps `play_count`.
  MediaItem get _state => (_item ?? mirrorFilm(_id)).copyWith(
    viewCount: backend == MediaBackend.pleyaServer || played ? playCount : 0,
    viewOffsetMs: position,
    lastViewedAt: lastViewedAt ?? _item?.lastViewedAt,
  );

  void _refuseIfAsked() {
    if (refuses) throw StateError('server refused');
    final refusal = failure;
    if (refusal != null) throw refusal;
  }

  @override
  Future<MediaItem?> fetchItem(String id) async {
    onRead?.call();
    return _state;
  }

  @override
  Future<MediaItem?> fetchFreshItem(String id) async => freshIsEmpty ? null : fetchItem(id);

  @override
  Future<MediaItem?> readCopyState(String id) async {
    onRead?.call();
    return gone ? null : _state.copyWith(viewCount: played ? playCount : 0);
  }

  @override
  Future<bool> writeCopyState(
    MediaItem item, {
    required Duration position,
    Duration? duration,
    required bool watched,
  }) async {
    await holdUntil;
    _refuseIfAsked();
    tokens.add(token);
    if (holdsTitle) return false;
    if (watched) {
      this.watched.add(item.id);
      played = true;
      playCount++;
      this.position = 0;
      return true;
    }
    this.position = position.inMilliseconds;
    positions.add(position.inMilliseconds);
    for (final (count, waiter) in _waiters) {
      if (positions.length >= count && !waiter.isCompleted) waiter.complete();
    }
    return true;
  }

  @override
  Future<void> reportPlaybackStarted({
    required String itemId,
    required Duration position,
    Duration? duration,
    String? playSessionId,
    String? playMethod,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    started++;
    if (startFails) throw StateError('no session');
    tokens.add(token);
    played = false;
    playCount++;
    lastViewedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    onStart?.call();
  }

  @override
  Future<void> reportPlaybackStopped({
    required String itemId,
    required Duration position,
    Duration? duration,
    String? playSessionId,
    String? mediaSourceId,
    PlaybackReportMetadata report = const PlaybackReportMetadata.live(),
  }) async {
    await holdUntil;
    _refuseIfAsked();
    tokens.add(token);
    stopped++;
    this.position = position.inMilliseconds;
    positions.add(position.inMilliseconds);
  }

  @override
  Future<void> markWatched(MediaItem item) async {
    _refuseIfAsked();
    tokens.add(token);
    watched.add(item.id);
    played = true;
    playCount++;
  }

  @override
  Future<void> markUnwatched(MediaItem item) async {
    _refuseIfAsked();
    tokens.add(token);
    unwatched.add(item.id);
    played = false;
    position = 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const mirrorHour = 60 * 60 * 1000;

MediaItem mirrorFilm(String server, {int durationMs = 2 * mirrorHour}) => MediaItem(
  id: 'film',
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Sintel',
  serverId: server,
  serverName: server,
  durationMs: durationMs,
);
