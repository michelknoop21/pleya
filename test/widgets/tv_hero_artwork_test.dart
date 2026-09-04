/// Fase 8 (hoofdstuk 9.4, fase-8 brief §23): what the Home hero draws for a
/// title, and — the half that matters most — what it refuses to draw.
///
/// Pure, against `tvHeroArtFor`, because the claim is about a `MediaItem` and
/// a box, not about pixels: given a film with only a poster you must get
/// [TvHeroArtKind.posterFill] rather than a poster silently cover-cropped
/// across a 2.465:1 card, and given a film with nothing you must get
/// [TvHeroArtKind.none] rather than some other title's backdrop.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/widgets/tv/tv_hero_artwork.dart';

MediaItem _film({String? art, String? square, String? poster}) => MediaItem(
  id: 'f1',
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'A Film',
  artPath: art,
  backgroundSquarePath: square,
  thumbPath: poster,
  serverId: 'server_1',
);

void main() {
  // The full-bleed hero is the screen's own ratio (DEC-095).
  const heroRatio = 16 / 9;

  test('a real backdrop is drawn sharp', () {
    final art = tvHeroArtFor(
      _film(art: '/art/backdrop', poster: '/art/poster'),
      containerAspectRatio: heroRatio,
    );
    expect(art.kind, TvHeroArtKind.sharp);
    expect(art.path, '/art/backdrop');
  });

  test('the backdrop wins over the poster, so the hero never crops a poster it did not have to', () {
    final art = tvHeroArtFor(
      _film(art: '/art/backdrop', poster: '/art/poster'),
      containerAspectRatio: heroRatio,
    );
    expect(art.path, isNot('/art/poster'));
  });

  test('poster-only art becomes a blurred fill, never a sharp crop', () {
    // The failure this guards: a 2:3 poster cover-cropped into a 2.465:1 card
    // keeps about a quarter of its height and none of its composition — a
    // giant face, which is exactly what hoofdstuk 9.4 forbids.
    final art = tvHeroArtFor(_film(poster: '/art/poster'), containerAspectRatio: heroRatio);
    expect(art.kind, TvHeroArtKind.posterFill);
    expect(art.path, '/art/poster');
  });

  test('a title with no artwork at all resolves to nothing, not to a stand-in', () {
    final art = tvHeroArtFor(_film(), containerAspectRatio: heroRatio);
    expect(art.kind, TvHeroArtKind.none);
    expect(art.path, isNull);
  });

  test('every candidate comes from the item itself', () {
    // Fase-8 brief §23: no other title's backdrop, no generated image. The
    // resolver is a pure function of one `MediaItem`, so the strongest
    // statement available is that whatever it returns is one of that item's
    // own paths — asserted here so a future "borrow the show's art" shortcut
    // has to break a test to get in.
    final item = _film(art: '/art/backdrop', square: '/art/square', poster: '/art/poster');
    final paths = {item.artPath, item.backgroundSquarePath, item.thumbPath};
    final art = tvHeroArtFor(item, containerAspectRatio: heroRatio);
    expect(paths, contains(art.path));
  });

  test('square background art is sharp on a wide card only when no backdrop exists', () {
    // `billboardArt` picks square over a backdrop on a *narrow* box; the hero
    // card is 2.465:1, so on it the backdrop must win and square is a
    // fallback. Both branches are asserted, because getting the container
    // ratio wrong here is the DEC-057 double-crop bug in a new place.
    expect(
      tvHeroArtFor(
        _film(art: '/art/backdrop', square: '/art/square'),
        containerAspectRatio: heroRatio,
      ).path,
      '/art/backdrop',
    );
    final squareOnly = tvHeroArtFor(_film(square: '/art/square'), containerAspectRatio: heroRatio);
    expect(squareOnly.path, '/art/square');
  });
}
