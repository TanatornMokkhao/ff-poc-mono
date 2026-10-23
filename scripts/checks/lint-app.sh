#!/usr/bin/env bash
# eslint, warnings included, on the files of one app that this change adds or modifies.
#   scripts/checks/lint-app.sh be|fe     (the app's dependencies must be installed)
set -euo pipefail
APP=$1
cd "$(git rev-parse --show-toplevel)"
files=()
while IFS= read -r f; do
  case "$f" in
    # .d.ts files hold types only; the type check reads them, eslint has nothing to lint there.
    apps/"$APP"/node_modules/* | apps/"$APP"/dist/* | apps/"$APP"/android/* | apps/"$APP"/ios/* | *.d.ts) continue ;;
    apps/"$APP"/*.js | apps/"$APP"/*.mjs | apps/"$APP"/*.ts | apps/"$APP"/*.vue) files+=("${f#apps/"$APP"/}") ;;
  esac
done < <(bash scripts/checks/changed-files.sh)
[ ${#files[@]} -gt 0 ] || { echo "No $APP source files changed."; exit 0; }
cd "apps/$APP"
npx eslint --max-warnings 0 --format stylish "${files[@]}"
