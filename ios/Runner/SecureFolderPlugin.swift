import Flutter
import UIKit
import UniformTypeIdentifiers

/// Folder access with security-scoped bookmarks.
///
/// The Dart-side file_picker plugin returns only `url.path` from the document
/// picker and discards the security scope, so the sandbox denies every read
/// of the picked folder. This plugin owns the full flow instead: pick a
/// folder, immediately start accessing it, and hand Dart a persistable
/// bookmark that `resolveBookmark` can re-open after an app restart.
public class SecureFolderPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
  private var pendingResult: FlutterResult?

  /// URLs whose security scope is currently open, keyed by path. The sandbox
  /// only honors scoped reads while the *URL that started the access* is alive,
  /// so we must retain it — a deallocated URL silently revokes access and later
  /// directory listings come back empty. Balanced by `stopAccess`.
  private var accessedURLs: [String: URL] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.pleya/secure_folder", binaryMessenger: registrar.messenger())
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

  /// Retain [url] and keep its scope open for the app session. Idempotent per
  /// path so the start/stop use-count stays balanced.
  private func retainAccess(_ url: URL) {
    if accessedURLs[url.path] != nil { return }
    accessedURLs[url.path] = url
  }

  private func stopAccess(_ path: String) {
    guard let url = accessedURLs.removeValue(forKey: path) else { return }
    url.stopAccessingSecurityScopedResource()
  }

  private func pickFolder(result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(FlutterError(code: "BUSY", message: "Picker already open", details: nil))
      return
    }
    guard let controller = Self.topViewController() else {
      result(FlutterError(code: "NO_VIEWCONTROLLER", message: "No view controller to present from", details: nil))
      return
    }
    pendingResult = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder])
    picker.allowsMultipleSelection = false
    picker.delegate = self
    controller.present(picker, animated: true)
  }

  public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    let result = pendingResult
    pendingResult = nil
    guard let url = urls.first else {
      result?(nil)
      return
    }
    // Keep the scope open for this session; the bookmark restores it later.
    let accessing = url.startAccessingSecurityScopedResource()
    do {
      let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      if accessing { retainAccess(url) }
      result?(["path": url.path, "bookmark": bookmark.base64EncodedString()])
    } catch {
      if accessing { url.stopAccessingSecurityScopedResource() }
      result?(FlutterError(code: "BOOKMARK_FAILED", message: error.localizedDescription, details: nil))
    }
  }

  public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingResult?(nil)
    pendingResult = nil
  }

  private func resolveBookmark(_ data: Data, result: @escaping FlutterResult) {
    do {
      var isStale = false
      let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
      if url.startAccessingSecurityScopedResource() { retainAccess(url) }
      var response: [String: Any] = ["path": url.path]
      if isStale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
        response["bookmark"] = fresh.base64EncodedString()
      }
      result(response)
    } catch {
      result(FlutterError(code: "RESOLVE_FAILED", message: error.localizedDescription, details: nil))
    }
  }

  private static func topViewController() -> UIViewController? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    guard var top = (windows.first(where: { $0.isKeyWindow }) ?? windows.first)?.rootViewController else {
      return nil
    }
    while let presented = top.presentedViewController {
      top = presented
    }
    return top
  }
}
