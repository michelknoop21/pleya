import Foundation
import UIKit

#if canImport(FlutterMacOS)
  import FlutterMacOS
#else
  import Flutter
#endif

/// Presents native tvOS text entry by making a zero-alpha `UITextField` the
/// first responder — tvOS then shows its fullscreen system keyboard, which is
/// exactly what triggers the "type with iPhone" Continuity prompt. Live edits
/// stream back to Dart via `textChanged`; the final value returns from `edit`.
///
/// One session at a time (`BUSY` otherwise). Menu-dismiss returns the current
/// text with `submitted=false`; Done returns it with `submitted=true`.
final class NativeTextEntryPlugin: NSObject, FlutterPlugin, UITextFieldDelegate {
  private static let channelName = "com.pleya/native_text_entry"

  private var channel: FlutterMethodChannel?
  private var textField: UITextField?
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
      guard pendingResult == nil, textField == nil else {
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
    guard let view = Self.rootView() else {
      result(FlutterError(code: "UNAVAILABLE", message: "No root view controller", details: nil))
      return
    }

    let field = UITextField(frame: .zero)
    field.text = args["text"] as? String ?? ""
    field.delegate = self
    field.alpha = 0.0
    field.isSecureTextEntry = (args["obscure"] as? Bool) ?? false
    field.keyboardType = Self.keyboardType(args["keyboardType"] as? String)
    field.returnKeyType = Self.returnKeyType(args["action"] as? String)
    field.autocorrectionType = ((args["autocorrect"] as? Bool) ?? true) ? .yes : .no
    field.autocapitalizationType = Self.capitalization(args["capitalization"] as? String)
    if let hint = args["hint"] as? String {
      field.placeholder = hint
    }

    view.addSubview(field)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(textDidChange(_:)),
      name: UITextField.textDidChangeNotification,
      object: field)

    textField = field
    pendingResult = result

    if !field.becomeFirstResponder() {
      cleanup()
      pendingResult = nil
      result(
        FlutterError(code: "UNAVAILABLE", message: "Text field could not become first responder", details: nil))
    }
  }

  // MARK: - UITextFieldDelegate

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    finish(submitted: true)
    return true
  }

  func textFieldDidEndEditing(_ textField: UITextField) {
    // Menu-dismiss resigns the responder without a Done — keep the text, no submit.
    finish(submitted: false)
  }

  @objc private func textDidChange(_ note: Notification) {
    guard let field = textField, (note.object as? UITextField) === field else { return }
    channel?.invokeMethod("textChanged", arguments: field.text ?? "")
  }

  private func finish(submitted: Bool) {
    guard let result = pendingResult else { return }
    pendingResult = nil
    let text = textField?.text ?? ""
    cleanup()
    result(["text": text, "submitted": submitted])
  }

  private func cleanup() {
    if let field = textField {
      NotificationCenter.default.removeObserver(self, name: UITextField.textDidChangeNotification, object: field)
      field.resignFirstResponder()
      field.removeFromSuperview()
    }
    textField = nil
    // Restore the view controller's first-responder role so
    // PleyaFlutterViewController resumes intercepting play/pause. There is no
    // viewDidAppear cycle on this path, so we must do it explicitly.
    Self.rootViewController()?.becomeFirstResponder()
  }

  // MARK: - Lookups

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

  private static func rootView() -> UIView? {
    rootViewController()?.view
  }

  private static func keyboardType(_ value: String?) -> UIKeyboardType {
    switch value {
    case "url": return .URL
    case "email": return .emailAddress
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

// ponytail: if the zero-alpha field shows no keyboard on a real device (see
// verification step 2), swap begin() for a UIAlertController + addTextField —
// same Dart API, no channel changes.
