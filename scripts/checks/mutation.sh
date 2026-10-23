#!/usr/bin/env bash
# Mutation testing on the lines this change adds to one app: Stryker changes the code in small
# ways (a flipped condition, a removed call) and runs the tests each time. A change the tests still
# pass means no test checks that behaviour. Only the added lines are mutated (file:start-end
# ranges), so an old weak spot in a touched file does not fail a change that did not write it.
# Fails when the score is below the break threshold in apps/<app>/stryker.config.json.
# Coverage only says a line ran; this says a test noticed.
#   scripts/checks/mutation.sh be|fe     (the app's dependencies must be installed)
set -euo pipefail
APP=$1
cd "$(git rev-parse --show-toplevel)"
if [ -z "${BASE:-}" ] || ! git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  echo "No base commit: mutation testing applies to pull requests and pushes only."; exit 0
fi
# Source files whose lines are mutated, as a path inside the app; tests, entry points and config
# are left out.
mutable() {
  case "$APP:$1" in
    be:*.test.js | be:*.test.mjs | be:index.js | be:migrate.js | be:eslint.config.js) return 1 ;;
    be:*.js | be:*.mjs) return 0 ;;
    fe:src/*.spec.ts | fe:src/main.ts | fe:src/*.d.ts) return 1 ;;
    fe:src/*.ts | fe:src/*.vue) return 0 ;;
    *) return 1 ;;
  esac
}
ranges=()
file=""
while IFS= read -r line; do
  case "$line" in
    "+++ "*)
      p=${line#+++ b/}
      p=${p#apps/"$APP"/}
      if mutable "$p"; then file=$p; else file=""; fi ;;
    "@@"*)
      [ -n "$file" ] || continue
      added=$(sed -E 's/^@@ [^+]*\+([0-9]+)(,([0-9]+))? @@.*/\1 \3/' <<<"$line")
      read -r start count <<<"$added"
      count=${count:-1}
      [ "$count" -gt 0 ] || continue
      ranges+=("$file:$start-$((start + count - 1))") ;;
  esac
done < <(git diff -U0 --diff-filter=ACMR "$BASE" HEAD -- "apps/$APP")
[ ${#ranges[@]} -gt 0 ] || { echo "No $APP source lines added."; exit 0; }
cd "apps/$APP"
echo "Mutating the added lines: ${ranges[*]}"
npx stryker run --mutate "$(IFS=,; echo "${ranges[*]}")"
