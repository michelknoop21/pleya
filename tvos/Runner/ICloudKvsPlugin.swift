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

  /// Whether this platform can use the key-value store at all.
  ///
  /// Deliberately *not* `ubiquityIdentityToken` on tvOS. That token reports the
  /// iCloud **Drive** Documents identity, and iCloud Drive does not exist on
  /// tvOS, so it is nil on a correctly signed-in Apple TV. Gating on it made
  /// the app claim "sign in to iCloud" and disable the toggle on every Apple
  /// TV. `NSUbiquitousKeyValueStore` is a separate facility, authorised by the
  /// `com.apple.developer.ubiquity-kvstore-identifier` entitlement that the
  /// tvOS target carries, so on tvOS the answer is simply yes. A store that
  /// then fails to reach the server surfaces as a sync status on the Dart
  /// side; it does not retroactively make the platform unsupported.
  ///
  /// On iOS and macOS the token remains the right question: there the account
  /// really can be absent, and a nil token means writes would be kept local.
  private static var isKvsAvailable: Bool {
    #if os(tvOS)
      return true
    #else
      return FileManager.default.ubiquityIdentityToken != nil
    #endif
  }

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
    store.synchronize()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(Self.isKvsAvailable)
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
