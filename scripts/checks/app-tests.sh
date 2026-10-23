#!/usr/bin/env bash
# The test files of one app that this change needs, relative to apps/<app>, one per line.
#   bash scripts/checks/app-tests.sh be|fe      (root dependencies, for Nx, must be installed)
# Nx says which projects the change affects. A feature project (<app>-<feature>, with its own
# project.json) runs the tests in its folder; the app project runs the tests outside every feature
# folder (routing, pages, migrations). A change that reaches every test (dependencies, compiler,
# test or build settings, this selection itself) and a run without a base commit (nightly) get all.
set -euo pipefail
APP=$1
cd "$(git rev-parse --show-toplevel)"
case "$APP" in
  be) TESTS='\.test\.(js|mjs)$' ;;
  fe) TESTS='\.(spec|test)\.ts$' ;;
  *) echo "::error::unknown app $APP" >&2; exit 1 ;;
esac
tests_in() { git ls-files "$1" | grep -E "$TESTS" | grep -vE '(^|/)(node_modules|tests/e2e)/' || true; }
FEATURES=$(git ls-files "apps/$APP/**/project.json" | grep -v "^apps/$APP/project.json$" | sed 's#/project.json$##' || true)
out() { sed "s#^apps/$APP/##" | sort -u; }
# exit here, not inside a pipeline: a pipeline's exit would leave only its subshell.
all() { tests_in "apps/$APP" | out; exit 0; }

if [ -z "${BASE:-}" ] || ! git cat-file -e "$BASE^{commit}" 2>/dev/null; then all; fi
GLOBAL="^(apps/$APP/(package(-lock)?\.json|jsconfig\.json|tsconfig[^/]*\.json|vite\.config\.ts|stryker\.config\.json|\.env\.example|\.eslintrc\.cjs)|package(-lock)?\.json|nx\.json|\.github/workflows/ci\.yml|scripts/checks/app-tests\.sh)$"
if git diff --name-only "$BASE" HEAD | grep -qE "$GLOBAL"; then all; fi

for p in $(NX_DAEMON=false npx nx show projects --affected --base="$BASE" --head=HEAD); do
  if [ "$p" = "$APP" ]; then
    # The app's own tests: everything outside the feature folders.
    tests_in "apps/$APP" | while IFS= read -r t; do
      inside=false
      for f in $FEATURES; do case "$t" in "$f"/*) inside=true ;; esac; done
      [ "$inside" = true ] || echo "$t"
    done
  elif [[ "$p" == "$APP"-* ]]; then
    root=$(NX_DAEMON=false npx nx show project "$p" --json | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>console.log(JSON.parse(s).root))")
    tests_in "$root"
  fi
done | out
