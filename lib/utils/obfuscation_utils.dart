/// Blurs all artwork and scrambles titles, for store screenshots that must not
/// show real library content. Build with `--dart-define=BLUR_ARTWORK=true`;
/// still a `const`, so a normal build tree-shakes the whole path away.
const kBlurArtwork = bool.fromEnvironment('BLUR_ARTWORK');

/// Rotates vowels (a→e, e→i, i→o, o→u, u→a) when [kBlurArtwork] is `true`.
String obfuscateText(String text) {
  if (!kBlurArtwork) return text;
  const from = 'aeiouAEIOU';
  const to = 'eiouaEIOUA';
  final buf = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final idx = from.indexOf(text[i]);
    buf.write(idx >= 0 ? to[idx] : text[i]);
  }
  return buf.toString();
}
