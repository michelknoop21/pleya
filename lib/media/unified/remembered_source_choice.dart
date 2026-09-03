/// One remembered "which source did I last pick for this title" entry
/// (hoofdstuk 14.8 of docs/tvos-unified-experience.md).
///
/// Mirrors `TrackLanguageChoice`: a small JSON-round-tripping value with its
/// own `updatedAt`, so the map holding every title can be capped by recency
/// without a second index. [updatedAt] is what makes the cap an LRU rather
/// than an arbitrary truncation.
library;

class RememberedSourceChoice {
  /// `UnifiedMediaSource.sourceKey`, i.e. `serverId:itemId`.
  final String sourceKey;

  /// Milliseconds since epoch of the choice.
  final int updatedAt;

  const RememberedSourceChoice({required this.sourceKey, required this.updatedAt});

  factory RememberedSourceChoice.fromJson(Map<String, dynamic> json) => RememberedSourceChoice(
    sourceKey: json['sourceKey'] as String? ?? '',
    updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {'sourceKey': sourceKey, 'updatedAt': updatedAt};

  /// An entry with no source key is not a choice — a decode of malformed or
  /// truncated storage should drop out rather than surface as a preference
  /// for the empty string, which would never match a real source.
  bool get isEmpty => sourceKey.isEmpty;

  @override
  String toString() => 'RememberedSourceChoice($sourceKey, updatedAt: $updatedAt)';
}
