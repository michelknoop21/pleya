#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

chmod +x .githooks/pre-commit .githooks/pre-push \
         scripts/ci_checks.sh scripts/gen_release_notes.sh scripts/check_hooks_installed.sh
# Deliberately the relative '.githooks' and never an absolute path. This lands in
# the shared .git/config, which every worktree of this repository reads, and git
# resolves a relative hooksPath against the top level of whichever worktree is
# running. An absolute path there points every worktree at one checkout's hooks,
# on whatever branch that checkout happens to have out, so a stale hook from an
# unrelated branch runs on commits and pushes made somewhere else entirely.
git config core.hooksPath .githooks

cat <<EOF
Git hooks installed.
  pre-commit  runs the local CI gate: SDK pin, formatting, codegen freshness, native
              formatting and the analyzer. The tree-wide unused-code and unused-file
              scans stay out of it and run in CI; the hook takes no arguments, so to
              see them locally run ./scripts/ci_checks.sh --with-unused yourself.
  pre-push    reports whether docs/RELEASES.md has fallen behind the commits since
              the last published build. It writes nothing, commits nothing and blocks
              nothing. Generating the notes belongs to the documentation round:
              scripts/gen_release_notes.sh.

Bypass once:  git commit --no-verify  /  git push --no-verify
Bypass env:   SKIP_HOOKS=1 git commit ...
Run manually: ./scripts/ci_checks.sh  ·  ./scripts/gen_release_notes.sh
Uninstall:    git config --unset core.hooksPath
EOF
