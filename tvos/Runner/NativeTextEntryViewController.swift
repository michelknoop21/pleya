import Foundation
import UIKit

/// Single source of truth for "a native UIKit surface owns the Siri Remote".
///
/// While a session is active `PleyaFlutterViewController` must not be first
/// responder and must not feed presses into the engine. `FlutterViewController`
/// converts every press to `flutter/keydata` and only falls through to the
/// responder chain once Dart reports the key *unhandled* — which never happens,
/// because Pleya's focus tree handles every arrow and select. That is why a
/// presented dialog used to be both unusable and undismissable: the presses
/// never reached it.
enum NativeInputSession {
  static let didChange = Notification.Name("PleyaNativeInputSessionDidChange")

  private(set) static var isActive = false

  /// Presses forwarded while a session was up. Feeds the dead-surface watchdog:
  /// input arriving with nothing on screen reacting is the failure itself.
  private(set) static var forwardedPressCount = 0

  /// Menu escape hatch. It lives here rather than on the presented controller
  /// because presses land on the Flutter controller — that is the only object
  /// guaranteed to be in the press path.
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

/// Text entry that hands the remote to UIKit and lets tvOS raise its own
/// keyboard.
///
/// A plain `UITextField` taking first responder is all the platform needs: the
/// system keyboard appears, and that keyboard is the *only* dictation surface
/// tvOS offers — the Siri Remote mic types into it with no API, entitlement or
/// Info.plist key on our side. An intermediate alert box would only add a step
/// the user has to navigate through first.
///
/// Dictation is disabled by the system for secure fields and for numeric
/// keyboard types; see `NativeTextEntryPlugin.configure`.
final class NativeTextEntryViewController: UIViewController, UITextFieldDelegate {
  /// `failure` is non-nil when the surface never became usable. Callers turn
  /// that into a permanent fallback rather than showing it again.
  var onFinished: ((_ text: String, _ submitted: Bool, _ failure: String?) -> Void)?
  var onTextChanged: ((String) -> Void)?

  let textField = UITextField()

  /// Long enough to cover the keyboard transition, short enough that a dead
  /// surface is gone before the user starts hunting for a way out.
  private static let watchdogTimeout: TimeInterval = 4

  static let deadFailure = "KEYBOARD_DEAD"
  static let unavailableFailure = "KEYBOARD_UNAVAILABLE"

  private var didBeginEditing = false
  private var committed = false
  private var finished = false
  private var watchdog: Timer?

  override var canBecomeFirstResponder: Bool { true }

  override var preferredFocusEnvironments: [UIFocusEnvironment] { [textField] }

  override func viewDidLoad() {
    super.viewDidLoad()
    // .overFullScreen keeps the Flutter view in the hierarchy behind us, so a
    // dim is all we need — and, crucially, no lifecycle events fire (see the
    // presentation style note in NativeTextEntryPlugin).
    view.backgroundColor = UIColor.black.withAlphaComponent(0.4)

    textField.delegate = self
    textField.font = .preferredFont(forTextStyle: .title2)
    textField.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(textField)
    NSLayoutConstraint.activate([
      textField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      textField.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      textField.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.6),
    ])

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(textDidChange(_:)),
      name: UITextField.textDidChangeNotification,
      object: textField)

    // Second net for Menu, independent of the responder chain.
    let menuTap = UITapGestureRecognizer(target: self, action: #selector(cancelFromMenu))
    menuTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
    view.addGestureRecognizer(menuTap)

    // Armed here rather than in viewDidAppear so a presentation that loads but
    // never finishes appearing still resolves instead of hanging forever.
    startWatchdog()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // Must be here, not in viewDidLoad: the field needs a window before tvOS
    // will raise the system keyboard for it.
    textField.becomeFirstResponder()
  }

  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if presses.contains(where: { $0.type == .menu }) {
      cancelFromMenu()
      return
    }
    super.pressesBegan(presses, with: event)
  }

  @objc func cancelFromMenu() {
    finish(submitted: false, failure: nil)
  }

  // MARK: - Watchdog

  private func startWatchdog() {
    watchdog?.invalidate()
    watchdog = Timer.scheduledTimer(withTimeInterval: Self.watchdogTimeout, repeats: false) { [weak self] _ in
      guard let self, !self.didBeginEditing else { return }
      // Either the keyboard never came up at all, or the user has been pressing
      // buttons with nothing responding. Bail out with a code the Dart side
      // latches on, so this can never turn into a trap again.
      let failure = NativeInputSession.forwardedPressCount > 0 ? Self.deadFailure : Self.unavailableFailure
      self.finish(submitted: false, failure: failure)
    }
  }

  // MARK: - UITextFieldDelegate

  func textFieldDidBeginEditing(_ textField: UITextField) {
    didBeginEditing = true
    watchdog?.invalidate()
    watchdog = nil
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    committed = true
    textField.resignFirstResponder()
    return true
  }

  func textFieldDidEndEditing(_ textField: UITextField, reason: UITextField.DidEndEditingReason) {
    // The system keyboard just closed. Nothing interactive is left on screen,
    // so the session ends here — otherwise the user is staring at an empty
    // overlay that needs dismissing a second time.
    finish(submitted: committed || reason == .committed, failure: nil)
  }

  @objc private func textDidChange(_ note: Notification) {
    onTextChanged?(textField.text ?? "")
  }

  private func finish(submitted: Bool, failure: String?) {
    // resignFirstResponder during teardown re-enters through the delegate.
    guard !finished else { return }
    finished = true
    watchdog?.invalidate()
    watchdog = nil
    onFinished?(textField.text ?? "", submitted, failure)
  }
}
