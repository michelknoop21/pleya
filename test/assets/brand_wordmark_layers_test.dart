import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// The Pleya lockup is **composed**, not stored: `scripts/gen_brand_assets.py`
/// builds it from `pleya_mark.png` plus `pleya_lettering.png` and writes the
/// canonical `pleya_wordmark.png` and its two layers.
///
/// That is a correction, not a preference. The lockup used to be a hand-made
/// file, and its "P" had fallen behind the mark — a closed dark counter and
/// faint red speed lines where `pleya_mark.png` has an open counter and amber
/// ones. Because every derived lockup was built from that file, the tvOS app
/// icon, all three Top Shelf images, the Android TV banner and the site's OG
/// image carried the old drawing while the iOS, macOS, Android and Linux icons
/// carried the new one. One brand, two P's, and nothing holding them together
/// ([DEC-074]).
///
/// So these are the invariants that keep them together, asserted on the real
/// bytes off disk (not through `rootBundle`, so a stale bundle is caught too):
///
///  1. the layers share the canonical lockup's canvas and reproduce it exactly;
///  2. the mark half really is the current `pleya_mark.png`, so the P cannot
///     drift away from it again;
///  3. the counter stays an actual hole, which is what lets the mark sit on a
///     light surface at all;
///  4. the two halves stay separable by colour, so tinting the lettering can
///     never touch the mark.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List wordmark;
  late Uint8List mark;
  late Uint8List lettering;
  late int width;
  late int height;
  final images = <ui.Image>[];

  Future<(ui.Image, Uint8List)> decode(String path) async {
    final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
    final image = (await codec.getNextFrame()).image;
    images.add(image);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return (image, data!.buffer.asUint8List());
  }

  late ui.Image wordmarkImage;
  late ui.Image markImage;
  late ui.Image letteringImage;
  late ui.Image sourceMarkImage;
  late Uint8List sourceMark;

  setUpAll(() async {
    (wordmarkImage, wordmark) = await decode('assets/branding/pleya_wordmark.png');
    (markImage, mark) = await decode('assets/branding/pleya_wordmark_mark.png');
    (letteringImage, lettering) = await decode('assets/branding/pleya_wordmark_text.png');
    (sourceMarkImage, sourceMark) = await decode('assets/branding/pleya_mark.png');
    width = wordmarkImage.width;
    height = wordmarkImage.height;
  });

  tearDownAll(() {
    for (final image in images) {
      image.dispose();
    }
  });

  /// The ink box of an RGBA buffer — everything with any opacity at all.
  (int, int, int, int) inkBox(Uint8List px, int w, int h) {
    var minX = w, minY = h, maxX = -1, maxY = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (px[(y * w + x) * 4 + 3] == 0) continue;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    return (minX, minY, maxX, maxY);
  }

  test('both layers keep the canonical canvas, not their own bounding box', () {
    // The load-bearing one. The generator has a `load_cropped` helper that most
    // assets use; reaching for it here would pass every other test in this file
    // and still take the lockup apart on screen, because two layers cropped to
    // their own boxes have different aspect ratios and `BoxFit.contain` at a
    // fixed height would then give them different widths.
    expect((markImage.width, markImage.height), (width, height), reason: 'mark layer');
    expect((letteringImage.width, letteringImage.height), (width, height), reason: 'lettering layer');
  });

  test('the two layers are disjoint and together reproduce the lockup exactly', () {
    var markOnly = 0;
    var letteringOnly = 0;
    for (var i = 0; i < wordmark.length; i += 4) {
      final wa = wordmark[i + 3];
      final ma = mark[i + 3];
      final la = lettering[i + 3];

      expect(ma == 0 || la == 0, isTrue, reason: 'pixel ${i ~/ 4} is opaque in both layers');

      if (wa == 0) {
        expect(ma, 0, reason: 'mark layer paints where the lockup does not, at ${i ~/ 4}');
        expect(la, 0, reason: 'lettering layer paints where the lockup does not, at ${i ~/ 4}');
        continue;
      }

      final carrier = ma != 0 ? mark : lettering;
      if (ma != 0) {
        markOnly++;
      } else {
        letteringOnly++;
      }
      for (var c = 0; c < 4; c++) {
        expect(carrier[i + c], wordmark[i + c], reason: 'channel $c differs at pixel ${i ~/ 4}');
      }
    }
    expect(markOnly, greaterThan(0), reason: 'the mark layer is empty');
    expect(letteringOnly, greaterThan(0), reason: 'the lettering layer is empty');
  });

  test('the P in the lockup is the current pleya_mark.png, not a drawing of its own', () {
    // The regression guard for the defect this whole change exists to fix. The
    // mark is scaled into the lockup with LANCZOS, so this compares shape and
    // colour at a coarse resolution rather than demanding identical bytes —
    // a full-file hash would be both stricter and more brittle than the thing
    // that actually matters, which is "it is still that mark".
    const grid = 24;

    List<double> fingerprint(Uint8List px, int w, int h) {
      final (x0, y0, x1, y1) = inkBox(px, w, h);
      final bw = x1 - x0 + 1;
      final bh = y1 - y0 + 1;
      final out = <double>[];
      for (var gy = 0; gy < grid; gy++) {
        for (var gx = 0; gx < grid; gx++) {
          var r = 0.0, g = 0.0, b = 0.0, a = 0.0;
          var n = 0;
          final sx0 = x0 + (gx * bw) ~/ grid;
          final sx1 = x0 + ((gx + 1) * bw) ~/ grid;
          final sy0 = y0 + (gy * bh) ~/ grid;
          final sy1 = y0 + ((gy + 1) * bh) ~/ grid;
          for (var y = sy0; y < sy1; y++) {
            for (var x = sx0; x < sx1; x++) {
              final i = (y * w + x) * 4;
              r += px[i];
              g += px[i + 1];
              b += px[i + 2];
              a += px[i + 3];
              n++;
            }
          }
          if (n == 0) n = 1;
          out.addAll([r / n, g / n, b / n, a / n]);
        }
      }
      return out;
    }

    final inLockup = fingerprint(mark, width, height);
    final canonical = fingerprint(sourceMark, sourceMarkImage.width, sourceMarkImage.height);
    var total = 0.0;
    for (var i = 0; i < inLockup.length; i++) {
      total += (inLockup[i] - canonical[i]).abs();
    }
    final mean = total / inLockup.length;
    // The old, drifted P scored far outside this: a filled counter and red
    // rather than amber speed lines move whole cells of the grid.
    expect(
      mean,
      lessThan(12.0),
      reason: 'the lockup P no longer matches pleya_mark.png — it has drifted again (mean channel delta $mean)',
    );
  });

  test('the counter stays an opening, not a painted shape', () {
    // What makes the mark usable on a themed surface at all: the hole inside
    // the P shows the ground through it. The drawing this replaced had it
    // filled with near-black, which reads as a blob on the light palette.
    final (x0, y0, x1, y1) = inkBox(mark, width, height);
    final bw = x1 - x0 + 1;
    final bh = y1 - y0 + 1;
    var transparent = 0;
    var sampled = 0;
    // The bowl of the P, safely inside the ink box.
    for (var y = y0 + (bh * 0.22).round(); y < y0 + (bh * 0.42).round(); y++) {
      for (var x = x0 + (bw * 0.46).round(); x < x0 + (bw * 0.62).round(); x++) {
        sampled++;
        if (mark[(y * width + x) * 4 + 3] == 0) transparent++;
      }
    }
    expect(sampled, greaterThan(0));
    expect(
      transparent / sampled,
      greaterThan(0.25),
      reason: 'the counter is filled in; the mark would sit as a dark blob on a light surface',
    );
  });

  test('the halves stay separable by colour, so tinting the lettering cannot reach the mark', () {
    // The lettering is achromatic — white, with grey antialiasing — and the
    // mark is saturated red and amber. That is the property the two-layer split
    // rests on, and it is what the generator checks before it writes anything.
    var chromaticInLettering = 0;
    var chromaticInMark = 0;
    for (var i = 0; i < mark.length; i += 4) {
      int chroma(Uint8List px) {
        final hi = [px[i], px[i + 1], px[i + 2]].reduce((a, b) => a > b ? a : b);
        final lo = [px[i], px[i + 1], px[i + 2]].reduce((a, b) => a < b ? a : b);
        return hi - lo;
      }

      if (mark[i + 3] >= 128 && chroma(mark) > 60) chromaticInMark++;
      if (lettering[i + 3] >= 128 && chroma(lettering) > 60) chromaticInLettering++;
    }
    expect(chromaticInMark, greaterThan(1000), reason: 'the mark half lost its brand colour');
    expect(chromaticInLettering, 0, reason: 'brand colour leaked into the half that gets retinted');
  });

  test('nothing in lib draws the lockup except the one widget that owns it', () {
    // Mirrors `pleya_logo_test.dart`'s guard. Two things at once: the layers
    // stay behind [PleyaWordmark], and no callsite reaches for the whole-lockup
    // file — which exists for consumers outside the app, and drawing it would
    // put untintable white lettering back on the light palette.
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('lib/widgets/pleya_wordmark.dart')) continue;
      final source = file.readAsStringSync();
      for (final line in source.split('\n')) {
        final code = line.trim();
        if (code.startsWith('//') || code.startsWith('///')) continue;
        if (code.contains('assets/branding/pleya_wordmark')) offenders.add('${file.path}: $code');
      }
    }
    expect(offenders, isEmpty, reason: 'the lockup assets belong behind PleyaWordmark');
  });
}
