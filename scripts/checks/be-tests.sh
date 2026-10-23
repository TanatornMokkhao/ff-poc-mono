#!/usr/bin/env bash
# The be test files this change needs, relative to apps/be, one per line. Nx says which be projects
# the change affects: be-<feature> runs apps/be/features/<feature>/*.test.js, be runs the tests at
# the top of apps/be (routing, migrations). Changes that reach every test (dependencies, compiler
# or test settings, this selection itself) and runs without a base commit (nightly) get them all.
#   bash scripts/checks/be-tests.sh      (root dependencies, for Nx, must be installed)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
all() { git ls-files 'apps/be/*.test.js' 'apps/be/**/*.test.js' | sed 's#^apps/be/##'; exit 0; }
if [ -z "${BASE:-}" ] || ! git cat-file -e "$BASE^{commit}" 2>/dev/null; then all; fi
if git diff --name-only "$BASE" HEAD | grep -qE '^(apps/be/(package(-lock)?\.json|jsconfig\.json|stryker\.config\.json|\.env\.example)|package(-lock)?\.json|nx\.json|\.github/workflows/ci\.yml|scripts/checks/be-tests\.sh)$'; then all; fi
for p in $(NX_DAEMON=false npx nx show projects --affected --base="$BASE" --head=HEAD); do
  case "$p" in
    # A git pathspec * also matches "/", so keep only the files directly in apps/be.
    be) git ls-files 'apps/be/*.test.js' | grep -E '^apps/be/[^/]+$' || true ;;
    be-*) git ls-files "apps/be/features/${p#be-}/*.test.js" ;;
  esac
done | sed 's#^apps/be/##' | sort -u
