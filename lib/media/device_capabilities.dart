/// What this device can play, in four layers.
///
/// Distinct from `ServerCapabilities` in this same directory, which says which
/// affordances the UI may show for a *backend*. Both types end up in the
/// playback path, which is why every file in this family carries a `device_`
/// prefix and repeats the distinction.
library;

import 'device_audio_capabilities.dart';
import 'device_connection_capabilities.dart';
import 'device_decoder_capabilities.dart';
import 'device_display_capabilities.dart';

export 'device_audio_capabilities.dart';
export 'device_capability.dart';
export 'device_connection_capabilities.dart';
export 'device_decoder_capabilities.dart';
export 'device_display_capabilities.dart';

/// The answer to one question: what can this combination of app, device,
/// output and connection handle right now.
///
/// Four layers, each with its own source of truth. It is a snapshot, not a
/// notifier: nothing rebuilds on it, and the two profile builders take it as a
/// parameter so a test can hand them one without touching global state.
class DeviceCapabilities {
  const DeviceCapabilities({
    required this.decoder,
    required this.display,
    required this.audio,
    required this.connection,
  });

  /// Every layer unknown. What consumers must treat as "keep doing what you
  /// did before", and the value the app carries until detection has run.
  static const unknown = DeviceCapabilities(
    decoder: DeviceDecoderCapabilities.unknown,
    display: DeviceDisplayCapabilities.unknown,
    audio: DeviceAudioCapabilities.unknown,
    connection: DeviceConnectionCapabilities.unknown,
  );

  final DeviceDecoderCapabilities decoder;
  final DeviceDisplayCapabilities display;
  final DeviceAudioCapabilities audio;
  final DeviceConnectionCapabilities connection;

  DeviceCapabilities copyWith({
    DeviceDecoderCapabilities? decoder,
    DeviceDisplayCapabilities? display,
    DeviceAudioCapabilities? audio,
    DeviceConnectionCapabilities? connection,
  }) {
    return DeviceCapabilities(
      decoder: decoder ?? this.decoder,
      display: display ?? this.display,
      audio: audio ?? this.audio,
      connection: connection ?? this.connection,
    );
  }

  /// One line for the startup log, in the shape of
  /// `DevicePerformance.describeSync()`. Reading it on a device is how the
  /// detection layer gets checked without a debugger.
  String describe() => '${decoder.describe()} ${display.describe()} ${audio.describe()} ${connection.describe()}';

  @override
  String toString() => 'DeviceCapabilities(${describe()})';
}
