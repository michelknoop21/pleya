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
    case "listDirectory":
      guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "path required", details: nil))
        return
      }
      listDirectory(path, result: result)
    case "resolvePlaybackPath":
      guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "path required", details: nil))
        return
      }
      resolvePlaybackPath(path, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Resolve [path] against a retained scoped URL. The sandbox extension for a
  /// File Provider folder is bound to the URL object that came out of the
  /// bookmark — a fresh `URL(fileURLWithPath:)` to the same path is denied.
  /// Subpaths (Serie/Seizoen) are derived from the scoped root per segment.
  private func scopedURL(for path: String) -> URL? {
    if let exact = accessedURLs[path] { return exact }
    for (rootPath, rootURL) in accessedURLs {
      let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
      guard path.hasPrefix(prefix) else { continue }
      var url = rootURL
      for segment in path.dropFirst(prefix.count).split(separator: "/") {
        url.appendPathComponent(String(segment))
      }
      return url
    }
    return nil
  }

  /// Enumerate a directory via FileManager + a coordinated read. Unlike Dart's
  /// POSIX `Directory.list`, this works for File Provider folders (e.g. another
  /// app's shared storage like Infuse), which don't enumerate over raw readdir.
  ///
  /// Runs on a background queue: NSFileCoordinator on the main thread can
  /// deadlock against a File Provider extension that needs our runloop —
  /// the channel call then never returns and the library spins forever.
  private func listDirectory(_ path: String, result: @escaping FlutterResult) {
    let url = scopedURL(for: path) ?? URL(fileURLWithPath: path)
    DispatchQueue.global(qos: .userInitiated).async {
      let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
      var coordError: NSError?
      var listError: Error?
      var entries: [[String: Any]] = []
      NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { coordinatedURL in
        do {
          let contents = try FileManager.default.contentsOfDirectory(
            at: coordinatedURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
          )
          for entry in contents {
            let values = try? entry.resourceValues(forKeys: Set(keys))
            let modifiedMs = (values?.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000
            entries.append([
              "uri": entry.path,
              "name": entry.lastPathComponent,
              "isDir": values?.isDirectory ?? false,
              "length": values?.fileSize ?? 0,
              "lastModified": Int(modifiedMs),
            ])
          }
        } catch {
          listError = error
        }
      }
      DispatchQueue.main.async {
        if let error = coordError ?? (listError as NSError?) {
          result(
            FlutterError(
              code: "LIST_FAILED",
              message: error.localizedDescription,
              details: "\(error.domain)#\(error.code)"
            ))
          return
        }
        result(entries)
      }
    }
  }

  /// Make [path] openable by libmpv at playback time. Files picked from another
  /// app's File Provider (Infuse/Files/NAS) are denied unless (a) their scope is
  /// active and (b) they are materialized on disk. Re-derive the scoped URL from
  /// the retained root, start accessing it, and run a coordinated read to force
  /// materialization; for a plain local scoped file the coordinated read is a
  /// no-op. Returns the resolved path.
  ///
  /// A path not under any retained scope (e.g. Pleya's own download dir) is
  /// returned as-is — those need no scope.
  private func resolvePlaybackPath(_ path: String, result: @escaping FlutterResult) {
    guard let url = scopedURL(for: path) else {
      result(path)
      return
    }
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let accessing = url.startAccessingSecurityScopedResource()
      var coordError: NSError?
      NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { _ in }
      DispatchQueue.main.async {
        // Keep the per-file scope open for the playback session. ponytail:
        // bounded leak (one retained URL per distinct file played this session);
        // stopAccess on the root path balances the root, per-file scopes drop at
        // process exit. Add per-file stopAccess if this ever grows unbounded.
        if accessing { self?.retainAccess(url) }
        result(url.path)
      }
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
    // Background queue: bookmark resolution may talk to a File Provider
    // extension and must not block the main runloop (deadlock risk).
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let reply: (Any?) -> Void = { value in DispatchQueue.main.async { result(value) } }
      do {
        var isStale = false
        let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        let accessing = url.startAccessingSecurityScopedResource()
        DispatchQueue.main.async {
          guard let self = self else { return }
          if accessing {
            self.retainAccess(url)
          } else if self.accessedURLs[url.path] == nil {
            // No scope obtained and none open for this path: surface it instead
            // of silently returning a path every later read will be denied on.
            result(
              FlutterError(code: "SCOPE_DENIED", message: "startAccessingSecurityScopedResource failed", details: nil))
            return
          }
          var response: [String: Any] = ["path": url.path]
          if isStale,
            let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
          {
            response["bookmark"] = fresh.base64EncodedString()
          }
          result(response)
        }
      } catch {
        reply(FlutterError(code: "RESOLVE_FAILED", message: error.localizedDescription, details: nil))
      }
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
