#!/usr/bin/env bash
# A workflow creates tags and pushes main only through the deploy key. GITHUB_TOKEN gets HTTP 403
# creating a ref on a commit that holds workflow files, and its pushes start no workflow.
# Checks the lines this change adds to .github/workflows/:
#   - "gh release create" with --target (the API creates the tag with GITHUB_TOKEN)
#   - "gh api .../git/refs" that is not a DELETE (creates a ref with GITHUB_TOKEN)
#   - "git push" in a workflow whose checkout has no ssh-key
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
bad=0
while IFS= read -r f; do
  case "$f" in .github/workflows/*.yml | .github/workflows/*.yaml) ;; *) continue ;; esac
  if [ -n "${BASE:-}" ] && git cat-file -e "$BASE^{commit}" 2>/dev/null; then
    added=$(git diff -U0 "$BASE" HEAD -- "$f" | grep -E '^\+[^+]' | cut -c2- || true)
  else
    added=$(cat "$f")
  fi
  if grep -qE 'gh release create[^#]*--target' <<<"$added"; then
    echo "::error file=$f::gh release create --target makes the tag with GITHUB_TOKEN (403). Push the tag with the deploy key, then gh release create --verify-tag."
    bad=1
  fi
  # Deleting a ref with GITHUB_TOKEN works; creating one is what fails.
  if grep -E 'gh api[^#]*git/refs' <<<"$added" | grep -qvE '(-X|--method)[[:space:]]+DELETE'; then
    echo "::error file=$f::gh api .../git/refs creates a ref with GITHUB_TOKEN. Push it with the deploy key instead."
    bad=1
  fi
  if grep -qE '(^|[;&|[:space:]])git push( |$)' <<<"$added" && ! grep -qE 'ssh-key:[[:space:]]*\$\{\{[[:space:]]*secrets\.DEPLOY_KEY' "$f"; then
    echo "::error file=$f::git push in a workflow whose checkout has no 'ssh-key: \${{ secrets.DEPLOY_KEY }}': GITHUB_TOKEN cannot get past the main ruleset."
    bad=1
  fi
done < <(bash scripts/checks/changed-files.sh)
exit "$bad"
