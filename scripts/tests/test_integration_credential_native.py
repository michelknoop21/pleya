#!/usr/bin/env python3
"""Exercise the actual native per-record result decision, without CloudKit access."""
from pathlib import Path
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[2]
    source = (root / "ios/Runner/ICloudKvsPlugin.swift").read_text()
    helper = source[source.index("private final class CredentialWriteResult"):]
    property_line = next(line for line in source.splitlines() if "credentials = ICloudCredentialStore()" in line)
    for platform in ("tvos", "macos"):
        platform_source = (root / platform / "Runner/ICloudKvsPlugin.swift").read_text()
        if property_line not in platform_source.splitlines():
            raise SystemExit("Credential initialization differs between Apple platforms")
    boot_probe = '''
final class ICloudCredentialStore {
  static var initializations = 0
  init() { Self.initializations += 1 }
}
final class PluginProbe {
PROPERTY
  func useCredentials() { _ = credentials }
}
private let plugin = PluginProbe()
check(ICloudCredentialStore.initializations == 0, "Registering KVS must not initialize CloudKit")
plugin.useCredentials()
check(ICloudCredentialStore.initializations == 1, "The first credential request initializes CloudKit")
plugin.useCredentials()
check(ICloudCredentialStore.initializations == 1, "Later requests reuse the same credential store")
'''.replace("PROPERTY", property_line)
    assertions = '''
var failures = 0
func check(_ condition: Bool, _ message: String) {
  if !condition { failures += 1; print(message) }
}
let recordFailure = NSError(domain: "fake-cloud", code: 14)
let operationFailure = NSError(domain: "fake-network", code: 1)
func failed(_ result: Result<Void, Error>) -> Bool {
  if case .failure = result { return true }
  return false
}
private let missing = CredentialWriteResult()
check(failed(missing.completed(.success(()))), "An operation success without a record result is not a saved credential")
private let rejected = CredentialWriteResult()
rejected.set(.failure(recordFailure))
check(failed(rejected.completed(.success(()))), "A per-record conflict must survive operation success")
private let interrupted = CredentialWriteResult()
interrupted.set(.success(()))
check(failed(interrupted.completed(.failure(operationFailure))), "Operation failure must survive record success")
private let saved = CredentialWriteResult()
saved.set(.success(()))
check(!failed(saved.completed(.success(()))), "Both success results are needed")
'''
    assertions += boot_probe + "\nif failures > 0 { exit(1) }\n"
    with tempfile.TemporaryDirectory(prefix="pleya-credential-native-") as tmp:
        folder = Path(tmp)
        path = folder / "main.swift"
        path.write_text("import Foundation\n" + helper + assertions)
        command = ["xcrun", "swiftc", "-module-cache-path", str(folder / "modules"), str(path), "-o", str(folder / "test")]
        subprocess.run(command, check=True)
        subprocess.run([str(folder / "test")], check=True)
        # Negative control: treating an operation success as the complete write
        # loses record-level conflicts. The exact same assertions must reject it.
        start = helper.index("  func completed(")
        end = helper.index("  private func get()", start)
        mutant = helper[:start] + "  func completed(_ operation: Result<Void, Error>) -> Result<Void, Error> { return operation }\n" + helper[end:]
        path.write_text("import Foundation\n" + mutant + assertions)
        subprocess.run(command, check=True)
        result = subprocess.run([str(folder / "test")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode != 1:
            raise SystemExit("Negative control did not fail cleanly with exit 1")
        # Eager construction would run CloudKit before the opt-in/Verify guard.
        eager = assertions.replace(property_line, property_line.replace("lazy var", "let"))
        path.write_text("import Foundation\n" + helper + eager)
        subprocess.run(command, check=True)
        result = subprocess.run([str(folder / "test")], capture_output=True, text=True)
        if result.returncode != 1 or "Registering KVS must not initialize CloudKit" not in result.stdout:
            raise SystemExit("Eager initialization negative control missed the intended regression")
    print("Native result and deferred startup pass; operation-only and eager-init mutants fail")


if __name__ == "__main__":
    main()
