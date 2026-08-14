import Foundation

#if canImport(AVFoundation)
  import AVFoundation
#endif

#if canImport(FlutterMacOS)
  import FlutterMacOS
#else
  import Flutter
#endif

#if os(iOS) || os(tvOS)

  /// Exposes the audio route to Dart so playback can pick between Dolby
  /// passthrough, multichannel PCM and stereo.
  ///
  /// Two things have to be true before the system hands us anything wider than
  /// stereo. The session must run in `.moviePlayback`, and the app must opt in
  /// with `setSupportsMultichannelContent(true)` — without it AirPods and most
  /// AirPlay routes keep reporting two channels, mpv's `ao_audiounit` sees
  /// `outputNumberOfChannels <= 2` and hard-downmixes to stereo. A stereo
  /// stream has nothing left to spatialize, which is why the app sounded flat
  /// next to players that do set the flag.
  ///
  /// Head-tracked vs fixed spatial audio is deliberately absent:
  /// `setIntendedSpatialExperience` is visionOS-only, and on iOS/tvOS the
  /// choice belongs to Control Center.
  ///
  /// Present on iOS and tvOS only; macOS has no AVAudioSession, and the Dart
  /// guard keeps every other platform off the channel.
  final class AudioSessionPlugin: NSObject, FlutterPlugin {
    private static let channelName = "com.pleya/audio_session"
    private static let eventChannelName = "com.pleya/audio_session/events"

    private var eventSink: FlutterEventSink?
    private var observers: [NSObjectProtocol] = []

    static func register(with registrar: FlutterPluginRegistrar) {
      let instance = AudioSessionPlugin()
      let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
      registrar.addMethodCallDelegate(instance, channel: channel)
      let events = FlutterEventChannel(name: eventChannelName, binaryMessenger: registrar.messenger())
      events.setStreamHandler(instance)
      instance.startObserving()
    }

    /// Applies the session configuration playback needs. Safe to call more than
    /// once: AVAudioSession folds repeated identical settings into a no-op, and
    /// the returned snapshot always reflects the route as it is *after* the
    /// call, which is what the channel-negotiation decision runs on.
    /// `options` exists for the Pleya Share keepalive, which needs
    /// `.mixWithOthers` so its silent loop cannot interrupt real playback. It
    /// still goes through here rather than setting the category itself: doing
    /// that dropped the mode back to `.default` and lost the multichannel
    /// opt-in, so a host that played something while sharing was on got stereo
    /// until sharing stopped.
    static func configure(multichannel: Bool, options: AVAudioSession.CategoryOptions = []) {
      let session = AVAudioSession.sharedInstance()
      do {
        try session.setCategory(.playback, mode: .moviePlayback, options: options)
        try session.setSupportsMultichannelContent(multichannel)
        try session.setActive(true)
      } catch {
        NSLog("[AudioSession] configure(multichannel: \(multichannel)) failed: \(error)")
      }
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
      switch call.method {
      case "configure":
        let args = call.arguments as? [String: Any]
        let multichannel = (args?["multichannel"] as? Bool) ?? true
        AudioSessionPlugin.configure(multichannel: multichannel)
        result(Self.snapshot())
      case "snapshot":
        result(Self.snapshot())
      case "measure":
        result(Self.measure())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // MARK: - Measurement

    /// Answers the one question the documentation does not: does this route
    /// actually widen past stereo once the app opts into multichannel content?
    ///
    /// Apple's own docs only promise that the opt-in lets the system offer more
    /// channels, and there are field reports of Bluetooth routes staying at two
    /// regardless. The multichannel-PCM path is only worth taking where the
    /// answer is yes, so this measures rather than assumes: read the route with
    /// the flag off, then with it on, and report both.
    ///
    /// Leaves the session with the flag ON, which is the state playback wants.
    /// Meant to run before playback starts — flipping the flag mid-stream would
    /// reload the audio output.
    static func measure() -> [String: Any] {
      let session = AVAudioSession.sharedInstance()

      try? session.setCategory(.playback, mode: .moviePlayback)
      try? session.setActive(true)

      try? session.setSupportsMultichannelContent(false)
      let before = snapshot()

      try? session.setSupportsMultichannelContent(true)
      let after = snapshot()

      return ["before": before, "after": after]
    }

    // MARK: - Snapshot

    static func snapshot() -> [String: Any] {
      let session = AVAudioSession.sharedInstance()
      let output = session.currentRoute.outputs.first

      var map: [String: Any] = [
        "maximumOutputNumberOfChannels": session.maximumOutputNumberOfChannels,
        "outputNumberOfChannels": session.outputNumberOfChannels,
        "supportsMultichannelContent": session.supportsMultichannelContent,
        "spatialAudioEnabled": output?.isSpatialAudioEnabled ?? false,
        "portType": output?.portType.rawValue ?? "",
        "portName": output?.portName ?? "",
        // Classified here, against the real AVAudioSession.Port constants,
        // rather than by string-matching raw values on the Dart side — those
        // values are undocumented ("LineOut", not "Line Out") and a typo would
        // fail silently as a branch that simply never runs.
        "isDigitalOutput": output.map(Self.isDigitalOutput) ?? false,
      ]

      // renderingMode is iOS/tvOS 17.2+; the iOS deployment target is lower, so
      // it stays absent there rather than reporting a wrong value.
      if #available(iOS 17.2, tvOS 17.2, *) {
        map["renderingMode"] = Self.renderingModeName(session.renderingMode)
      }

      return map
    }

    /// Wired digital outputs that can carry a Dolby bitstream to something that
    /// decodes it — the routes where passthrough beats decoding locally.
    private static func isDigitalOutput(_ port: AVAudioSessionPortDescription) -> Bool {
      switch port.portType {
      case .HDMI, .displayPort, .lineOut, .usbAudio:
        return true
      default:
        return false
      }
    }

    @available(iOS 17.2, tvOS 17.2, *)
    private static func renderingModeName(_ mode: AVAudioSession.RenderingMode) -> String {
      switch mode {
      case .notApplicable: return "notApplicable"
      case .monoStereo: return "monoStereo"
      case .surround: return "surround"
      case .spatialAudio: return "spatialAudio"
      case .dolbyAudio: return "dolbyAudio"
      case .dolbyAtmos: return "dolbyAtmos"
      @unknown default: return "unknown"
      }
    }

    // MARK: - Observation

    private func startObserving() {
      observe(AVAudioSession.routeChangeNotification, reason: "routeChange")
      observe(AVAudioSession.spatialPlaybackCapabilitiesChangedNotification, reason: "spatialCapabilities")
      if #available(iOS 17.2, tvOS 17.2, *) {
        observe(AVAudioSession.renderingModeChangeNotification, reason: "renderingMode")
      }
    }

    private func observe(_ name: NSNotification.Name, reason: String) {
      let observer = NotificationCenter.default.addObserver(
        forName: name,
        object: AVAudioSession.sharedInstance(),
        queue: .main
      ) { [weak self] _ in
        guard let sink = self?.eventSink else { return }
        var payload = Self.snapshot()
        payload["reason"] = reason
        sink(payload)
      }
      observers.append(observer)
    }

    deinit {
      for observer in observers {
        NotificationCenter.default.removeObserver(observer)
      }
    }
  }

  extension AudioSessionPlugin: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
      eventSink = events
      return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
      eventSink = nil
      return nil
    }
  }

#endif
