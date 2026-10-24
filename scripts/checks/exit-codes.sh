#!/usr/bin/env bash
# GitHub runs every run: step with bash -e, so a command that fails stops the step before the next
# line. A line that is only `x=$?` therefore never sees a failure: read the code on the same line,
# `x=0; cmd || x=$?`. Found when terraform plan's "changes" exit (2) failed the plan job.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
bad=0
while IFS= read -r f; do
  case "$f" in .github/workflows/*.yml | .github/workflows/*.yaml) ;; *) continue ;; esac
  while IFS=: read -r line _; do
    echo "::error file=$f,line=$line::exit code read on its own line; bash -e stops before it. Use: x=0; cmd || x=\$?"
    bad=1
  done < <(grep -nE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\$\?[[:space:]]*$' "$f" || true)
done < <(bash scripts/checks/changed-files.sh)
exit "$bad"
