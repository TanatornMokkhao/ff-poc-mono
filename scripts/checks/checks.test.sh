#!/usr/bin/env bash
# Proves each home-made check fails on the mistake it exists for and passes once it is fixed.
# Every case runs in a throwaway git repo holding a copy of scripts/checks.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
pass=0
fail=0

# A repo with one base commit; prints its path. BASE is that commit.
repo() {
  local d
  d=$(mktemp -d)
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@t
  git -C "$d" config user.name t
  git -C "$d" config core.fileMode false
  mkdir -p "$d/scripts/checks" "$d/.github/workflows" "$d/apps/fe/android"
  cp "$HERE"/*.sh "$d/scripts/checks/"
  git -C "$d" add -A
  git -C "$d" update-index --chmod=+x scripts/checks/*.sh
  git -C "$d" commit -qm base
  echo "$d"
}

# expect <0|1> <check> <case name>: runs the check in the current repo with BASE set.
expect() {
  local want=$1 check=$2 name=$3 got=0
  (cd "$R" && BASE=$(git rev-parse HEAD~1) bash "scripts/checks/$check" >/dev/null 2>&1) || got=1
  if [ "$got" = "$want" ]; then pass=$((pass + 1)); echo "ok   $check: $name"
  else fail=$((fail + 1)); echo "FAIL $check: $name (exit $got, wanted $want)"; fi
}

commit() { git -C "$R" add -A; git -C "$R" commit -qm "$1"; }

# executable-files.sh
R=$(repo)
printf '#!/bin/sh\n' > "$R/apps/fe/android/gradlew"
git -C "$R" add apps/fe/android/gradlew
git -C "$R" update-index --chmod=-x apps/fe/android/gradlew
commit "gradlew without exec"
expect 1 executable-files.sh "gradlew added as 100644 fails"
git -C "$R" update-index --chmod=+x apps/fe/android/gradlew
commit "gradlew exec"
expect 0 executable-files.sh "gradlew fixed to 100755 passes"
printf '#!/bin/sh\n' > "$R/scripts/new.sh"
git -C "$R" add scripts/new.sh
git -C "$R" update-index --chmod=-x scripts/new.sh
commit "script without exec"
expect 1 executable-files.sh "new script as 100644 fails"
rm -rf "$R"

# no-token-refs.sh
R=$(repo)
printf 'jobs:\n  a:\n    steps:\n      - run: gh release create "prod/v1" --target "$SHA"\n' > "$R/.github/workflows/a.yml"
commit "release create with target"
expect 1 no-token-refs.sh "gh release create --target fails"
printf 'jobs:\n  a:\n    steps:\n      - run: gh release create "prod/v1" --verify-tag\n' > "$R/.github/workflows/a.yml"
commit "verify-tag"
expect 0 no-token-refs.sh "gh release create --verify-tag passes"
printf 'jobs:\n  a:\n    steps:\n      - run: gh api repos/o/r/git/refs -f ref=refs/tags/x\n' > "$R/.github/workflows/b.yml"
commit "git refs api"
expect 1 no-token-refs.sh "gh api git/refs fails"
printf 'jobs:\n  a:\n    steps:\n      - run: gh api -X DELETE "repos/o/r/git/refs/tags/$TAG"\n' > "$R/.github/workflows/b.yml"
commit "delete a ref"
expect 0 no-token-refs.sh "gh api -X DELETE git/refs passes"
printf 'jobs:\n  a:\n    steps:\n      - uses: actions/checkout@v4\n      - run: git push origin HEAD:main\n' > "$R/.github/workflows/c.yml"
commit "push without key"
expect 1 no-token-refs.sh "git push without the deploy key fails"
printf 'jobs:\n  a:\n    steps:\n      - uses: actions/checkout@v4\n        with:\n          ssh-key: ${{ secrets.DEPLOY_KEY }}\n      - run: git push origin HEAD:main\n' > "$R/.github/workflows/c.yml"
commit "push with key"
expect 0 no-token-refs.sh "git push with the deploy key passes"
rm -rf "$R"

# fix-has-test.sh (the title comes from the pull request)
R=$(repo)
mkdir -p "$R/apps/be"
echo "export const a = 1;" > "$R/apps/be/a.js"
commit "app code only"
PR_TITLE="fix: a is wrong" expect 1 fix-has-test.sh "a fix with app code and no test fails"
PR_TITLE="feat: add a" expect 0 fix-has-test.sh "a feature without a test is not this rule's business"
echo "test('a', () => {});" > "$R/apps/be/a.test.js"
echo "export const a = 2;" > "$R/apps/be/a.js"
commit "app code and a test"
PR_TITLE="fix: a is wrong" expect 0 fix-has-test.sh "a fix with a test passes"
rm -rf "$R"

# exit-codes.sh
R=$(repo)
printf 'jobs:\n  a:\n    steps:\n      - run: |\n          terraform plan -detailed-exitcode\n          code=$?\n' > "$R/.github/workflows/plan.yml"
commit "status read on its own line"
expect 1 exit-codes.sh "code=\$? on its own line fails"
printf 'jobs:\n  a:\n    steps:\n      - run: |\n          code=0\n          terraform plan -detailed-exitcode || code=$?\n' > "$R/.github/workflows/plan.yml"
commit "status read on the command line"
expect 0 exit-codes.sh "cmd || code=\$? passes"
rm -rf "$R"

# secrets.sh (the key is split so this file does not hold one)
R=$(repo)
mkdir -p "$R/apps/be"
echo "aws_access_key_id = AKIA""Z7XK4P2MWQ5RJ3TB" > "$R/apps/be/.env.local"
commit "an AWS key committed by mistake"
expect 1 secrets.sh "an AWS access key in a new commit fails"
rm "$R/apps/be/.env.local"
commit "key removed"
expect 0 secrets.sh "a commit that removes it passes"
rm -rf "$R"

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
