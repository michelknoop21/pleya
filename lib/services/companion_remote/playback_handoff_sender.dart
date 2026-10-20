import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../mixins/disposable_change_notifier_mixin.dart';
import '../../models/companion_remote/remote_command.dart';
import '../../providers/companion_remote_provider.dart';
import '../../utils/app_logger.dart';
import 'playback_handoff.dart';
import 'pleya_fly_receive.dart';

/// What the sender needs from the Companion Remote, so it can be driven by a
/// fake in tests (A-23d).
abstract class PlaybackHandoffTransport {
  /// Name of this device, shown on the receiver.
  String get deviceName;

  /// Whether this device hosts a Companion Remote session right now.
  bool get hostRunning;

  /// Starts listening for beacons; null when the remote identity is missing.
  Future<Stream<List<DiscoveredHost>>?> discover();
  void stopDiscovery();

  /// The host and the client share one peer service, so a host has to stop
  /// before this device can join another one as a client.
  Future<void> stopHost();
  Future<void> restartHost();

  Future<void> connect(DiscoveredHost host);
  Future<PlaybackHandoffOutcome> handOff(
    PlaybackHandoffRequest request, {
    void Function(String profile, bool pin)? onSwitching,
  });

  /// Tells the receiver the sender gave up on [requestId].
  Future<void> cancel(String requestId);
  Future<void> leave();
}

/// The transport over [CompanionRemoteProvider]. [ensureCrypto] derives the
/// remote identity of the active profile before a search.
class CompanionRemoteHandoffTransport implements PlaybackHandoffTransport {
  CompanionRemoteHandoffTransport(this._provider, {required this.ensureCrypto});

  final CompanionRemoteProvider _provider;
  final Future<bool> Function() ensureCrypto;

  @override
  String get deviceName => _provider.deviceName;

  @override
  bool get hostRunning => _provider.isHostServerRunning;

  @override
  Future<Stream<List<DiscoveredHost>>?> discover() async {
    if (!await ensureCrypto()) return null;
    return _provider.discoverHosts();
  }

  @override
  void stopDiscovery() => _provider.stopDiscovery();

  @override
  Future<void> stopHost() => _provider.stopHostServer();

  @override
  Future<void> restartHost() => _provider.startHostServer();

  @override
  Future<void> connect(DiscoveredHost host) => _provider.connectToDiscoveredHost(host);

  @override
  Future<PlaybackHandoffOutcome> handOff(
    PlaybackHandoffRequest request, {
    void Function(String profile, bool pin)? onSwitching,
  }) => _provider.handOffPlayback(request, onSwitching: onSwitching);

  @override
  Future<void> cancel(String requestId) async {
    _provider.sendCommand(RemoteCommandType.syncState, data: {handoffCancelKey: requestId});
    // Sending encrypts asynchronously; closing the session now could drop it.
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  @override
  Future<void> leave() => _provider.leaveSession();
}

/// Why a phone refused, shown on its row until the next try (A-23b reasons).
enum PlaybackHandoffRefusal { wrongProfile, pinNotEntered }

/// The Apple TV side of Pleya Fly to an iPhone or iPad (A-23d): finds the
/// phones that have Pleya open and hands the playback to one of them. The
/// roles of A-23 invert for one fly: the phone hosts, the Apple TV joins as a
/// client, and afterwards the Apple TV hosts again.
///
/// Ported from the iPhone's `PlaybackHandoffSheet`; it outlives the panel
/// sub-view, so Menu can close the view while the fly goes on.
class PlaybackHandoffSender with ChangeNotifier, DisposableChangeNotifierMixin {
  PlaybackHandoffSender({
    required this.transport,
    required this.currentStop,
    this.onPlaying,
    this.onFailed,
    this.searchTimeout = const Duration(seconds: 8),
  });

  final PlaybackHandoffTransport transport;

  /// The Stop of the player that plays now; read at the press and again on success.
  final VoidCallback? Function() currentStop;

  /// The phone plays; this device has stopped its player.
  final void Function(DiscoveredHost host)? onPlaying;

  /// The phone did not start; this device keeps playing. [refusal] says why,
  /// when the phone said so and no open view could mark its row.
  final void Function(DiscoveredHost host, PlaybackHandoffRefusal? refusal)? onFailed;

  final Duration searchTimeout;

  StreamSubscription<List<DiscoveredHost>>? _subscription;
  Timer? _timeout;

  List<DiscoveredHost> _hosts = const [];
  bool _searching = false;
  DiscoveredHost? _handingTo;
  ({String profile, bool pin})? _switching;
  ({String clientId, PlaybackHandoffRefusal reason})? _refusal;
  bool _viewOpen = false;

  /// The iPhones and iPads with Pleya open; other hosts are not targets.
  List<DiscoveredHost> get hosts => _hosts;
  bool get searching => _searching;
  DiscoveredHost? get handingTo => _handingTo;
  bool get busy => _handingTo != null;

  /// Whether [host] is the phone this fly goes to. Beacons are rebuilt as they
  /// arrive, so a host is known by its client id, not by the object.
  bool isHandingTo(DiscoveredHost host) => _handingTo?.clientId == host.clientId;

  /// The phones to show: the search result, plus the phone a fly goes to when
  /// its beacon dropped out meanwhile, so the busy row never turns into the
  /// empty state with a Search again in the middle of a fly.
  List<DiscoveredHost> get visibleHosts {
    final target = _handingTo;
    if (target == null || _hosts.any(isHandingTo)) return _hosts;
    return [target, ..._hosts];
  }

  /// The profile the phone switches to first (A-23b), with or without PIN.
  ({String profile, bool pin})? get switching => _switching;

  PlaybackHandoffRefusal? refusalFor(DiscoveredHost host) =>
      _refusal?.clientId == host.clientId ? _refusal!.reason : null;

  /// A view shows this sender; until [stopSearch] it marks a refusal on its row.
  void attachView() => _viewOpen = true;

  /// Starts a fresh search; the list fills as beacons arrive. Not while a fly
  /// runs: that fly holds the session the search would rebuild.
  Future<void> search() async {
    if (isDisposed || busy) return;
    _searching = true;
    _refusal = null;
    // Rows of the last search may be gone; only beacons of this one are offered.
    _hosts = const [];
    safeNotifyListeners();
    await _subscription?.cancel();
    _subscription = null;
    // Deriving the identity for the search can stop a running host (a crypto
    // rebuild); a phone must still be able to reach this Apple TV afterwards.
    final hadHost = transport.hostRunning;
    Stream<List<DiscoveredHost>>? stream;
    try {
      stream = await transport.discover();
    } catch (e) {
      appLogger.w('Pleya Fly: discovery failed (${e.runtimeType})');
    }
    // Not while a fly runs: it stopped the host itself and holds the client
    // session a restart would take over (it restarts the host when it ends).
    if (hadHost && !busy && !transport.hostRunning) {
      try {
        await transport.restartHost();
      } catch (e) {
        appLogger.w('Pleya Fly: restarting the host after the search failed (${e.runtimeType})');
      }
    }
    if (isDisposed) return;
    if (stream == null) {
      _searching = false;
      safeNotifyListeners();
      return;
    }
    _subscription = stream.listen((hosts) {
      _hosts = hosts.where(isPleyaFlyTarget).toList();
      if (_hosts.isNotEmpty) _searching = false;
      safeNotifyListeners();
    });
    _timeout?.cancel();
    _timeout = Timer(searchTimeout, () {
      _searching = false;
      safeNotifyListeners();
    });
  }

  /// Stops listening for beacons and detaches the view; a fly that runs goes on.
  void stopSearch() {
    _viewOpen = false;
    _timeout?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    if (!busy) transport.stopDiscovery();
  }

  /// Hands the playback to [host]. Returns once the phone answered or the
  /// wait ended; this device keeps playing unless the phone plays.
  Future<void> handOff(
    DiscoveredHost host, {
    required String serverId,
    required String itemId,
    required int positionMs,
    required String title,
  }) async {
    if (_handingTo != null) return;
    _handingTo = host;
    _refusal = null;
    _switching = null;
    safeNotifyListeners();

    final request = PlaybackHandoffRequest(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      serverId: serverId,
      itemId: itemId,
      positionMs: positionMs,
      title: title,
      from: transport.deviceName,
    );
    // The Stop of the player this fly started from. A later player has its own.
    final stopThisPlayer = currentStop();
    final hadHost = transport.hostRunning;
    var outcome = PlaybackHandoffOutcome.failed;
    try {
      // Joining overwrites the peer service a running host still holds.
      if (hadHost) await transport.stopHost();
      await transport.connect(host);
      // No Plex token in this direction (A-23d): the phone asks its own PIN.
      outcome = await transport.handOff(
        request,
        onSwitching: (profile, pin) {
          _switching = (profile: profile, pin: pin);
          safeNotifyListeners();
        },
      );
    } catch (e) {
      appLogger.w('Pleya Fly to ${host.name} failed (${e.runtimeType})');
    }

    try {
      // Giving up: tell the phone, so a late start does not leave both playing.
      if (outcome == PlaybackHandoffOutcome.timedOut) await transport.cancel(request.id);
      await transport.leave();
    } catch (e) {
      appLogger.w('Pleya Fly: leaving the session failed (${e.runtimeType})');
    }
    // Every outcome: the phone that hands over to this Apple TV needs the host back.
    if (hadHost) {
      try {
        await transport.restartHost();
      } catch (e) {
        appLogger.w('Pleya Fly: restarting the host failed (${e.runtimeType})');
      }
    }

    _handingTo = null;
    _switching = null;
    // The view closed while this ran: its search stopped, so stop listening too.
    if (!_viewOpen) transport.stopDiscovery();
    if (outcome == PlaybackHandoffOutcome.playing) {
      if (currentStop() == stopThisPlayer) stopThisPlayer?.call();
      safeNotifyListeners();
      onPlaying?.call(host);
      return;
    }
    final refusal = switch (outcome) {
      PlaybackHandoffOutcome.wrongProfile => PlaybackHandoffRefusal.wrongProfile,
      PlaybackHandoffOutcome.pinCancelled => PlaybackHandoffRefusal.pinNotEntered,
      _ => null,
    };
    // A closed view cannot mark the row: the user must still hear that it failed.
    if (refusal != null && _viewOpen && !isDisposed) {
      // The user can fix it on the phone and try again, so the list stays.
      _refusal = (clientId: host.clientId, reason: refusal);
      safeNotifyListeners();
      return;
    }
    safeNotifyListeners();
    onFailed?.call(host, refusal);
  }

  @override
  void dispose() {
    stopSearch();
    super.dispose();
  }
}
