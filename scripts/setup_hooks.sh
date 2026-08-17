#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

chmod +x .githooks/pre-commit .githooks/pre-push \
         scripts/ci_checks.sh scripts/gen_release_notes.sh scripts/check_hooks_installed.sh
git config core.hooksPath .githooks

cat <<EOF
Git hooks installed.
  pre-commit  runs the CI analyze pipeline (format + analyze + unused code + unused files)
  pre-push    refreshes docs/RELEASES.md from the commits since the last published
              build. If it wrote anything it commits that and aborts the push, because
              a commit made by the hook is not part of the refs git already resolved.
              Push again and it goes along.

Bypass once:  git commit --no-verify  /  git push --no-verify
Bypass env:   SKIP_HOOKS=1 git commit ...
Run manually: ./scripts/ci_checks.sh  ·  ./scripts/gen_release_notes.sh
Uninstall:    git config --unset core.hooksPath
EOF
