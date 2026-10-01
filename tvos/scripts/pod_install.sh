#!/usr/bin/env bash
# Runs `pod install` for the tvOS target with UTF-8 locale forced — CocoaPods
# 1.16 on Ruby 4.0 crashes with Encoding::CompatibilityError when LANG/LC_ALL
# are unset or non-UTF-8.

set -euo pipefail

TVOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TVOS_DIR"

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Called from fastlane, GEM_PATH points at fastlane's own gems; under Ruby 4.0 CocoaPods then fails to load
# with "Could not find 'minitest'" (tvos_beta, 1 Oct 2026). pod has its own gem environment, so start clean.
unset GEM_PATH GEM_HOME RUBYOPT BUNDLE_GEMFILE BUNDLE_BIN_PATH
exec pod install "$@"
