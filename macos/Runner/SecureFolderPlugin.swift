import Cocoa
import FlutterMacOS

/// Folder access with security-scoped bookmarks (sandboxed macOS builds).
/// Mirrors the iOS plugin: pick a folder via NSOpenPanel, start accessing it,
/// and return a `.withSecurityScope` bookmark that survives app restarts.
public class SecureFolderPlugin: NSObject, FlutterPlugin {
  /// URLs whose security scope is open, keyed by path. The scope is only
  /// honored while the URL that started it is alive, so retain it for the
  /// session — otherwise later directory listings come back empty.
  private var accessedURLs: [String: URL] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.pleya/secure_folder", binaryMessenger: registrar.messenger)
    let instance = SecureFolderPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pickFolder":
      pickFolder(result: result)
    case "resolveBookmark":
      guard let args = call.arguments as? [String: Any], let bookmarkB64 = args["bookmark"] as? String,
        let data = Data(base64Encoded: bookmarkB64)
      else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "bookmark (base64) required", details: nil))
        return
      }
      resolveBookmark(data, result: result)
    case "stopAccess":
      if let args = call.arguments as? [String: Any], let path = args["path"] as? String {
        stopAccess(path)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func retainAccess(_ url: URL) {
    if accessedURLs[url.path] != nil { return }
    accessedURLs[url.path] = url
  }

  private func stopAccess(_ path: String) {
    guard let url = accessedURLs.removeValue(forKey: path) else { return }
    url.stopAccessingSecurityScopedResource()
  }

  private func pickFolder(result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.begin { response in
      guard response == .OK, let url = panel.url else {
        result(nil)
        return
      }
      let accessing = url.startAccessingSecurityScopedResource()
      do {
        let bookmark = try url.bookmarkData(
          options: [.withSecurityScope],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        if accessing { self.retainAccess(url) }
        result(["path": url.path, "bookmark": bookmark.base64EncodedString()])
      } catch {
        result(FlutterError(code: "BOOKMARK_FAILED", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func resolveBookmark(_ data: Data, result: @escaping FlutterResult) {
    do {
      var isStale = false
      let url = try URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      if url.startAccessingSecurityScopedResource() { retainAccess(url) }
      var response: [String: Any] = ["path": url.path]
      if isStale,
        let fresh = try? url.bookmarkData(
          options: [.withSecurityScope],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
      {
        response["bookmark"] = fresh.base64EncodedString()
      }
      result(response)
    } catch {
      result(FlutterError(code: "RESOLVE_FAILED", message: error.localizedDescription, details: nil))
    }
  }
}
