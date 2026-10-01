import Flutter
import UIKit
import AVFoundation
import GameController
import os
import universal_gamepad
import os_media_controls
import wakelock_plus

@objc class PleyaFlutterViewController: FlutterViewController {
  private lazy var tvRemoteChannel = FlutterBasicMessageChannel(
    name: "flutter/gamepadtouchevent",
    binaryMessenger: binaryMessenger,
    codec: FlutterJSONMessageCodec.sharedInstance()
  )

  // NAV2 (docs/tvos-fysieke-correctieronde.md): station 3 of the pipeline
  // (docs/tvos-remote-press-pipeline.md) as an app-log line instead of only
  // NSLog, because `[PleyaTvosPress]` never reaches a relay log. Read-only:
  // this channel carries no reply and changes no behaviour, it only lets
  // `AppleTvRemoteTouchService` log what this hook already computes.
  private lazy var tvosPressDiagChannel = FlutterBasicMessageChannel(
    name: "nl.michelknoop.pleya/tvos_press_diag",
    binaryMessenger: binaryMessenger,
    codec: FlutterJSONMessageCodec.sharedInstance()
  )

  /// Debug level on purpose. This fires for every press of every session and
  /// twice per press (see below), so at default level it would push everything
  /// else out of the log buffer during normal remote use. Read it with
  /// `log stream --level debug --predicate 'processImagePath CONTAINS "Runner"'`.
  private static let pressLog = Logger(subsystem: "nl.michelknoop.pleya", category: "PleyaTvosPress")

  // RAIL2 (zijdeur 4): per press type, the last delivery answered here and
  // what it was answered with. Both swizzle hops of one `sendEvent:` carry the
  // same `UIPress` in the same phase with the same `timestamp`; any new
  // delivery has a new timestamp. So type + phase + timestamp pins one
  // delivery exactly. Not the object: UIKit reuses one `UIPress` per type (§4a
  // of docs/tvos-remote-input-authority.md), so an object-keyed slot could
  // mistake the next real press for a repeat. One entry per type, so a second
  // press in the same event cannot evict it.
  private struct Delivery {
    let phase: UIPress.Phase
    let timestamp: TimeInterval
    let result: Bool
    let dropped: Bool
  }
  private var lastDelivery: [Int: Delivery] = [:]

  // DBL1 press filter, see `pressFilterDrop`. Keyed by `press.type.rawValue`,
  // not by the press object: UIKit reuses one `UIPress` per type (§4a of
  // docs/tvos-remote-input-authority.md).
  /// UIKit time (`UIPress.timestamp`, ms) of the last `.ended`/`.cancelled` per arrow type.
  private var lastArrowEndedMs: [Int: Double] = [:]
  /// Arrow types whose current lifecycle was dropped at `.began`, with that
  /// began's UIKit time. Every later phase of the lifecycle is dropped too, so
  /// the engine never sees half a pair.
  private var droppedArrowLifecycles: [Int: Double] = [:]

  // Stepping aside for a native session is the whole fix: while one is up this
  // controller must not hold first responder, or every press is delivered here
  // and swallowed by the engine before the presented controller sees it.
  override var canBecomeFirstResponder: Bool {
    !NativeInputSession.isActive
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(nativeInputSessionChanged),
      name: NativeInputSession.didChange,
      object: nil)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if !NativeInputSession.isActive {
      becomeFirstResponder()
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    resignFirstResponder()
    super.viewWillDisappear(animated)
  }

  @objc private func nativeInputSessionChanged() {
    if NativeInputSession.isActive {
      resignFirstResponder()
    } else if isViewLoaded, view.window != nil {
      becomeFirstResponder()
    }
  }

  /// The one place the engine asks whether it may claim a press.
  ///
  /// Answering `false` is what gives the tvOS system keyboard its clicks back.
  /// The engine's own implementation returns YES for everything, and the
  /// swizzled `sendEvent:` then skips the original implementation, so UIKit
  /// never begins its responder chain and the keyboard never learns that a
  /// letter was selected. Swipes were unaffected because those are
  /// `UIEventTypeTouches`, which the swizzle ignores. The split between what
  /// worked and what did not was exactly the split between UITouch and UIPress.
  ///
  /// `super` is deliberately *not* called on the session branch. Super is what
  /// synthesizes the press and posts `flutter/keydata`, so calling it would put
  /// the press into Flutter's focus tree as well and the UI behind the keyboard
  /// would start moving again. There is nothing to hand over to: while a
  /// session is up, UIKit owns the remote outright.
  ///
  /// Both swizzled hops (`UIApplication` and `UIWindow`) land here, so this runs
  /// twice per press, and until RAIL2 that second call could double something
  /// after all: forwarding it to `super` both times let the same `.ended`
  /// phase reach the engine's `tapIfMissingKeyDown:YES` path twice, and the
  /// second call finds the key `super` already removed, mistakes that for a
  /// missed `.began`, and synthesizes a phantom Down/Up pair (build 281, log
  /// `8x94u`, 15 sep 2026; `docs/tvos-remote-input-authority.md` §3). See
  /// `lastDelivery` below.
  ///
  /// Menu needs no exception. The engine's `shouldPassMenuPressToSystem:` sits
  /// ahead of this point, and with the session branch returning `false` Menu
  /// reaches UIKit along with everything else.
  override func tvosHandlePress(fromUIEvent press: UIPress) -> Bool {
    // Station 3 of docs/tvos-remote-press-pipeline.md: one line per hop, with
    // the raw type, the phase and the press identity, so a log can tell a
    // `.began`/`.ended` pair of one press from two presses. NSLog, like the
    // hook-availability line below: `Logger` info lines never reached
    // `log show` on the simulator, NSLog does (`scripts/tvos_sim.sh logs`).
    NSLog(
      "[PleyaTvosPress] press=%@ phase=%ld uipress=%lx", Self.pressName(press), press.phase.rawValue,
      ObjectIdentifier(press).hashValue & 0xffff)
    let previous = lastDelivery[press.type.rawValue]
    let isRepeatDelivery = previous?.phase == press.phase && previous?.timestamp == press.timestamp
    // The second swizzle hop of a dropped phase is dropped too, session or not.
    if isRepeatDelivery, previous?.dropped == true {
      return true
    }
    let filter = isRepeatDelivery ? nil : filterArrowPress(press)
    var diag: [String: Any] = [
      "press": Self.pressName(press),
      "phase": press.phase.rawValue,
      "uipress": ObjectIdentifier(press).hashValue & 0xffff,
      "systemUptimeMs": Int(ProcessInfo.processInfo.systemUptime * 1000),
      // DBL1: UIKit's own time for this phase (HID origin, same clock as
      // systemUptime). `systemUptimeMs` is when this hook ran; this is when the
      // press happened. A re-dispatch of one phase repeats it, a new delivery
      // does not. `uipress` cannot tell those apart: UIKit reuses one UIPress
      // object per press type (log oc8pw, build 303).
      "uikitMs": Int(press.timestamp * 1000),
      "hw": Self.pressHardwareSnapshot(press),
    ]
    if let filter {
      diag["filter"] = filter
    }
    tvosPressDiagChannel.sendMessage(diag)
    if let filter {
      // Claimed without `super`, for every phase of the lifecycle: the swizzle
      // then skips UIKit's own `sendEvent:` just as it does for any arrow the
      // engine claims, so UIKit sees neither half (no build 256), and the
      // engine sees neither half, so no key enters its pressed set and no
      // repeat timer starts (no build 257).
      Self.pressLog.debug("\(Self.pressName(press), privacy: .public) \(filter, privacy: .public)")
      return rememberDelivery(press, result: true, dropped: true)
    }
    guard NativeInputSession.isActive else {
      if isRepeatDelivery, let previous {
        return previous.result
      }
      return rememberDelivery(press, result: super.tvosHandlePress(fromUIEvent: press), dropped: false)
    }
    Self.pressLog.debug("\(Self.pressName(press), privacy: .public) -> yield to UIKit")
    return false
  }

  private func rememberDelivery(_ press: UIPress, result: Bool, dropped: Bool) -> Bool {
    lastDelivery[press.type.rawValue] = Delivery(
      phase: press.phase, timestamp: press.timestamp, result: result, dropped: dropped)
    return result
  }

  /// A dropped `.began` that still reaches the responder chain came in an
  /// event with a second, unclaimed press (Menu under passthrough, say): the
  /// swizzle then runs UIKit's own `sendEvent:`, UIKit tracks the press, and
  /// the engine's `pressesBegan:` would synthesize its Down. Such a press is
  /// not filtered: the drop is undone here, before `super`, so the Down goes
  /// out and the `.ended` later reaches the engine as usual. Without this the
  /// engine would hold a Down whose `.ended` the filter swallows (build 257).
  private func undoDropsReachingResponderChain(_ presses: Set<UIPress>) {
    for press in presses where press.phase == .began {
      let type = press.type.rawValue
      guard droppedArrowLifecycles[type] == press.timestamp * 1000 else { continue }
      droppedArrowLifecycles[type] = nil
      lastDelivery[type] = nil
      tvosPressDiagChannel.sendMessage([
        "press": Self.pressName(press), "phase": press.phase.rawValue,
        "uipress": ObjectIdentifier(press).hashValue & 0xffff,
        "systemUptimeMs": Int(ProcessInfo.processInfo.systemUptime * 1000),
        "uikitMs": Int(press.timestamp * 1000),
        "filter": "undo mixed-event type=\(Self.arrowName(press) ?? "?")",
      ])
    }
  }

  // DBL1: tvOS hands Pleya extra arrow lifecycles that its own home screen
  // filters out. In log 76ott (build 307, AppleTV14,1) the clickpad switch
  // clicked again 15, 15, 15 and 28 ms (UIKit time) after the release; the
  // fastest real re-press there starts 46 ms after the release. This is the
  // one sanctioned exception to "no timing at station 3": it reads UIKit's own
  // HID timestamps, never the clock of this hook. A bounce that slips through
  // costs one extra step; a real press eaten is worse (build 254), so the
  // threshold sits just above the slowest bounce measured. Mirrored 1:1 in
  // test/services/tvos_press_filter_replay_test.dart; change both together.

  /// Calibration: a same-direction re-press whose `.began` comes sooner than
  /// this after the previous `.ended` (UIKit time) is a bounce. 76ott: 2 ms
  /// above the slowest bounce (28), 16 ms below the fastest real press (46).
  static let bounceGapMs = 30.0

  /// The decision for an arrow `.began`: a drop reason, or nil to keep it.
  static func pressFilterDrop(beganMs: Double, previousEndedMs: Double?) -> String? {
    guard let previousEndedMs else { return nil }
    let gap = beganMs - previousEndedMs
    guard gap >= 0, gap < bounceGapMs else { return nil }
    return String(format: "bounce gapMs=%.0f", gap)
  }

  /// Applies `pressFilterDrop` to a live press and keeps the whole lifecycle
  /// together: a dropped `.began` drops its `.changed`/`.ended`/`.cancelled`,
  /// and every `.began` starts a fresh lifecycle. Select, Menu and Play/Pause
  /// are never filtered. During a native session no new lifecycle is dropped
  /// (UIKit owns the remote and filters for itself).
  private func filterArrowPress(_ press: UIPress) -> String? {
    guard let arrow = Self.arrowName(press) else { return nil }
    let type = press.type.rawValue
    let atMs = press.timestamp * 1000
    switch press.phase {
    case .began:
      droppedArrowLifecycles[type] = nil
      guard !NativeInputSession.isActive,
        let reason = Self.pressFilterDrop(beganMs: atMs, previousEndedMs: lastArrowEndedMs[type])
      else { return nil }
      droppedArrowLifecycles[type] = atMs
      return "drop \(reason) type=\(arrow)"
    case .ended, .cancelled:
      lastArrowEndedMs[type] = atMs
      guard let beganMs = droppedArrowLifecycles.removeValue(forKey: type) else { return nil }
      return String(format: "drop lifecycle type=%@ holdMs=%.0f", arrow, atMs - beganMs)
    default:
      return droppedArrowLifecycles[type] == nil ? nil : "drop lifecycle type=\(arrow)"
    }
  }

  private static func arrowName(_ press: UIPress) -> String? {
    switch press.type {
    case .upArrow: return "up"
    case .downArrow: return "down"
    case .leftArrow: return "left"
    case .rightArrow: return "right"
    default: return nil
    }
  }

  // NAV1, the second half: one arrow press that moved the focus twice.
  //
  // No single *phase* is filtered here on purpose (RAIL2 above dedupes a
  // *duplicate delivery* of the same phase, and DBL1 drops a *whole lifecycle*,
  // began through ended; both are different things). The double step
  // was never a phase problem: `super` posts one keydown on `.began` and one
  // keyup on `.ended`, exactly as it should. What doubled it was the Menu
  // passthrough. The
  // engine answers an *enable* on `flutter/tvos_system_navigation` with
  // `releaseAllSynthesizedPresses` (a synthetic keyup for every remote key it
  // still holds), and `.ended` then re-taps the released arrow as a fresh
  // down/up pair (`tapIfMissingKeyDown:YES`). The press that lands on the
  // Home tab raises the passthrough, so that press stepped twice (log
  // `wa6v9`, build 255). `TvosSystemNavigationService` now parks the enable
  // until every key is up.
  //
  // Both answers that were tried here for `.ended` are worse: yielding it to
  // UIKit (`false`, build 256) trips `_verifyTrackingPresses:` because the
  // engine claimed the matching `.began`; swallowing it (`true` without
  // `super`, build 257) leaves the key in the engine's pressed set, and its
  // 0.4 s / 80 ms repeat timer then steps in that direction forever. The
  // engine file is reconstructed by `scripts/tvos_engine_source.sh`; the
  // contract is in `docs/tvos-remote-press-pipeline.md`.

  /// DBL1: what the remote itself reports at the moment UIKit hands over a
  /// phase, read-only, so one hardware log can tell where a burst of extra
  /// arrow lifecycles comes from. `gcA` is the clickpad click
  /// (`GCMicroGamepad.buttonA`); still 1 on every `.ended` of a burst means one
  /// held click became several presses. `gcX`/`gcY` is the thumb position
  /// relative to the pad centre (the engine sets `reportsAbsoluteDpadValues`),
  /// so a value near 1 is the ring edge. `gcD=1` marks an analog clickpad
  /// (`GCDirectionalGamepad`, Siri Remote 2nd generation on); with `gcA` it is
  /// what a future log needs before a click-less rule could be justified
  /// (DBL1 dropped that rule for lack of evidence). `gcN` counts connected controllers
  /// (the iPhone Remote app is a second one under
  /// `GCSupportsMultipleMicroGamepads`). `resp` and `gr` are the responder
  /// UIKit targeted and how many gesture recognizers track the press. Only
  /// properties are read: no handler is set, so the engine's own
  /// `dpad.valueChangedHandler` stays the only one.
  private static func pressHardwareSnapshot(_ press: UIPress) -> String {
    let pads = GCController.controllers().compactMap(\.microGamepad)
    var fields = ["gcN=\(pads.count)"]
    if let pad = pads.first {
      fields.append("gcA=\(pad.buttonA.isPressed ? 1 : 0)")
      fields.append(String(format: "gcX=%.2f gcY=%.2f", pad.dpad.xAxis.value, pad.dpad.yAxis.value))
      fields.append("gcD=\(pad is GCDirectionalGamepad && pad.dpad.isAnalog ? 1 : 0)")
    }
    fields.append("resp=\(press.responder.map { String(describing: type(of: $0)) } ?? "nil")")
    fields.append("gr=\(press.gestureRecognizers?.count ?? 0)")
    return fields.joined(separator: " ")
  }

  /// For the log line only. The symbolic cases are not reliable on tvOS 26 (the
  /// runtime delivers 2040 for select and 2041 for menu where the SDK compiles
  /// 4 and 5), so the raw value is printed alongside rather than trusted.
  private static func pressName(_ press: UIPress) -> String {
    let name: String
    switch press.type {
    case .upArrow: name = "up"
    case .downArrow: name = "down"
    case .leftArrow: name = "left"
    case .rightArrow: name = "right"
    case .select: name = "select"
    case .menu: name = "menu"
    case .playPause: name = "playPause"
    default: name = "press"
    }
    return "\(name)(\(press.type.rawValue))"
  }

  /// Whether this press is the Menu/Back button.
  ///
  /// `press.type == .menu` is *not* enough. On tvOS 26 the delivered raw value
  /// is 2041 while `UIPress.PressType.menu.rawValue` compiles to 5, so the
  /// obvious comparison silently never matches — which is exactly why the
  /// system keyboard could not be dismissed: the press was forwarded past the
  /// escape hatch instead of triggering it. Measured on tvOS 26.2 (simulator):
  /// select = 2040, menu = 2041. The symbolic case is kept first so this keeps
  /// working if the runtime ever agrees with the SDK again, and the escape
  /// keyCode covers a hardware keyboard (and the simulator's Escape).
  private static let menuPressRawValue = 2041

  private static func containsMenuPress(_ presses: Set<UIPress>) -> Bool {
    presses.contains { press in
      press.type == .menu
        || press.type.rawValue == menuPressRawValue
        || press.key?.keyCode == .keyboardEscape
    }
  }

  /// Keeps presses out of the engine while a native surface owns the remote.
  ///
  /// `super` is `FlutterViewController`, which routes into the keyboard manager
  /// and only reaches the responder chain after an async Dart round-trip that
  /// reports "unhandled" — which never happens, because Pleya's focus tree
  /// handles every arrow and select. Swallowing outright would be just as bad:
  /// the focus engine would never see the press either. So forward to `next`.
  private func yieldPressToNativeSession(
    _ presses: Set<UIPress>,
    with event: UIPressesEvent?,
    handlingMenu: Bool,
    forward: (Set<UIPress>, UIPressesEvent?) -> Void
  ) -> Bool {
    guard NativeInputSession.isActive else { return false }

    if Self.containsMenuPress(presses) {
      if handlingMenu {
        NativeInputSession.onMenuPress?()
      }
      return true
    }

    NativeInputSession.noteForwardedPress()
    forward(presses, event)
    return true
  }

  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    undoDropsReachingResponderChain(presses)
    if handlePlayPausePress(presses) {
      return
    }
    if yieldPressToNativeSession(
      presses, with: event, handlingMenu: true,
      forward: { presses, event in
        next?.pressesBegan(presses, with: event)
      })
    {
      return
    }

    super.pressesBegan(presses, with: event)
  }

  // The engine overrides pressesChanged too; without this, a held direction
  // leaks into Flutter mid-session.
  override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if containsPlayPausePress(presses) {
      return
    }
    if yieldPressToNativeSession(
      presses, with: event, handlingMenu: false,
      forward: { presses, event in
        next?.pressesChanged(presses, with: event)
      })
    {
      return
    }

    super.pressesChanged(presses, with: event)
  }

  override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if containsPlayPausePress(presses) {
      return
    }
    if yieldPressToNativeSession(
      presses, with: event, handlingMenu: false,
      forward: { presses, event in
        next?.pressesEnded(presses, with: event)
      })
    {
      return
    }

    super.pressesEnded(presses, with: event)
  }

  override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if containsPlayPausePress(presses) {
      return
    }
    if yieldPressToNativeSession(
      presses, with: event, handlingMenu: false,
      forward: { presses, event in
        next?.pressesCancelled(presses, with: event)
      })
    {
      return
    }

    super.pressesCancelled(presses, with: event)
  }

  override func remoteControlReceived(with event: UIEvent?) {
    guard let event = event else {
      super.remoteControlReceived(with: event)
      return
    }

    let subtype = event.subtype
    print("PleyaTvRemote: remote control event subtype=\(remoteControlSubtypeName(subtype))")
    switch subtype {
    case .remoteControlPlay, .remoteControlPause, .remoteControlTogglePlayPause:
      sendPlayPauseEvent(source: "remote_control", detail: remoteControlSubtypeName(subtype))
    default:
      super.remoteControlReceived(with: event)
    }
  }

  private func handlePlayPausePress(_ presses: Set<UIPress>) -> Bool {
    guard containsPlayPausePress(presses) else { return false }

    sendPlayPauseEvent(source: "presses", detail: "playPause")
    return true
  }

  private func containsPlayPausePress(_ presses: Set<UIPress>) -> Bool {
    presses.contains { press in
      press.type == .playPause
    }
  }

  private func sendPlayPauseEvent(source: String, detail: String) {
    print("PleyaTvRemote: intercepted play/pause source=\(source) detail=\(detail)")
    tvRemoteChannel.sendMessage(["type": "play_pause", "source": source, "detail": detail])
  }

  private func remoteControlSubtypeName(_ subtype: UIEvent.EventSubtype) -> String {
    switch subtype {
    case .remoteControlPlay:
      return "remoteControlPlay"
    case .remoteControlPause:
      return "remoteControlPause"
    case .remoteControlTogglePlayPause:
      return "remoteControlTogglePlayPause"
    case .remoteControlStop:
      return "remoteControlStop"
    case .remoteControlNextTrack:
      return "remoteControlNextTrack"
    case .remoteControlPreviousTrack:
      return "remoteControlPreviousTrack"
    case .remoteControlBeginSeekingForward:
      return "remoteControlBeginSeekingForward"
    case .remoteControlEndSeekingForward:
      return "remoteControlEndSeekingForward"
    case .remoteControlBeginSeekingBackward:
      return "remoteControlBeginSeekingBackward"
    case .remoteControlEndSeekingBackward:
      return "remoteControlEndSeekingBackward"
    default:
      return "unknown(\(subtype.rawValue))"
    }
  }
}
