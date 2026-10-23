#!/usr/bin/env bash
# Mutation testing on the be source files this change adds or modifies: Stryker changes the code in
# small ways (a flipped condition, a removed call) and runs the tests each time. A change the tests
# still pass means no test checks that behaviour. Fails when the score is below the break
# threshold in apps/be/stryker.config.json. Coverage only says a line ran; this says a test noticed.
#   scripts/checks/mutation.sh      (run from anywhere; be dependencies must be installed)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
if [ -z "${BASE:-}" ] || ! git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  echo "No base commit: mutation testing applies to pull requests and pushes only."; exit 0
fi
files=()
while IFS= read -r f; do
  p=${f#apps/be/}
  [ "$p" != "$f" ] || continue
  case "$p" in
    *.test.js | *.test.mjs | index.js | migrate.js | eslint.config.js) continue ;;
    *.js | *.mjs) files+=("$p") ;;
  esac
done < <(bash scripts/checks/changed-files.sh)
[ ${#files[@]} -gt 0 ] || { echo "No be source files changed."; exit 0; }
cd apps/be
echo "Mutating: ${files[*]}"
npx stryker run --mutate "$(IFS=,; echo "${files[*]}")"
