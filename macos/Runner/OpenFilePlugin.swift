import Cocoa
import FlutterMacOS

/// Receives a video file opened with Pleya from Finder ("Open with", a double
/// click, a drop on the Dock icon) and passes its path to Dart, which plays it.
///
/// Paths wait in `pending` until Dart takes them: a file that launched the app
/// arrives before anything listens. The sandbox lets the app read a file the
/// user opened this way for as long as it runs, so no bookmark is needed.
final class OpenFilePlugin: NSObject, FlutterPlugin, FlutterAppLifecycleDelegate {
  private var channel: FlutterMethodChannel?
  private var pending: [String] = []

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.pleya/open_file", binaryMessenger: registrar.messenger)
    let instance = OpenFilePlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "takePendingFiles":
      result(pending)
      pending = []
    case "releaseFiles":
      // Nothing to let go of: no Inbox copy, and the system grants access to
      // an opened file for as long as the app runs.
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Takes the file URLs. The answer is for the whole event and the first
  /// delegate that says yes keeps the rest from seeing it, so an event that
  /// also carries another URL (a sign-in callback) is answered no: the files
  /// are queued either way, and the other URLs reach whoever handles them.
  func handleOpen(_ urls: [URL]) -> Bool {
    let files = urls.filter { $0.isFileURL }
    guard !files.isEmpty else { return false }
    pending.append(contentsOf: files.map { $0.path })
    channel?.invokeMethod("onFilesAvailable", arguments: nil)
    return files.count == urls.count
  }
}
