#!/usr/bin/env bash
set -euo pipefail
files=$(ls)
for f in $files; do echo $f; done
