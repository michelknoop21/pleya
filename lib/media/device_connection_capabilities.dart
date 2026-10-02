/// What the link to the server carries: one of the four layers of
/// `DeviceCapabilities`. Not `ServerCapabilities`, which describes a backend
/// rather than this device.
library;

import 'device_capability.dart';

/// Whether the server is reached locally, and how much bandwidth playback may
/// assume.
class DeviceConnectionCapabilities {
  const DeviceConnectionCapabilities({
    this.isLocal = const Capability<bool>.unknown(),
    this.maxBitrateKbps = const Capability<int>.unknown(),
  });

  static const unknown = DeviceConnectionCapabilities();

  /// Whether this connection is a local one.
  ///
  /// Unknown in PS-5, and that is a decision rather than an omission. A
  /// private-address check on the server URL is not proof: a VPN, split DNS, a
  /// relay and plain local routing all break it in both directions, and Plex
  /// treats `location` as a hard input. The model carries the property so the
  /// PS-6 planner has a place to read it; the value waits for a source that
  /// can be trusted.
  final Capability<bool> isLocal;

  /// Ceiling playback may plan for, in kbit/s. Comes from
  /// `TranscodeQualityPreset` as a user override; unknown when the preset is
  /// `original`, which asks for no cap at all.
  final Capability<int> maxBitrateKbps;

  String describe() => 'connection(local=${isLocal.describe()}, maxKbps=${maxBitrateKbps.describe()})';
}
