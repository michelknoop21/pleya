#!/usr/bin/env python3
"""Execute the plugin's command/option lifecycle against a recording MediaPlayer double.

This is not a device/UI test. SDK typechecking and physical iPhone acceptance stay separate.
"""
from pathlib import Path
import subprocess
import tempfile
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'third_party/os_media_controls/ios/os_media_controls/Sources/os_media_controls/OsMediaControlsPlugin.swift'


def method(source, name):
    start = source.index('    private func ' + name + '(')
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end].replace('private func ', 'func ').replace('let commandCenter = MPRemoteCommandCenter.shared()', 'let commandCenter = self.commandCenter')


source = (Path(sys.argv[1]) if len(sys.argv) > 1 else SOURCE).read_text()
methods = '\n'.join(method(source, name) for name in (
    'addHandler', 'removeCommandTargets', 'setupRemoteCommandCenter',
    'ensureHandlersRegistered', 'setSubtitleOptions', 'sendPlaybackCommand', 'clear',
))
# The lifecycle tests run on the host; the tvOS-only gesture debounce is hardware-owned.
commands = ('play pause togglePlayPause nextTrack previousTrack changePlaybackPosition '
            'skipForward skipBackward changePlaybackRate enableLanguageOption disableLanguageOption').split()
prelude = '''
import Foundation
enum MPRemoteCommandHandlerStatus { case success, commandFailed }
class MPRemoteCommandEvent {}
class MPChangePlaybackPositionCommandEvent: MPRemoteCommandEvent { var positionTime = 0.0 }
class MPSkipIntervalCommandEvent: MPRemoteCommandEvent { var interval = 7.5 }
class MPChangePlaybackRateCommandEvent: MPRemoteCommandEvent { var playbackRate: Float = 1 }
class MPChangeLanguageOptionCommandEvent: MPRemoteCommandEvent {
    var languageOption: MPNowPlayingInfoLanguageOption
    init(_ option: MPNowPlayingInfoLanguageOption) { languageOption = option }
}
class MPRemoteCommand {
    var isEnabled = false
    var preferredIntervals: [NSNumber] = []
    var supportedPlaybackRates: [NSNumber] = []
    var handlers: [Int: (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus] = [:]
    var serial = 0
    func addTarget(handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) -> Any {
        serial += 1; handlers[serial] = handler; return serial
    }
    func removeTarget(_ target: Any?) { handlers.removeValue(forKey: target as! Int) }
    func fire(_ event: MPRemoteCommandEvent = MPRemoteCommandEvent()) -> MPRemoteCommandHandlerStatus {
        assert(handlers.count == 1); return handlers.values.first!(event)
    }
}
class MPRemoteCommandCenter {
'''
prelude += '\n'.join(f'    let {name}Command = MPRemoteCommand()' for name in commands)
prelude += '''
}
class MPNowPlayingInfoLanguageOption {
    enum OptionType { case legible }
    let identifier: String?
    init(type: OptionType, languageTag: String, characteristics: [String], displayName: String, identifier: String) {
        self.identifier = identifier
    }
}
class MPNowPlayingInfoLanguageOptionGroup {
    let options: [MPNowPlayingInfoLanguageOption]
    init(languageOptions: [MPNowPlayingInfoLanguageOption], defaultLanguageOption: MPNowPlayingInfoLanguageOption?, allowEmptySelection: Bool) {
        options = languageOptions; assert(allowEmptySelection)
    }
}
let MPNowPlayingInfoPropertyAvailableLanguageOptions = "available"
let MPNowPlayingInfoPropertyCurrentLanguageOptions = "selected"
class InfoCenter { var nowPlayingInfo: [String: Any]? }
class AVAudioSession {
    static func sharedInstance() -> AVAudioSession { AVAudioSession() }
    enum Options { case notifyOthersOnDeactivation }
    func setActive(_ active: Bool, options: Options) throws {}
}
class Harness {
    let commandCenter = MPRemoteCommandCenter()
    let nowPlayingCenter = InfoCenter()
    var commandTargets: [(MPRemoteCommand, Any)] = []
    var subtitleOptions: [String: MPNowPlayingInfoLanguageOption] = [:]
    var currentMetadata: [String: Any] = [:]
    func setNativePlaybackState(_ state: String) {}
    var handlersCleared = true
    var eventSink: Bool? = true
    var events: [[String: Any]] = []
    func sendEvent(_ event: [String: Any]) { events.append(event) }
'''
checks = '''
}
let h = Harness()
h.ensureHandlersRegistered()
assert(h.commandTargets.count == 11)
h.setupRemoteCommandCenter()
h.ensureHandlersRegistered()
assert(h.commandTargets.count == 11)
assert(h.commandCenter.playCommand.fire() == .success)
assert(h.events.last?["type"] as? String == "play")
assert(h.commandCenter.pauseCommand.fire() == .success)
assert(h.events.last?["type"] as? String == "pause")
assert(h.commandCenter.skipForwardCommand.fire(MPSkipIntervalCommandEvent()) == .commandFailed)
h.commandCenter.skipForwardCommand.isEnabled = true
assert(h.commandCenter.skipForwardCommand.fire(MPSkipIntervalCommandEvent()) == .success)
assert(h.events.last?["interval"] as? Double == 7.5)
h.setSubtitleOptions(["options": [["id": "nl", "language": "nl", "title": "Nederlands"]], "selectedId": "nl"])
assert(h.commandCenter.enableLanguageOptionCommand.isEnabled)
assert(h.commandCenter.disableLanguageOptionCommand.isEnabled)
assert((h.nowPlayingCenter.nowPlayingInfo?["selected"] as? [MPNowPlayingInfoLanguageOption])?.first?.identifier == "nl")
assert(h.commandCenter.enableLanguageOptionCommand.fire(MPChangeLanguageOptionCommandEvent(h.subtitleOptions["nl"]!)) == .success)
assert(h.events.last?["id"] as? String == "nl")
h.setSubtitleOptions(["options": []])
assert(!h.commandCenter.enableLanguageOptionCommand.isEnabled)
assert(!h.commandCenter.disableLanguageOptionCommand.isEnabled)
assert(h.commandCenter.disableLanguageOptionCommand.fire() == .commandFailed)
// Removal owns only its own target; another owner's target survives cleanup.
let foreign = h.commandCenter.playCommand.addTarget { _ in .success }
for _ in 0..<3 {
    h.clear()
    assert(h.nowPlayingCenter.nowPlayingInfo == nil)
    assert(h.subtitleOptions.isEmpty)
    assert(h.commandCenter.playCommand.handlers.count == 1)
    h.ensureHandlersRegistered()
    assert(h.commandTargets.count == 11)
    assert(h.commandCenter.playCommand.handlers.count == 2)
}
h.commandCenter.playCommand.removeTarget(foreign)
assert(h.commandCenter.playCommand.fire() == .success)
print("PASS: command intent, interval, subtitle state/empty tracks, three re-registrations, foreign ownership")
'''
with tempfile.TemporaryDirectory(prefix='pleya-system-remote-') as tmp:
    swift = Path(tmp) / 'main.swift'
    swift.write_text(prelude + methods + checks)
    subprocess.run(['swift', str(swift)], check=True)
