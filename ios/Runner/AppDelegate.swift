import Flutter
import UIKit
import AVFoundation
import AVKit
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var deviceAdjustmentChannel: FlutterMethodChannel?
  private var originalBrightness: CGFloat?
  private var volumeView: MPVolumeView?
  private weak var volumeSlider: UISlider?
  private var airPlayChannel: FlutterMethodChannel?
  private var airPlayRoutePicker: AVRoutePickerView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Configure audio session for media playback
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default)
      try session.setActive(true)
    } catch {
      print("Failed to configure audio session: \(error)")
    }

    application.beginReceivingRemoteControlEvents()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Register MPV player plugin
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MpvPlayerPlugin") {
      MpvPlayerPlugin.register(with: registrar)
    }

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeviceAdjustmentChannel") {
      registerDeviceAdjustmentChannel(messenger: registrar.messenger())
    }

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AirPlayChannel") {
      registerAirPlayChannel(messenger: registrar.messenger())
    }

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ICloudKvsPlugin") {
      ICloudKvsPlugin.register(with: registrar)
    }

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SecureFolderPlugin") {
      SecureFolderPlugin.register(with: registrar)
    }
  }

  private func registerAirPlayChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.pleya/airplay", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      DispatchQueue.main.async {
        self?.handleAirPlayCall(call, result: result)
      }
    }
    airPlayChannel = channel
  }

  private func handleAirPlayCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "showRoutePicker":
      // AVRoutePickerView owns the system picker; it exposes no public present
      // API, so add it offscreen and forward a tap to its internal button.
      guard let window = activeWindow else {
        result(FlutterError(code: "NO_WINDOW", message: "No active window", details: nil))
        return
      }
      let picker = airPlayRoutePicker ?? AVRoutePickerView(frame: .zero)
      picker.prioritizesVideoDevices = true
      if picker.superview == nil {
        picker.isHidden = true
        window.addSubview(picker)
      }
      airPlayRoutePicker = picker
      if let button = picker.subviews.compactMap({ $0 as? UIButton }).first {
        button.sendActions(for: .touchUpInside)
        result(true)
      } else {
        result(FlutterError(code: "NO_PICKER_BUTTON", message: "Route picker button unavailable", details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func registerDeviceAdjustmentChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.pleya/device_adjustment", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      DispatchQueue.main.async {
        self?.handleDeviceAdjustmentCall(call, result: result)
      }
    }
    deviceAdjustmentChannel = channel
  }

  private func handleDeviceAdjustmentCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getBrightness":
      result(Double(UIScreen.main.brightness))
    case "setBrightness":
      guard let value = normalizedArgument(call.arguments, result: result) else { return }
      if originalBrightness == nil {
        originalBrightness = UIScreen.main.brightness
      }
      UIScreen.main.brightness = CGFloat(value)
      result(nil)
    case "restoreBrightness":
      if let originalBrightness = originalBrightness {
        UIScreen.main.brightness = originalBrightness
        self.originalBrightness = nil
      }
      result(nil)
    case "getMediaVolume":
      result(Double(AVAudioSession.sharedInstance().outputVolume))
    case "setMediaVolume":
      guard let value = normalizedArgument(call.arguments, result: result) else { return }
      if setMediaVolume(value) {
        result(nil)
      } else {
        result(
          FlutterError(code: "DEVICE_ADJUSTMENT_UNAVAILABLE", message: "System volume slider unavailable", details: nil)
        )
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func normalizedArgument(_ arguments: Any?, result: @escaping FlutterResult) -> Double? {
    guard let value = arguments as? NSNumber else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected a numeric value", details: nil))
      return nil
    }
    let doubleValue = value.doubleValue
    guard doubleValue.isFinite else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected a finite numeric value", details: nil))
      return nil
    }
    return min(1.0, max(0.0, doubleValue))
  }

  private func setMediaVolume(_ value: Double) -> Bool {
    guard let slider = ensureVolumeSlider() else { return false }
    slider.setValue(Float(value), animated: false)
    slider.sendActions(for: .valueChanged)
    slider.sendActions(for: .touchUpInside)
    return true
  }

  private func ensureVolumeSlider() -> UISlider? {
    if let volumeSlider = volumeSlider { return volumeSlider }

    let volumeView = self.volumeView ?? MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
    volumeView.showsVolumeSlider = true
    volumeView.alpha = 0.01
    volumeView.isUserInteractionEnabled = false

    if volumeView.superview == nil {
      activeWindow?.addSubview(volumeView)
    }
    volumeView.layoutIfNeeded()

    self.volumeView = volumeView
    let slider = findVolumeSlider(in: volumeView)
    volumeSlider = slider
    return slider
  }

  private func findVolumeSlider(in view: UIView) -> UISlider? {
    if let slider = view as? UISlider { return slider }
    for subview in view.subviews {
      if let slider = findVolumeSlider(in: subview) { return slider }
    }
    return nil
  }

  private var activeWindow: UIWindow? {
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      if let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
        return keyWindow
      }
    }
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene, let window = windowScene.windows.first else { continue }
      return window
    }
    return nil
  }
}
