import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/hero_focus_points.dart';
import 'package:pleya/widgets/hero_focus_crop.dart';

const _wide = 16 / 9;

/// The iPhone card: 358 x 500, so 0.40 of a 16:9 backdrop stays visible.
const _card = 358 / 500;

/// Which share of the image's width a cover crop at [alignment] shows.
(double left, double right) _window(Alignment alignment) {
  final visible = _card / _wide;
  final left = (1 - visible) * (alignment.x + 1) / 2;
  return (left, left + visible);
}

void main() {
  group('heroFocusAlignment', () {
    test('centres the focus point in the card', () {
      final (left, right) = _window(heroFocusAlignment(const HeroFocus(0.7, _wide), boxAspect: _card));
      expect((left + right) / 2, closeTo(0.7, 1e-9));
    });

    test('clamps at the image edges instead of showing past them', () {
      expect(heroFocusAlignment(const HeroFocus(0.98, _wide), boxAspect: _card).x, 1);
      expect(heroFocusAlignment(const HeroFocus(0.02, _wide), boxAspect: _card).x, -1);
    });

    test('keeps the plain top-centre crop without a focus or without a horizontal crop', () {
      expect(heroFocusAlignment(null, boxAspect: _card), Alignment.topCenter);
      expect(heroFocusAlignment(const HeroFocus(0.9, 0.5), boxAspect: _card), Alignment.topCenter);
    });
  });

  group('HeroFocusPoints', () {
    String? stored;

    setUp(() => stored = null);

    HeroFocusPoints points(Future<HeroFocus?> Function(String path) detect) => HeroFocusPoints(
      detect: detect,
      localFile: (url, key) async => '/cache/$key',
      readStore: () async => stored,
      writeStore: (json) async => stored = json,
    );

    test('runs detection once per image and remembers it across launches', () async {
      final seen = <String>[];
      Future<HeroFocus?> detect(String path) async {
        seen.add(path);
        return const HeroFocus(0.7, _wide);
      }

      final first = points(detect);
      expect((await first.resolve(url: 'u', key: 'art-1'))?.x, 0.7);
      expect((await first.resolve(url: 'u', key: 'art-1'))?.x, 0.7);

      // A fresh instance is the next launch: the stored point, no Vision pass.
      final relaunched = points(detect);
      expect((await relaunched.resolve(url: 'u', key: 'art-1'))?.x, 0.7);
      expect(seen, ['/cache/art-1']);
    });

    test('a failed detection keeps the plain crop and stores nothing', () async {
      final failing = points((path) async => throw StateError('no channel'));
      expect(await failing.resolve(url: 'u', key: 'art-2'), isNull);
      expect(stored, isNull);
    });

    test('drops the oldest entries past the cap', () async {
      final store = points((path) async => const HeroFocus(0.5, _wide));
      for (var i = 0; i <= HeroFocusPoints.maxEntries; i++) {
        await store.resolve(url: 'u', key: 'art-$i');
      }
      final raw = stored!;
      expect(raw.contains('"art-0"'), isFalse);
      expect(raw.contains('"art-${HeroFocusPoints.maxEntries}"'), isTrue);
    });
  });

  testWidgets('HeroFocusCrop paints the plain crop first, then moves to the focus', (tester) async {
    final detected = Completer<HeroFocus?>();
    final points = HeroFocusPoints(
      detect: (path) => detected.future,
      localFile: (url, key) async => '/cache/$key',
      readStore: () async => null,
      writeStore: (json) async {},
    );
    final alignments = <Alignment>[];
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: HeroFocusCrop(
          imageUrl: 'u',
          cacheKey: 'art-1',
          boxAspect: _card,
          points: points,
          builder: (alignment) {
            alignments.add(alignment);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(alignments.single, Alignment.topCenter);

    detected.complete(const HeroFocus(0.7, _wide));
    await tester.pumpAndSettle();
    expect(alignments.last, heroFocusAlignment(const HeroFocus(0.7, _wide), boxAspect: _card));
  });
}
