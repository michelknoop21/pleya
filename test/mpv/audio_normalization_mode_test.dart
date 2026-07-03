import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/mpv/models.dart';

void main() {
  test('off disables the af filter', () {
    expect(AudioNormalizationMode.off.mpvFilter, '');
    expect(AudioNormalizationMode.off.isEnabled, isFalse);
  });

  test('normalize and night use distinct loudnorm targets', () {
    expect(AudioNormalizationMode.normalize.mpvFilter, 'loudnorm=I=-14:TP=-3:LRA=4');
    expect(AudioNormalizationMode.night.mpvFilter, 'loudnorm=I=-16:TP=-2:LRA=2');
    expect(AudioNormalizationMode.normalize.isEnabled, isTrue);
    expect(AudioNormalizationMode.night.isEnabled, isTrue);
    // Night compresses harder: lower LRA than normalize.
    expect(AudioNormalizationMode.night.mpvFilter.contains('LRA=2'), isTrue);
  });
}
