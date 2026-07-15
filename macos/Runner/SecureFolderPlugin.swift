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
    case "listDirectory":
      guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "path required", details: nil))
        return
      }
      listDirectory(path, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Resolve [path] against a retained scoped URL — the sandbox extension is
  /// bound to the bookmark's URL object, not to the path string. Subpaths are
  /// derived from the scoped root per segment.
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

  /// Enumerate a directory via FileManager + a coordinated read, which (unlike
  /// Dart's POSIX `Directory.list`) works for File Provider folders.
  private func listDirectory(_ path: String, result: @escaping FlutterResult) {
    let url = scopedURL(for: path) ?? URL(fileURLWithPath: path)
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
      if url.startAccessingSecurityScopedResource() {
        retainAccess(url)
      } else if accessedURLs[url.path] == nil {
        result(FlutterError(code: "SCOPE_DENIED", message: "startAccessingSecurityScopedResource failed", details: nil))
        return
      }
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
