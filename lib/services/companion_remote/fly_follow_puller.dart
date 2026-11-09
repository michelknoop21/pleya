import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../media/media_item.dart';
import '../../mixins/disposable_change_notifier_mixin.dart';
import '../../providers/companion_remote_provider.dart';
import '../../utils/app_logger.dart';
import 'pleya_fly_follow.dart';

/// What the phone needs from the Companion Remote to follow an Apple TV
/// (A-23e), so the puller runs against a fake in tests.
abstract class FlyFollowTransport {
  /// Starts listening for beacons; null when this profile has no remote identity.
  Future<Stream<List<DiscoveredHost>>?> discover();
  void stopDiscovery();
  bool get listening;

  /// Claims the one outgoing link of this device; false while another runs
  /// (a remote session, or a fly to the Apple TV).
  bool begin();
  void end();

  Future<void> connect(DiscoveredHost host);
  Future<FlyFollowAnswer> ask({required bool peek});
  Future<void> leave();
}

class CompanionRemoteFollowTransport implements FlyFollowTransport {
  CompanionRemoteFollowTransport(this._provider, {required this.ensureCrypto});

  final CompanionRemoteProvider _provider;
  final Future<bool> Function() ensureCrypto;

  @override
  Future<Stream<List<DiscoveredHost>>?> discover() async {
    if (!await ensureCrypto()) return null;
    return _provider.discoverHosts();
  }

  @override
  void stopDiscovery() => _provider.stopDiscovery();

  @override
  bool get listening => _provider.isListeningForHosts;

  @override
  bool begin() {
    // A remote session the user set up is not ours to take over.
    if (_provider.isInSession && !_provider.isHandoffOnlyHost) return false;
    return _provider.beginOutgoingFly();
  }

  @override
  void end() => _provider.endOutgoingFly();

  @override
  Future<void> connect(DiscoveredHost host) => _provider.connectToDiscoveredHost(host);

  @override
  Future<FlyFollowAnswer> ask({required bool peek}) => _provider.askFlyFollow(peek: peek);

  @override
  Future<void> leave() => _provider.leaveSession();
}

/// Why the card shows a title without a Meenemen button.
enum FlyFollowCardBlock {
  /// A local folder, Pleya Share or live TV.
  unsupported,

  /// Samen kijken with a code runs on the Apple TV.
  busy,

  /// The active profile on this phone cannot reach the item's server (DEC point 8).
  unreachable,
}

/// The Home card (45-h): what an Apple TV in the Home plays.
@immutable
class FlyFollowCard {
  const FlyFollowCard({required this.tv, required this.title, this.offer, this.item, this.block});

  final DiscoveredHost tv;
  final String title;

  /// Present when this phone can follow: what plays and where.
  final FlyFollowOffer? offer;

  /// The item as this phone's own server knows it, for artwork and duration.
  final MediaItem? item;
  final FlyFollowCardBlock? block;

  bool get canFollow => offer != null && block == null;
}

/// The phone side of Meenemen (A-23e): watches the beacons of the Home for an
/// Apple TV that plays, asks it what (one short Companion Remote session), and
/// on a tap asks for the session and joins it. One tap; the player opens from
/// the session's playback state.
class FlyFollowPuller with ChangeNotifier, DisposableChangeNotifierMixin {
  FlyFollowPuller({
    required this.transport,
    required this.resolveItem,
    required this.join,
    this.relistenEvery = const Duration(seconds: 15),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// First wait before an Apple TV that did not answer is asked again; it
  /// doubles per failure up to [maxRetryWait].
  static const firstRetryWait = Duration(seconds: 10);
  static const maxRetryWait = Duration(minutes: 5);

  final FlyFollowTransport transport;

  /// The item on this phone's own servers, or null when the active profile
  /// cannot reach [serverId].
  final Future<MediaItem?> Function(String serverId, String itemId) resolveItem;

  /// Joins the Watch Together session of [offer] as a follower.
  final Future<void> Function(FlyFollowOffer offer) join;

  /// Another view (the Pleya Fly sheet) may stop the shared listener; the
  /// puller starts it again after this long.
  final Duration relistenEvery;

  StreamSubscription<List<DiscoveredHost>>? _subscription;
  Timer? _relisten;

  /// The beacons as last seen. Discovery emits only on a change, so a retry
  /// after a wait looks at these again instead of waiting for a new emission.
  List<DiscoveredHost> _lastHosts = const [];
  Timer? _retryTimer;
  FlyFollowCard? _card;
  String? _askedFor;
  final Map<String, ({DateTime at, Duration wait})> _retry = {};
  bool _linkBusy = false;
  bool _taking = false;
  bool _running = false;

  FlyFollowCard? get card => _card;
  bool get taking => _taking;

  Future<void> start() async {
    if (_running || isDisposed) return;
    _running = true;
    await _listen();
    if (!_running || isDisposed) return;
    _relisten = Timer.periodic(relistenEvery, (_) {
      if (_running && !transport.listening && !_linkBusy) unawaited(_listen());
    });
  }

  void stop() {
    _running = false;
    _relisten?.cancel();
    _relisten = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    // Only the listener this puller started; a fly under way keeps its own.
    if (!_linkBusy) transport.stopDiscovery();
  }

  Future<void> _listen() async {
    await _subscription?.cancel();
    _subscription = null;
    Stream<List<DiscoveredHost>>? stream;
    try {
      stream = await transport.discover();
    } catch (e) {
      appLogger.w('Meenemen: discovery failed (${e.runtimeType})');
    }
    if (stream == null) return;
    // Stopped while discovery started: that listener belongs to nobody now.
    if (!_running || isDisposed) {
      if (!_linkBusy) transport.stopDiscovery();
      return;
    }
    _subscription = stream.listen(_onHosts);
  }

  void _onHosts(List<DiscoveredHost> hosts) {
    _lastHosts = hosts;
    final tv = hosts.where((h) => h.platform == 'tvOS' && h.playing).firstOrNull;
    if (tv == null) {
      // While this phone is connected (a peek or the tap), the Apple TV hides
      // its hint for it: that is no stop, and the answer under way stays valid.
      if (_linkBusy || _taking) return;
      // The Apple TV stopped, or left the network: the card goes (45-h).
      _askedFor = null;
      if (_card != null && !_taking) {
        _card = null;
        safeNotifyListeners();
      }
      return;
    }
    if (_askedFor == tv.clientId) return;
    // An Apple TV that did not answer is asked again only after its wait (M6).
    final retry = _retry[tv.clientId];
    if (retry != null && _clock().isBefore(retry.at)) return;
    _askedFor = tv.clientId;
    unawaited(_peek(tv));
  }

  /// No usable answer (another link ran, the Apple TV failed, or its player
  /// is still opening): ask again later, each time waiting twice as long. A
  /// steady beacon emits nothing new, so the wait ends in a timer that looks
  /// at the last beacons again.
  void _backOff(String clientId) {
    _askedFor = null;
    // Stopped while the ask ran: no timer outlives the puller's run.
    if (!_running) return;
    final previous = _retry[clientId]?.wait;
    final wait = previous == null ? firstRetryWait : (previous * 2 > maxRetryWait ? maxRetryWait : previous * 2);
    _retry[clientId] = (at: _clock().add(wait), wait: wait);
    _retryTimer?.cancel();
    _retryTimer = Timer(wait, () {
      _retryTimer = null;
      if (_running && !isDisposed) _onHosts(_lastHosts);
    });
  }

  /// Asks [tv] over one short Companion Remote link; null when another link runs.
  Future<FlyFollowAnswer?> _overLink(DiscoveredHost tv, {required bool peek}) async {
    if (_linkBusy || !transport.begin()) return null;
    _linkBusy = true;
    try {
      await transport.connect(tv);
      return await transport.ask(peek: peek);
    } catch (e) {
      appLogger.w('Meenemen: asking ${tv.name} failed (${e.runtimeType})');
      return const FlyFollowAnswer.refused(FlyFollowRefusal.failed);
    } finally {
      try {
        await transport.leave();
      } catch (e) {
        appLogger.w('Meenemen: leaving the session failed (${e.runtimeType})');
      }
      transport.end();
      _linkBusy = false;
    }
  }

  Future<void> _peek(DiscoveredHost tv) async {
    final answer = await _overLink(tv, peek: true);
    if (isDisposed || _askedFor != tv.clientId) return;
    if (answer == null || answer.refusal == FlyFollowRefusal.failed) {
      _backOff(tv.clientId);
      return;
    }
    if (answer.refusal == FlyFollowRefusal.nothing) {
      // Its beacon says a player is open, but it has nothing to offer yet: the
      // player is still opening (the Apple TV advertises from the first frame).
      _backOff(tv.clientId);
      return;
    }
    _retry.remove(tv.clientId);
    _card = await _cardFor(tv, answer);
    safeNotifyListeners();
  }

  Future<FlyFollowCard?> _cardFor(DiscoveredHost tv, FlyFollowAnswer answer) async {
    final offer = answer.offer;
    if (offer == null) {
      final title = answer.title;
      return switch (answer.refusal) {
        FlyFollowRefusal.unsupported when title != null => FlyFollowCard(
          tv: tv,
          title: title,
          block: FlyFollowCardBlock.unsupported,
        ),
        FlyFollowRefusal.busy when title != null => FlyFollowCard(tv: tv, title: title, block: FlyFollowCardBlock.busy),
        _ => null,
      };
    }
    MediaItem? item;
    try {
      item = await resolveItem(offer.serverId, offer.itemId);
    } catch (e) {
      appLogger.d('Meenemen: item lookup failed (${e.runtimeType})');
    }
    return FlyFollowCard(
      tv: tv,
      title: offer.title.isNotEmpty ? offer.title : (item?.displayTitle ?? ''),
      offer: offer,
      item: item,
      block: item == null ? FlyFollowCardBlock.unreachable : null,
    );
  }

  /// The one tap (45-h): ask the Apple TV for its session and join it. True
  /// when this phone now follows; the player opens from the session.
  Future<bool> take() async {
    final card = _card;
    if (card == null || !card.canFollow || _taking) return false;
    _taking = true;
    safeNotifyListeners();
    try {
      final answer = await _overLink(card.tv, peek: false);
      final offer = answer?.offer;
      if (offer == null || offer.sessionId == null) return false;
      await join(offer);
      return true;
    } catch (e) {
      appLogger.w('Meenemen: following failed (${e.runtimeType})');
      return false;
    } finally {
      _taking = false;
      safeNotifyListeners();
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
