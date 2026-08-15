import Foundation
import UIKit

/// Single source of truth for "a native UIKit surface owns the Siri Remote".
///
/// While a session is active `PleyaFlutterViewController` must not be first
/// responder and must not feed presses into the engine. `FlutterViewController`
/// converts every press to `flutter/keydata` and only falls through to the
/// responder chain once Dart reports the key *unhandled* — which never happens,
/// because Pleya's focus tree handles every arrow and select.
///
/// **Not the same thing as `NativeInputSession` in `lib/utils/`.** The Dart
/// class of that name is bookkeeping for Dart's own fail-safe gates. This enum
/// is the one the engine hook reads: `tvosHandlePress(fromUIEvent:)` has to
/// decide while `sendEvent:` is still on the stack, so asking Dart over a
/// channel is not an option. The two are kept in step, but this one never
/// follows the other.
///
/// The window is exact on both ends: ownership starts at a `becomeFirstResponder`
/// that actually took, and ends only once the field has released it and the
/// keyboard dismissal has finished. Starting earlier yields presses to a
/// keyboard that is not up yet; ending earlier hands the remote back to Flutter
/// while the user is still looking at one.
enum NativeInputSession {
  static let didChange = Notification.Name("PleyaNativeInputSessionDidChange")

  private(set) static var isActive = false

  /// Presses forwarded while a session was up. Feeds the dead-surface watchdog:
  /// input arriving with nothing on screen reacting is the failure itself.
  private(set) static var forwardedPressCount = 0

  /// Menu escape hatch, invoked from the controller that is in the press path.
  static var onMenuPress: (() -> Void)?

  // Info level, not debug: two lines per session is nothing, and without them
  // the whole ownership window is invisible in a device log, which is exactly
  // what has to be provable when the keyboard misbehaves again.
  static func begin(onMenuPress: @escaping () -> Void) {
    self.onMenuPress = onMenuPress
    forwardedPressCount = 0
    isActive = true
    NSLog("[NativeInputSession] begin: UIKit owns the remote")
    NotificationCenter.default.post(name: didChange, object: nil)
  }

  static func end() {
    guard isActive else { return }
    onMenuPress = nil
    isActive = false
    NSLog("[NativeInputSession] end: remote handed back to Flutter")
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
  /// Roughly two seconds of trying before we stop waiting for the keyboard.
  private static let maxDismissAttempts = 5
  /// Backstop for the result we hand Dart. It waits for the dismissal to
  /// finish, and a dismissal that never calls back would leave the `edit` call
  /// pending forever, which is a remote that does nothing at all on any screen.
  private static let finishReportTimeout: TimeInterval = 1

  private var didBeginEditing = false
  private var committed = false
  private var finished = false
  private var watchdog: Timer?
  private var responderPoll: Timer?
  private var dismissAttempts = 0
  private weak var host: UIView?
  /// What was already on screen when we attached, so teardown only ever closes
  /// the keyboard tvOS put up for *us*.
  private weak var presentedBeforeAttach: UIViewController?

  // MARK: - Lifecycle

  func attach(to host: UIView) {
    self.host = host
    // Whatever was already presented before we asked for the keyboard is not
    // ours to close. Anything that appears on top of this is.
    presentedBeforeAttach = Self.topPresented(from: host)

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
    if became {
      // Ownership flips here and not a moment sooner. It used to start in the
      // plugin, before `attach` ran, which left a window in which every press
      // was yielded to a keyboard that did not exist yet. A refusal leaves the
      // flag off entirely, so the existing flow stays intact and the watchdog
      // below turns the dead surface into a failure Dart can fall back on.
      //
      // This is not the single-session guard: that one lives in
      // `NativeTextEntryPlugin` (`pendingResult`/`entry`) and still spans the
      // whole call, so nothing can slip in while this attach is in flight.
      NativeInputSession.begin { [weak self] in self?.cancel() }
    }
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

  /// The safety net for a session that ends without tvOS calling a delegate
  /// method we handle.
  ///
  /// It used to read "field is no longer first responder" as "the keyboard is
  /// gone". That is inverted: on tvOS the keyboard is a presentation UIKit owns,
  /// and losing first responder is exactly the state in which the keyboard is
  /// *still up* and this field is the only thing that can take it down. Tearing
  /// down there removed the field and dropped the last strong reference, which
  /// is how users ended up watching the app navigate underneath a keyboard they
  /// could not close. Nothing presented is the signal; not first responder only
  /// tells us to go and close it.
  private func startResponderPoll() {
    responderPoll?.invalidate()
    responderPoll = Timer.scheduledTimer(withTimeInterval: Self.responderPollInterval, repeats: true) {
      [weak self] _ in
      guard let self else { return }
      guard !self.textField.isFirstResponder else { return }

      if Self.topPresented(from: self.host) !== self.presentedBeforeAttach {
        // Bounded: if the keyboard refuses to go after this long, finishing and
        // handing Dart a result beats spinning forever on a surface we cannot
        // move. `finish` makes one more dismissal attempt on the way out.
        self.dismissAttempts += 1
        guard self.dismissAttempts <= Self.maxDismissAttempts else {
          self.diag("keyboard still presented after \(Self.maxDismissAttempts) attempts — giving up")
          self.finish(submitted: self.committed, failure: nil)
          return
        }
        self.diag("responder lost while keyboard still presented — dismissing (\(self.dismissAttempts))")
        self.dismissSystemKeyboardIfPresented()
        return
      }

      self.diag("responder poll: keyboard gone")
      self.finish(submitted: self.committed, failure: nil)
    }
  }

  // MARK: - Dismissal

  /// The controller currently sitting on top of the app, or nil when nothing is
  /// presented. tvOS stacks its keyboard here; we never created it, so it is not
  /// reachable through any reference of ours.
  private static func topPresented(from view: UIView?) -> UIViewController? {
    guard var top = view?.window?.rootViewController?.presentedViewController else { return nil }
    while let next = top.presentedViewController { top = next }
    return top
  }

  /// Close the keyboard tvOS put up for us — and only that. Anything that was
  /// already presented when we attached belongs to someone else.
  ///
  /// `completion` runs once the presentation is really gone, and runs straight
  /// away when there was nothing of ours to dismiss.
  private func dismissSystemKeyboardIfPresented(completion: (() -> Void)? = nil) {
    guard let top = Self.topPresented(from: host), top !== presentedBeforeAttach,
      let presenter = top.presentingViewController
    else {
      completion?()
      return
    }
    diag("dismissing keyboard presentation \(type(of: top))")
    // Via the presenter, never the presented controller itself: `dismiss` routes
    // to the receiver's *presented* child, so calling it on the keyboard would
    // close whatever the keyboard is showing and leave the keyboard. DEC-011.
    presenter.dismiss(animated: false, completion: completion)
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
    let text = textField.text ?? ""
    // Length only, never the text. This line goes to the app log, and the
    // fields that use this surface include passwords and server URLs. It is
    // also the marker `scripts/tvos_sim.sh check-select` measures: proving a
    // press arrived is not the same as proving it entered a letter, and that
    // gap is what let the click-does-nothing bug through `check-keyboard`.
    diag("textChanged length=\(text.count)")
    onTextChanged?(text)
  }

  /// The one way out, for every exit there is: submit, cancel/Menu,
  /// `didEndEditing`, the watchdog, the responder poll giving up, and every
  /// failure branch. They all land here, `finished` makes it run once, and the
  /// session is ended from a single place inside it. One exit that skipped this
  /// would leave the remote yielded to a keyboard that is gone, which is a
  /// remote that does nothing on any screen.
  private func finish(submitted: Bool, failure: String?) {
    guard !finished else { return }
    finished = true
    watchdog?.invalidate()
    watchdog = nil
    responderPoll?.invalidate()
    responderPoll = nil
    NotificationCenter.default.removeObserver(self)

    let text = textField.text ?? ""
    textField.resignFirstResponder()
    // Resigning is *not* enough. tvOS raises its keyboard by presenting a
    // controller over the app, and once `textFieldDidEndEditing` has already
    // fired — which it does with reason `.cancelled` when the user backs out
    // with the remote — the field is no longer editing and the resign above is
    // a no-op. Removing the field then leaves that presentation on screen with
    // nothing owning it: letters select nothing, Menu falls through to Flutter,
    // and you watch the app navigate underneath a keyboard you cannot close.
    // Build 203 hit this and fixed it via `presentingViewController`; the
    // rewrite to a parked field (no presented VC of our own) dropped that
    // escape without replacing it. This is the replacement.
    //
    // Report only once that dismissal has finished. Reporting earlier ends the
    // Dart-side session, and so hands the remote back to Flutter, while the
    // presentation is still on screen: presses during the transition then drive
    // the UI behind a keyboard the user is still looking at. Strong `self` on
    // purpose, because the plugin holds this object until `onFinished` fires and
    // a weak capture that came back nil would leave the Dart call pending
    // forever. The timer is the backstop for a completion that never arrives.
    var reported = false
    let report = { [self] in
      guard !reported else { return }
      reported = true
      diag("finish submitted=\(submitted) failure=\(failure ?? "-")")
      // The single place ownership goes back to Flutter, and only once the
      // field has released first responder (above) and the dismissal has
      // really finished. Ending it when submit or cancel is merely *requested*
      // reopens the border case this fix exists for: the Search click starts
      // while UIKit owns the remote, and the tail of that same press would
      // then reach the engine and move focus in the UI behind the keyboard.
      NativeInputSession.end()
      onFinished?(text, submitted, failure)
    }
    dismissSystemKeyboardIfPresented(completion: report)
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.finishReportTimeout, execute: report)
    // Not in this runloop turn. Resigning starts an asynchronous dismissal, and
    // yanking the field out of the tree now, moments before the plugin drops the
    // last strong reference to us, destroys the object driving it. The closure
    // holds the field alive until the transition has had its turn.
    let field = textField
    DispatchQueue.main.async { field.removeFromSuperview() }
  }
}
