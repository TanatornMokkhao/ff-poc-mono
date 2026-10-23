#!/usr/bin/env bash
# A fix comes with a test: a pull request titled fix... that changes app code must also add or
# change a test, so the bug cannot come back unnoticed. Write the test first and watch it fail
# for the bug's reason, then fix the code.
#   PR_TITLE="fix: ..." scripts/checks/fix-has-test.sh     (outside a pull request it passes)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
title=${PR_TITLE:-}
[[ "$title" =~ ^fix(\(|!|:) ]] || { echo "Not a fix: no test required by this rule."; exit 0; }
app_code=false
tests=false
while IFS= read -r f; do
  case "$f" in
    apps/*/node_modules/* | apps/*/android/* | apps/*/ios/*) ;;
    apps/*.test.* | apps/*.spec.* | apps/*/tests/*) tests=true ;;
    apps/*.js | apps/*.mjs | apps/*.ts | apps/*.vue | apps/*.sql) app_code=true ;;
  esac
done < <(bash scripts/checks/changed-files.sh)
if [ "$app_code" = true ] && [ "$tests" = false ]; then
  echo "::error::\"$title\" changes app code but no test. Add a test that fails without the fix (and fails for the bug's reason)."
  exit 1
fi
echo "Fix rule: $([ "$app_code" = true ] && echo "app code and a test changed" || echo "no app code changed")."
