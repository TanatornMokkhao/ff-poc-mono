#!/usr/bin/env bash
# Runs shellcheck on every shell script this change adds or modifies. A grep with no match inside
# $(...) under pipefail once stopped deploy.sh with no message; shellcheck finds that family of
# mistakes (unquoted values, ignored exit codes, unset variables) before it runs.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
files=()
while IFS= read -r f; do
  case "$f" in *.sh) files+=("$f") ;; esac
done < <(bash scripts/checks/changed-files.sh)
[ ${#files[@]} -gt 0 ] || { echo "No shell scripts changed."; exit 0; }
shellcheck --severity=warning --format=gcc "${files[@]}" | sed -E 's/^([^:]+):([0-9]+):([0-9]+): (warning|error): (.*)$/::error file=\1,line=\2,col=\3::\5/'
exit "${PIPESTATUS[0]}"
