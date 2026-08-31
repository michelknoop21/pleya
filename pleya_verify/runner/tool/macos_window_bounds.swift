// Prints "windowId,x,y,width,height" for the first on-screen window owned
// by a pid.
//
// Why this exists rather than an AppleScript one-liner: `System Events`
// reaches windows through the Accessibility API, which needs the calling
// process to hold Accessibility permission. Without it the process is still
// found but `window 1` comes back as an invalid index — indistinguishable
// from "the app has no window", and that ambiguity is a bad thing to build
// evidence on. `CGWindowListCopyWindowInfo` reports geometry for on-screen
// windows without that permission, so this asks the window server directly.
//
// Used by `MacosDriver.screenshot()` to scope the [C5] capture to the app's
// own window instead of grabbing the whole display — see the long comment
// there for what a full-screen grab put in an evidence bundle. The window id
// is what the capture actually uses: `screencapture -l<id>` grabs that one
// window's content regardless of which display it sits on and of what
// overlaps it, while `-R<rect>` has to reason about a coordinate space
// spanning every attached display and fails outright ("could not create
// image from rect") when the window is not on the main one. The rect is
// printed alongside it for the driver log.
//
// Compiled on demand and cached in `.build/pleya-verify/bin/`.
//
// Exit codes: 0 with the rect on stdout, 1 when the pid owns no usable
// window, 2 when the window list itself is unavailable.

import CoreGraphics
import Foundation

let pid = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 0 : 0

guard
  let list = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
  ) as? [[String: Any]]
else {
  FileHandle.standardError.write(Data("could not read the window list\n".utf8))
  exit(2)
}

for window in list {
  guard
    let owner = window[kCGWindowOwnerPID as String] as? Int, owner == pid,
    let windowId = window[kCGWindowNumber as String] as? Int,
    let bounds = window[kCGWindowBounds as String] as? [String: Any],
    let x = bounds["X"] as? Double,
    let y = bounds["Y"] as? Double,
    let width = bounds["Width"] as? Double,
    let height = bounds["Height"] as? Double,
    // Skip the 1x1 helper windows a GUI app keeps around; only a real,
    // drawable window can be evidence of anything.
    width > 1, height > 1
  else { continue }

  print("\(windowId),\(Int(x)),\(Int(y)),\(Int(width)),\(Int(height))")
  exit(0)
}

FileHandle.standardError.write(Data("pid \(pid) owns no on-screen window\n".utf8))
exit(1)
