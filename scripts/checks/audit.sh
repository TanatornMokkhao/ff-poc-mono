#!/usr/bin/env bash
# Known vulnerabilities in the packages one app ships (dependencies, not devDependencies), from the
# npm advisory database. Fails on a high or critical one; lower levels are printed only.
#   scripts/checks/audit.sh be|fe     (run after npm ci)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)/apps/$1"
npm audit --omit=dev --audit-level=high
