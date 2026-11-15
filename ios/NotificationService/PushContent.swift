import CryptoKit
import Foundation
import Security

/// Rich push (DEC-XXX), shared by Runner and the Notification Service Extension.
///
/// The app makes one AES-256 key per push installation and sends it to the
/// Pleya Server on registration. The server seals the title and a poster
/// reference with it; Apple only carries the ciphertext. The key lives in a
/// device-only keychain item in the shared access group, next to the base URL
/// of the server it was registered with.
enum PushContent {
  static let service = "nl.michelknoop.pleya.push"
  /// Serial, so making a key and pruning keys never overtake each other.
  static let queue = DispatchQueue(label: "nl.michelknoop.pleya.push-keys", qos: .userInitiated)

  /// What the server sealed: final, localized text plus an optional poster.
  struct Rich: Decodable, Equatable {
    let title: String
    let body: String
    let artwork: String?
    let token: String?
  }

  struct Stored: Codable {
    let key: String
    let base: String
  }

  /// Opens nonce|ciphertext|tag (CryptoKit's `combined`). Nil on any failure,
  /// which leaves the generic alert in place.
  static func open(_ sealed: Data, key: Data, aad: String) -> Rich? {
    guard key.count == 32,
      let box = try? AES.GCM.SealedBox(combined: sealed),
      let plain = try? AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: Data(aad.utf8)),
      let rich = try? JSONDecoder().decode(Rich.self, from: plain),
      !rich.title.isEmpty
    else { return nil }
    return rich
  }

  /// The poster on the server that registered this installation; HTTPS only.
  static func posterURL(base: String, artwork: String) -> URL? {
    guard UUID(uuidString: artwork) != nil,
      var components = URLComponents(string: base),
      components.scheme == "https", components.host?.isEmpty == false
    else { return nil }
    let path = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
    components.path = path + "/pleya/v1/artwork/" + artwork.lowercased()
    components.queryItems = [URLQueryItem(name: "width", value: "960")]
    components.fragment = nil
    return components.url
  }

  /// The rich content of a notification's userInfo, with the server base it
  /// came from. Nil when anything is missing or does not open.
  static func rich(from userInfo: [AnyHashable: Any]) -> (Rich, base: String)? {
    guard let pleya = userInfo["pleya"] as? [String: Any],
      let installation = pleya["i"] as? String,
      let notificationID = userInfo["notification_id"] as? String,
      let content = pleya["c"] as? String,
      let sealed = Data(base64Encoded: content),
      let stored = stored(installation),
      let key = Data(base64Encoded: stored.key),
      let rich = open(sealed, key: key, aad: installation + "|" + notificationID)
    else { return nil }
    return (rich, stored.base)
  }

  // MARK: - Keychain

  /// `$(AppIdentifierPrefix)nl.michelknoop.pleya.shared`, from Info.plist so
  /// app and extension name the same group without knowing the team prefix.
  private static var group: String? {
    Bundle.main.object(forInfoDictionaryKey: "PleyaPushKeychainGroup") as? String
  }

  // Verify copies must never read or prune the production keychain group.
  static func allowsKeychain(_ bundle: String?) -> Bool {
    bundle == "nl.michelknoop.pleya" || bundle == "nl.michelknoop.pleya.NotificationService"
  }

  private static func query(_ installation: String?) -> [String: Any]? {
    guard allowsKeychain(Bundle.main.bundleIdentifier), let group, !group.hasPrefix("$(")
    else { return nil }
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccessGroup as String: group,
      kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
    ]
    if let installation { query[kSecAttrAccount as String] = installation }
    return query
  }

  static func stored(_ installation: String) -> Stored? {
    guard var lookup = query(installation) else { return nil }
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else { return nil }
    return try? JSONDecoder().decode(Stored.self, from: data)
  }

  /// The installation's key in base64, made on first use. The base URL is
  /// rewritten each time, so a server that moved is followed. Nil when the
  /// keychain refuses; the app then registers without a key.
  static func key(for installation: String, base: String) -> String? {
    guard let match = query(installation) else { return nil }
    let key =
      stored(installation)?.key
      ?? SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).base64EncodedString() }
    guard let data = try? JSONEncoder().encode(Stored(key: key, base: base)) else { return nil }
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    var status = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      status = SecItemAdd(match.merging(attributes) { _, new in new } as CFDictionary, nil)
    }
    return status == errSecSuccess ? key : nil
  }

  /// Deletes every key whose installation is not in `keep`: an opt-out, a
  /// removed connection or a sign-out takes the key with it.
  static func retain(_ keep: Set<String>) {
    guard var lookup = query(nil) else { return }
    lookup[kSecReturnAttributes as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitAll
    var items: CFTypeRef?
    guard SecItemCopyMatching(lookup as CFDictionary, &items) == errSecSuccess,
      let found = items as? [[String: Any]]
    else { return }
    for account in found.compactMap({ $0[kSecAttrAccount as String] as? String }) where !keep.contains(account) {
      if let match = query(account) { SecItemDelete(match as CFDictionary) }
    }
  }
}
