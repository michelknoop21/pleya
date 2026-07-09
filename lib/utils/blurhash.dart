import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Minimal pure-Dart BlurHash decoder + placeholder widget. Jellyfin ships a
/// BlurHash string per image in its item API (`ImageBlurHashes`); we decode it
/// to a tiny bitmap and let the GPU smooth-scale it up as a poster placeholder.
/// No client-side hashing, no dependency — the string is already on the item.
///
/// Decode is cheap (a few hundred pixels) but we still cache the resulting
/// [ui.Image] per hash so a scrolling grid re-rendering the same placeholder
/// doesn't redecode. ponytail: unbounded-ish cache, capped at [_cacheLimit].
const _base83 = r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~';

int _decode83(String str, int from, int to) {
  var value = 0;
  for (var i = from; i < to; i++) {
    final index = _base83.indexOf(str[i]);
    if (index == -1) return value;
    value = value * 83 + index;
  }
  return value;
}

double _signPow(double val, double exp) => (val < 0 ? -1.0 : 1.0) * math.pow(val.abs(), exp).toDouble();

double _linearToSrgb(double value) {
  final v = value.clamp(0.0, 1.0);
  if (v <= 0.0031308) return (v * 12.92 * 255 + 0.5);
  return ((1.055 * math.pow(v, 1 / 2.4) - 0.055) * 255 + 0.5);
}

double _srgbToLinear(int value) {
  final v = value / 255.0;
  if (v <= 0.04045) return v / 12.92;
  return math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

/// Decode [blurHash] into a [width]×[height] RGBA byte buffer, or null if the
/// hash is malformed.
Uint8List? decodeBlurHashRgba(String blurHash, {int width = 32, int height = 32, double punch = 1.0}) {
  if (blurHash.length < 6) return null;

  final sizeFlag = _decode83(blurHash, 0, 1);
  final numY = (sizeFlag ~/ 9) + 1;
  final numX = (sizeFlag % 9) + 1;
  final expected = 4 + 2 * numX * numY;
  if (blurHash.length != expected) return null;

  final maxAcEnc = _decode83(blurHash, 1, 2);
  final maxValue = (maxAcEnc + 1) / 166.0;

  final colors = List<List<double>>.filled(numX * numY, const []);
  for (var i = 0; i < colors.length; i++) {
    if (i == 0) {
      final value = _decode83(blurHash, 2, 6);
      colors[i] = [_srgbToLinear((value >> 16) & 255), _srgbToLinear((value >> 8) & 255), _srgbToLinear(value & 255)];
    } else {
      final value = _decode83(blurHash, 4 + i * 2, 6 + i * 2);
      final quantR = (value / (19 * 19)).floor();
      final quantG = ((value / 19) % 19).floor();
      final quantB = (value % 19).toDouble();
      final p = maxValue * punch;
      colors[i] = [
        _signPow((quantR - 9) / 9.0, 2.0) * p,
        _signPow((quantG - 9) / 9.0, 2.0) * p,
        _signPow((quantB - 9) / 9.0, 2.0) * p,
      ];
    }
  }

  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var r = 0.0, g = 0.0, b = 0.0;
      for (var j = 0; j < numY; j++) {
        for (var i = 0; i < numX; i++) {
          final basis = math.cos((math.pi * x * i) / width) * math.cos((math.pi * y * j) / height);
          final color = colors[i + j * numX];
          r += color[0] * basis;
          g += color[1] * basis;
          b += color[2] * basis;
        }
      }
      final idx = 4 * (x + y * width);
      pixels[idx] = _linearToSrgb(r).clamp(0, 255).toInt();
      pixels[idx + 1] = _linearToSrgb(g).clamp(0, 255).toInt();
      pixels[idx + 2] = _linearToSrgb(b).clamp(0, 255).toInt();
      pixels[idx + 3] = 255;
    }
  }
  return pixels;
}

const _cacheLimit = 256;
final _imageCache = <String, ui.Image>{};

Future<ui.Image?> _decodeToImage(String blurHash, int width, int height) async {
  final cached = _imageCache[blurHash];
  if (cached != null) return cached;
  final rgba = decodeBlurHashRgba(blurHash, width: width, height: height);
  if (rgba == null) return null;
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, width, height, ui.PixelFormat.rgba8888, completer.complete);
  final image = await completer.future;
  if (_imageCache.length >= _cacheLimit) {
    _imageCache.remove(_imageCache.keys.first);
  }
  _imageCache[blurHash] = image;
  return image;
}

/// Renders a decoded BlurHash, scaled to fill and smoothed. Synchronous when
/// the hash is already cached (common while scrolling), else a one-frame decode.
class BlurHashPlaceholder extends StatefulWidget {
  final String blurHash;
  final int decodeWidth;
  final int decodeHeight;

  const BlurHashPlaceholder(this.blurHash, {super.key, this.decodeWidth = 32, this.decodeHeight = 32});

  @override
  State<BlurHashPlaceholder> createState() => _BlurHashPlaceholderState();
}

class _BlurHashPlaceholderState extends State<BlurHashPlaceholder> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(BlurHashPlaceholder old) {
    super.didUpdateWidget(old);
    if (old.blurHash != widget.blurHash) _load();
  }

  void _load() {
    final cached = _imageCache[widget.blurHash];
    if (cached != null) {
      _image = cached;
      return;
    }
    _decodeToImage(widget.blurHash, widget.decodeWidth, widget.decodeHeight).then((img) {
      if (mounted && img != null) setState(() => _image = img);
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return const SizedBox.expand();
    return SizedBox.expand(
      child: RawImage(image: image, fit: BoxFit.cover, filterQuality: FilterQuality.low),
    );
  }
}
