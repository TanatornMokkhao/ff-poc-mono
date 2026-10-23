#!/usr/bin/env bash
# actionlint on every workflow this change adds or modifies: expression and context mistakes,
# wrong job outputs, and (through shellcheck) the bash inside run: steps.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
files=()
while IFS= read -r f; do
  case "$f" in .github/workflows/*.yml | .github/workflows/*.yaml) files+=("$f") ;; esac
done < <(bash scripts/checks/changed-files.sh)
[ ${#files[@]} -gt 0 ] || { echo "No workflows changed."; exit 0; }
# One GitHub annotation per finding; the line break inside the quotes ends each one.
actionlint -shellcheck="${SHELLCHECK:-shellcheck}" -format '{{range $err := .}}::error file={{$err.Filepath}},line={{$err.Line}},col={{$err.Column}}::{{$err.Message}}
{{end}}' "${files[@]}"
