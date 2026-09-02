import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/server_capabilities.dart';

/// The two rating flags answer different questions, and
/// [DEC-075](../../docs/DECISIONS.md#dec-075) is why they had to be split.
///
/// `numericUserRating` decides which control the rating sheet draws.
/// `userRating` decides whether a membership belongs in a fan-out's fraction at
/// all. Before the split, Jellyfin and a local folder were indistinguishable:
/// both said "no numbers here", but one keeps a like and the other keeps
/// nothing. Counting the local one would leave every rating stuck on "gelukt op
/// 1 van 2" forever; counting it as done would claim a write that never
/// happened.
void main() {
  test('a backend that stores a number also stores a rating', () {
    for (final caps in [ServerCapabilities.plex, ServerCapabilities.jellyfin, ServerCapabilities.local]) {
      if (caps.numericUserRating) expect(caps.userRating, isTrue);
    }
  });

  test('like/dislike is a rating; storing nothing is not', () {
    expect(ServerCapabilities.jellyfin.userRating, isTrue);
    expect(ServerCapabilities.jellyfin.numericUserRating, isFalse);
    expect(ServerCapabilities.local.userRating, isFalse, reason: 'LocalFolderClient.rate is a no-op');
  });

  test('copyWith carries the new flag, like every other one', () {
    // Plex reaches its capabilities through copyWith, so a flag this forgets is
    // a flag Plex silently loses.
    expect(ServerCapabilities.local.copyWith(userRating: true).userRating, isTrue);
    expect(ServerCapabilities.plex.copyWith(richHubs: false).userRating, isTrue);
  });
}
