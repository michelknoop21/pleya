import 'dart:async';

import 'package:flutter/material.dart';

import '../media/media_item.dart';

const String kVideoPlayerRouteName = '/video_player';

/// The player's route. Disposal is the one signal that also arrives when the
/// navigator itself is torn down (a profile switch, a sign-out), where the
/// future of the push never completes.
class _VideoPlayerRoute extends PageRouteBuilder<bool> {
  _VideoPlayerRoute({required super.pageBuilder})
    : super(
        settings: const RouteSettings(name: kVideoPlayerRouteName),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      );

  final Completer<void> _disposed = Completer<void>();

  Future<void> get disposed => _disposed.future;

  @override
  void dispose() {
    if (!_disposed.isCompleted) _disposed.complete();
    super.dispose();
  }
}

Route<dynamic>? _playerRoute;

/// The route every built-in player is pushed as. It is registered here, so
/// [activePlayerRoute] knows it, and [onPlayerRoute] gets the future that
/// completes when the route is disposed.
Route<bool> createVideoPlayerRoute({required WidgetBuilder builder, void Function(Future<void> gone)? onPlayerRoute}) {
  final route = _VideoPlayerRoute(pageBuilder: (context, animation, secondaryAnimation) => builder(context));
  _playerRoute = route;
  onPlayerRoute?.call(route.disposed);
  return route;
}

/// The route of the player that is on a navigator right now, if any: not
/// necessarily on top, a dialog or a sheet can lie over it.
Route<dynamic>? get activePlayerRoute {
  final route = _playerRoute;
  return route != null && route.isActive && route.navigator != null ? route : null;
}

/// Drops a second start of the same title while the first is still on its
/// way to the player.
///
/// `mediaIndex` is the version the caller asked for, null when it left the
/// choice to the saved preference. The key is taken before that preference is
/// read, so it has to describe the request, not what the request resolves to.
/// A start that left the choice open takes a second key once the preference
/// is read, under the version it resolved to: otherwise "the saved version"
/// and that same version asked for by number would both get through.
///
/// The key holds the `globalKey` of the requested title, the version number
/// and `isOffline`. The check for a mounted player further down compares
/// `activeId` and `activeMediaIndex`. The source id a version menu passes
/// along is left out: it names the entry at that number, and a start without
/// it would otherwise never meet a start with it. On Jellyfin and Emby the source id
/// does win over the number when the stream is fetched, so two starts with
/// one number and different source ids count as one start here.
///
/// The quality is left out as well. A plain start passes none and the version
/// menu always passes one, so keying on it let both through; the mounted
/// player refuses a second start of the same version whatever its quality, so
/// the guard refuses nothing the player would have let in a frame later.
class VideoPlayerNavigationInFlightGuard {
  final Set<String> _keys = <String>{};

  bool tryStart(MediaItem metadata, {required int? mediaIndex, required bool isOffline}) {
    return _keys.add(_keyFor(metadata, mediaIndex: mediaIndex, isOffline: isOffline));
  }

  void finish(MediaItem metadata, {required int? mediaIndex, required bool isOffline}) {
    _keys.remove(_keyFor(metadata, mediaIndex: mediaIndex, isOffline: isOffline));
  }

  String _keyFor(MediaItem metadata, {required int? mediaIndex, required bool isOffline}) {
    return [metadata.globalKey, mediaIndex ?? 'saved', isOffline].join('|');
  }
}
