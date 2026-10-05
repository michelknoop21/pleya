/// Parsers for the title facts on a seerr movie/tv detail payload. Field names
/// follow Overseerr's `server/models/Movie.ts` / `Tv.ts` (Jellyseerr matches):
/// movies carry `releases` (TMDB release_dates), series `contentRatings`, and
/// both a `watchProviders` list of `{iso_3166_1, flatrate: [{name}]}`.
library;

/// Country code to age classification, e.g. `{'NL': '12', 'US': 'PG-13'}`.
/// Countries without a non-empty classification are left out.
Map<String, String> parseSeerrCertifications(Map<String, dynamic> json) {
  final out = <String, String>{};
  final releases = json['releases'];
  final ratings = json['contentRatings'];
  final results = releases is Map ? releases['results'] : (ratings is Map ? ratings['results'] : null);
  if (results is! List) return out;
  for (final r in results) {
    if (r is! Map) continue;
    final country = r['iso_3166_1'];
    if (country is! String || country.isEmpty) continue;
    String? value;
    final dates = r['release_dates'];
    if (dates is List) {
      for (final d in dates) {
        final c = d is Map ? d['certification'] : null;
        if (c is String && c.trim().isNotEmpty) {
          value = c.trim();
          break;
        }
      }
    } else if (r['rating'] is String && (r['rating'] as String).trim().isNotEmpty) {
      value = (r['rating'] as String).trim();
    }
    if (value != null) out[country] = value;
  }
  return out;
}

/// Region code to the names of its subscription (flatrate) services. Regions
/// with only buy/rent offers are left out.
Map<String, List<String>> parseSeerrFlatrateProviders(Map<String, dynamic> json) {
  final out = <String, List<String>>{};
  final regions = json['watchProviders'];
  if (regions is! List) return out;
  for (final r in regions) {
    if (r is! Map) continue;
    final region = r['iso_3166_1'];
    final flatrate = r['flatrate'];
    if (region is! String || region.isEmpty || flatrate is! List) continue;
    final names = [
      for (final p in flatrate)
        if (p is Map && p['name'] is String && (p['name'] as String).isNotEmpty) p['name'] as String,
    ];
    if (names.isNotEmpty) out[region] = names;
  }
  return out;
}
