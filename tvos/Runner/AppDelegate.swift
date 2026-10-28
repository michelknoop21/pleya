import Flutter
import UIKit
import AVFoundation
import GameController
import os
import universal_gamepad
import os_media_controls
import wakelock_plus

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var navAccessibilityChannel: FlutterMethodChannel?

  /// One line at startup so an engine bump cannot break the press hook in
  /// silence.
  ///
  /// `tvosHandlePressFromUIEvent:` is engine-internal and appears in no public
  /// header; `Runner-Bridging-Header.h` only promises the compiler it exists. If
  /// a future `tvos/engine.version` drops or renames it,
  /// `PleyaFlutterViewController.tvosHandlePress(fromUIEvent:)` simply stops
  /// being called and the system keyboard goes back to ignoring every click.
  ///
  /// Asked of `FlutterViewController` itself, never of an instance: our own
  /// subclass implements the selector, so any instance answers yes regardless of
  /// what the engine still provides.
  private static func logPressHookAvailability() {
    let selector = NSSelectorFromString("tvosHandlePressFromUIEvent:")
    let supported = FlutterViewController.instancesRespond(to: selector)
    NSLog("[PleyaTvosPress] engine press hook available=%@", supported ? "true" : "false")
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    Self.logPressHookAvailability()

    // `.moviePlayback` plus the multichannel opt-in; without the latter the
    // system caps the route at two channels and mpv downmixes before Dolby or
    // spatial rendering can ever apply.
    AudioSessionPlugin.configure(multichannel: true)

    application.beginReceivingRemoteControlEvents()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Plugins register once the implicit engine exists. Under the UIScene
  /// lifecycle (required since tvOS 27, see `PleyaSceneDelegate`) the window,
  /// and with it the storyboard's `FlutterViewController`, is created by the
  /// scene after `didFinishLaunching`, so `self.registrar(forPlugin:)` there
  /// would find no engine and register nothing.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LocalLibraryStorage") {
      let channel = FlutterMethodChannel(name: "com.pleya/local_library", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "availableBytes" else { result(FlutterMethodNotImplemented); return }
        do {
          let values = try URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [
            .volumeAvailableCapacityKey
          ])
          result(values.volumeAvailableCapacity.map { Int64($0) })
        } catch {
          result(FlutterError(code: "STORAGE_UNAVAILABLE", message: "Unable to read available storage", details: nil))
        }
      }
    }

    if let r = engineBridge.pluginRegistry.registrar(forPlugin: "TvNavAccessibility") {
      let channel = FlutterMethodChannel(name: "pleya/tvos_nav_accessibility", binaryMessenger: r.messenger())
      navAccessibilityChannel = channel
      channel.setMethodCallHandler { call, result in
        if call.method == "reduceTransparency" {
          result(UIAccessibility.isReduceTransparencyEnabled)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(navTransparencyChanged),
        name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
        object: nil
      )
    }
    if let r = engineBridge.pluginRegistry.registrar(forPlugin: "SharedPreferencesPlugin") {
      SharedPreferencesPlugin.register(with: r)
    }
    if let r = engineBridge.pluginRegistry.registrar(forPlugin: "MpvPlayerPlugin") {
      MpvPlayerPlugin.register(with: r)
    }
    if let r = engineBridge.pluginRegistry.registrar(forPlugin: "PackageInfoPlusPlugin") {
      PackageInfoPlusPlugin.register(with: r)
    }
    if let r = engineBridge.pluginRegistry.registrar(forPlugin: "PathProviderPlugin") {
      PathProviderPlugin.register(with: r)
    }
    if let r = engineBridge.pluginRegistry.registrar(forPlugin: "GamepadPlugin") {
      GamepadPlugin.register(with: r)
    }
    if let r = engineBridge.pluginRegistry.registrar(forPlugin: "DeviceInfoPlusPlugin") {
      DeviceInfoPlusPlugin.register(with: r)
    }
    if let r = engineBridge.pluginRegistry.registrar(forPlugin: "ConnectivityPlusPlugin") {
      ConnectivityPlusPlugin.register(with: r)
    }
    if let r = engineBridge.pluginRegistry.registrar(forPlugin: "OsMediaControlsPlugin") {
      OsMediaControlsPlugin.register(with: r)
    }
    if let r = engineBridge.pluginRegistry.registrar(forPlugin: "WakelockPlusPlugin") {
      WakelockPlusPlugin.register(with: r)
    }
    if let r = engineBridge.pluginRegistry.registrar(forPlugin: "SystemShelfPlugin") {
      SystemShelfPlugin.register(with: r)
    }
    if let r = engineBridge.pluginRegistry.registrar(forPlugin: "ICloudKvsPlugin") {
      ICloudKvsPlugin.register(with: r)
    }
    if let r = engineBridge.pluginRegistry.registrar(forPlugin: "AudioSessionPlugin") {
      AudioSessionPlugin.register(with: r)
    }
    if let r = engineBridge.pluginRegistry.registrar(forPlugin: "PleyaKeychainPlugin") {
      PleyaKeychainPlugin.register(with: r)
    }
    if let r = engineBridge.pluginRegistry.registrar(forPlugin: "NativeTextEntryPlugin") {
      NativeTextEntryPlugin.register(with: r)
    }
  }

  @objc private func navTransparencyChanged() {
    navAccessibilityChannel?.invokeMethod(
      "reduceTransparencyChanged", arguments: UIAccessibility.isReduceTransparencyEnabled)
  }

}
