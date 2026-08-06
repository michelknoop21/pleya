import Foundation
import UIKit

/// Single source of truth for "a native UIKit surface owns the Siri Remote".
///
/// While a session is active `PleyaFlutterViewController` must not be first
/// responder and must not feed presses into the engine. `FlutterViewController`
/// converts every press to `flutter/keydata` and only falls through to the
/// responder chain once Dart reports the key *unhandled* — which never happens,
/// because Pleya's focus tree handles every arrow and select.
enum NativeInputSession {
  static let didChange = Notification.Name("PleyaNativeInputSessionDidChange")

  private(set) static var isActive = false

  /// Presses forwarded while a session was up. Feeds the dead-surface watchdog:
  /// input arriving with nothing on screen reacting is the failure itself.
  private(set) static var forwardedPressCount = 0

  /// Menu escape hatch, invoked from the controller that is in the press path.
  static var onMenuPress: (() -> Void)?

  static func begin(onMenuPress: @escaping () -> Void) {
    self.onMenuPress = onMenuPress
    forwardedPressCount = 0
    isActive = true
    NotificationCenter.default.post(name: didChange, object: nil)
  }

  static func end() {
    guard isActive else { return }
    onMenuPress = nil
    isActive = false
    NotificationCenter.default.post(name: didChange, object: nil)
  }

  static func noteForwardedPress() {
    forwardedPressCount += 1
  }
}

/// Native text entry: a `UITextField` parked in the Flutter view controller's
/// own view, made first responder so tvOS raises its system keyboard — the
/// platform's only dictation surface, since the Siri Remote mic is system
/// property and no app API exists.
///
/// **Deliberately not a presented view controller.** An earlier version
/// presented one, and every way out of it turned out to be conditional:
/// `dismiss` routes to the receiver's *presented* controller (so it closed the
/// system keyboard and left the overlay behind), `viewDidAppear` fires a second
/// time when that keyboard closes (reopening it), and `presentingViewController`
/// can be nil exactly when you need it. Users got trapped on a screen with no
/// way back. Nothing is presented here, so teardown is unconditional:
/// resign and remove.
///
/// Dictation is disabled by the system for secure fields and numeric keyboard
/// types; see `NativeTextEntryPlugin.configure`.
final class NativeTextEntryField: NSObject, UITextFieldDelegate {
  /// `failure` is non-nil when the surface never became usable. Callers turn
  /// that into a fallback rather than showing it again.
  var onFinished: ((_ text: String, _ submitted: Bool, _ failure: String?) -> Void)?
  var onTextChanged: ((String) -> Void)?
  /// Breadcrumbs for the app log — this path is hard to observe otherwise.
  var onDiagnostic: ((String) -> Void)?

  private func diag(_ message: String) {
    // NSLog as well as the Dart channel: os_log is readable from the simulator
    // without a debugger, which is how this path gets verified at all.
    NSLog("[NativeTextEntry] %@", message)
    onDiagnostic?(message)
  }

  let textField = UITextField()

  static let deadFailure = "KEYBOARD_DEAD"
  static let unavailableFailure = "KEYBOARD_UNAVAILABLE"

  /// Long enough to cover the keyboard transition, short enough that a dead
  /// surface is gone before the user starts hunting for a way out.
  private static let watchdogTimeout: TimeInterval = 4
  /// How often to check whether the system keyboard is still up.
  private static let responderPollInterval: TimeInterval = 0.4

  private var didBeginEditing = false
  private var committed = false
  private var finished = false
  private var watchdog: Timer?
  private var responderPoll: Timer?

  // MARK: - Lifecycle

  func attach(to host: UIView) {
    textField.delegate = self
    // Parked off-screen on purpose: tvOS draws its own full-screen keyboard, so
    // nothing of ours should be visible behind it. The field only has to be in
    // the window to be allowed first responder.
    textField.frame = CGRect(x: -2, y: -2, width: 1, height: 1)
    host.addSubview(textField)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(textDidChange(_:)),
      name: UITextField.textDidChangeNotification,
      object: textField)

    let became = textField.becomeFirstResponder()
    diag("attach becameFirstResponder=\(became)")
    startWatchdog()
  }

  /// Menu, from whichever responder actually saw the press.
  @objc func cancel() {
    diag("cancel (menu)")
    finish(submitted: false, failure: nil)
  }

  // MARK: - Watchdogs

  private func startWatchdog() {
    watchdog?.invalidate()
    watchdog = Timer.scheduledTimer(withTimeInterval: Self.watchdogTimeout, repeats: false) { [weak self] _ in
      guard let self, !self.didBeginEditing else { return }
      // Either the keyboard never came up, or presses arrived with nothing
      // responding. Bail out with a code Dart latches on.
      let failure = NativeInputSession.forwardedPressCount > 0 ? Self.deadFailure : Self.unavailableFailure
      self.diag("watchdog fired failure=\(failure) presses=\(NativeInputSession.forwardedPressCount)")
      self.finish(submitted: false, failure: failure)
    }
  }

  /// The only teardown trigger that does not depend on tvOS choosing a
  /// particular delegate callback: once the field stops being first responder,
  /// the system keyboard is gone and the session is over no matter how it was
  /// closed. Without this the session had no safety net at all after editing
  /// began — which is precisely when users got stuck.
  private func startResponderPoll() {
    responderPoll?.invalidate()
    responderPoll = Timer.scheduledTimer(withTimeInterval: Self.responderPollInterval, repeats: true) {
      [weak self] _ in
      guard let self else { return }
      guard !self.textField.isFirstResponder else { return }
      self.diag("responder poll: keyboard gone")
      self.finish(submitted: self.committed, failure: nil)
    }
  }

  // MARK: - UITextFieldDelegate

  func textFieldDidBeginEditing(_ textField: UITextField) {
    diag("didBeginEditing")
    didBeginEditing = true
    watchdog?.invalidate()
    watchdog = nil
    startResponderPoll()
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    diag("shouldReturn")
    committed = true
    textField.resignFirstResponder()
    return true
  }

  func textFieldDidEndEditing(_ textField: UITextField, reason: UITextField.DidEndEditingReason) {
    diag("didEndEditing reason=\(reason.rawValue)")
    finish(submitted: committed || reason == .committed, failure: nil)
  }

  @objc private func textDidChange(_ note: Notification) {
    onTextChanged?(textField.text ?? "")
  }

  private func finish(submitted: Bool, failure: String?) {
    guard !finished else { return }
    finished = true
    watchdog?.invalidate()
    watchdog = nil
    responderPoll?.invalidate()
    responderPoll = nil
    NotificationCenter.default.removeObserver(self)

    let text = textField.text ?? ""
    // Unconditional: no presentation to unwind, nothing that can refuse.
    textField.resignFirstResponder()
    textField.removeFromSuperview()
    diag("finish submitted=\(submitted) failure=\(failure ?? "-")")
    onFinished?(text, submitted, failure)
  }
}
