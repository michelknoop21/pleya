"""Run the actual tvOS suspension callbacks with a controllable mpv reply queue."""
from pathlib import Path
import subprocess
import tempfile
import sys

source = Path(sys.argv[1] if len(sys.argv) > 1 else 'ios/Runner/MpvPlayer/MpvPlayerCore.swift').read_text()

def method(name):
    start = source.index('func ' + name + '(')
    start = source.rfind('\n', 0, start) + 1
    at = source.index('{', start)
    depth = 1
    end = at + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    body = source[start:end].replace('@objc private ', '').replace('private func ', 'func ')
    return '\n'.join(line for line in body.splitlines() if not line.strip().startswith(('#if', '#endif')))

fields = '\n'.join(line.strip().replace('private ', '') for line in source.splitlines()
                   if line.strip().startswith('private var tv'))
assert 'UIApplication.willResignActiveNotification' in source
harness = '''
import Foundation
final class Layer {
  var flushes = 0
  func flushAndRemoveImage() { flushes += 1 }
}
final class Core {
  var isPaused = true
  var isDisposed = false
  var isBackgrounded = false
  var isPipActive = false
  var isPipStarting = false
  var videoLayer: Layer? = Layer()
  var reads: [(Result<String?, Error>) -> Void] = []
  var writes: [(String, (Result<Void, Error>) -> Void)] = []
  var submitted: [String] = []
  var snapshots: [String] = []
  var draws = 0
  static func log(_ message: String) {}
  func logMemorySnapshot(_ reason: String) { snapshots.append(reason) }
  func forceDraw() { draws += 1 }
  func getPropertyAsync(_ name: String, completion: @escaping (Result<String?, Error>) -> Void) {
    assert(name == "vid"); reads.append(completion)
  }
  func setProperty(_ name: String, value: String) { setPropertyAsync(name, value: value) { _ in } }
  func setPropertyAsync(_ name: String, value: String, completion: @escaping (Result<Void, Error>) -> Void) {
    assert(name == "vid"); submitted.append(value); writes.append((value, completion))
  }
  func read(_ track: String?) { reads.removeFirst()(.success(track)) }
  func ack(_ error: Bool = false) {
    writes.removeFirst().1(error ? .failure(NSError(domain: "test", code: 1)) : .success(()))
  }
'''
tests = '''
let playing = Core(); playing.isPaused = false; playing.resignActive()
assert(playing.reads.isEmpty && playing.submitted.isEmpty)
let pip = Core(); pip.isPipActive = true; pip.resignActive(); assert(pip.reads.isEmpty)
let noVideo = Core(); noVideo.resignActive(); noVideo.read("no")
assert(noVideo.submitted.isEmpty)
let failedRead = Core(); failedRead.resignActive()
failedRead.reads.removeFirst()(.failure(NSError(domain: "test", code: 1)))
assert(failedRead.submitted.isEmpty && failedRead.tvSavedVideoTrack == nil)
let paused = Core(); paused.resignActive(); paused.read("3")
assert(paused.submitted == ["no"])
paused.ack(); assert(paused.videoLayer!.flushes == 1 && paused.isPaused)
paused.becameActive(); assert(paused.submitted == ["no", "3"])
paused.ack(); assert(paused.tvSavedVideoTrack == nil && paused.draws == 1 && paused.isPaused)
assert(paused.snapshots.contains("tv-paused-video-released"))
let earlyActive = Core(); earlyActive.resignActive(); earlyActive.becameActive(); earlyActive.read("4")
assert(earlyActive.submitted.isEmpty)
let staleRead = Core(); staleRead.resignActive(); staleRead.becameActive(); staleRead.resignActive()
staleRead.read("3"); assert(staleRead.submitted.isEmpty)
staleRead.read("4"); assert(staleRead.submitted == ["no"])
let inFlight = Core(); inFlight.resignActive(); inFlight.read("7"); inFlight.becameActive()
assert(inFlight.submitted == ["no"])
inFlight.ack(); assert(inFlight.submitted == ["no", "7"] && inFlight.videoLayer!.flushes == 0)
inFlight.becameActive(); assert(inFlight.submitted.count == 2)
inFlight.ack(); assert(inFlight.tvSavedVideoTrack == nil)
let failed = Core(); failed.resignActive(); failed.read("2"); failed.ack(true); failed.becameActive()
assert(failed.tvSavedVideoTrack == nil && failed.videoLayer!.flushes == 0 && failed.submitted == ["no"])
let retry = Core(); retry.resignActive(); retry.read("8"); retry.ack(); retry.becameActive(); retry.ack(true)
assert(retry.tvSavedVideoTrack == "8")
retry.becameActive(); retry.ack(); assert(retry.tvSavedVideoTrack == nil)
let playingRestore = Core(); playingRestore.resignActive(); playingRestore.read("9"); playingRestore.ack()
playingRestore.becameActive(); playingRestore.isPaused = false; playingRestore.ack()
assert(playingRestore.draws == 0 && playingRestore.submitted == ["no", "9"])
let reenter = Core(); reenter.resignActive(); reenter.read("6"); reenter.ack(); reenter.becameActive()
reenter.resignActive(); reenter.ack(); reenter.read("6"); reenter.ack()
assert(reenter.submitted == ["no", "6", "no"] && reenter.tvSavedVideoTrack == "6")
let lateBackground = Core(); lateBackground.resignActive(); lateBackground.read("11"); lateBackground.ack()
lateBackground.becameActive(); lateBackground.resignActive(); lateBackground.enterBackground(); lateBackground.ack()
assert(lateBackground.submitted == ["no", "11", "no"] && lateBackground.tvSavedVideoTrack == "11")
lateBackground.ack(); assert(lateBackground.videoLayer!.flushes == 2)
lateBackground.enterForeground(); lateBackground.ack()
assert(lateBackground.submitted == ["no", "11", "no", "11"] && lateBackground.tvSavedVideoTrack == nil)
let disposed = Core(); disposed.resignActive(); disposed.read("5"); disposed.isDisposed = true; disposed.ack()
assert(disposed.videoLayer!.flushes == 0 && disposed.submitted == ["no"])
let background = Core(); background.resignActive(); background.isBackgrounded = true; background.read("5")
assert(background.submitted.isEmpty)
print("tvOS paused-video reclamation: all callback/race checks passed")
'''
with tempfile.TemporaryDirectory(prefix='pleya-tvos-reclaim-') as tmp:
    path = Path(tmp)
    (path/'main.swift').write_text(harness + fields + '\n' + '\n'.join(method(n) for n in
                              ['resignActive', 'disableSavedTvVideo', 'restorePausedTvVideo', 'becameActive', 'enterBackground', 'enterForeground']) + '\n}\n' + tests)
    subprocess.run(['xcrun', 'swiftc', str(path/'main.swift'), '-o', str(path/'test')], check=True)
    subprocess.run([str(path/'test')], check=True)
