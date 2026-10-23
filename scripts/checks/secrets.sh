#!/usr/bin/env bash
# gitleaks on the commits this change adds: a key, token or password committed by mistake fails
# the change before it reaches main (a secret in git history stays readable after it is deleted).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
if [ -n "${BASE:-}" ] && git cat-file -e "$BASE^{commit}" 2>/dev/null; then RANGE="$BASE..HEAD"; else RANGE="-1"; fi
gitleaks git --log-opts="$RANGE" --redact --no-banner --exit-code 1 .
