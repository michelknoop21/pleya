part of '../../video_player_screen.dart';

/// Pleya Fly Meenemen (A-23e) in the player. On the Apple TV: answer a phone
/// that asks what plays and open the Watch Together session it follows, around
/// the player that already runs. On the phone: start muted.
extension _VideoPlayerFlyFollowMethods on VideoPlayerScreenState {
  /// The rule of Pleya Fly: an item of a server, not live, downloaded or local.
  bool get _flyFollowSupported =>
      !widget.isLive &&
      !_isOfflinePlayback &&
      _currentMetadata.serverId != null &&
      _currentMetadata.backend != MediaBackend.local;

  /// Registered as [CompanionRemoteReceiver.onFlyFollow] while this player is open.
  Future<FlyFollowAnswer> _answerFlyFollow({required bool peek}) async {
    final currentPlayer = player;
    if (!mounted || currentPlayer == null) return const FlyFollowAnswer.refused(FlyFollowRefusal.nothing);
    final title = _currentMetadata.displayTitle;
    if (!_flyFollowSupported) return FlyFollowAnswer.refused(FlyFollowRefusal.unsupported, title: title);
    final WatchTogetherProvider watchTogether;
    final CompanionRemoteProvider companion;
    try {
      watchTogether = context.read<WatchTogetherProvider>();
      companion = context.read<CompanionRemoteProvider>();
    } catch (_) {
      return const FlyFollowAnswer.refused(FlyFollowRefusal.failed);
    }
    // Samen kijken with a code is the user's own session: Meenemen does not take it over.
    if (watchTogether.isInSession && !(watchTogether.isFlySession && watchTogether.isHost)) {
      return FlyFollowAnswer.refused(FlyFollowRefusal.busy, title: title);
    }
    final offer = FlyFollowOffer(
      serverId: _currentMetadata.serverId!,
      itemId: _currentMetadata.id,
      positionMs: currentPlayer.state.position.inMilliseconds,
      title: title,
      from: companion.deviceName,
    );
    if (peek) return FlyFollowAnswer.offer(offer);

    if (!watchTogether.isFlySession) {
      try {
        await watchTogether.createSession(
          controlMode: ControlMode.anyone,
          displayName: companion.deviceName,
          sessionId: generateFlySessionId(),
          mediaRatingKey: _currentMetadata.id,
          mediaServerId: _currentMetadata.serverId,
          mediaTitle: title,
          flySession: true,
        );
      } catch (e) {
        appLogger.w('Meenemen: could not open the session (${e.runtimeType})');
        return FlyFollowAnswer.refused(FlyFollowRefusal.failed, title: title);
      }
      // The player closed while the relay answered: nothing to follow.
      if (!mounted || player != currentPlayer) {
        unawaited(watchTogether.leaveSession());
        return const FlyFollowAnswer.refused(FlyFollowRefusal.nothing);
      }
      // Mid-play attach: the room takes over what this screen does right now.
      _attachToWatchTogetherSession(adoptPlayback: true);
    }
    final sessionId = watchTogether.sessionId;
    if (sessionId == null) return FlyFollowAnswer.refused(FlyFollowRefusal.failed, title: title);
    final customRelay = SettingsService.instanceOrNull?.read(SettingsService.customRelayUrl)?.trim();
    return FlyFollowAnswer.offer(
      FlyFollowOffer(
        serverId: offer.serverId,
        itemId: offer.itemId,
        // Taken again: opening the session took a moment.
        positionMs: currentPlayer.state.position.inMilliseconds,
        title: title,
        from: offer.from,
      ).withSession(sessionId, relayUrl: customRelay == null || customRelay.isEmpty ? null : customRelay),
    );
  }

  /// Read at wiring time: a following phone joined before its player opened.
  bool get _playbackReportsAllowed {
    try {
      return playbackReportsAllowed(context.read<WatchTogetherProvider>());
    } catch (_) {
      return true;
    }
  }

  /// "Geluid aan" (45-i): back to the volume this device uses.
  Future<void> _unmuteFlyFollow() async {
    final settings = await SettingsService.getInstance();
    await _flyMute.release(player, settings.read(SettingsService.volume));
  }

  /// The player of a Meenemen session closes: a phone leaves the session, and
  /// the Apple TV ends it, which stops every phone with it (DEC points 6 and 7).
  void _leaveFlySessionOnExit(WatchTogetherProvider watchTogether) {
    if (!watchTogether.isFlySession || _isReplacingWithVideo) return;
    unawaited(watchTogether.leaveSession());
  }
}
