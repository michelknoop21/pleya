import Foundation
import Security

#if canImport(FlutterMacOS)
  import FlutterMacOS
#else
  import Flutter
#endif

#if os(iOS) || os(tvOS)

  /// Small strings in the iCloud keychain, so iPhone, iPad and Apple TV share
  /// them. Generic passwords under one service, synchronizable, readable after
  /// the first unlock. Never a `ThisDeviceOnly` class: those do not sync.
  ///
  /// iOS and tvOS share bundle ID and team, so the default access group is
  /// the same on both and no extra entitlement is needed.
  ///
  /// A call with `scope: "device"` uses a second service whose items do not
  /// sync and are `ThisDeviceOnly`: tracker tokens, which belong to one device.
  /// An unknown scope is refused, so a typo can never land in iCloud.
  ///
  /// A missing item reads as nil. Every other status comes back as a
  /// FlutterError with the OSStatus, so Dart never mistakes a keychain
  /// failure for "nothing stored". Values never appear in an error.
  final class PleyaKeychainPlugin: NSObject, FlutterPlugin {
    private static let channelName = "com.pleya/keychain"
    private static let service = "nl.michelknoop.pleya.assistant"
    private static let deviceService = "nl.michelknoop.pleya.device"
    /// SecItem calls can block on securityd; serial so a write and its
    /// readback never overtake each other.
    private static let queue = DispatchQueue(label: "com.pleya.keychain", qos: .userInitiated)

    static func register(with registrar: FlutterPluginRegistrar) {
      let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
      registrar.addMethodCallDelegate(PleyaKeychainPlugin(), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
      let args = call.arguments as? [String: Any]
      guard let key = args?["key"] as? String, !key.isEmpty else {
        result(FlutterError(code: "BAD_ARGS", message: "\(call.method) needs a key", details: nil))
        return
      }
      let deviceOnly: Bool
      switch args?["scope"] as? String {
      case nil: deviceOnly = false
      case "device": deviceOnly = true
      default:
        result(FlutterError(code: "BAD_ARGS", message: "unknown scope", details: nil))
        return
      }
      let work: () -> Any?
      switch call.method {
      case "read":
        work = { Self.read(key, deviceOnly) }
      case "write":
        guard let value = args?["value"] as? String else {
          result(FlutterError(code: "BAD_ARGS", message: "write needs a value", details: nil))
          return
        }
        work = { Self.write(key, value, deviceOnly) }
      case "delete":
        work = { Self.delete(key, deviceOnly) }
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      Self.queue.async {
        let value = work()
        DispatchQueue.main.async { result(value) }
      }
    }

    private static func query(_ key: String, _ deviceOnly: Bool) -> [String: Any] {
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: deviceOnly ? deviceService : service,
        kSecAttrAccount as String: key,
        kSecAttrSynchronizable as String: (deviceOnly ? kCFBooleanFalse : kCFBooleanTrue) as Any,
      ]
    }

    private static func failure(_ status: OSStatus) -> FlutterError {
      FlutterError(code: "KEYCHAIN", message: "OSStatus \(status)", details: Int(status))
    }

    private static func read(_ key: String, _ deviceOnly: Bool) -> Any? {
      var lookup = query(key, deviceOnly)
      lookup[kSecReturnData as String] = true
      lookup[kSecMatchLimit as String] = kSecMatchLimitOne
      var item: CFTypeRef?
      let status = SecItemCopyMatching(lookup as CFDictionary, &item)
      if status == errSecItemNotFound { return nil }
      guard status == errSecSuccess else { return failure(status) }
      guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
        return FlutterError(code: "KEYCHAIN", message: "item is not UTF-8 text", details: nil)
      }
      return value
    }

    /// Update first; add only when the item does not exist yet. An add that
    /// races another writer (a sync landing in between) updates after all.
    private static func write(_ key: String, _ value: String, _ deviceOnly: Bool) -> Any {
      let data = Data(value.utf8)
      let attributes: [String: Any] = [
        kSecValueData as String: data,
        kSecAttrAccessible as String: deviceOnly
          ? kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly : kSecAttrAccessibleAfterFirstUnlock,
      ]
      var status = SecItemUpdate(query(key, deviceOnly) as CFDictionary, attributes as CFDictionary)
      if status == errSecItemNotFound {
        let add = query(key, deviceOnly).merging(attributes) { _, new in new }
        status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
          status = SecItemUpdate(query(key, deviceOnly) as CFDictionary, attributes as CFDictionary)
        }
      }
      return status == errSecSuccess ? true : failure(status)
    }

    private static func delete(_ key: String, _ deviceOnly: Bool) -> Any? {
      let status = SecItemDelete(query(key, deviceOnly) as CFDictionary)
      return status == errSecSuccess || status == errSecItemNotFound ? nil : failure(status)
    }
  }

#endif
