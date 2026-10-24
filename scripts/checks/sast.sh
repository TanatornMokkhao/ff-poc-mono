#!/usr/bin/env bash
# Semgrep (community rules) on what this change adds: a finding that is not already on the base
# commit fails it. With no base (the nightly run) it scans everything.
# Two rules are left out on purpose: actions are pinned by tag except the AWS credentials one, and
# `secrets: inherit` only ever passes secrets to this repo's own workflows.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
BASELINE=()
if [ -n "${BASE:-}" ] && git cat-file -e "$BASE^{commit}" 2>/dev/null; then BASELINE=(--baseline-commit "$BASE"); fi
semgrep scan --metrics=off --error --quiet "${BASELINE[@]}" \
  --config p/javascript --config p/typescript --config p/nodejs \
  --config p/dockerfile --config p/github-actions --config .semgrep \
  --exclude-rule yaml.github-actions.security.github-actions-mutable-action-tag.github-actions-mutable-action-tag \
  --exclude-rule yaml.github-actions.security.secrets-inherit.secrets-inherit \
  --exclude node_modules --exclude android --exclude ios --exclude dist --exclude coverage \
  apps .github
