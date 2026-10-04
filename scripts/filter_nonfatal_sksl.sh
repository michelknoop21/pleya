#!/usr/bin/env bash
# Filters Flutter build output (stdin -> stdout) for an Xcode Run Script phase.
#
# Flutter compiles every shader for SkSL too on targets that still carry a
# Skia path: `flutter build bundle` (default android-arm, used by tvOS) and
# `flutter assemble` for darwin (macOS). liquid_glass_renderer's shaders do not
# fit SkSL. Flutter then retries without SkSL, keeps the build green, and
# prints the SkSL compiler output as a warning with lines like
# "error: 58: ...". Xcode reads those lines as build errors, and
# `xcodebuild archive` stops with exit 65 although the script exited 0.
#
# Only on tvOS and macOS, and only for that package: neither platform ever
# builds a real glass widget (see lib/theme/glass/glass_settings.dart).
# "error:" is rewritten only inside Flutter's own non-fatal block, from its
# "warning: Shader `...` is incompatible with SkSL" line to its "Full ... error
# output written to" line. Any other shader failure is fatal in Flutter, exits
# non-zero, and passes through unchanged. Callers must use `set -o pipefail`.
exec awk '
  /^warning: Shader `.*\/liquid_glass_renderer-[^\/]*\/.*` is incompatible with SkSL/ { in_block = 1 }
  in_block { gsub(/error:/, "sksl error -") }
  { print }
  in_block && /^Full ".*" error output written to/ { in_block = 0 }
'
