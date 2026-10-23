#!/usr/bin/env bash
# What a release tag does, case by case, in a throwaway repo with a fake `gh` that knows which
# release carries which files. Each case is a situation that once went wrong or must stay refused.
set -euo pipefail
META="$(cd "$(dirname "$0")" && pwd)/release-meta.sh"
pass=0
fail=0

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/assets"
# Fake gh: `gh release view <tag> ...` prints the file names listed for that tag, or fails.
cat > "$W/bin/gh" <<'GH'
#!/usr/bin/env bash
f="$FAKE_ASSETS/$(echo "$3" | tr '/' '_')"
[ "$1 $2" = "release view" ] && [ -f "$f" ] && cat "$f" && exit 0
exit 1
GH
chmod +x "$W/bin/gh"
export PATH="$W/bin:$PATH" FAKE_ASSETS="$W/assets" MAIN_REF=main RELEASE_REFS=refs/heads/release/

R="$W/repo"
git init -q -b main "$R"
cd "$R"
git config user.email t@t
git config user.name t
c() { echo "$1" > "f-$1"; git add -A; git commit -qm "$1"; git rev-parse HEAD; }
built() { printf '%s\n' web-build-staging.zip web-build-prod.zip "${@:2}" > "$FAKE_ASSETS/$(echo "$1" | tr '/' '_')"; }

# expect ok|refused <tag> <case> [text ...]: runs release-meta and checks the outcome. Each text
# must be a whole output line when ok (key=value), or part of the refusal message when refused.
expect() {
  local want=$1 tag=$2 name=$3 out got=ok kv
  shift 3
  out=$(bash "$META" "$tag" 2>&1) || got=refused
  if [ "$got" != "$want" ]; then fail=$((fail + 1)); echo "FAIL $name: $got, wanted $want"; echo "$out" | sed 's/^/     /'; return; fi
  for kv in "$@"; do
    if { [ "$want" = ok ] && ! grep -qxF "$kv" <<<"$out"; } || { [ "$want" = refused ] && ! grep -qF "$kv" <<<"$out"; }; then fail=$((fail + 1)); echo "FAIL $name: no $kv in"; echo "$out" | sed 's/^/     /'; return; fi
  done
  pass=$((pass + 1)); echo "ok   $name"
}

A=$(c a)
git tag staging/v1.0.0-rc.1 "$A"
expect ok staging/v1.0.0-rc.1 "first rc on main builds web for both stages" 'from=' 'web_stages=["staging","prod"]'
built staging/v1.0.0-rc.1 android-staging-debug.apk android-prod-debug.apk

git tag staging/v1.0.0-rc.2 "$A"
expect ok staging/v1.0.0-rc.2 "a second rc on the same commit reuses the first" 'from=staging/v1.0.0-rc.1' 'web_stages=[]' 'mobile_stages=[]'

git tag staging/v1.0.0-rc.3 "$A"
rm "$FAKE_ASSETS/staging_v1.0.0-rc.1"
expect ok staging/v1.0.0-rc.3 "an rc that built nothing (refused) is not reused" 'from=' 'web_stages=["staging","prod"]'
built staging/v1.0.0-rc.1 android-staging-debug.apk android-prod-debug.apk

git tag prod/v1.0.0 "$A"
expect ok prod/v1.0.0 "prod reuses its rc and its apps" 'from=staging/v1.0.0-rc.1' 'web_stages=[]' 'mobile_stages=[]' 'direct=false'

git tag staging/v1.0.0-rc.4 "$A"
expect refused staging/v1.0.0-rc.4 "an rc of a version already in prod is refused" "already released to prod"

B=$(c b)
git tag prod/v1.1.0 "$B"
expect refused prod/v1.1.0 "prod on a commit no rc built is refused" "has no built staging/v1.1.0-rc.N"

git switch -q -c release/1.0.1 prod/v1.0.0
H=$(c hotfix)
git switch -q main
git tag prod/v1.0.1 "$H"
expect ok prod/v1.0.1 "a hotfix straight to prod from the head of release/1.0.1 builds prod only" 'direct=true' 'web_stages=["prod"]' 'mobile_stages=["prod"]'

git tag staging/v1.2.0-rc.1 "$B"
built staging/v1.2.0-rc.1
git switch -q -c release/1.2.0 prod/v1.0.0
O=$(c other-line)
git switch -q main
git tag staging/v1.2.0-rc.2 "$O"
expect refused staging/v1.2.0-rc.2 "a version another line of code already used is refused" "on another line of code"

git switch -q --detach "$A"
L=$(c loose)
git switch -q main
git tag staging/v1.3.0-rc.1 "$L"
expect refused staging/v1.3.0-rc.1 "an rc on neither main nor a release branch is refused" "neither main nor a release"

git tag staging/1.4.0-rc.1 "$B"
expect refused staging/1.4.0-rc.1 "a tag without the v is refused" "must be staging/vX.Y.Z-rc.N"

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
