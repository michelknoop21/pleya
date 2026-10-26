# Pinned plugins with Swift Package Manager packaging

Roadmap: A-18. These copies add Swift Package Manager support missing from the
exact plugin revisions already used by Pleya. The reviewed local runtime changes
are listed below. `upstream.json` records original package-cache identities and SHA-256
hashes for every copied runtime file. Licences are included. Examples, upstream
tests and build output are not part of these runtime copies.

The root `dependency_overrides` select these copies on **all** platforms. Original
dependency declarations remain as provenance, but changing those declarations
alone does not update the effective overridden package. For an update, replace
the runtime copy from the reviewed upstream revision, regenerate its provenance
hashes, reapply packaging, resolve the lockfile and rerun the package/native gates.
Remove the override when the selected upstream revision supports SPM itself.

Local differences:

- `os_media_controls`: IOS-SYSTEM-REMOTE1 adds public subtitle language options,
  preserves explicit play/pause intent and removes only owned command targets.
  `upstream.json` retains original hashes plus reviewed `local_files` hashes.
  Check the native lifecycle with `python3 scripts/test_tvos_system_remote.py`.

- `Package.swift` per supported Apple platform; library product names use hyphens.
- `Classes` moved under `<platform>/<name>/Sources/<name>` and CocoaPods source paths
  adjusted. CocoaPods remains supported, including the tvOS plugin path.
- Cupertino's existing ObjC source uses ARC; an include directory makes it a valid
  Clang module. Its exported FFI symbols must remain present in linked builds.
- Sparkle stays at **2.9.0**, matching the existing macOS Podfile lock. The SPM
  dependency is exact, rather than silently choosing a newer updater binary.
- The screen retriever's SPM target is macOS 10.13 (SwiftPM's supported minimum),
  below Pleya's app deployment target.

Run `python3 scripts/test_spm_plugins.py` to check source parity and packaging.
Native iOS/macOS builds are required; static checks alone do not prove HTTP FFI,
gamepad hardware, media controls, Wi-Fi Aware or updater runtime behaviour.
