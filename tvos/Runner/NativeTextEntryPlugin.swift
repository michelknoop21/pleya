import Foundation
import UIKit

#if canImport(FlutterMacOS)
  import FlutterMacOS
#else
  import Flutter
#endif

/// Presents native tvOS text entry as a `UIAlertController` with a text field —
/// a proper modal that owns the tvOS focus engine, so the on-screen keyboard is
/// navigable with the remote (and still offers the "type with iPhone" Continuity
/// prompt). Live edits stream back to Dart via `textChanged`; the final value
/// returns from `edit`.
///
/// One session at a time (`BUSY` otherwise). Cancel/Menu returns the current
/// text with `submitted=false`; Done returns it with `submitted=true`.
final class NativeTextEntryPlugin: NSObject, FlutterPlugin, UITextFieldDelegate {
  private static let channelName = "com.pleya/native_text_entry"

  private var channel: FlutterMethodChannel?
  private var textField: UITextField?
  private var alert: UIAlertController?
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
    guard let presenter = Self.rootViewController() else {
      result(FlutterError(code: "UNAVAILABLE", message: "No root view controller", details: nil))
      return
    }

    // A UIAlertController with a text field is the idiomatic tvOS text entry: a
    // proper modal that captures the focus engine, so the on-screen keyboard is
    // actually navigable. The old zero-alpha first-responder trick left the
    // Flutter view competing for the remote, so the keyboard stayed dead.
    let alert = UIAlertController(title: args["hint"] as? String, message: nil, preferredStyle: .alert)
    alert.addTextField { [weak self] field in
      guard let self = self else { return }
      field.text = args["text"] as? String ?? ""
      field.delegate = self
      field.isSecureTextEntry = (args["obscure"] as? Bool) ?? false
      field.keyboardType = Self.keyboardType(args["keyboardType"] as? String)
      field.returnKeyType = Self.returnKeyType(args["action"] as? String)
      field.autocorrectionType = ((args["autocorrect"] as? Bool) ?? true) ? .yes : .no
      field.autocapitalizationType = Self.capitalization(args["capitalization"] as? String)
      if let hint = args["hint"] as? String {
        field.placeholder = hint
      }
      self.textField = field
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(self.textDidChange(_:)),
        name: UITextField.textDidChangeNotification,
        object: field)
    }
    let done = UIAlertAction(title: "Done", style: .default) { [weak self] _ in
      self?.finish(submitted: true)
    }
    let cancel = UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
      self?.finish(submitted: false)
    }
    alert.addAction(done)
    alert.addAction(cancel)
    alert.preferredAction = done

    self.alert = alert
    pendingResult = result
    presenter.present(alert, animated: true)
  }

  // MARK: - UITextFieldDelegate

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    finish(submitted: true)
    return true
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
    }
    textField = nil
    alert?.dismiss(animated: true)
    alert = nil
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
