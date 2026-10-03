/// Explicit server decisions retained from the existing negotiation response.
/// Missing fields remain unknown; neither source codecs nor subtitle format
/// say what the server actually decided to do.
enum PlaybackStreamDecision { copy, transcode }

enum PlaybackSubtitleDecision { copy, burn }

class PlaybackStreamEvidence {
  const PlaybackStreamEvidence({this.video, this.audio, this.subtitle});

  final PlaybackStreamDecision? video;
  final PlaybackStreamDecision? audio;
  final PlaybackSubtitleDecision? subtitle;

  static PlaybackStreamDecision? _stream(Object? value) => switch (value) {
    'copy' || 'directplay' || 'directstream' => PlaybackStreamDecision.copy,
    'transcode' => PlaybackStreamDecision.transcode,
    _ => null,
  };

  static PlaybackSubtitleDecision? _subtitle(Object? value) => switch (value) {
    'copy' || 'directplay' || 'directstream' || 'embed' => PlaybackSubtitleDecision.copy,
    'burn' => PlaybackSubtitleDecision.burn,
    _ => null,
  };

  /// Plex's decision response contains only the negotiated part's streams.
  /// Refuse ambiguous collections rather than attributing another part's
  /// decisions to the selected file.
  factory PlaybackStreamEvidence.plex(Object? response) {
    Object? single(Object? value) => value is List && value.length == 1 ? value.single : null;
    Object? field(Object? value, String key) => value is Map ? value[key] : null;
    final container = field(response, 'MediaContainer');
    final metadata = single(field(container, 'Metadata'));
    final media = single(field(metadata, 'Media'));
    final part = single(field(media, 'Part'));
    final streams = field(part, 'Stream');
    Object? decision(int type) {
      if (streams is! List) return null;
      final matching = streams.whereType<Map>().where((s) => s['streamType'].toString() == '$type');
      final decided = matching.where((s) => s['decision'] != null).toList();
      return decided.length == 1 ? decided.single['decision'] : null;
    }

    return PlaybackStreamEvidence(
      video: _stream(field(media, 'videoDecision') ?? decision(1)),
      audio: _stream(field(media, 'audioDecision') ?? decision(2)),
      subtitle: _subtitle(field(media, 'subtitleDecision') ?? decision(3)),
    );
  }

  /// Only explicit server-reported direct/copy decisions qualify. A codec
  /// requested in a transcoding URL is not proof of runtime output.
  factory PlaybackStreamEvidence.jellyfin(Object? source) {
    final info = source is Map ? source['TranscodingInfo'] : null;
    if (info is! Map) return const PlaybackStreamEvidence();
    PlaybackStreamDecision? direct(Object? value) => switch (value) {
      true => PlaybackStreamDecision.copy,
      false => PlaybackStreamDecision.transcode,
      _ => null,
    };
    return PlaybackStreamEvidence(
      video: direct(info['IsVideoDirect']),
      audio: direct(info['IsAudioDirect']),
      subtitle: _subtitle(info['SubtitleDeliveryMethod']),
    );
  }
}
