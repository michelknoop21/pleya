/// What the attached display accepts: one of the four layers of
/// `DeviceCapabilities`. Not `ServerCapabilities`, which describes a backend
/// rather than this device.
library;

import 'device_capability.dart';

/// Resolution, refresh rates and HDR transfer functions of the output this
/// device is currently driving.
///
/// The honest state of this layer in PS-5 is mostly [CapabilityConfidence.unknown],
/// and deliberately so. Windows is the only platform where the app already
/// enumerates real display modes (`DisplayModeService`), so it is the only one
/// that can say [CapabilityConfidence.detected]. Everywhere else the app knows
/// the size of its own view, which is a floor and not the panel, and it knows
/// whether it *asked* mpv for HDR output, which is a request and not a
/// measurement of the panel. Reporting the request as a capability would let a
/// backend direct-play HDR to an SDR screen.
class DeviceDisplayCapabilities {
  const DeviceDisplayCapabilities({
    this.maxWidth = const Capability<int>.unknown(),
    this.maxHeight = const Capability<int>.unknown(),
    this.refreshRatesHz = const Capability<Set<int>>.unknown(),
    this.hdrTransfers = const Capability<Set<String>>.unknown(),
  });

  static const unknown = DeviceDisplayCapabilities();

  final Capability<int> maxWidth;

  /// Height in physical pixels. The override that caps this (`auto`, `1080p`,
  /// `2160p`) is the "never transcode above 1080p" from architecture 9.3.
  final Capability<int> maxHeight;

  /// Refresh rates the display reports, in whole Hz. Detected on Windows from
  /// the real mode list; unknown elsewhere.
  final Capability<Set<int>> refreshRatesHz;

  /// Transfer functions the panel accepts, as the tokens the backends use
  /// (`sdr`, `hdr10`, `hlg`, `dovi`).
  ///
  /// Windows can answer this because `isHDRSupported` asks the OS about the
  /// panel. On iOS, macOS and tvOS the app only knows that it enables mpv's
  /// `hdr-enabled`, which says what the player was told to do rather than what
  /// the screen can show, so this stays unknown there.
  final Capability<Set<String>> hdrTransfers;

  /// True when the display layer can state a resolution ceiling a backend may
  /// act on.
  bool get hasResolutionCeiling => maxWidth.isKnown && maxHeight.isKnown;

  String describe() =>
      'display(${maxWidth.describe()}x${maxHeight.describe()}, '
      'hz=${refreshRatesHz.describe()}, hdr=${hdrTransfers.describe()})';
}
