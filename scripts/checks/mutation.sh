#!/usr/bin/env bash
# Mutation testing on the be lines this change adds: Stryker changes the code in small ways (a
# flipped condition, a removed call) and runs the tests each time. A change the tests still pass
# means no test checks that behaviour. Only the added lines are mutated (file:start-end ranges),
# so an old weak spot in a touched file does not fail a change that did not write it. Fails when
# the score is below the break threshold in apps/be/stryker.config.json.
# Coverage only says a line ran; this says a test noticed.
#   scripts/checks/mutation.sh      (be dependencies must be installed)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
if [ -z "${BASE:-}" ] || ! git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  echo "No base commit: mutation testing applies to pull requests and pushes only."; exit 0
fi
ranges=()
file=""
while IFS= read -r line; do
  case "$line" in
    "+++ "*)
      p=${line#+++ b/}
      p=${p#apps/be/}
      case "$p" in
        *.test.js | *.test.mjs | index.js | migrate.js | eslint.config.js | "+++ /dev/null") file="" ;;
        *.js | *.mjs) file=$p ;;
        *) file="" ;;
      esac ;;
    "@@"*)
      [ -n "$file" ] || continue
      added=$(sed -E 's/^@@ [^+]*\+([0-9]+)(,([0-9]+))? @@.*/\1 \3/' <<<"$line")
      read -r start count <<<"$added"
      count=${count:-1}
      [ "$count" -gt 0 ] || continue
      ranges+=("$file:$start-$((start + count - 1))") ;;
  esac
done < <(git diff -U0 --diff-filter=ACMR "$BASE" HEAD -- apps/be)
[ ${#ranges[@]} -gt 0 ] || { echo "No be source lines added."; exit 0; }
cd apps/be
echo "Mutating the added lines: ${ranges[*]}"
npx stryker run --mutate "$(IFS=,; echo "${ranges[*]}")"
