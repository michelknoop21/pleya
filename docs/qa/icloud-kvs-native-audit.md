# Native audit: `ICloudKvsPlugin.swift`

Date: 2026-08-21. Scope: A15. Files: `ios/Runner/ICloudKvsPlugin.swift`,
`tvos/Runner/ICloudKvsPlugin.swift` (byte-identical to the iOS one) and
`macos/Runner/ICloudKvsPlugin.swift`, which differs in exactly two lines: the macOS registrar
exposes `messenger` as a property where iOS and tvOS expose `messenger()`.

The rule this audit followed: change Swift only where a contract gap was demonstrated. Two of the
nine points produced one; the rest are recorded as verified, with what verified them.

## 1. Store registration

`NSUbiquitousKeyValueStore.default`, held for the plugin's lifetime. Correct: the default store is
the only one the entitlement grants.

Verdict: no change.

## 2. Entitlement

`com.apple.developer.ubiquity-kvstore-identifier` is present in all four entitlement files
(`ios/Runner/Runner.entitlements`, `tvos/Runner/Runner.entitlements`,
`macos/Runner/Release.entitlements`, `macos/Runner/DebugProfile.entitlements`), each with the value
`$(TeamIdentifierPrefix)$(CFBundleIdentifier)`.

Verdict: no change.

## 3. Bundle and team identity: do the three platforms share one store?

This is the point that decides whether a Mac and an Apple TV can see each other's settings at all,
and the entitlement value alone does not answer it: it expands per target.

Measured: `PRODUCT_BUNDLE_IDENTIFIER` is `nl.michelknoop.pleya` in `ios/Runner.xcodeproj`, in
`tvos/Runner.xcodeproj` and in `macos/Runner/Configs/AppInfo.xcconfig`. The tvOS Top Shelf extension
has its own id (`nl.michelknoop.pleya.TopShelfExtension`) and does not use the store. With one team
prefix, all three app targets therefore expand to the same KVS identifier and address one store.

Verdict: no change. Worth re-checking after any bundle-id change, which is why it is written down.

## 4. `synchronize`

Called once at registration and exposed as a method so the Dart flush can ask for it. Apple treats
it as a hint, not a commit, and the Dart layer never relies on it for correctness: a value counts as
sent when `set` returns.

Verdict: no change.

## 5. `didChangeExternallyNotification`

Observed with `object: store`, and the payload's reason and changed-keys are forwarded verbatim.

Verdict: no change.

## 6. Quota and account-change reasons

The raw reason integer crosses the channel and `ICloudKvsTransport.translateEvent` maps it:
`2 -> quotaExceeded`, `3 -> accountChanged`, `1 -> initialSync`, `0 -> serverChange`, and anything
unknown to `serverChange`, because re-reading is cheap and guessing is not.

Verdict: no change.

## 7. Observer lifecycle: gap, fixed

There was no `deinit` and no `removeObserver`. In the app as it ships this leaks nothing visible:
the registrar keeps one plugin instance for the life of the engine, and since iOS 9 an unbalanced
`NotificationCenter` observer no longer dangles.

What it is not safe against is a second engine. Register twice and there are two live instances, two
observers on the same notification, and two event sinks, so every remote change is delivered twice
and every batch is applied twice. Pleya runs one engine today; the fix is one line and removes the
question.

Change: `deinit { NotificationCenter.default.removeObserver(self) }`.

## 8. Availability

`FileManager.default.ubiquityIdentityToken != nil`. A nil token is the documented signal for "no
iCloud account", and the Dart side turns it into `unavailable` rather than an error.

Verdict: no change.

## 9. Account identity change: gap, fixed

`NSUbiquityIdentityDidChangeNotification` was not observed anywhere. The store's own
`didChangeExternallyNotification` carries an account-change reason, but it is a notification about
the store, and the store belongs to the account that just went away. A sign-out is exactly the case
where relying on it is weakest.

The consequence was not theoretical. Availability is read at start and when the toggle is used, so a
sign-out mid-session left the status reporting a healthy sync while every write went nowhere, until
the next launch.

Change: observe `NSUbiquityIdentityDidChange` and emit it under the store's own account-change
reason (`NSUbiquitousKeyValueStoreAccountChange`), so the Dart side needs no second vocabulary. On
the Dart side that reason now re-reads availability first and only reconciles when there is still a
store to talk to. Two tests in `test/services/preferences/reconcile_lifecycle_test.dart` cover both
branches.

## Deliberately not changed: buffering events that arrive before Dart subscribes

`storeDidChangeExternally` starts with `guard let sink = eventSink else { return }`, so a
notification that arrives before the Dart side subscribes is dropped, and there is no buffer.

That looks like a hole and is not one. Every path that subscribes also reconciles: `listen()` runs
inside the boot and enable triggers, and both end in `applyAllRemote()` followed by `reconcile()`.
A change missed during startup is therefore read from the store moments later by a pass that does
not depend on having seen the event. Adding a buffer would add a queue, a flush and an ordering
question, to re-deliver information the next read already carries.

Recorded rather than built. If a device test ever shows a change that startup reconciliation does
not pick up, this is the first place to look, and then the buffer has evidence behind it.

## Also deliberately not changed: `startObserving()` runs regardless of the toggle

Registration happens at app start whether or not iCloud sync is switched on. The notification then
arrives at a Dart handler whose first line is `if (!_enabled()) return;`. The cost is one ignored
callback; gating the native side would add a second switch that has to be kept in step with the
first.

## What this audit does not prove

Nothing here proves that two Apple devices actually exchange a setting. These are code and
configuration findings. The device matrix in `preference-sync-and-playback-matrix.md` is still open,
and the account-change path in particular (S10) can only be exercised by signing out on real
hardware.
