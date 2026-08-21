part of '../../pleya_server_client.dart';

/// Direct play and watch state on Pleya Protocol v1: everything PS-4 added.
///
/// ## One event type, six server-side rules
///
/// A watch-state update is a gebeurtenis and not a value. The client says what
/// happened; the server decides what that means for the canonical state, using
/// the ownership model from DEC-049. Three fields carry the client's half of
/// that conversation and all three sit behind
/// [PleyaCapabilities.watchStateOwnership], because `WatchStateEvent` is a
/// closed schema and an older server refuses the whole request rather than
/// ignoring a field it does not know:
///
///   * `explicit_action: playback_started` is the only way to acquire the write
///     right. A progress report never acquires it, not even when the previous
///     owner's lease has expired;
///   * `cause` says whether someone pressed play (`user_started`, takes over
///     regardless of another device's lease) or whether this session is
///     reopening its own (`reclaim`, only once the lease has run out);
///   * `base_revision` is the causality claim. The server applies the write
///     only when it matches the current revision, so a device that acted on a
///     stale view cannot overwrite a newer state.
///
/// The answer is always the current state, including when the event was
/// refused. That is why [_applyWatchState] records the revision from every
/// answer: a refused write teaches this client what it missed, and the next
/// write carries the right claim.
///
/// ## The stream URL carries no credential
///
/// `GET /stream/{version_id}` is class `authenticated`, and this client
/// authorises it with a bearer header rather than with the query-string stream
/// token. The token in a URL exists for players that cannot set a header; mpv
/// can, and a credential that never enters a URL never enters a log, a referrer
/// or a shell history either. [PleyaServerClient.streamHeaders] carries it.
mixin _PleyaServerPlaybackMethods on _PleyaServerRequests {
  /// The watched fraction the server uses when a report carries no `completed`.
  /// Kept in step with `watch.WatchedFraction` on the server side.
  static const double _watchedFraction = 0.9;

  // ---------------------------------------------------------------------------
  // Direct play
  // ---------------------------------------------------------------------------

  /// Resolve an item to a playable URL.
  ///
  /// No plan and no capability negotiation: PS-4 is direct play, and a file
  /// this device cannot decode fails visibly in the player. That is the
  /// documented boundary, not a gap — inventing a transcode path here would be
  /// PS-8 arriving early and would hide the one signal that says a later phase
  /// is needed.
  Future<PlaybackInitializationResult> getPlaybackInitialization(PlaybackInitializationOptions options) async {
    final versions = options.metadata.mediaVersions ?? const <MediaVersion>[];
    if (versions.isEmpty) {
      return PlaybackInitializationResult(availableVersions: const []);
    }

    final index = options.selectedMediaIndex >= 0 && options.selectedMediaIndex < versions.length
        ? options.selectedMediaIndex
        : 0;
    final version = versions[index];

    // Warm the header before the player opens the URL. The token is short
    // lived and minted per request everywhere else; here mpv holds the URL, so
    // the one thing this call has to guarantee is that the header handed to it
    // is fresh at open time.
    await _session.authHeaders();

    return PlaybackInitializationResult(
      availableVersions: versions,
      videoUrl: _streamUrl(version.id),
      selectedMediaIndex: index,
      playMethod: 'DirectPlay',
      playSessionId: _watchLedger.sessionFor(options.metadata.id, _mintSessionId),
      externalSubtitles: const [],
    );
  }

  /// A URL an external player can open on its own.
  ///
  /// This is the one place the query-string stream token belongs: VLC and MX
  /// Player get a URL and nothing else, so a header is not an option. The token
  /// opens one version and has no rights on the rest of the API.
  Future<String?> resolveExternalPlaybackUrl(MediaItem item, {int mediaIndex = 0, String? mediaSourceId}) async {
    final versions = item.mediaVersions ?? const <MediaVersion>[];
    if (versions.isEmpty) return null;
    final index = mediaIndex >= 0 && mediaIndex < versions.length ? mediaIndex : 0;
    final versionId = versions[index].id;

    final json = await _postJson('/auth/stream-token', {'version_id': versionId});
    if (json == null) return null;
    try {
      final token = PleyaStreamToken.fromJson(json);
      return Uri.parse(_streamUrl(versionId)).replace(queryParameters: {'stream_token': token.streamToken}).toString();
    } on PleyaWireFormatException catch (e) {
      appLogger.w('PleyaServerClient: stream token did not match the contract', error: e);
      return null;
    }
  }

  String _streamUrl(String versionId) =>
      '${connection.baseUrl}$pleyaProtocolPrefix/stream/${Uri.encodeComponent(versionId)}';

  // ---------------------------------------------------------------------------
  // Watch state: reporting
  // ---------------------------------------------------------------------------

  /// Someone pressed play. This is the acquisition, and the only event that
  /// takes the write right from another device.
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
    final session = _watchLedger.openSession(itemId, _mintSessionId);
    await _applyWatchState(
      itemId: itemId,
      sessionId: session,
      position: position,
      duration: duration,
      action: 'playback_started',
      cause: 'user_started',
    );
  }

  /// A passive progress tick. Never acquires ownership; a device that is not
  /// the owner reports into the void by design, and the answer tells it so.
  Future<void> reportPlaybackProgress({
    required String itemId,
    required Duration position,
    required Duration duration,
    bool isPaused = false,
    String? playSessionId,
    String? playMethod,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    await _applyWatchState(
      itemId: itemId,
      sessionId: _watchLedger.sessionFor(itemId, _mintSessionId),
      position: position,
      duration: duration,
    );
  }

  /// The last tick of a viewing.
  ///
  /// `completed` is computed here rather than left to the server's threshold,
  /// because the player knows whether the user reached the end or closed the
  /// screen at eighty percent, and those look identical from a position alone.
  Future<void> reportPlaybackStopped({
    required String itemId,
    required Duration position,
    Duration? duration,
    String? playSessionId,
    String? mediaSourceId,
    PlaybackReportMetadata report = const PlaybackReportMetadata.live(),
  }) async {
    final completed =
        duration != null &&
        duration.inMilliseconds > 0 &&
        position.inMilliseconds >= _watchedFraction * duration.inMilliseconds;

    await _applyWatchState(
      itemId: itemId,
      sessionId: _watchLedger.sessionFor(itemId, _mintSessionId),
      position: position,
      duration: duration,
      completed: completed,
      // An offline replay is a backlog, and the server treats a backlog as
      // history: it never acquires ownership and never moves a newer canonical
      // state. Reporting it as live would be a lie the server cannot detect.
      backlog: report.isOfflineReplay,
    );
    _watchLedger.closeSession(itemId);
  }

  // ---------------------------------------------------------------------------
  // Watch state: explicit actions
  // ---------------------------------------------------------------------------

  /// Mark watched. Ignores another device's lease, by rule 5.
  Future<void> markWatched(MediaItem item) async => _applyWatchState(
    itemId: item.id,
    sessionId: _watchLedger.sessionFor(item.id, _mintSessionId),
    position: Duration.zero,
    duration: item.durationMs == null ? null : Duration(milliseconds: item.durationMs!),
    action: 'mark_watched',
  );

  Future<void> markUnwatched(MediaItem item) async => _applyWatchState(
    itemId: item.id,
    sessionId: _watchLedger.sessionFor(item.id, _mintSessionId),
    position: Duration.zero,
    action: 'mark_unwatched',
  );

  /// Hide from Continue Watching.
  ///
  /// The protocol has no separate flag for it, so this is `mark_unwatched`:
  /// position zero and not watched is exactly the state that keeps a title out
  /// of the row. A dedicated flag arrives with the personal layer in PS-9P;
  /// until then this is the honest mapping and not a workaround, because the
  /// visible outcome is the one the user asked for.
  Future<void> removeFromContinueWatching(MediaItem item) async => markUnwatched(item);

  // ---------------------------------------------------------------------------
  // Watch state: reading
  // ---------------------------------------------------------------------------

  /// Titles this identity finished, newest first.
  ///
  /// `GET /watch-state` sorts on `updated_at` descending, so the watched ones
  /// come out in the right order without a second sort; what it cannot do is
  /// filter, so the finished ones are picked out here. The page is capped
  /// rather than walked: this feeds a recommendation row, and a row that is
  /// briefly short is repairable where a request that never returns is not.
  Future<List<MediaItem>> fetchRecentlyWatched({int limit = 5}) async {
    if (!wireCapabilities.watchState) return const [];

    final json = await _getJson('/watch-state', queryParameters: {'limit': '100'});
    if (json == null) return const [];

    final List<PleyaWatchStateEntry> entries;
    try {
      entries = PleyaWatchStateEntry.pageFromJson(json);
    } on PleyaWireFormatException catch (e) {
      appLogger.w('PleyaServerClient: /watch-state did not match the contract', error: e);
      return const [];
    }

    final wanted = <String>[];
    for (final entry in entries) {
      _watchLedger.remember(entry.itemId, entry.state.revision);
      if (entry.state.watched && wanted.length < limit) wanted.add(entry.itemId);
    }
    if (wanted.isEmpty) return const [];

    final items = await Future.wait(wanted.map(fetchItem));
    return [
      for (final item in items)
        if (item != null) item,
    ];
  }

  // ---------------------------------------------------------------------------
  // The one place an event is built
  // ---------------------------------------------------------------------------

  /// Build, send and account for one watch-state event.
  ///
  /// Every caller goes through here so the three ownership fields are decided
  /// in one place. Scattering them would make "does this event acquire the
  /// lease" a property of the call site instead of of the action.
  Future<void> _applyWatchState({
    required String itemId,
    required String sessionId,
    required Duration position,
    Duration? duration,
    String action = 'none',
    String? cause,
    bool completed = false,
    bool backlog = false,
  }) async {
    if (!wireCapabilities.watchState) return;

    final event = PleyaWatchStateEvent(
      itemId: itemId,
      sessionId: sessionId,
      positionMs: position.inMilliseconds,
      durationMs: duration?.inMilliseconds,
      occurredAt: DateTime.now().toUtc(),
      completed: completed,
      action: action,
      cause: cause,
      backlog: backlog,
      // Only under the capability, and the type drops it again when the flag is
      // off: the request schema is closed, so sending it to a server that
      // predates DEC-049 fails the whole call rather than dropping the field.
      baseRevision: wireCapabilities.watchStateOwnership ? _watchLedger.revisionOf(itemId) : null,
    );

    final body = event.toJson(ownership: wireCapabilities.watchStateOwnership);
    final json = await _postJson('/watch-state', body);
    if (json == null) return;
    try {
      final state = PleyaUserState.fromJson(json);
      _watchLedger.remember(itemId, state.revision);
      if (state.ownedByThisSession == false) {
        // Not an error, and not something the user should see. Another device
        // holds the lease, and this client keeps reporting so it can take over
        // when the lease runs out.
        appLogger.d('PleyaServerClient: another session owns $itemId');
      }
    } on PleyaWireFormatException catch (e) {
      appLogger.w('PleyaServerClient: watch-state answer did not match the contract', error: e);
    }
  }

  String _mintSessionId() => const Uuid().v4();
}
