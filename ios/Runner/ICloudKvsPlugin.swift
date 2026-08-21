import Foundation

#if canImport(FlutterMacOS)
  import FlutterMacOS
#else
  import Flutter
#endif

/// Bridges the app's settings to NSUbiquitousKeyValueStore (iCloud key-value
/// store). Moves opaque Strings only — the Dart side owns typing and encoding.
/// Present on iOS, tvOS and macOS; the Dart guard keeps other platforms off it.
final class ICloudKvsPlugin: NSObject, FlutterPlugin {
  private static let channelName = "com.pleya/icloud_kvs"
  private static let eventChannelName = "com.pleya/icloud_kvs/events"

  private let store = NSUbiquitousKeyValueStore.default
  private var eventSink: FlutterEventSink?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ICloudKvsPlugin()
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    let events = FlutterEventChannel(name: eventChannelName, binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
    instance.startObserving()
  }

  private func startObserving() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(storeDidChangeExternally(_:)),
      name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
      object: store)
    // Signing out of iCloud, or switching account, is not reliably a store
    // change: the store belongs to the account that just went away. Without
    // this the Dart side keeps reporting the sync as healthy while every write
    // goes nowhere.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(ubiquityIdentityDidChange(_:)),
      name: .NSUbiquityIdentityDidChange,
      object: nil)
    store.synchronize()
  }

  deinit {
    // The registrar keeps this plugin for the life of the engine, so in a
    // single-engine app this never runs. It exists for the case that does not
    // hold: a second engine registers a second instance, and two live
    // observers would deliver every change twice.
    NotificationCenter.default.removeObserver(self)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(FileManager.default.ubiquityIdentityToken != nil)
    case "getAll":
      var out: [String: String] = [:]
      for (key, value) in store.dictionaryRepresentation {
        if let string = value as? String { out[key] = string }
      }
      result(out)
    case "set":
      guard let args = call.arguments as? [String: Any],
        let key = args["key"] as? String,
        let value = args["value"] as? String
      else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing key/value", details: nil))
        return
      }
      store.set(value, forKey: key)
      result(nil)
    case "remove":
      guard let args = call.arguments as? [String: Any], let key = args["key"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing key", details: nil))
        return
      }
      store.removeObject(forKey: key)
      result(nil)
    case "synchronize":
      result(store.synchronize())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// The iCloud account itself changed. Reported under the store's own
  /// account-change reason, so the Dart side needs no second vocabulary for it.
  @objc private func ubiquityIdentityDidChange(_ notification: Notification) {
    guard let sink = eventSink else { return }
    sink(["reason": NSUbiquitousKeyValueStoreAccountChange, "changedKeys": [String]()])
  }

  @objc private func storeDidChangeExternally(_ notification: Notification) {
    guard let sink = eventSink else { return }
    let info = notification.userInfo ?? [:]
    let reason = (info[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int) ?? -1
    let changedKeys = (info[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
    sink(["reason": reason, "changedKeys": changedKeys])
  }
}

extension ICloudKvsPlugin: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
