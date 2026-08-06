import Foundation
import UIKit

#if canImport(FlutterMacOS)
  import FlutterMacOS
#else
  import Flutter
#endif

/// Presents native tvOS text entry: a `NativeTextEntryViewController` whose
/// text field takes first responder, so the system keyboard — the platform's
/// only dictation surface — comes up directly. Live edits stream back to Dart
/// via `textChanged`; the final value returns from `edit`.
///
/// One session at a time (`BUSY` otherwise). Menu returns the current text with
/// `submitted=false`; committing on the keyboard returns it with
/// `submitted=true`. A surface that never becomes usable returns
/// `KEYBOARD_DEAD`/`KEYBOARD_UNAVAILABLE` so Dart can fall back for good.
final class NativeTextEntryPlugin: NSObject, FlutterPlugin {
  private static let channelName = "com.pleya/native_text_entry"

  private var channel: FlutterMethodChannel?
  private var entry: NativeTextEntryViewController?
  private var pendingResult: FlutterResult?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = NativeTextEntryPlugin()
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "edit":
      guard pendingResult == nil, entry == nil else {
        result(FlutterError(code: "BUSY", message: "A text entry session is already active", details: nil))
        return
      }
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
        return
      }
      begin(args: args, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func begin(args: [String: Any], result: @escaping FlutterResult) {
    guard let presenter = Self.rootViewController() else {
      result(FlutterError(code: "UNAVAILABLE", message: "No root view controller", details: nil))
      return
    }
    // Presenting onto a controller that is already presenting is a silent
    // no-op in UIKit: the view would never load, so the watchdog below would
    // never arm and this call's future would never complete — leaving the
    // input gate closed app-wide until relaunch. Refuse up front instead.
    guard presenter.presentedViewController == nil else {
      result(FlutterError(code: "BUSY", message: "Another controller is already presented", details: nil))
      return
    }

    let entry = NativeTextEntryViewController()
    // .overFullScreen, never .fullScreen: the latter removes the Flutter view
    // from the hierarchy, which tears down the render surface and sends
    // AppLifecycleState.paused to Dart — media controls, wakelock and server
    // health checks all react to that. Opening a keyboard must not.
    entry.modalPresentationStyle = .overFullScreen
    Self.configure(entry.textField, from: args)
    entry.onTextChanged = { [weak self] text in
      self?.channel?.invokeMethod("textChanged", arguments: text)
    }
    entry.onFinished = { [weak self] text, submitted, failure in
      self?.finish(text: text, submitted: submitted, failure: failure)
    }

    self.entry = entry
    pendingResult = result

    NativeInputSession.begin { [weak entry] in entry?.cancelFromMenu() }
    presenter.present(entry, animated: true)
  }

  private func finish(text: String, submitted: Bool, failure: String?) {
    guard let result = pendingResult else { return }
    pendingResult = nil

    let entry = self.entry
    self.entry = nil

    // Dismiss through the *presenting* controller, never `entry.dismiss()`.
    // While the system keyboard is up it is a presentation of `entry`, and
    // UIKit routes `dismiss` to the receiver's presented controller — so
    // `entry.dismiss()` closed the keyboard and left this overlay on screen
    // for good, with the remote already handed back to Flutter underneath it.
    //
    // Hand that remote back only once the dismissal has completed: ending the
    // session restores first responder, and doing that while the keyboard
    // window is still tearing down loses the next press.
    if let presenter = entry?.presentingViewController {
      presenter.dismiss(animated: true) { NativeInputSession.end() }
    } else {
      NativeInputSession.end()
    }

    if let failure {
      result(FlutterError(code: failure, message: "Native text entry never became usable", details: nil))
    } else {
      result(["text": text, "submitted": submitted])
    }
  }

  // MARK: - Lookups

  private static func configure(_ field: UITextField, from args: [String: Any]) {
    field.text = args["text"] as? String ?? ""
    field.isSecureTextEntry = (args["obscure"] as? Bool) ?? false
    field.keyboardType = keyboardType(args["keyboardType"] as? String)
    field.returnKeyType = returnKeyType(args["action"] as? String)
    field.autocorrectionType = ((args["autocorrect"] as? Bool) ?? true) ? .yes : .no
    field.autocapitalizationType = capitalization(args["capitalization"] as? String)
    if let hint = args["hint"] as? String {
      field.placeholder = hint
    }
  }

  private static func rootViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes
    for scene in scenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows where window.isKeyWindow {
        if let root = window.rootViewController { return root }
      }
    }
    for scene in scenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      if let root = windowScene.windows.first?.rootViewController { return root }
    }
    return nil
  }

  private static func keyboardType(_ value: String?) -> UIKeyboardType {
    switch value {
    case "url": return .URL
    case "email": return .emailAddress
    // .numberPad/.phonePad disable system dictation, but a numeric field has
    // nothing to dictate into anyway.
    case "number": return .numberPad
    case "phone": return .phonePad
    default: return .default
    }
  }

  private static func returnKeyType(_ value: String?) -> UIReturnKeyType {
    switch value {
    case "go": return .go
    case "search": return .search
    case "send": return .send
    case "next": return .next
    default: return .done
    }
  }

  private static func capitalization(_ value: String?) -> UITextAutocapitalizationType {
    switch value {
    case "words": return .words
    case "sentences": return .sentences
    case "characters": return .allCharacters
    case "none": return .none
    default: return .sentences
    }
  }
}
