import Flutter
import UIKit
import AVFoundation
import universal_gamepad
import os_media_controls
import wakelock_plus

@objc class PleyaFlutterViewController: FlutterViewController {
  private lazy var tvRemoteChannel = FlutterBasicMessageChannel(
    name: "flutter/gamepadtouchevent",
    binaryMessenger: binaryMessenger,
    codec: FlutterJSONMessageCodec.sharedInstance()
  )

  // Stepping aside for a native session is the whole fix: while one is up this
  // controller must not hold first responder, or every press is delivered here
  // and swallowed by the engine before the presented controller sees it.
  override var canBecomeFirstResponder: Bool {
    !NativeInputSession.isActive
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(nativeInputSessionChanged),
      name: NativeInputSession.didChange,
      object: nil)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if !NativeInputSession.isActive {
      becomeFirstResponder()
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    resignFirstResponder()
    super.viewWillDisappear(animated)
  }

  @objc private func nativeInputSessionChanged() {
    if NativeInputSession.isActive {
      resignFirstResponder()
    } else if isViewLoaded, view.window != nil {
      becomeFirstResponder()
    }
  }

  /// Keeps presses out of the engine while a native surface owns the remote.
  ///
  /// `super` is `FlutterViewController`, which routes into the keyboard manager
  /// and only reaches the responder chain after an async Dart round-trip that
  /// reports "unhandled" — which never happens, because Pleya's focus tree
  /// handles every arrow and select. Swallowing outright would be just as bad:
  /// the focus engine would never see the press either. So forward to `next`.
  private func yieldPressToNativeSession(
    _ presses: Set<UIPress>,
    with event: UIPressesEvent?,
    handlingMenu: Bool,
    forward: (Set<UIPress>, UIPressesEvent?) -> Void
  ) -> Bool {
    guard NativeInputSession.isActive else { return false }

    if presses.contains(where: { $0.type == .menu }) {
      if handlingMenu {
        NativeInputSession.onMenuPress?()
      }
      return true
    }

    NativeInputSession.noteForwardedPress()
    forward(presses, event)
    return true
  }

  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if handlePlayPausePress(presses) {
      return
    }
    if yieldPressToNativeSession(
      presses, with: event, handlingMenu: true,
      forward: { presses, event in
        next?.pressesBegan(presses, with: event)
      })
    {
      return
    }

    super.pressesBegan(presses, with: event)
  }

  // The engine overrides pressesChanged too; without this, a held direction
  // leaks into Flutter mid-session.
  override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if containsPlayPausePress(presses) {
      return
    }
    if yieldPressToNativeSession(
      presses, with: event, handlingMenu: false,
      forward: { presses, event in
        next?.pressesChanged(presses, with: event)
      })
    {
      return
    }

    super.pressesChanged(presses, with: event)
  }

  override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if containsPlayPausePress(presses) {
      return
    }
    if yieldPressToNativeSession(
      presses, with: event, handlingMenu: false,
      forward: { presses, event in
        next?.pressesEnded(presses, with: event)
      })
    {
      return
    }

    super.pressesEnded(presses, with: event)
  }

  override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if containsPlayPausePress(presses) {
      return
    }
    if yieldPressToNativeSession(
      presses, with: event, handlingMenu: false,
      forward: { presses, event in
        next?.pressesCancelled(presses, with: event)
      })
    {
      return
    }

    super.pressesCancelled(presses, with: event)
  }

  override func remoteControlReceived(with event: UIEvent?) {
    guard let event = event else {
      super.remoteControlReceived(with: event)
      return
    }

    let subtype = event.subtype
    print("PleyaTvRemote: remote control event subtype=\(remoteControlSubtypeName(subtype))")
    switch subtype {
    case .remoteControlPlay, .remoteControlPause, .remoteControlTogglePlayPause:
      sendPlayPauseEvent(source: "remote_control", detail: remoteControlSubtypeName(subtype))
    default:
      super.remoteControlReceived(with: event)
    }
  }

  private func handlePlayPausePress(_ presses: Set<UIPress>) -> Bool {
    guard containsPlayPausePress(presses) else { return false }

    sendPlayPauseEvent(source: "presses", detail: "playPause")
    return true
  }

  private func containsPlayPausePress(_ presses: Set<UIPress>) -> Bool {
    presses.contains { press in
      press.type == .playPause
    }
  }

  private func sendPlayPauseEvent(source: String, detail: String) {
    print("PleyaTvRemote: intercepted play/pause source=\(source) detail=\(detail)")
    tvRemoteChannel.sendMessage(["type": "play_pause", "source": source, "detail": detail])
  }

  private func remoteControlSubtypeName(_ subtype: UIEvent.EventSubtype) -> String {
    switch subtype {
    case .remoteControlPlay:
      return "remoteControlPlay"
    case .remoteControlPause:
      return "remoteControlPause"
    case .remoteControlTogglePlayPause:
      return "remoteControlTogglePlayPause"
    case .remoteControlStop:
      return "remoteControlStop"
    case .remoteControlNextTrack:
      return "remoteControlNextTrack"
    case .remoteControlPreviousTrack:
      return "remoteControlPreviousTrack"
    case .remoteControlBeginSeekingForward:
      return "remoteControlBeginSeekingForward"
    case .remoteControlEndSeekingForward:
      return "remoteControlEndSeekingForward"
    case .remoteControlBeginSeekingBackward:
      return "remoteControlBeginSeekingBackward"
    case .remoteControlEndSeekingBackward:
      return "remoteControlEndSeekingBackward"
    default:
      return "unknown(\(subtype.rawValue))"
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default)
      try session.setActive(true)
    } catch {
      print("Failed to configure audio session: \(error)")
    }

    application.beginReceivingRemoteControlEvents()

    if let url = launchOptions?[UIApplication.LaunchOptionsKey.url] as? URL {
      _ = SystemShelfPlugin.handleOpenURL(url)
    }

    if let r = self.registrar(forPlugin: "SharedPreferencesPlugin") {
      SharedPreferencesPlugin.register(with: r)
    }
    if let r = self.registrar(forPlugin: "MpvPlayerPlugin") {
      MpvPlayerPlugin.register(with: r)
    }
    if let r = self.registrar(forPlugin: "PackageInfoPlusPlugin") {
      PackageInfoPlusPlugin.register(with: r)
    }
    if let r = self.registrar(forPlugin: "PathProviderPlugin") {
      PathProviderPlugin.register(with: r)
    }
    if let r = self.registrar(forPlugin: "GamepadPlugin") {
      GamepadPlugin.register(with: r)
    }
    if let r = self.registrar(forPlugin: "DeviceInfoPlusPlugin") {
      DeviceInfoPlusPlugin.register(with: r)
    }
    if let r = self.registrar(forPlugin: "ConnectivityPlusPlugin") {
      ConnectivityPlusPlugin.register(with: r)
    }
    if let r = self.registrar(forPlugin: "OsMediaControlsPlugin") {
      OsMediaControlsPlugin.register(with: r)
    }
    if let r = self.registrar(forPlugin: "WakelockPlusPlugin") {
      WakelockPlusPlugin.register(with: r)
    }
    if let r = self.registrar(forPlugin: "SystemShelfPlugin") {
      SystemShelfPlugin.register(with: r)
    }
    if let r = self.registrar(forPlugin: "ICloudKvsPlugin") {
      ICloudKvsPlugin.register(with: r)
    }
    if let r = self.registrar(forPlugin: "NativeTextEntryPlugin") {
      NativeTextEntryPlugin.register(with: r)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if SystemShelfPlugin.handleOpenURL(url) {
      return true
    }
    return super.application(application, open: url, options: options)
  }
}
