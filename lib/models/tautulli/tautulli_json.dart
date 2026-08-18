/// Lenient readers shared by the Tautulli models.
///
/// Tautulli is inconsistent about types across commands and versions: the same
/// `get_activity` container answers `stream_count` as the string `"1"` and
/// `stream_count_transcode` as the number `0`. Numeric fields also arrive as
/// empty strings when they do not apply, which is why every reader returns null
/// rather than throwing or defaulting to zero.
library;

int? tInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double? tDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

String? tStr(Object? v) {
  if (v is String) return v.isEmpty ? null : v;
  if (v == null) return null;
  return v.toString();
}
