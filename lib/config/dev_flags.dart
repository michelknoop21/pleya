import 'package:flutter/foundation.dart';

/// Debug-only development gates for work in progress.
///
/// These are never user-facing settings: nothing here is read by
/// [SettingsExportService], nothing is persisted to `SharedPreferences`, and
/// every gate collapses to `false` outside [kDebugMode] regardless of the
/// in-memory value. A gate exists to let a feature under active development
/// be flipped on locally (e.g. from the Debug section in Settings) without
/// exposing it to release builds or shipping it as an opt-in toggle.
class DevFlags {
  DevFlags._();

  static bool _tvUnifiedExperience = false;

  /// Pleya Unified TV 2026 (docs/tvos-unified-experience.md). Gates the
  /// unified multi-server catalog and the new TV shell while they are built
  /// across phases; see docs/DECISIONS.md#dec-063.
  static bool get tvUnifiedExperience => kDebugMode && _tvUnifiedExperience;

  static set tvUnifiedExperience(bool value) => _tvUnifiedExperience = value;
}
