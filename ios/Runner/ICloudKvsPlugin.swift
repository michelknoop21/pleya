import Foundation
import CloudKit

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

  private let credentials = ICloudCredentialStore()
  private let store = NSUbiquitousKeyValueStore.default
  private var eventSink: FlutterEventSink?

  /// Whether the key-value store can be used at all.
  ///
  /// Not `ubiquityIdentityToken` on tvOS: that token is the iCloud Drive
  /// Documents identity, which tvOS does not have, so it is nil on a signed-in
  /// Apple TV and the toggle went dead there ("sign in to iCloud"). The store is
  /// gated by the `com.apple.developer.ubiquity-kvstore-identifier` entitlement
  /// the tvOS target carries. On iOS and macOS the token stays the account check.
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
    case "credentialRead", "credentialWrite":
      credentials.handle(call, result: result)
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

  /// The iCloud account itself changed. Reported under the store's own
  /// account-change reason, so the Dart side needs no second vocabulary for it.
  @objc private func ubiquityIdentityDidChange(_ notification: Notification) {
    emit(["reason": NSUbiquitousKeyValueStoreAccountChange, "changedKeys": [String]()])
  }

  @objc private func storeDidChangeExternally(_ notification: Notification) {
    let info = notification.userInfo ?? [:]
    let reason = (info[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int) ?? -1
    let changedKeys = (info[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
    emit(["reason": reason, "changedKeys": changedKeys])
  }

  /// Channel traffic has to happen on the platform thread; NotificationCenter
  /// delivers on the posting thread, and Apple documents none for these two
  /// notifications. The sink is read inside the hop so a cancel that raced the
  /// notification is honoured.
  private func emit(_ payload: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      guard let sink = self?.eventSink else { return }
      sink(payload)
    }
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

/// Credentials use a private CloudKit encrypted field, never the KVS store.
/// Keep this implementation identical on iOS, tvOS and macOS.
private final class ICloudCredentialStore: NSObject {
  private let container: CKContainer
  private var generation = 0
  private var operations: [CKOperation] = []

  override init() {
    // Verify has its own container; it must never read production credentials.
    let bundle = Bundle.main.bundleIdentifier ?? "invalid.pleya.bundle"
    container = CKContainer(identifier: "iCloud.\(bundle)")
    super.init()
    NotificationCenter.default.addObserver(
      self, selector: #selector(accountChanged), name: .CKAccountChanged, object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    for operation in operations { operation.cancel() }
  }

  @objc private func accountChanged() {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.generation += 1
      for operation in self.operations { operation.cancel() }
      self.operations.removeAll()
    }
  }

  private func failure(_ code: String, _ result: @escaping FlutterResult) {
    // CloudKit error descriptions can include identities and record contents.
    result(FlutterError(code: code, message: "Connection synchronization unavailable", details: nil))
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 15.0, tvOS 15.0, macOS 12.0, *) else {
      failure("CREDENTIAL_UNAVAILABLE", result)
      return
    }
    let epoch = generation
    container.fetchUserRecordID { [weak self] account, error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        guard epoch == self.generation else {
          self.failure("CREDENTIAL_ACCOUNT_CHANGED", result)
          return
        }
        guard error == nil, let account = account else {
          self.failure("CREDENTIAL_UNAVAILABLE", result)
          return
        }
        let args = call.arguments as? [String: Any] ?? [:]
        if call.method == "credentialWrite", args["account"] as? String != account.recordName {
          self.failure("CREDENTIAL_ACCOUNT_CHANGED", result)
          return
        }
        self.fetch(call, args: args, account: account.recordName, epoch: epoch, result: result)
      }
    }
  }

  private func writeFailure(_ error: Error, result: @escaping FlutterResult) {
    let cloud = error as? CKError
    let conflict =
      cloud?.code == .serverRecordChanged
      || (cloud?.partialErrorsByItemID?.values.contains { ($0 as? CKError)?.code == .serverRecordChanged } ?? false)
    failure(conflict ? "CREDENTIAL_CONFLICT" : "CREDENTIAL_WRITE_FAILED", result)
  }

  @available(iOS 15.0, tvOS 15.0, macOS 12.0, *)
  private func fetch(
    _ call: FlutterMethodCall, args: [String: Any], account: String, epoch: Int,
    result: @escaping FlutterResult
  ) {
    let recordID = CKRecord.ID(recordName: "integration-credentials-v1")
    container.privateCloudDatabase.fetch(withRecordID: recordID) { [weak self] record, error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        guard epoch == self.generation else {
          self.failure("CREDENTIAL_ACCOUNT_CHANGED", result)
          return
        }
        if let error = error as? CKError, error.code != .unknownItem {
          self.failure("CREDENTIAL_READ_FAILED", result)
          return
        } else if error != nil && (error as? CKError)?.code != .unknownItem {
          self.failure("CREDENTIAL_READ_FAILED", result)
          return
        }
        if record == nil && (error as? CKError)?.code != .unknownItem {
          self.failure("CREDENTIAL_READ_FAILED", result)
          return
        }
        if call.method == "credentialRead" {
          guard let record = record else {
            result(["account": account])
            return
          }
          guard let payload = record.encryptedValues["payloadV1"] as? String,
            let tag = record.recordChangeTag
          else {
            self.failure("CREDENTIAL_INVALID_RECORD", result)
            return
          }
          result(["account": account, "payload": payload, "tag": tag])
          return
        }
        guard let payload = args["payload"] as? String, payload.utf8.count <= 256 * 1024 else {
          self.failure("CREDENTIAL_INVALID_ARGS", result)
          return
        }
        // A missing tag means "create only"; a failed read is never an empty
        // database. CKModifyRecordsOperation enforces this again atomically.
        guard record?.recordChangeTag == args["tag"] as? String else {
          self.failure("CREDENTIAL_CONFLICT", result)
          return
        }
        let updated = record ?? CKRecord(recordType: "PleyaIntegrationCredentialsV1", recordID: recordID)
        updated.encryptedValues["payloadV1"] = payload as NSString
        let operation = CKModifyRecordsOperation(recordsToSave: [updated], recordIDsToDelete: nil)
        operation.savePolicy = .ifServerRecordUnchanged
        operation.isAtomic = false
        let saved = CredentialWriteResult()
        operation.perRecordSaveBlock = { _, outcome in
          saved.set(outcome.map { _ in () })
        }
        operation.modifyRecordsResultBlock = { [weak self, weak operation] outcome in
          DispatchQueue.main.async {
            guard let self = self else { return }
            self.operations.removeAll { $0 === operation }
            guard epoch == self.generation else {
              self.failure("CREDENTIAL_ACCOUNT_CHANGED", result)
              return
            }
            switch saved.completed(outcome) {
            case .success: result(nil)
            case .failure(let error): self.writeFailure(error, result: result)
            }
          }
        }
        self.operations.append(operation)
        self.container.privateCloudDatabase.add(operation)
      }
    }
  }
}

/// CloudKit's per-record and operation callbacks can arrive on different queues.
private final class CredentialWriteResult: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Result<Void, Error>?
  func set(_ result: Result<Void, Error>) {
    lock.lock()
    defer { lock.unlock() }
    value = result
  }
  func completed(_ operation: Result<Void, Error>) -> Result<Void, Error> {
    switch operation {
    case .failure: return operation
    case .success:
      return get() ?? .failure(NSError(domain: "PleyaCredentialWrite", code: 1))
    }
  }
  private func get() -> Result<Void, Error>? {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}
