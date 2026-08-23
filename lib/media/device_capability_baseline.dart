/// What the Flutter player is credited with decoding, before anything is
/// measured.
///
/// These are the values the detection layer publishes as
/// [CapabilityConfidence.inferred]. They are deliberately not the same
/// constants the profile builders fall back on when the model knows nothing:
/// those are a frozen record of what the app sent before PS-5, and they must
/// stay frozen. These are a belief about the player and may widen when there is
/// a reason to widen them. Today the two happen to agree.
library;

/// Video codecs, in the order they go on the wire. Comma-separated codec lists
/// are order-sensitive on both backends.
const kInferredVideoCodecs = {'hevc', 'h264', 'h265', 'vp8', 'vp9', 'av1', 'mpeg4', 'mpeg2video'};

/// Audio codecs the player decodes. Separate from passthrough, which is about
/// not decoding at all.
const kInferredAudioCodecs = {'aac', 'mp3', 'mp2', 'ac3', 'eac3', 'flac', 'opus', 'vorbis', 'dts'};

/// Containers we are willing to have a backend direct-play.
///
/// Conservative on purpose: mpv demuxes considerably more than this (`avi`,
/// `m2ts`, `wmv`, `flv`, `mpg`, `vob`), and the local scanner in
/// `local_folder_client.dart` recognises sixteen extensions for exactly that
/// reason. Widening what we *declare* to a backend changes which files get
/// direct-played, which is a playback change and needs the hardware round that
/// goes with one.
const kInferredContainers = {'mp4', 'mkv', 'm4v', 'webm', 'mov', 'ts'};
