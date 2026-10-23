#!/usr/bin/env bash
# Scripts and the Gradle wrapper must keep their executable mode. A copy into this repo on Windows
# once dropped it from apps/fe/android/gradlew, and every Android build stopped with exit 126.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
bad=0
while IFS= read -r f; do
  case "$f" in
    */gradlew | scripts/*.sh | scripts/*/*.sh) ;;
    *) continue ;;
  esac
  mode=$(git ls-files -s -- "$f" | awk '{print $1}')
  if [ "$mode" != 100755 ]; then
    echo "::error file=$f::$f is mode $mode; it must be 100755. Run: git update-index --chmod=+x $f"
    bad=1
  fi
done < <(bash scripts/checks/changed-files.sh)
exit "$bad"
