import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/mpv/player/player_base.dart';

/// Minimal concrete PlayerBase. parseTrackList reads nothing but its argument,
/// so the channel is never touched — it only has to exist.
class _ParsingPlayer extends PlayerBase {
  @override
  final EventChannel eventChannel = const EventChannel('test/parse-track-list');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the container stream index is read from ff-index', () {
    final player = _ParsingPlayer();
    final result = player.parseTrackList([
      {'id': 1, 'type': 'sub', 'ff-index': 3, 'lang': 'nld', 'selected': false},
      {'id': 2, 'type': 'sub', 'lang': 'eng', 'selected': false},
    ]);

    final tracks = result.tracks.subtitle;
    // Without ff-index the resolver has nothing to compare a Jellyfin
    // MediaStreams index against: mpv's own id is a per-type ordinal.
    expect(tracks.firstWhere((t) => t.id == '1').ffIndex, 3);
    expect(tracks.firstWhere((t) => t.id == '2').ffIndex, isNull);
  });
}
