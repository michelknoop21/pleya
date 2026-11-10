#!/usr/bin/env bash
# Rich push (DEC-XXX): compile the extension's decrypt code for macOS and open
# the vector the Go tests seal. No keychain, no simulator.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
swiftc -parse-as-library -o "$out/push_content_check" \
  ios/NotificationService/PushContent.swift ios/NotificationService/NotificationService.swift \
  ios/NotificationService/Tests/PushContentCheck.swift
"$out/push_content_check" pleya_server/internal/push/testdata/rich_vector.json "$out/poster.png"
