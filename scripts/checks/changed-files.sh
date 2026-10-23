#!/usr/bin/env bash
# Files this change adds or modifies (deleted files are left out), one per line.
# The rules check new code only: CI sets BASE to the pull request's base commit, or to the commit
# before a push. Without a usable BASE (a new branch, a local run) every tracked file counts.
set -euo pipefail
if [ -n "${BASE:-}" ] && git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  git diff --name-only --diff-filter=ACMR "$BASE" HEAD
else
  git ls-files
fi
