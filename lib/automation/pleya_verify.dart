/// Compile-time switch for Pleya Verify, the automation/verification control
/// plane (see docs/architecture/pleya-verify.md). Build with
/// `--dart-define=PLEYA_VERIFY=true` (threaded into the tvOS build as the
/// `PLEYA_VERIFY` env var read by `tvos/scripts/xcode_appletv.sh`).
///
/// A normal build keeps this `const false`, so the Dart tree-shaker removes
/// every `if (kPleyaVerify)` branch — and everything it guards — from a
/// release binary. Same idiom as `kBlurArtwork` in
/// lib/utils/obfuscation_utils.dart.
const bool kPleyaVerify = bool.fromEnvironment('PLEYA_VERIFY');

/// Protocol marker sent as the `X-Pleya-Verify` header value on every
/// `/v1/*` request, and embedded as a literal string so a release binary can
/// be grepped to prove the whole automation path was tree-shaken out.
const String kAutomationProtocolMarker = 'PleyaVerify/1';
