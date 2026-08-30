/// What one source row of the picker actually says (hoofdstuk 14.3 of
/// docs/tvos-unified-experience.md).
///
/// Pure, and separate from the widget on purpose. 14.3 lists nine things a row
/// *may* carry and then makes the important rule: "Ontbrekende metadata wordt
/// weggelaten. Geen rijen vol 'Onbekend'." That rule is content, not painting —
/// it is decided per field, from a [MediaItem] whose backends disagree about
/// which fields they populate at all — so it belongs somewhere it can be
/// checked field by field without a widget tree.
///
/// The row is deliberately not built from [MediaVersion.displayLabel]: that
/// helper falls back to `t.common.unknown` when it has nothing, which is
/// precisely the string 14.3 forbids here.
library;

import 'package:flutter/foundation.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_backend.dart';
import '../../media/media_item.dart';
import '../../media/media_stream.dart';
import '../../media/unified/source_availability.dart';
import '../../media/unified/unified_media_source.dart';
import '../../utils/codec_utils.dart';
import '../../utils/formatters.dart';

/// One source row, reduced to the values that are actually present.
@immutable
class TvSourceRowDescriptor {
  final String sourceKey;

  /// Line one, left: the server the user recognises.
  final String serverName;

  /// Line two: backend · library · edition, only the parts that exist.
  final List<String> contextParts;

  /// Line three: resolution · dynamic range · audio, only the parts that
  /// exist. Empty for a source whose server never reported media details —
  /// F13, where the row simply has one line fewer.
  final List<String> qualityParts;

  final SourceAvailability availability;

  /// The remembered choice for this title (hoofdstuk 14.8's "Laatst gebruikt").
  final bool isPreferred;

  /// This row's server is the profile's default for duplicate content. A
  /// different, stronger statement than [isPreferred]: this one is why most
  /// titles never opened a picker at all.
  final bool isPreferredServer;

  /// The source the surface behind the picker is already showing — only set
  /// when the picker was reopened from a detail page (hoofdstuk 15).
  final bool isCurrent;

  /// "Hervatten op 42:18" or "Bekeken"; null when this source has no watch
  /// state of its own.
  final String? progressLabel;

  /// 0..1 resume progress, or null when there is nothing to draw.
  final double? progressFraction;

  const TvSourceRowDescriptor({
    required this.sourceKey,
    required this.serverName,
    required this.contextParts,
    required this.qualityParts,
    required this.availability,
    required this.isPreferred,
    required this.isCurrent,
    this.isPreferredServer = false,
    this.progressLabel,
    this.progressFraction,
  });

  bool get isUsable => availability.isUsable;

  /// The status word on the right of line one, or null when the row is simply
  /// usable and unremarkable. Hoofdstuk 14.7 requires an auth error to read
  /// differently from an unreachable server, so these never collapse into one
  /// "unavailable".
  ///
  /// Only one label fits on the line, so they rank. Unusable outranks
  /// everything — a row nobody can pick has one thing worth saying. Among
  /// usable rows the standing default outranks the per-title memory, which
  /// outranks "you are already looking at this one".
  String? get statusLabel => switch (availability) {
    SourceAvailability.online =>
      isPreferredServer
          ? t.sourcePicker.preferredServer
          : isPreferred
          ? t.sourcePicker.lastUsed
          : (isCurrent ? t.sourcePicker.currentSource : null),
    SourceAvailability.authError => t.sourcePicker.signInRequired,
    SourceAvailability.offline || SourceAvailability.unknown => t.sourcePicker.unavailable,
  };

  /// One flat sentence for VoiceOver, built from the same present-only parts
  /// the row renders — so a screen reader never announces a field the eye
  /// cannot see either.
  String get accessibleDescription =>
      [serverName, ...contextParts, ...qualityParts, ?progressLabel, ?statusLabel].join(', ');
}

/// Describes every source in a group, in the order given.
///
/// [showBackend] is decided here rather than per row because 14.3 only allows
/// the backend "wanneer onderscheid nuttig is": on a group whose sources are
/// all Plex, the word "Plex" on every row is noise that pushes the library name
/// — the part that actually differs — further from the eye.
List<TvSourceRowDescriptor> describeSources(
  List<UnifiedMediaSource> sources, {
  String? preferredSourceKey,
  String? currentSourceKey,
  String? preferredServerId,
}) {
  final showBackend = sources.map((s) => s.backend).toSet().length > 1;
  return [
    for (final source in sources)
      describeSource(
        source,
        showBackend: showBackend,
        isPreferred: source.sourceKey == preferredSourceKey,
        isCurrent: source.sourceKey == currentSourceKey,
        isPreferredServer: source.serverId.value == preferredServerId,
      ),
  ];
}

/// Describes one source. Prefer [describeSources]; this is public for the
/// single-source callers and for tests that pin one field at a time.
TvSourceRowDescriptor describeSource(
  UnifiedMediaSource source, {
  required bool showBackend,
  bool isPreferred = false,
  bool isCurrent = false,
  bool isPreferredServer = false,
}) {
  final item = source.item;
  return TvSourceRowDescriptor(
    sourceKey: source.sourceKey,
    // `serverName` already falls back to the server id in
    // `UnifiedMediaSource.fromItem`, so a row always has something to head it.
    serverName: source.serverName,
    contextParts: [
      if (showBackend) backendDisplayLabel(source.backend),
      if (_present(source.libraryTitle)) source.libraryTitle!.trim(),
      if (_present(item.editionTitle)) item.editionTitle!.trim(),
    ],
    qualityParts: [
      if (_resolutionLabel(item) != null) _resolutionLabel(item)!,
      if (_dynamicRangeLabel(item) != null) _dynamicRangeLabel(item)!,
      if (_audioLabel(item) != null) _audioLabel(item)!,
    ],
    availability: source.availability,
    isPreferred: isPreferred,
    isCurrent: isCurrent,
    isPreferredServer: isPreferredServer,
    progressLabel: _progressLabel(item),
    progressFraction: _progressFraction(item),
  );
}

/// Brand names, matching the labels the rating sheet already shows. Note what
/// is *not* here: hoofdstuk 33.6 #3 records that the mockups show an "Emby"
/// backend that Pleya does not have, and the code wins.
String backendDisplayLabel(MediaBackend backend) => switch (backend) {
  MediaBackend.plex => 'Plex',
  MediaBackend.jellyfin => 'Jellyfin',
  MediaBackend.local => 'Local',
  MediaBackend.pleyaServer => 'Pleya Server',
};

bool _present(String? value) => value != null && value.trim().isNotEmpty;

final _numericResolution = RegExp(r'^\d+$');

String? _resolutionLabel(MediaItem item) {
  final version = (item.mediaVersions ?? const []).firstOrNull;
  if (version == null) return null;
  final raw = version.videoResolution?.trim();
  if (raw != null && raw.isNotEmpty) {
    return _numericResolution.hasMatch(raw) ? '${raw}p' : raw.toUpperCase();
  }
  final height = version.height;
  return height != null && height > 0 ? '${height}p' : null;
}

/// Dolby Vision beats HDR10 when a file carries both, because that is the mode
/// the user gets. A file with neither says nothing at all rather than "SDR":
/// SDR is the default, and labelling the default is the row noise 14.3 bans.
String? _dynamicRangeLabel(MediaItem item) {
  final streams = _streamsOf(item);
  if (streams.any((s) => s.kind == MediaStreamKind.video && s.dolbyVision)) return 'Dolby Vision';
  if (streams.any((s) => s.kind == MediaStreamKind.video && s.hdr)) return 'HDR';
  return null;
}

/// Codec plus, when they add something, the Atmos marker or the channel
/// layout. "E-AC3 Atmos" and "DTS-HD 7.1" are worth a glance from the couch;
/// "AAC Stereo" on every row of a group is not, but it is also the honest
/// answer when that is the only difference between two sources, so it stays.
String? _audioLabel(MediaItem item) {
  final audio = _streamsOf(item).where((s) => s.kind == MediaStreamKind.audio);
  if (audio.isEmpty) return null;
  final stream = audio.firstWhere((s) => s.selected, orElse: () => audio.first);
  final codec = stream.codec?.trim();
  if (codec == null || codec.isEmpty) return null;
  final parts = <String>[CodecUtils.formatAudioCodec(codec)];
  if ((stream.profile ?? '').toLowerCase().contains('atmos')) {
    parts.add('Atmos');
  } else {
    final layout = _present(stream.channelLayout)
        ? stream.channelLayout!.trim()
        : CodecUtils.formatAudioChannels(stream.channels);
    if (layout != null && layout.isNotEmpty) parts.add(layout);
  }
  return parts.join(' ');
}

List<MediaStream> _streamsOf(MediaItem item) => [
  for (final version in item.mediaVersions ?? const [])
    for (final part in version.parts) ...part.streams,
];

String? _progressLabel(MediaItem item) {
  final fraction = _progressFraction(item);
  if (fraction != null) {
    return t.sourcePicker.resumeAt(position: formatDurationTimestamp(Duration(milliseconds: item.viewOffsetMs!)));
  }
  return (item.viewCount ?? 0) > 0 ? t.sourcePicker.watched : null;
}

/// Resume progress, or null when there is none worth drawing.
///
/// A duration is required, not optional: without it there is no denominator,
/// and a bar drawn against a guessed one would be a lie the user can measure
/// against the row next to it.
double? _progressFraction(MediaItem item) {
  final offset = item.viewOffsetMs;
  final duration = item.durationMs;
  if (offset == null || offset <= 0) return null;
  if (duration == null || duration <= 0) return null;
  return (offset / duration).clamp(0.0, 1.0);
}
