import Flutter
import UIKit

/// Receives a video file another app hands to Pleya ("Open in…" in Files, the
/// share sheet, AirDrop) and passes its path to Dart, which plays it.
///
/// Paths wait in `pending` until Dart takes them: a file that launched the app
/// arrives with the scene connection, before the engine has a channel and long
/// before anything listens. That is why the state is static.
final class OpenFilePlugin: NSObject, FlutterPlugin {
  private static var channel: FlutterMethodChannel?
  private static var pending: [String] = []

  /// Files opened in place stay readable only while their security scope is
  /// open, so the URL is kept until Dart releases the file. One entry per
  /// distinct file.
  private static var scopedURLs: [String: URL] = [:]

  /// Paths the system copied into our Inbox. Only these are ever deleted on
  /// release: a file opened in place is the user's own, wherever it lies,
  /// also in a folder of theirs that happens to be called Inbox.
  private static var copies: Set<String> = []

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.pleya/open_file", binaryMessenger: registrar.messenger())
    self.channel = channel
    registrar.addMethodCallDelegate(OpenFilePlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "takePendingFiles":
      result(Self.pending)
      Self.pending = []
    case "releaseFiles":
      for path in call.arguments as? [String] ?? [] {
        Self.release(path)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Takes the file URLs out of [contexts] and returns the rest (sign-in
  /// callbacks and other links) for whoever handles those.
  static func receive(_ contexts: Set<UIOpenURLContext>) -> Set<UIOpenURLContext> {
    let files = contexts.filter { $0.url.isFileURL }
    // The system copied these into our Inbox. Earlier copies are ours to
    // remove, or every opened film stays on the device. Once per delivery:
    // per file, two films arriving together would remove each other.
    clearInbox(keeping: files.filter { !$0.options.openInPlace }.map { $0.url })
    for context in files {
      prepare(context.url, inPlace: context.options.openInPlace)
    }
    return contexts.subtracting(files)
  }

  private static func prepare(_ url: URL, inPlace: Bool) {
    // Off the main thread: a coordinated read can wait on a File Provider
    // extension (iCloud Drive, a NAS app) that needs our run loop.
    DispatchQueue.global(qos: .userInitiated).async {
      var accessing = false
      if inPlace {
        accessing = url.startAccessingSecurityScopedResource()
        // Forces a file that is still in the cloud onto disk, where libmpv
        // can open it by path.
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { _ in }
      }
      DispatchQueue.main.async {
        if accessing {
          if scopedURLs[url.path] == nil {
            scopedURLs[url.path] = url
          } else {
            url.stopAccessingSecurityScopedResource()
          }
        }
        if !inPlace { copies.insert(url.path) }
        pending.append(url.path)
        channel?.invokeMethod("onFilesAvailable", arguments: nil)
      }
    }
  }

  /// Lets go of the file at [path] once no player has it: closes the security
  /// scope of a file opened in place and removes the copy the system made in
  /// the Inbox, which nothing else would ever delete.
  private static func release(_ path: String) {
    // Delivered again in the meantime: that delivery still has to play.
    guard !pending.contains(path) else { return }
    scopedURLs.removeValue(forKey: path)?.stopAccessingSecurityScopedResource()
    guard copies.remove(path) != nil else { return }
    let url = URL(fileURLWithPath: path)
    if isOwnInbox(url.deletingLastPathComponent().resolvingSymlinksInPath()) {
      try? FileManager.default.removeItem(at: url)
    }
  }

  /// Whether [directory] is an Inbox inside the app's own container: nothing
  /// the user keeps elsewhere is ever removed.
  private static func isOwnInbox(_ directory: URL) -> Bool {
    // Symlinks resolved on both sides: the system hands out /private/var
    // paths where NSHomeDirectory answers /var.
    directory.lastPathComponent.hasSuffix("Inbox")
      && directory.path.hasPrefix(URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path + "/")
  }

  /// Removes what the Inbox of [copies] holds besides them.
  private static func clearInbox(keeping copies: [URL]) {
    guard let inbox = copies.first?.deletingLastPathComponent().resolvingSymlinksInPath(),
      isOwnInbox(inbox),
      let entries = try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)
    else { return }
    let keep = Set(copies.map { $0.lastPathComponent })
    for entry in entries where !keep.contains(entry.lastPathComponent) {
      try? FileManager.default.removeItem(at: entry)
    }
  }
}

/// The window scene of the app. Under the scene lifecycle an opened file comes
/// in here: as a connection option when it launches the app, through
/// `openURLContexts` while the app runs. Handled in the delegate itself, not
/// through Flutter's plugin forwarding: with multiple scenes enabled (the
/// external display) Flutter cannot promise a plugin the launch options.
class PleyaSceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    _ = OpenFilePlugin.receive(connectionOptions.urlContexts)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let others = OpenFilePlugin.receive(URLContexts)
    if !others.isEmpty {
      super.scene(scene, openURLContexts: others)
    }
  }
}
