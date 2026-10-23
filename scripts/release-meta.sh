#!/usr/bin/env bash
# Decides what a release tag does, or refuses it. Prints key=value lines (stage, version, sha,
# from, web_stages, mobile_stages, config_stages) on stdout; errors go to stderr as ::error::.
#   scripts/release-meta.sh <tag>
# MAIN_REF and RELEASE_REFS name main and the release branches (the remote ones by default);
# release-meta.test.sh points them at local branches. Asset names come from `gh release view`.
set -euo pipefail

TAG=$1
MAIN_REF=${MAIN_REF:-origin/main}
RELEASE_REFS=${RELEASE_REFS:-refs/remotes/origin/release/}

fail() { echo "::error::$1" >&2; exit 1; }
assets() { gh release view "$1" --json assets --jq '.assets[].name' 2>/dev/null || true; }

if [[ "$TAG" =~ ^staging/v([0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+)$ ]]; then
  STAGE=staging; VERSION="${BASH_REMATCH[1]}"
elif [[ "$TAG" =~ ^prod/v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
  STAGE=prod; VERSION="${BASH_REMATCH[1]}"
else
  fail "Tag $TAG must be staging/vX.Y.Z-rc.N or prod/vX.Y.Z."
fi
SHA=$(git rev-parse "$TAG^{commit}")

# The newest rc on this commit (matching the pattern) whose builds exist; a refused or cancelled rc
# on the same commit built nothing and must not be reused.
built_rc() {
  local t
  for t in $(git tag --points-at "$SHA" | grep -E "$1" | grep -vx "$TAG" | sort -Vr || true); do
    assets "$t" | grep -qx web-build-prod.zip && { echo "$t"; return; }
  done
  return 0
}

DIRECT=false
if [ "$STAGE" = prod ]; then
  PREV=$(built_rc "^staging/v$VERSION-rc\.[0-9]+$")
  if [ -z "$PREV" ]; then
    # A hotfix straight to prod: the tag must be the head of release/X.Y.Z.
    if [ "$(git rev-parse -q --verify "${RELEASE_REFS}$VERSION" || true)" = "$SHA" ]; then DIRECT=true
    else fail "${SHA::7} has no built staging/v$VERSION-rc.N and is not the head of release/$VERSION. Use Promote."; fi
  fi
else
  PREV=$(built_rc '^staging/v[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$')
  # An rc is cut from main, or from a release/* branch (a hotfix cut from a prod tag).
  if ! git merge-base --is-ancestor "$SHA" "$MAIN_REF" && [ -z "$(git for-each-ref --contains "$SHA" "$RELEASE_REFS")" ]; then
    fail "$TAG is on ${SHA::7}, which is on neither main nor a release/* branch."
  fi
  # One version number names one line of code: every earlier rc of it must come before this commit.
  # Otherwise main and a hotfix (or two hotfixes) would share the number.
  BASE="${VERSION%-rc.*}"
  if git rev-parse -q --verify "refs/tags/prod/v$BASE" >/dev/null; then fail "$BASE is already released to prod; use the next version."; fi
  for t in $(git tag --list "staging/v$BASE-rc.*" | grep -vx "$TAG" || true); do
    if ! git merge-base --is-ancestor "$t" "$SHA"; then
      LINE="${BASE%.*}"
      HIGH=$(git tag --list "prod/v$LINE.*" "staging/v$LINE.*" | sed -E 's#^(prod|staging)/v##; s/-rc\.[0-9]+$//' | sort -V | tail -1)
      fail "$t is on another line of code (not before ${SHA::7}), so $BASE is taken. Use $LINE.$(( ${HIGH##*.} + 1 ))."
    fi
  done
fi

has() { [ -n "$PREV" ] && assets "$PREV" | grep -qx "$1"; }
if [ "$STAGE" = prod ]; then
  if has android-prod-app-release.aab || has android-prod-debug.apk; then MOBILE='[]'; else MOBILE='["prod"]'; fi
else
  if has android-staging-app-release.apk || has android-staging-debug.apk; then MOBILE='[]'; else MOBILE='["staging","prod"]'; fi
fi
if [ "$STAGE" = staging ] && [ -z "$PREV" ]; then WEB='["staging","prod"]'
elif [ "$DIRECT" = true ]; then WEB='["prod"]'
else WEB='[]'; fi
if [ "$WEB" != '[]' ]; then CONFIG="$WEB"; else CONFIG="$MOBILE"; fi

echo "stage=$STAGE"
echo "version=$VERSION"
echo "sha=$SHA"
echo "from=$PREV"
echo "direct=$DIRECT"
echo "web_stages=$WEB"
echo "mobile_stages=$MOBILE"
echo "config_stages=$CONFIG"
