import Foundation
import TVServices

#if os(tvOS)
  import Flutter

  final class SystemShelfPlugin: NSObject, FlutterPlugin {
    private static let channelName = "com.pleya/system_shelf"
    private static let appGroupIdentifier = "group.nl.michelknoop.pleya"
    private static let cacheDataKey = "PleyaSystemShelfCacheData"
    /// `["contentId": id, "action": "play" | "open"]`; `action` is absent on
    /// links from older Top Shelf builds. Dart's `ShelfDeepLink.fromNative`
    /// reads this shape.
    private static var pendingDeepLink: [String: String]?
    private static var methodChannel: FlutterMethodChannel?

    static func register(with registrar: FlutterPluginRegistrar) {
      let channel = FlutterMethodChannel(
        name: channelName,
        binaryMessenger: registrar.messenger()
      )
      methodChannel = channel
      registrar.addMethodCallDelegate(SystemShelfPlugin(), channel: channel)
    }

    static func handleOpenURL(_ url: URL) -> Bool {
      guard let link = deepLink(from: url) else { return false }
      pendingDeepLink = link
      methodChannel?.invokeMethod("onShelfItemTap", arguments: link)
      return true
    }

    private static func deepLink(from url: URL) -> [String: String]? {
      guard url.scheme == "pleya", url.host == "play" else { return nil }
      let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      guard let contentId = queryItems.first(where: { $0.name == "content_id" })?.value else { return nil }
      var link = ["contentId": contentId]
      link["action"] = queryItems.first { $0.name == "action" }?.value
      return link
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
      switch call.method {
      case "isSupported":
        result(Self.sharedDefaults != nil)
      case "sync":
        guard let args = call.arguments as? [String: Any], let rawItems = args["items"] as? [[String: Any]] else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing items", details: nil))
          return
        }
        // Current Dart sends `sections` (Continue Watching, title localized)
        // plus an optional `carousel` (hero films, then Continue Watching);
        // `items` alone is the older one-row shape.
        if let sections = args["sections"] as? [[String: Any]] {
          result(Self.writeSections(sections, carousel: args["carousel"] as? [[String: Any]]))
        } else {
          result(Self.writeItems(rawItems.map(Self.normalizedItem)))
        }
      case "imageDirectory":
        // Dart stores the carousel artwork here; the extension reads the
        // file:// URLs it writes into the payload.
        result(Self.imageDirectoryURL?.path)
      case "clear":
        result(Self.clearCache())
      case "remove":
        guard let args = call.arguments as? [String: Any], let contentId = args["contentId"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing contentId", details: nil))
          return
        }
        result(Self.removeItem(contentId: contentId))
      case "getInitialDeepLink":
        let link = Self.pendingDeepLink
        Self.pendingDeepLink = nil
        result(link)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    private static var sharedDefaults: UserDefaults? {
      UserDefaults(suiteName: appGroupIdentifier)
    }

    private static var imageDirectoryURL: URL? {
      FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
        .appendingPathComponent("TopShelfImages", isDirectory: true)
    }

    private static func normalizedItem(_ item: [String: Any]) -> [String: Any] {
      item.reduce(into: [String: Any]()) { result, entry in
        if entry.value is NSNull { return }
        result[entry.key] = entry.value
      }
    }

    private static func writeItems(_ items: [[String: Any]]) -> Bool {
      let payload: [String: Any] = [
        "updatedAt": Date().timeIntervalSince1970,
        "sections": [
          [
            "id": "continue_watching",
            "title": "Continue Watching",
            "items": items,
          ]
        ],
      ]

      return writePayload(payload)
    }

    /// `writePayload` drops NSNull values recursively, so items need no
    /// separate normalization here.
    private static func writeSections(_ sections: [[String: Any]], carousel: [[String: Any]]?) -> Bool {
      var payload: [String: Any] = [
        "updatedAt": Date().timeIntervalSince1970,
        "sections": sections,
      ]
      payload["carousel"] = carousel
      return writePayload(payload)
    }

    private static func writePayload(_ payload: [String: Any]) -> Bool {
      guard let defaults = sharedDefaults else {
        return false
      }

      let sanitizedPayload = sanitizedJSONObject(payload)
      guard JSONSerialization.isValidJSONObject(sanitizedPayload) else {
        return false
      }

      do {
        let data = try JSONSerialization.data(withJSONObject: sanitizedPayload)
        defaults.set(data, forKey: cacheDataKey)
        defaults.synchronize()
      } catch {
        return false
      }

      TVTopShelfContentProvider.topShelfContentDidChange()
      return true
    }

    private static func sanitizedJSONObject(_ object: [String: Any]) -> [String: Any] {
      object.reduce(into: [String: Any]()) { result, entry in
        if let value = sanitizedJSONValue(entry.value) {
          result[entry.key] = value
        }
      }
    }

    private static func sanitizedJSONValue(_ value: Any) -> Any? {
      if value is NSNull { return nil }

      if let value = value as? String { return value }
      if let value = value as? NSNumber {
        if CFGetTypeID(value) == CFBooleanGetTypeID() { return value.boolValue }
        return value.doubleValue.isFinite ? value : nil
      }
      if let value = value as? Bool { return value }
      if let value = value as? Int { return value }
      if let value = value as? Int64 { return value }
      if let value = value as? Double { return value.isFinite ? value : nil }
      if let value = value as? Float { return value.isFinite ? Double(value) : nil }

      if let value = value as? [String: Any] {
        return value.reduce(into: [String: Any]()) { result, entry in
          if let nestedValue = sanitizedJSONValue(entry.value) {
            result[entry.key] = nestedValue
          }
        }
      }

      if let value = value as? [Any] {
        return value.compactMap { nestedValue in
          sanitizedJSONValue(nestedValue)
        }
      }

      return nil
    }

    private static func clearCache() -> Bool {
      guard let defaults = sharedDefaults else {
        return false
      }

      defaults.removeObject(forKey: cacheDataKey)
      defaults.synchronize()
      if let images = imageDirectoryURL {
        try? FileManager.default.removeItem(at: images)
      }

      TVTopShelfContentProvider.topShelfContentDidChange()
      return true
    }

    private static func removeItem(contentId: String) -> Bool {
      guard let defaults = sharedDefaults,
        let data = defaults.data(forKey: cacheDataKey),
        var payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let sections = payload["sections"] as? [[String: Any]]
      else {
        return false
      }

      var removed = false
      let filteredSections = sections.map { section -> [String: Any] in
        var nextSection = section
        if let items = section["items"] as? [[String: Any]] {
          let filteredItems = items.filter { $0["contentId"] as? String != contentId }
          removed = removed || filteredItems.count != items.count
          nextSection["items"] = filteredItems
        }
        return nextSection
      }

      if let carousel = payload["carousel"] as? [[String: Any]] {
        let filteredCarousel = carousel.filter { $0["contentId"] as? String != contentId }
        removed = removed || filteredCarousel.count != carousel.count
        payload["carousel"] = filteredCarousel
      }

      if !removed {
        return false
      }
      payload["updatedAt"] = Date().timeIntervalSince1970
      payload["sections"] = filteredSections
      return writePayload(payload)
    }
  }
#endif
