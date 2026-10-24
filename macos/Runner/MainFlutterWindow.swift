import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()

    // Keep the window itself opaque so WindowServer does not have to blend the
    // whole video window with the desktop every frame. Flutter stays clear so
    // the native video layer behind it remains visible.
    self.isOpaque = true
    self.backgroundColor = NSColor.black
    flutterViewController.backgroundColor = NSColor.clear

    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Apply initial window configuration BEFORE frame restoration
    // This prevents the window from shrinking on launch
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)

    // Add forwarding toolbar for click-through in titlebar area
    let toolbar = ForwardingToolbar(flutterViewController: flutterViewController)
    self.toolbar = toolbar

    // Register MPV player plugin for video playback
    MpvPlayerPlugin.register(
      with: flutterViewController.registrar(forPlugin: "MpvPlayerPlugin"))

    // Register window utils plugin for dynamic titlebar/fullscreen control from Dart
    WindowUtilsPlugin.register(
      with: flutterViewController.registrar(forPlugin: "WindowUtilsPlugin"))

    // Security-scoped folder picker (local folder sources under the sandbox)
    SecureFolderPlugin.register(
      with: flutterViewController.registrar(forPlugin: "SecureFolderPlugin"))

    // Video files opened with Pleya from Finder
    OpenFilePlugin.register(
      with: flutterViewController.registrar(forPlugin: "OpenFilePlugin"))
    WindowUtilsPlugin.setWindow(self)
    WindowUtilsPlugin.installWindowDelegate()
    WindowUtilsPlugin.syncWindowChrome()

    // iCloud key-value settings sync
    ICloudKvsPlugin.register(
      with: flutterViewController.registrar(forPlugin: "ICloudKvsPlugin"))

    let registrar = flutterViewController.registrar(forPlugin: "LocalLibraryStorage")
    do {
      let channel = FlutterMethodChannel(name: "com.pleya/local_library", binaryMessenger: registrar.messenger)
      channel.setMethodCallHandler { call, result in
        guard call.method == "availableBytes" else { result(FlutterMethodNotImplemented); return }
        do {
          let values = try URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
          ])
          result(values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map { Int64($0) })
        } catch {
          result(FlutterError(code: "STORAGE_UNAVAILABLE", message: "Unable to read available storage", details: nil))
        }
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Enable window position/size persistence
    self.setFrameAutosaveName("nl.michelknoop.pleya.MainWindow")
    WindowUtilsPlugin.syncWindowChrome()

    super.awakeFromNib()
  }
}
