import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/services/rating_actions.dart';

/// What a like becomes on a server that stores numbers, and why this file
/// asserts it rather than fixing it.
///
/// [DEC-075](../../docs/DECISIONS.md#dec-075), "De grenzen, expliciet", point 2
/// names this exact path and accepts it:
///
/// > Jellyfin kent alleen like/dislike, dus 7/10 wordt daar een like. Opent
/// > iemand later de sheet gebonden aan die Jellyfin-bron en tikt hij hem aan,
/// > dan schrijft de sheet 10.0, en die 10 reist via deze beslissing terug naar
/// > Plex over de 7 heen. (...) Dat is bewust geaccepteerd en niet weggeregeld:
/// > een merge-regel die een binaire bron een numerieke zusterwaarde laat
/// > behouden is een eigen productbesluit met een eigen DEC.
///
/// So the loss is decided, not overlooked, and changing it needs its own DEC
/// rather than a patch. What the same point records as the mitigation is real
/// and lives in `_ratingOrigin` (`tv_unified_context_menu.dart`): the TV menu
/// binds the sheet to a numeric source when the group has one, which makes the
/// path rare there. The detail page binds to its own source on purpose
/// (hoofdstuk 4.1/15), so it does not have that mitigation and this is where
/// the conversion actually happens.
///
/// These tests exist so the accepted behaviour is visible and a future DEC has
/// something concrete to change, including the part the prose does not spell
/// out: a dislike travels as `0.0`, and `0` is a real 0/10 on Plex, not an
/// absence of opinion. `RatingMirror`'s own doc already warns about that for
/// the clear sentinel `-1`; the binary control reaches the same conclusion by a
/// different route.
class _RecordingClient implements MediaServerClient {
  _RecordingClient({required this.numeric});

  final bool numeric;
  final List<double> writes = [];

  @override
  Future<void> rate(MediaItem item, double rating) async => writes.add(rating);

  @override
  ServerId get serverId => ServerId('s2');

  @override
  MediaBackend get backend => numeric ? MediaBackend.plex : MediaBackend.jellyfin;

  @override
  ServerCapabilities get capabilities => numeric ? ServerCapabilities.plex : ServerCapabilities.jellyfin;

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

RatingMirrorTarget _target(MediaServerClient client) => RatingMirrorTarget(
  sourceKey: 's2:i2',
  client: client,
  item: MediaItem(id: 'i2', backend: MediaBackend.plex, kind: MediaKind.unknown, serverId: 's2'),
);

/// The two values `RatingBottomSheet._submitServerLike` produces for a backend
/// without numeric ratings.
const double _like = 10.0;
const double _dislike = 0.0;

void main() {
  group('DEC-075 point 2: a binary origin writes an extreme to numeric siblings', () {
    test('a like reaches a numeric sibling as a full 10', () {
      final plex = _RecordingClient(numeric: true);
      final mirror = RatingMirror.withTargets([_target(plex)]);

      mirror.write(_like);

      return mirror.settled.then((_) {
        expect(plex.writes, [
          10.0,
        ], reason: 'accepted by DEC-075: the viewer said "I liked it" and Plex stores a perfect score');
      });
    });

    test('a dislike reaches a numeric sibling as a real zero, not as "no opinion"', () async {
      final plex = _RecordingClient(numeric: true);
      final mirror = RatingMirror.withTargets([_target(plex)]);

      mirror.write(_dislike);
      await mirror.settled;

      expect(plex.writes, [0.0]);
      expect(
        plex.writes.single,
        isNot(-1.0),
        reason: 'only -1 clears a rating; 0 is a score, which is the asymmetry a future DEC has to settle',
      );
    });

    test('the mirror itself is not where the loss happens: it passes the value through', () async {
      // Worth pinning separately, because it locates the decision. Any fix
      // belongs at the sheet, where a binary control is turned into a number,
      // not in the fan-out that faithfully carries whatever it is handed.
      final jellyfin = _RecordingClient(numeric: false);
      final mirror = RatingMirror.withTargets([_target(jellyfin)]);

      mirror.write(7.0);
      await mirror.settled;

      expect(jellyfin.writes, [7.0], reason: 'the lossy step is JellyfinClient.rate, downstream of here');
    });
  });

  group('the capability that decides which control is drawn', () {
    test('Jellyfin keeps a rating but not a number', () {
      expect(ServerCapabilities.jellyfin.userRating, isTrue);
      expect(
        ServerCapabilities.jellyfin.numericUserRating,
        isFalse,
        reason: 'this is what makes the sheet draw a thumb, and therefore what starts the conversion',
      );
    });

    test('a numeric sibling is a valid mirror target, so nothing filters the conversion out', () {
      expect(
        ServerCapabilities.plex.userRating,
        isTrue,
        reason: 'RatingMirror admits targets on userRating, never on numericUserRating',
      );
    });
  });
}
