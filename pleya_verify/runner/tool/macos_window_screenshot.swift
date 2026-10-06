import AppKit
import Foundation
import ScreenCaptureKit

@available(macOS 14.0, *)
@main
struct WindowScreenshot {
  static func main() async {
    _ = NSApplication.shared
    guard CommandLine.arguments.count == 3,
          let pid = Int32(CommandLine.arguments[1])
    else {
      FileHandle.standardError.write(Data("usage: macos_window_screenshot <pid> <output.png>\n".utf8))
      exit(64)
    }

    do {
      let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
      guard let window = content.windows.first(where: {
        $0.owningApplication?.processID == pid && $0.frame.width > 1 && $0.frame.height > 1
      }) else {
        throw ScreenshotError.windowNotFound(pid)
      }

      let filter = SCContentFilter(desktopIndependentWindow: window)
      let configuration = SCStreamConfiguration()
      configuration.width = Int(window.frame.width * 2)
      configuration.height = Int(window.frame.height * 2)
      configuration.showsCursor = false
      configuration.captureResolution = .best

      let image = try await SCScreenshotManager.captureImage(
        contentFilter: filter,
        configuration: configuration
      )
      let bitmap = NSBitmapImageRep(cgImage: image)
      guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw ScreenshotError.encodingFailed
      }
      try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    } catch {
      FileHandle.standardError.write(Data("\(error)\n".utf8))
      exit(1)
    }
  }
}

enum ScreenshotError: Error, CustomStringConvertible {
  case windowNotFound(Int32)
  case encodingFailed

  var description: String {
    switch self {
    case .windowNotFound(let pid): "pid \(pid) owns no capturable window"
    case .encodingFailed: "could not encode captured window as PNG"
    }
  }
}
