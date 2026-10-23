#!/usr/bin/env bash
# Release notes: what <to> ships that <from> did not, grouped by the commit prefix.
#   scripts/release-notes.sh <from ref or empty for "everything"> <to ref>
# A fix that reached <from> as a cherry-pick (a hotfix) is left out, so it is not listed twice.
# The bot's own commits (deploy records, README rows, menus) are not changes and are left out.
set -euo pipefail

FROM="${1:-}"
TO="$2"
if [ -n "$FROM" ]; then RANGE=(--cherry-pick --right-only "$FROM...$TO"); else RANGE=("$TO"); fi

BOT='^(staging|prod|hotfix): release |^prod: rollback |^docs: README shows |^ci: Promote and Rollback menus follow'
# Commits <from> already has as a cherry-pick -x (a cherry-pick with a resolved conflict changes
# the patch, so --cherry-pick alone misses it).
PICKED=""
[ -z "$FROM" ] || PICKED=$(git log --format=%B "$FROM" | sed -nE 's/.*cherry picked from commit ([0-9a-f]{40}).*/\1/p' | sort -u)
LOG=$(git log --no-merges --format='%H %s' "${RANGE[@]}" \
  | { if [ -n "$PICKED" ]; then grep -vFf <(sed 's/$/ /' <<<"$PICKED"); else cat; fi; } \
  | cut -d' ' -f2- | grep -Ev "$BOT" || true)

section() {
  local title=$1 pattern=$2 lines
  lines=$(grep -E "$pattern" <<<"$LOG" || true)
  [ -n "$lines" ] || return 0
  echo "### $title"
  sed -E 's/^[a-z]+(\([^)]*\))?!?: */- /' <<<"$lines"
  echo
}

if [ -z "$LOG" ]; then echo "No changes besides release records."; exit 0; fi
section Features '^feat(\(|!|:)'
section Fixes '^fix(\(|!|:)'
section Other '^(ci|docs|chore|refactor|test|build|perf)(\(|!|:)'
OTHER=$(grep -Ev '^(feat|fix|ci|docs|chore|refactor|test|build|perf)(\(|!|:)' <<<"$LOG" || true)
if [ -n "$OTHER" ]; then echo "### Unlabelled"; sed 's/^/- /' <<<"$OTHER"; echo; fi
