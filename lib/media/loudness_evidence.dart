/// Where a loudness figure comes from. The wire enum is open: an unknown value
/// parses to [unknown] and the planner treats it as no evidence.
enum LoudnessSource {
  serverScan('server_scan'),
  opusR128('opus_r128'),
  replaygain('replaygain'),
  realtimeEstimator('realtime_estimator'),
  unknown('unknown');

  const LoudnessSource(this.wire);
  final String wire;

  static LoudnessSource parse(Object? value) =>
      values.firstWhere((s) => s.wire == value, orElse: () => LoudnessSource.unknown);
}

/// How far a figure may be trusted. Only [measuredFull] and [tagTrusted] are
/// ever applied as a fixed gain; [tagHint] (ReplayGain, dialnorm) stays advice
/// until a fixture proves otherwise, and [estimated] is runtime status only.
enum LoudnessQuality {
  measuredFull('measured_full'),
  tagTrusted('tag_trusted'),
  tagHint('tag_hint'),
  estimated('estimated'),
  unknown('unknown');

  const LoudnessQuality(this.wire);
  final String wire;

  static LoudnessQuality parse(Object? value) =>
      values.firstWhere((q) => q.wire == value, orElse: () => LoudnessQuality.unknown);
}

/// Which stream a measurement belongs to. A re-probe replaces stream rows, so
/// the binding is file (or part) plus stream index plus the file generation.
class LoudnessStreamRef {
  const LoudnessStreamRef({this.fileId, this.partId, required this.streamIndex, this.generation, this.sourceRevision});

  final String? fileId;
  final String? partId;
  final int streamIndex;
  final int? generation;
  final String? sourceRevision;

  static LoudnessStreamRef? fromJson(Object? json) {
    if (json is! Map) return null;
    final index = json['stream_index'];
    if (index is! int) return null;
    return LoudnessStreamRef(
      fileId: json['file_id']?.toString(),
      partId: json['part_id']?.toString(),
      streamIndex: index,
      generation: json['generation'] is int ? json['generation'] as int : null,
      sourceRevision: json['source_revision']?.toString(),
    );
  }

  Map<String, Object?> toJson() => {
    'file_id': ?fileId,
    'part_id': ?partId,
    'stream_index': streamIndex,
    'generation': ?generation,
    'source_revision': ?sourceRevision,
  };
}

/// The canonical loudness evidence for one audio stream, identical in shape to
/// the server's `loudness.Evidence` and the `loudness` object on the wire.
///
/// Missing metrics stay null, never 0: a 0 LUFS programme is a real (and very
/// loud) answer. A measurement on one decode [basis] says nothing about another.
class LoudnessEvidence {
  const LoudnessEvidence({
    required this.source,
    required this.method,
    required this.methodVersion,
    this.integratedLufs,
    this.truePeakDbtp,
    this.lraLu,
    this.thresholdLufs,
    this.gainDb,
    this.referenceLufs,
    required this.quality,
    required this.coverageComplete,
    required this.basis,
    this.stream,
    this.measuredAt,
  });

  final LoudnessSource source;
  final String method;
  final int methodVersion;
  final double? integratedLufs;
  final double? truePeakDbtp;
  final double? lraLu;
  final double? thresholdLufs;

  /// Only for tag sources that carry a gain rather than an absolute level,
  /// expressed against [referenceLufs] (Opus R128: -23).
  final double? gainDb;
  final double? referenceLufs;
  final LoudnessQuality quality;
  final bool coverageComplete;
  final String basis;
  final LoudnessStreamRef? stream;
  final DateTime? measuredAt;

  /// The programme loudness, from a measurement or reconstructed from a tag
  /// gain (a gain of G against reference R means the programme sits at R - G).
  double? get programmeLufs {
    if (integratedLufs != null) return integratedLufs;
    final gain = gainDb, reference = referenceLufs;
    if (gain == null || reference == null) return null;
    return reference - gain;
  }

  static double? _num(Object? v) => v is num ? v.toDouble() : null;

  /// Null when the object is not evidence at all (missing required fields).
  static LoudnessEvidence? fromJson(Object? json) {
    if (json is! Map) return null;
    final method = json['method'], version = json['method_version'], basis = json['basis'];
    if (method is! String || version is! int || basis is! String) return null;
    final measuredAt = json['measured_at'];
    return LoudnessEvidence(
      source: LoudnessSource.parse(json['source']),
      method: method,
      methodVersion: version,
      integratedLufs: _num(json['integrated_lufs']),
      truePeakDbtp: _num(json['true_peak_dbtp']),
      lraLu: _num(json['lra_lu']),
      thresholdLufs: _num(json['threshold_lufs']),
      gainDb: _num(json['gain_db']),
      referenceLufs: _num(json['reference_lufs']),
      quality: LoudnessQuality.parse(json['quality']),
      coverageComplete: json['coverage_complete'] == true,
      basis: basis,
      stream: LoudnessStreamRef.fromJson(json['stream']),
      measuredAt: measuredAt is String ? DateTime.tryParse(measuredAt) : null,
    );
  }

  Map<String, Object?> toJson() => {
    'source': source.wire,
    'method': method,
    'method_version': methodVersion,
    'integrated_lufs': ?integratedLufs,
    'true_peak_dbtp': ?truePeakDbtp,
    'lra_lu': ?lraLu,
    'threshold_lufs': ?thresholdLufs,
    'gain_db': ?gainDb,
    'reference_lufs': ?referenceLufs,
    'quality': quality.wire,
    'coverage_complete': coverageComplete,
    'basis': basis,
    if (stream != null) 'stream': stream!.toJson(),
    if (measuredAt != null) 'measured_at': measuredAt!.toUtc().toIso8601String(),
  };
}
