import Foundation
import UIKit

#if canImport(FlutterMacOS)
  import FlutterMacOS
#else
  import Flutter
#endif

/// Native tvOS text entry: a `NativeTextEntryField` parked in the Flutter view
/// takes first responder, so the system keyboard — the platform's only
/// dictation surface — comes up directly. Live edits stream back to Dart via
/// `textChanged`; the final value returns from `edit`.
///
/// One session at a time (`BUSY` otherwise). Menu returns the current text with
/// `submitted=false`; committing on the keyboard returns it with
/// `submitted=true`. A surface that never becomes usable returns
/// `KEYBOARD_DEAD`/`KEYBOARD_UNAVAILABLE` so Dart can fall back for good.
final class NativeTextEntryPlugin: NSObject, FlutterPlugin {
  private static let channelName = "com.pleya/native_text_entry"

  private var channel: FlutterMethodChannel?
  private var entry: NativeTextEntryField?
  private var pendingResult: FlutterResult?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = NativeTextEntryPlugin()
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    NSLog("[NativeTextEntry] channel call %@", call.method)
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
    guard let host = Self.rootViewController()?.viewIfLoaded, host.window != nil else {
      result(FlutterError(code: "UNAVAILABLE", message: "No hosting view on screen", details: nil))
      return
    }

    let entry = NativeTextEntryField()
    Self.configure(entry.textField, from: args)
    entry.onTextChanged = { [weak self] text in
      self?.channel?.invokeMethod("textChanged", arguments: text)
    }
    entry.onDiagnostic = { [weak self] message in
      self?.channel?.invokeMethod("diagnostic", arguments: message)
    }
    entry.onFinished = { [weak self] text, submitted, failure in
      self?.finish(text: text, submitted: submitted, failure: failure)
    }

    self.entry = entry
    pendingResult = result

    NativeInputSession.begin { [weak entry] in entry?.cancel() }
    // Nothing is presented: the field goes straight into the Flutter view and
    // tvOS raises its own keyboard for it. See the note on NativeTextEntryField
    // for why a presented view controller had to go.
    entry.attach(to: host)
  }

  private func finish(text: String, submitted: Bool, failure: String?) {
    guard let result = pendingResult else { return }
    pendingResult = nil
    entry = nil

    // The field has already removed itself; handing the remote back is all
    // that is left, and it cannot fail.
    NativeInputSession.end()

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
