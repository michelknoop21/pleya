import Cocoa
import FlutterMacOS

/// Folder access with security-scoped bookmarks (sandboxed macOS builds).
/// Mirrors the iOS plugin: pick a folder via NSOpenPanel, start accessing it,
/// and return a `.withSecurityScope` bookmark that survives app restarts.
public class SecureFolderPlugin: NSObject, FlutterPlugin {
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
    default:
      result(FlutterMethodNotImplemented)
    }
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
      _ = url.startAccessingSecurityScopedResource()
      do {
        let bookmark = try url.bookmarkData(
          options: [.withSecurityScope],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
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
      _ = url.startAccessingSecurityScopedResource()
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
